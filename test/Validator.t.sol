// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {BaseAuthorization} from "src/BaseAuthorization.sol";
import {ECDSAValidator} from "./validators/ECDSAValidator.sol";
import {PasskeyValidator} from "./validators/PasskeyValidator.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Static} from "src/libraries/Static.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {IValidator} from "src/interfaces/IValidator.sol";

/**
 * @title RevertingValidator
 * @notice Mock validator that always reverts, for testing error handling
 */
contract RevertingValidator is IValidator {
    function validateSignature(
        bytes32, // keyHash
        bytes32, // messageHash
        bytes calldata // validatorData
    ) external pure returns (bool) {
        revert("Validator always reverts");
    }
}

/**
 * @title MockValidator
 * @notice Mock validator for testing external validator contracts
 * @dev Returns configurable validation results for testing purposes
 */
contract MockValidator is IValidator {
    bool private validationResult = true;

    function setValidationResult(bool result) external {
        validationResult = result;
    }

    function validateSignature(
        bytes32, // keyHash
        bytes32, // messageHash
        bytes calldata // validatorData
    ) external view returns (bool) {
        return validationResult;
    }
}

contract ValidatorTest is Base {
    // External validators for testing
    ECDSAValidator internal externalEcdsaValidator;
    PasskeyValidator internal externalPasskeyValidator;
    MockValidator internal mockValidator;

    event OwnerAdded(bytes32 keyHash, address validator, uint256 settings);
    event OwnerRemoved(bytes32 keyHash, address validator);
    event OwnerUpdated(bytes32 keyHash, address newValidator, uint256 settings);
    error FailedDeployment();

    function setUp() public override {
        super.setUp();

        // Deploy external validator contracts
        externalEcdsaValidator = new ECDSAValidator();
        externalPasskeyValidator = new PasskeyValidator();
        mockValidator = new MockValidator();
    }

    // Helper function to extract validator from getOwnerSettings
    function _getValidatorFromSettings(
        IOwnerManager manager,
        bytes32 keyHash
    ) internal view returns (address) {
        (address validator, , , , ) = manager.getOwnerSettings(keyHash);
        return validator;
    }

    // Helper function to reconstruct packed settings from getOwnerSettings
    function _getPackedSettings(
        IOwnerManager manager,
        bytes32 keyHash
    ) internal view returns (uint256) {
        (, address hook, uint40 expiration, bool isAdmin, ) = manager
            .getOwnerSettings(keyHash);
        return manager.packSettings(isAdmin, expiration, hook);
    }

    function test_RevertWhen_AddValidator_NonOwner() public {
        // Test that a non-owner can't add a validator through execute
        address validatorAddress = address(_ecdsaValidator);
        address nonOwner = address(0xdead);

        // Pack settings
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        // Build the calls to add an owner
        Call[] memory calls = _buildAddOwnerCalls(
            _aliceWallet,
            keccak256(abi.encodePacked(address(this))),
            validatorAddress,
            settings
        );

        // Non-owner tries to execute - should revert with InvalidCaller
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidCaller.selector,
                nonOwner
            )
        );
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_RevertWhen_AddValidator_InvalidImplementation() public {
        address dave = vm.addr(3);

        // Pack settings before setting expectRevert
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        // Expect invalid validator implementation revert when called through execute
        Call[] memory calls = _buildAddOwnerCalls(
            _aliceWallet,
            keccak256(abi.encodePacked(address(this))),
            dave,
            settings
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnerManager.InvalidValidatorImpl.selector,
                dave
            )
        );
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_RevertWhen_AddValidator_Duplicate() public {
        // Alice already has a validator from initialization, try to add duplicate
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));

        // Verify Alice has the validator first
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(keyHash));

        // Pack settings before setting expectRevert
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        Call[] memory calls = _buildAddOwnerCalls(
            _aliceWallet,
            keyHash,
            address(_ecdsaValidator),
            settings
        );

        vm.prank(_alice);
        vm.expectRevert(IOwnerManager.ValidatorAlreadyExists.selector);
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_RevertWhen_AddValidator_InvalidValidatorAddress() public {
        // Test that adding address(0) as validator should revert
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));

        // Pack settings
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        // Build calls to add address(0) as validator
        Call[] memory calls = _buildAddOwnerCalls(
            _aliceWallet,
            keyHash,
            address(0), // Invalid validator address
            settings
        );

        // Should revert with InvalidValidatorImpl error
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnerManager.InvalidValidatorImpl.selector,
                address(0)
            )
        );
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_Validator_CanBeAdded_Success() public {
        // Use the shared validator
        address charlieValidator = address(_ecdsaValidator);

        // Expect owner added event
        vm.expectEmit();
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        emit OwnerAdded(charlieKeyHash, charlieValidator, 0);

        // Deploy and add validator using the helper
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(_ecdsaValidator),
            0
        );
    }

    function test_NewValidator_CanValidateTransactions_Success() public {
        // Deploy and add validator using helper
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(_ecdsaValidator),
            0
        );

        Call[] memory calls = constructCallsData();

        // Relayer executes with Charlie signature
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _charlie,
            _charliePk,
            batchedCall,
            uint48(0)
        );

        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_ValidatorManagement_Success() public {
        // Alice already has a validator from initialization
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));

        // Pack settings before setting expectRevert
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        // Test that we can't add another validator for the same keyHash (should revert)
        Call[] memory calls = _buildAddOwnerCalls(
            _aliceWallet,
            keyHash,
            address(_ecdsaValidator),
            settings
        );

        vm.prank(_alice);
        vm.expectRevert(IOwnerManager.ValidatorAlreadyExists.selector);
        ISmartWallet(_aliceWallet).execute(calls);

        // Test removing the validator
        _executeRemoveValidator(_aliceWallet, keyHash);
    }

    function test_AddValidatorWithSettings_Success() public {
        // Use SELF_VALIDATION_ADDRESS for testing to avoid deployment issues
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        address hookAddress = address(0x1234);
        uint40 expiration = uint40(block.timestamp + 3600); // 1 hour from now
        bool isAdmin = true;

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            isAdmin,
            expiration,
            hookAddress
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            settings
        );

        // Verify settings were stored correctly
        (
            address validator,
            address hook,
            uint40 storedExpiration,
            bool storedIsAdmin,
            bool isExpired
        ) = IOwnerManager(_aliceWallet).getOwnerSettings(keyHash);

        assertEq(validator, validatorAddress);
        assertEq(hook, hookAddress);
        assertEq(storedExpiration, expiration);
        assertTrue(storedIsAdmin);
        assertFalse(isExpired);
    }

    function test_Validator_ExpirationFunctionality_Success() public {
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        uint40 expiration = uint40(block.timestamp + 1); // Expires in 1 second

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            expiration,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            settings
        );

        // Validator should be valid initially
        (address retrievedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(retrievedValidator, validatorAddress);
        assertFalse(_isSignerExpired(_aliceWallet, keyHash));

        // Advance time past expiration
        vm.warp(block.timestamp + 2);

        // Validator should now be expired but getOwnerSettings still returns the address
        // Only getVerifiedValidator checks expiration
        (retrievedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(retrievedValidator, validatorAddress); // Still returns the address
        assertTrue(_isSignerExpired(_aliceWallet, keyHash));
    }

    function test_GetVerifiedValidator_ReturnsZeroForExpiredOwner() public {
        // Add a validator with short expiration time
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        uint40 expiration = uint40(block.timestamp + 100); // Expires in 100 seconds

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            expiration,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            settings
        );

        // Before expiration, getVerifiedValidator should return the validator address
        address verifiedValidator = IOwnerManager(_aliceWallet)
            .getVerifiedValidator(keyHash);
        assertEq(
            verifiedValidator,
            validatorAddress,
            "Validator should be returned before expiration"
        );

        // Verify the validator exists in owner settings
        (address storedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(
            storedValidator,
            validatorAddress,
            "Validator should exist in owner settings"
        );

        // Fast forward time past expiration
        vm.warp(block.timestamp + 101);

        // After expiration, getVerifiedValidator should return address(0)
        verifiedValidator = IOwnerManager(_aliceWallet).getVerifiedValidator(
            keyHash
        );
        assertEq(
            verifiedValidator,
            address(0),
            "getVerifiedValidator should return address(0) for expired validator"
        );

        // But getOwnerSettings still returns the validator address (doesn't check expiration)
        (storedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(
            storedValidator,
            validatorAddress,
            "getOwnerSettings should still return the validator address"
        );

        // Verify the owner is indeed expired
        assertTrue(
            _isSignerExpired(_aliceWallet, keyHash),
            "Owner should be expired"
        );
    }

    function test_GetVerifiedValidator_ReturnsZeroForExpiredOwnerWithVerification()
        public
    {
        // Add a validator with short expiration time
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        uint40 expiration = uint40(block.timestamp + 100); // Expires in 100 seconds

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            expiration,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            settings
        );

        // Before expiration, getVerifiedValidator should return the validator address
        address verifiedValidator = IOwnerManager(_aliceWallet)
            .getVerifiedValidator(keyHash);
        assertEq(
            verifiedValidator,
            validatorAddress,
            "Validator should be returned before expiration"
        );

        // Verify the validator exists in owner settings
        (address storedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(
            storedValidator,
            validatorAddress,
            "Validator should exist in owner settings"
        );

        // Fast forward time past expiration
        vm.warp(block.timestamp + 101);

        // After expiration, getVerifiedValidator should return address(0)
        verifiedValidator = IOwnerManager(_aliceWallet).getVerifiedValidator(
            keyHash
        );
        assertEq(
            verifiedValidator,
            address(0),
            "getVerifiedValidator should return address(0) for expired validator"
        );

        // But getOwnerSettings still returns the validator address (doesn't check expiration)
        (storedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(
            storedValidator,
            validatorAddress,
            "getOwnerSettings should still return the validator address"
        );

        // Verify the owner is indeed expired
        assertTrue(
            _isSignerExpired(_aliceWallet, keyHash),
            "Owner should be expired"
        );
    }

    function test_PermanentValidator_NeverExpires_Success() public {
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            settings
        );

        // Even after advancing time significantly, validator should remain valid
        vm.warp(block.timestamp + 365 days);

        (address retrievedValidator, , , , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(keyHash);
        assertEq(retrievedValidator, validatorAddress);
        assertFalse(_isSignerExpired(_aliceWallet, keyHash));
        assertEq(_getSignerExpiration(_aliceWallet, keyHash), 0);
    }

    function test_AdminSigner_Functionality_Success() public {
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        // Add admin validator
        uint256 adminSettings = OwnerManager(_aliceWallet).packSettings(
            true,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            adminSettings
        );

        // Verify admin status
        assertTrue(_isSignerAdmin(_aliceWallet, keyHash));

        // Add non-admin validator
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        address nonAdminValidatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        uint256 nonAdminSettings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            nonAdminKeyHash,
            nonAdminValidatorAddress,
            nonAdminSettings
        );

        // Verify non-admin status
        assertFalse(_isSignerAdmin(_aliceWallet, nonAdminKeyHash));
    }

    function test_BackwardCompatibility_WithOldAddValidator_Success() public {
        // Test that old addValidator still works and has default settings
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            validatorAddress,
            settings
        );

        // Check that settings have default values
        (
            address validator,
            address hook,
            uint40 expiration,
            bool isAdmin,
            bool isExpired
        ) = IOwnerManager(_aliceWallet).getOwnerSettings(keyHash);

        assertEq(validator, validatorAddress);
        assertEq(hook, address(0)); // Default: no hook
        assertEq(expiration, 0); // Default: never expires
        assertFalse(isAdmin); // Default: not admin
        assertFalse(isExpired); // Default: not expired
    }

    function test_Initialize_SetsAdminPrivilegesForInitialOwners_Success()
        public
    {
        // Prepare initial owners with different keys
        bytes32[] memory keyHashes = new bytes32[](2);
        address[] memory validators = new address[](2);

        // First owner - Charlie
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        keyHashes[0] = charlieKeyHash;
        validators[0] = Static.ECDSA_VALIDATOR_ADDRESS;

        // Second owner - Bob
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        keyHashes[1] = bobKeyHash;
        validators[1] = Static.ECDSA_VALIDATOR_ADDRESS;

        // Deploy the wallet through factory with initial owners
        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );
        address newWallet = _factory.createAccount(initialOwners, 1); // Use salt 1 to avoid collision
        vm.deal(newWallet, 10 ether);

        // Verify both initial owners have admin privileges
        assertTrue(_isSignerAdmin(newWallet, charlieKeyHash));
        assertTrue(_isSignerAdmin(newWallet, bobKeyHash));

        // Verify their settings
        (
            address charlieValidator,
            address charlieHook,
            uint40 charlieExpiration,
            bool charlieIsAdmin,
            bool charlieIsExpired
        ) = IOwnerManager(newWallet).getOwnerSettings(charlieKeyHash);

        assertEq(charlieValidator, Static.ECDSA_VALIDATOR_ADDRESS);
        assertEq(charlieHook, address(0)); // No hook
        assertEq(charlieExpiration, 0); // Never expires
        assertTrue(charlieIsAdmin); // Admin privileges
        assertFalse(charlieIsExpired); // Not expired

        // Same for Bob
        (
            address bobValidator,
            address bobHook,
            uint40 bobExpiration,
            bool bobIsAdmin,
            bool bobIsExpired
        ) = IOwnerManager(newWallet).getOwnerSettings(bobKeyHash);

        assertEq(bobValidator, Static.ECDSA_VALIDATOR_ADDRESS);
        assertEq(bobHook, address(0)); // No hook
        assertEq(bobExpiration, 0); // Never expires
        assertTrue(bobIsAdmin); // Admin privileges
        assertFalse(bobIsExpired); // Not expired
    }

    function test_Initialize_WithEmptyInitialOwners_Success() public {
        // Deploy wallet through factory with empty array
        InitialOwner[] memory initialOwners = new InitialOwner[](0);
        address newWallet = _factory.createAccount(initialOwners, 2); // Use salt 2 to avoid collision
        vm.deal(newWallet, 10 ether);

        // Should succeed without errors
        // No signers should be set
        bytes32 testKeyHash = keccak256(abi.encodePacked(_alice));
        assertEq(
            _getValidatorFromSettings(IOwnerManager(newWallet), testKeyHash),
            address(0)
        );
        assertFalse(_isSignerAdmin(newWallet, testKeyHash));
    }

    function test_RevertWhen_RemoveValidator_NonOwner() public {
        // First add a validator to remove
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );

        // Try to call removeValidator directly from external address (not through execute)
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        (bool success, ) = _aliceWallet.call(
            abi.encodeWithSelector(OwnerManager.removeOwner.selector, keyHash)
        );
        // Note: vm.expectRevert() already validates the call failed with the expected error
        success; // Silence unused variable warning
    }

    function test_RevertWhen_RemoveValidator_NonAdmin() public {
        // Add a validator first (using admin)
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );

        // Add a non-admin signer - use the correct keyHash for _bob's address
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 nonAdminSettings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            nonAdminKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            nonAdminSettings
        );

        // Create a BatchedCall to remove validator using non-admin signer
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                keyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign with non-admin signer (_bob)
        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _bob,
            _bobPk,
            batchedCall,
            uint48(0)
        );

        // Should revert with NonAdminSelfCall
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.NonAdminSelfCall.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);
    }

    function test_RevertWhen_AddValidator_NonAdmin() public {
        // Add a non-admin signer - use the correct keyHash for _bob's address
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 nonAdminSettings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            nonAdminKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            nonAdminSettings
        );

        // Create a BatchedCall to add another validator using non-admin signer
        bytes32 newKeyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            uint40(0),
            address(0)
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                settings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign with non-admin signer (_bob)
        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _bob,
            _bobPk,
            batchedCall,
            uint48(0)
        );

        // Should revert with NonAdminSelfCall
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.NonAdminSelfCall.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);
    }

    function test_RemoveValidator_ForAdmin_Success() public {
        // First add a validator to remove
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );

        // Verify validator exists
        assertEq(
            _getValidatorFromSettings(IOwnerManager(_aliceWallet), keyHash),
            Static.ECDSA_VALIDATOR_ADDRESS
        );

        // Create a BatchedCall to remove validator using admin signer
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                keyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign with admin signer (default initial owner is admin)
        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should succeed
        vm.expectEmit(true, true, true, true);
        emit OwnerRemoved(keyHash, Static.ECDSA_VALIDATOR_ADDRESS);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);

        // Verify validator is removed
        assertEq(
            _getValidatorFromSettings(IOwnerManager(_aliceWallet), keyHash),
            address(0)
        );
    }

    function test_RevertWhen_RemoveValidator_OnNonexistentValidator() public {
        // Test that removing a validator that was never added reverts for consistency
        bytes32 nonExistentKeyHash = keccak256(abi.encodePacked(_dave));

        // Verify the validator doesn't exist
        assertEq(
            _getValidatorFromSettings(
                IOwnerManager(_aliceWallet),
                nonExistentKeyHash
            ),
            address(0)
        );
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(nonExistentKeyHash));

        // Create a BatchedCall to remove non-existent validator
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                nonExistentKeyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign with admin signer
        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert when trying to remove non-existent validator
        vm.expectRevert(
            abi.encodeWithSelector(IOwnerManager.ValidatorNotFound.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);

        // Verify the validator still doesn't exist
        assertEq(
            _getValidatorFromSettings(
                IOwnerManager(_aliceWallet),
                nonExistentKeyHash
            ),
            address(0)
        );
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(nonExistentKeyHash));
    }

    function test_UpdateValidator_Success() public {
        // First add a validator to update
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );

        // Verify initial validator
        assertEq(
            _getValidatorFromSettings(IOwnerManager(_aliceWallet), keyHash),
            Static.ECDSA_VALIDATOR_ADDRESS
        );

        // Create new settings
        uint256 newSettings = OwnerManager(_aliceWallet).packSettings(
            true,
            uint40(block.timestamp + 3600),
            address(0)
        );

        // Create a BatchedCall to update validator
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                keyHash,
                Static.PASSKEY_VALIDATOR_ADDRESS,
                newSettings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign with admin signer
        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should succeed and emit event
        vm.expectEmit(true, true, true, true);
        emit OwnerUpdated(
            keyHash,
            Static.PASSKEY_VALIDATOR_ADDRESS,
            newSettings
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);

        // Verify validator is updated
        assertEq(
            _getValidatorFromSettings(IOwnerManager(_aliceWallet), keyHash),
            Static.PASSKEY_VALIDATOR_ADDRESS
        );
        assertEq(
            _getPackedSettings(IOwnerManager(_aliceWallet), keyHash),
            newSettings
        );
    }

    function test_RevertWhen_UpdateValidator_NonExistentKeyHash() public {
        bytes32 nonExistentKeyHash = keccak256(abi.encodePacked("nonexistent"));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        // Create a BatchedCall to update non-existent validator
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                nonExistentKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                settings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert
        vm.expectRevert(
            abi.encodeWithSelector(IOwnerManager.ValidatorNotFound.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);
    }

    function test_RevertWhen_UpdateValidator_InvalidValidator() public {
        // First add a validator to update
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );

        uint256 updateSettings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        // Create a BatchedCall to update with invalid validator (EOA with no code)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                keyHash,
                _charlie, // EOA address with no code
                updateSettings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory signature = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnerManager.InvalidValidatorImpl.selector,
                _charlie
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, signature);
    }

    function test_UnifiedEncoding_Design_Success() public {
        // This test validates the unified abi.encodePacked design for all keyHash generation

        // Use alice's wallet which is already deployed and initialized
        address freshWallet = _aliceWallet;

        // Now both regular owners and EIP-7702 use the same encoding method
        bytes32 selfKeyHash = keccak256(abi.encodePacked(freshWallet));

        // This keyHash should NOT be a registered owner
        assertFalse(IOwnerManager(freshWallet).hasOwner(selfKeyHash));

        // With EIP-7702 built-in owner, should return ECDSA validator
        address validator = IOwnerManager(freshWallet).getVerifiedValidator(
            selfKeyHash
        );
        assertEq(validator, Static.ECDSA_VALIDATOR_ADDRESS);

        // Test that we can add this same keyHash as a regular owner
        // Use executeWithRelayer with alice's signature since alice is admin
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: freshWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                selfKeyHash,
                address(_ecdsaValidator),
                OwnerManager(freshWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(freshWallet)
        });

        bytes memory signature = _constructRelayerSignature(
            freshWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        ISmartWallet(freshWallet).executeWithRelayer(batchedCall, signature);

        // Now it should be a registered owner
        assertTrue(IOwnerManager(freshWallet).hasOwner(selfKeyHash));

        // And getVerifiedValidator should return the registered validator
        address registeredValidator = IOwnerManager(freshWallet)
            .getVerifiedValidator(selfKeyHash);
        assertEq(registeredValidator, address(_ecdsaValidator));
    }

    // ============ External Validator Tests ============

    function test_ExternalEcdsaValidator_Deployment_Success() public view {
        assertEq(address(externalEcdsaValidator).code.length > 0, true);
    }

    function test_ExternalEcdsaValidator_Integration_Success() public {
        // Add charlie as validator using external ECDSA validator
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(externalEcdsaValidator),
            settings
        );

        // Verify validator was added
        address addedValidator = _getValidatorFromSettings(
            IOwnerManager(_aliceWallet),
            charlieKeyHash
        );
        assertEq(addedValidator, address(externalEcdsaValidator));

        // Test executing transaction with external validator
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _charlie,
            _charliePk,
            batchedCall,
            uint48(0)
        );

        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_MockValidator_IntegrationSuccess_Success() public {
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(mockValidator),
            settings
        );

        mockValidator.setValidationResult(true);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = abi.encodePacked(
            charlieKeyHash,
            uint48(0), // validUntil (0 means no expiry)
            "mock signature data"
        );

        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_RevertWhen_MockValidator_IntegrationFailure() public {
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(mockValidator),
            settings
        );

        mockValidator.setValidationResult(false);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = abi.encodePacked(
            charlieKeyHash,
            uint48(0), // validUntil (0 means no expiry)
            "mock signature data"
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ Edge Case Tests ============

    function test_Validator_SignatureBoundaries_Success() public {
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(externalEcdsaValidator),
            settings
        );

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Test 1: Empty signature should fail
        bytes memory emptyValidatorData = abi.encodePacked(
            charlieKeyHash,
            uint48(0), // validUntil data
            bytes("")
        );
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            emptyValidatorData
        );

        // Test 2: Oversized signature should fail
        bytes memory oversizedSignature = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            oversizedSignature[i] = bytes1(uint8(i % 256));
        }
        bytes memory oversizedValidatorData = abi.encodePacked(
            charlieKeyHash,
            uint48(0), // validUntil data
            oversizedSignature
        );
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            oversizedValidatorData
        );

        // Test 3: Insufficient signature data should fail
        bytes memory insufficientValidatorData = abi.encodePacked(
            charlieKeyHash,
            uint48(0), // validUntil data
            bytes32(
                0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
            )
        );
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            insufficientValidatorData
        );
    }

    function test_RevertWhen_Validator_InvalidKeyhash() public {
        // Use zero keyHash (invalid)
        bytes32 invalidKeyHash = bytes32(0);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes32 typedDataHash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, 0, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, typedDataHash);

        bytes memory validatorData = abi.encodePacked(
            invalidKeyHash, // Invalid keyHash
            uint48(0), // validUntil (0 means no expiry)
            abi.encodePacked(r, s, v)
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidKeyHash.selector,
                invalidKeyHash
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ UserOp Edge Case Tests ============

    function test_ValidateUserOp_SignatureTooShort_ReturnsSigValidationFailed()
        public
    {
        vm.prank(_alice);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            aliceKeyHash,
            address(externalEcdsaValidator),
            0
        );

        vm.deal(address(account), 1 ether);

        PackedUserOperation memory userOp;
        // Signature too short (less than 38 bytes)
        userOp.signature = abi.encodePacked(
            bytes16(0x1234567890abcdef1234567890abcdef)
        );

        bytes32 userOpHash = keccak256("test");
        uint256 missingAccountFunds = 100;

        // Should return SIG_VALIDATION_FAILED for short signature
        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED,
            "Short signature should fail validation"
        );
    }

    function test_ValidateUserOp_EmptySignature_ReturnsSigValidationFailed()
        public
    {
        vm.prank(_alice);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            aliceKeyHash,
            address(externalEcdsaValidator),
            0
        );

        vm.deal(address(account), 1 ether);

        PackedUserOperation memory userOp;
        // Empty signature
        userOp.signature = bytes("");

        bytes32 userOpHash = keccak256("test");
        uint256 missingAccountFunds = 100;

        // Should return SIG_VALIDATION_FAILED for empty signature
        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED,
            "Empty signature should fail validation"
        );
    }

    function test_ValidateUserOp_MalformedKeyhashInSignature_ReturnsSigValidationFailed()
        public
    {
        vm.prank(_alice);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            aliceKeyHash,
            address(externalEcdsaValidator),
            0
        );

        vm.deal(address(account), 1 ether);

        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("test");

        // Use invalid keyHash (not registered)
        bytes32 invalidKeyHash = keccak256(abi.encodePacked(address(0xdead)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            invalidKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should return SIG_VALIDATION_FAILED (1 << 96)
        uint256 result = _testValidateUserOp(
            address(account),
            userOp,
            userOpHash,
            missingAccountFunds
        );
        assertEq(result, 1 << 96);
    }

    function test_RevertWhen_ExternalValidator_Reverts() public {
        // Deploy a RevertingValidator that always reverts
        RevertingValidator revertingValidator = new RevertingValidator();

        // Add the reverting validator
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            address(revertingValidator),
            settings
        );

        // Create a BatchedCall and try to execute with the reverting validator
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        // Create signature data - the actual signature doesn't matter since validator will revert
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, 0, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, hash);
        bytes memory validatorData = abi.encodePacked(
            keyHash,
            uint48(0), // validUntil (0 means no expiry)
            r,
            s,
            v
        );

        // The transaction should revert with InvalidSignature because the validator reverts
        // and _validateSignature returns false when external validator reverts
        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(relayer);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExternalValidator_ReturnsFalse() public {
        // Deploy a MockValidator and set it to return false
        MockValidator testMockValidator = new MockValidator();
        testMockValidator.setValidationResult(false);

        // Add the mock validator
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            address(testMockValidator),
            settings
        );

        // Create a BatchedCall and try to execute with the failing validator
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        // Create signature data
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, 0, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, hash);
        bytes memory validatorData = abi.encodePacked(
            keyHash,
            uint48(0), // validUntil (0 means no expiry)
            r,
            s,
            v
        );

        // The transaction should revert with InvalidSignature because validator returns false
        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(relayer);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_AddOwner_NotFromSelfForDirectCall() public {
        bytes32 newKeyHash = keccak256(abi.encodePacked(makeAddr("newOwner")));
        address newValidator = Static.ECDSA_VALIDATOR_ADDRESS;
        uint256 newSettings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );

        // Test 1: Direct call from external address should revert with NotFromSelf
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        OwnerManager(_aliceWallet).addOwner(
            newKeyHash,
            newValidator,
            newSettings
        );

        // Test 2: Direct call from owner (Alice) should also revert with NotFromSelf
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        OwnerManager(_aliceWallet).addOwner(
            newKeyHash,
            newValidator,
            newSettings
        );

        // Verify owner was not added
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(newKeyHash));
    }

    function test_RevertWhen_UpdateOwner_NotFromSelfForDirectCall() public {
        // First add an owner to update (through execute)
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );

        // Now try to update it directly
        address newValidator = Static.PASSKEY_VALIDATOR_ADDRESS;
        uint256 newSettings = OwnerManager(_aliceWallet).packSettings(
            true,
            0,
            address(0)
        );

        // Test 1: Direct call from external address should revert with NotFromSelf
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        OwnerManager(_aliceWallet).updateOwner(
            keyHash,
            newValidator,
            newSettings
        );

        // Test 2: Direct call from owner (Alice) should also revert with NotFromSelf
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        OwnerManager(_aliceWallet).updateOwner(
            keyHash,
            newValidator,
            newSettings
        );

        // Verify owner was not updated
        assertEq(
            _getValidatorFromSettings(IOwnerManager(_aliceWallet), keyHash),
            Static.ECDSA_VALIDATOR_ADDRESS
        );
    }
}
