// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {IValidation} from "src/interfaces/IValidation.sol";
import "src/libraries/Errors.sol";
import {Static} from "src/libraries/Static.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";

contract ValidatorTest is Base {
    address internal _charlie;
    uint256 internal _charliePk;

    event ValidatorAdded(address validator);
    event ValidatorRemoved(bytes32 keyHash);
    event ValidatorUpdated(bytes32 keyHash, address newValidator);
    error FailedDeployment();

    function setUp() public override {
        (_charlie, _charliePk) = makeAddrAndKey("charlie");
        super.setUp();
    }

    function test_addValidator_reverts_for_non_owner() public {
        // Just use the shared validator directly
        address validatorAddress = address(_ecdsaValidator);

        // Pack settings before setting expectRevert
        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            0,
            address(0)
        );

        vm.prank(_bob);
        // Expect not from self revert when calling directly (not through execute)
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        (bool success, ) = _alice.call(
            abi.encodeWithSelector(
                OwnersManager.addValidator.selector,
                keccak256(abi.encodePacked(address(this))),
                validatorAddress,
                settings
            )
        );
        // Note: vm.expectRevert() already validates the call failed with the expected error
        success; // Silence unused variable warning
    }

    function test_addValidator_reverts_for_invalid_implementation() public {
        address dave = vm.addr(2);

        // Pack settings before setting expectRevert
        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            0,
            address(0)
        );

        // Expect invalid validator implementation revert when called through execute
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValidatorImpl.selector, dave)
        );
        _executeAddValidatorWithSettings(
            _alice,
            keccak256(abi.encodePacked(address(this))),
            dave,
            settings
        );
    }

    function test_addValidator_reverts_for_duplicate() public {
        // Alice already has a validator from initialization, try to add duplicate
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));

        // Verify Alice has the validator first
        assertTrue(IOwnersManager(_alice).hasOwner(keyHash));

        // Pack settings before setting expectRevert
        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            0,
            address(0)
        );

        vm.expectRevert(Errors.ValidatorAlreadyExists.selector);
        _executeAddValidatorWithSettings(
            _alice,
            keyHash,
            address(_ecdsaValidator),
            settings
        );
    }

    function test_validator_can_be_added() public {
        // Use the shared validator
        address charlieValidator = address(_ecdsaValidator);

        // Expect validator added event
        vm.expectEmit();
        emit ValidatorAdded(charlieValidator);

        // Deploy and add validator using the helper
        _addValidator(_alice, _charlie);
    }

    function test_new_validator_can_validate_transactions() public {
        // Deploy and add validator using helper
        _addValidator(_alice, _charlie);

        Call[] memory calls = _construct_calls_data();

        // Relayer executes with Charlie signature
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _charlie,
            _charliePk,
            hash
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        IWalletCore(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_validator_management_succeeds() public {
        // Alice already has a validator from initialization
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));

        // Pack settings before setting expectRevert
        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            0,
            address(0)
        );

        // Test that we can't add another validator for the same keyHash (should revert)
        vm.expectRevert(Errors.ValidatorAlreadyExists.selector);
        _executeAddValidatorWithSettings(
            _alice,
            keyHash,
            address(_ecdsaValidator),
            settings
        );

        // Test removing the validator
        _executeRemoveValidator(_alice, keyHash);
    }

    function test_addValidatorWithSettings_succeeds() public {
        // Use SELF_VALIDATION_ADDRESS for testing to avoid deployment issues
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        address hookAddress = address(0x1234);
        uint40 expiration = uint40(block.timestamp + 3600); // 1 hour from now
        bool isAdmin = true;

        _executeAddValidator(
            _alice,
            keyHash,
            validatorAddress,
            isAdmin,
            expiration,
            hookAddress
        );

        // Verify settings were stored correctly
        (
            address validator,
            address hook,
            uint40 storedExpiration,
            bool storedIsAdmin,
            bool isExpired
        ) = IOwnersManager(_alice).getOwnerSettings(keyHash);

        assertEq(validator, validatorAddress);
        assertEq(hook, hookAddress);
        assertEq(storedExpiration, expiration);
        assertTrue(storedIsAdmin);
        assertFalse(isExpired);
    }

    function test_validator_expiration_functionality() public {
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        uint40 expiration = uint40(block.timestamp + 1); // Expires in 1 second

        _executeAddValidator(
            _alice,
            keyHash,
            validatorAddress,
            false,
            expiration,
            address(0)
        );

        // Validator should be valid initially
        address retrievedValidator = IOwnersManager(_alice).ownerValidators(
            keyHash
        );
        assertEq(retrievedValidator, validatorAddress);
        assertFalse(isSignerExpired(_alice, keyHash));

        // Advance time past expiration
        vm.warp(block.timestamp + 2);

        // Validator should now be expired but ownerValidators still returns the address
        // Only getVerifiedValidator checks expiration
        retrievedValidator = IOwnersManager(_alice).ownerValidators(keyHash);
        assertEq(retrievedValidator, validatorAddress); // Still returns the address
        assertTrue(isSignerExpired(_alice, keyHash));
    }

    function test_permanent_validator_never_expires() public {
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        _executeAddValidator(
            _alice,
            keyHash,
            validatorAddress,
            false,
            0,
            address(0)
        );

        // Even after advancing time significantly, validator should remain valid
        vm.warp(block.timestamp + 365 days);

        address retrievedValidator = IOwnersManager(_alice).ownerValidators(
            keyHash
        );
        assertEq(retrievedValidator, validatorAddress);
        assertFalse(isSignerExpired(_alice, keyHash));
        assertEq(getSignerExpiration(_alice, keyHash), 0);
    }

    function test_admin_signer_functionality() public {
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        // Add admin validator
        _executeAddValidator(
            _alice,
            keyHash,
            validatorAddress,
            true,
            0,
            address(0)
        );

        // Verify admin status
        assertTrue(isSignerAdmin(_alice, keyHash));

        // Add non-admin validator
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        address nonAdminValidatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        _executeAddValidator(
            _alice,
            nonAdminKeyHash,
            nonAdminValidatorAddress,
            false,
            0,
            address(0)
        );

        // Verify non-admin status
        assertFalse(isSignerAdmin(_alice, nonAdminKeyHash));
    }

    function test_backward_compatibility_with_old_addValidator() public {
        // Test that old addValidator still works and has default settings
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        _executeAddValidator(
            _alice,
            keyHash,
            validatorAddress,
            false,
            0,
            address(0)
        );

        // Check that settings have default values
        (
            address validator,
            address hook,
            uint40 expiration,
            bool isAdmin,
            bool isExpired
        ) = IOwnersManager(_alice).getOwnerSettings(keyHash);

        assertEq(validator, validatorAddress);
        assertEq(hook, address(0)); // Default: no hook
        assertEq(expiration, 0); // Default: never expires
        assertFalse(isAdmin); // Default: not admin
        assertFalse(isExpired); // Default: not expired
    }

    function test_initialize_sets_admin_privileges_for_initial_owners() public {
        // Create a new wallet for this test
        (address newWallet, ) = makeAddrAndKey("newWallet");
        vm.deal(newWallet, 10 ether);
        _setCodeToEOA(address(_walletCore), newWallet);

        // Prepare initial owners with different keys
        InitialOwner[] memory initialOwners = new InitialOwner[](2);

        // First owner - Charlie
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        initialOwners[0] = InitialOwner({
            keyHash: charlieKeyHash,
            validator: Static.ECDSA_VALIDATOR_ADDRESS
        });

        // Second owner - Bob
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        initialOwners[1] = InitialOwner({
            keyHash: bobKeyHash,
            validator: Static.ECDSA_VALIDATOR_ADDRESS
        });

        // Initialize the wallet with initial owners
        vm.prank(newWallet);
        IWalletCore(newWallet).initialize(initialOwners);

        // Verify both initial owners have admin privileges
        assertTrue(isSignerAdmin(newWallet, charlieKeyHash));
        assertTrue(isSignerAdmin(newWallet, bobKeyHash));

        // Verify their settings
        (
            address charlieValidator,
            address charlieHook,
            uint40 charlieExpiration,
            bool charlieIsAdmin,
            bool charlieIsExpired
        ) = IOwnersManager(newWallet).getOwnerSettings(charlieKeyHash);

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
        ) = IOwnersManager(newWallet).getOwnerSettings(bobKeyHash);

        assertEq(bobValidator, Static.ECDSA_VALIDATOR_ADDRESS);
        assertEq(bobHook, address(0)); // No hook
        assertEq(bobExpiration, 0); // Never expires
        assertTrue(bobIsAdmin); // Admin privileges
        assertFalse(bobIsExpired); // Not expired
    }

    function test_initialize_with_empty_initial_owners() public {
        // Create a new wallet for this test
        (address newWallet, ) = makeAddrAndKey("emptyWallet");
        vm.deal(newWallet, 10 ether);
        _setCodeToEOA(address(_walletCore), newWallet);

        // Initialize with empty array
        InitialOwner[] memory initialOwners = new InitialOwner[](0);

        vm.prank(newWallet);
        IWalletCore(newWallet).initialize(initialOwners);

        // Should succeed without errors
        // No signers should be set
        bytes32 testKeyHash = keccak256(abi.encodePacked(_alice));
        assertEq(
            IOwnersManager(newWallet).ownerValidators(testKeyHash),
            address(0)
        );
        assertFalse(isSignerAdmin(newWallet, testKeyHash));
    }

    function test_removeValidator_reverts_for_non_owner() public {
        // First add a validator to remove
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false,
            0,
            address(0)
        );

        // Try to call removeValidator directly from external address (not through execute)
        vm.prank(_bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        (bool success, ) = _alice.call(
            abi.encodeWithSelector(
                OwnersManager.removeValidator.selector,
                keyHash
            )
        );
        // Note: vm.expectRevert() already validates the call failed with the expected error
        success; // Silence unused variable warning
    }

    function test_removeValidator_reverts_for_non_admin() public {
        // Add a validator first (using admin)
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false,
            0,
            address(0)
        );

        // Add a non-admin signer - use the correct keyHash for _bob's address
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        _executeAddValidator(
            _alice,
            nonAdminKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false, // not admin
            0,
            address(0)
        );

        // Create a BatchedCall to remove validator using non-admin signer
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeValidator.selector,
                keyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        // Sign with non-admin signer (_bob)
        bytes memory signature = _construct_signature(
            batchedCall,
            _alice,
            _bobPk
        );

        // Should revert with NonAdminSelfCall
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonAdminSelfCall.selector)
        );
        IWalletCore(_alice).executeWithRelayer(batchedCall, signature);
    }

    function test_addValidator_reverts_for_non_admin() public {
        // Add a non-admin signer - use the correct keyHash for _bob's address
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        _executeAddValidator(
            _alice,
            nonAdminKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false, // not admin
            0,
            address(0)
        );

        // Create a BatchedCall to add another validator using non-admin signer
        bytes32 newKeyHash = keccak256(abi.encodePacked(_charlie));
        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            uint40(0),
            address(0)
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addValidator.selector,
                newKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                settings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        // Sign with non-admin signer (_bob)
        bytes memory signature = _construct_signature(
            batchedCall,
            _alice,
            _bobPk
        );

        // Should revert with NonAdminSelfCall
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonAdminSelfCall.selector)
        );
        IWalletCore(_alice).executeWithRelayer(batchedCall, signature);
    }

    function test_removeValidator_succeeds_for_admin() public {
        // First add a validator to remove
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false,
            0,
            address(0)
        );

        // Verify validator exists
        assertEq(
            IOwnersManager(_alice).ownerValidators(keyHash),
            Static.ECDSA_VALIDATOR_ADDRESS
        );

        // Create a BatchedCall to remove validator using admin signer
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeValidator.selector,
                keyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        // Sign with admin signer (default initial owner is admin)
        bytes memory signature = _construct_signature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should succeed
        vm.expectEmit(true, true, true, true);
        emit ValidatorRemoved(keyHash);
        IWalletCore(_alice).executeWithRelayer(batchedCall, signature);

        // Verify validator is removed
        assertEq(IOwnersManager(_alice).ownerValidators(keyHash), address(0));
    }

    function test_updateValidator_succeeds() public {
        // First add a validator to update
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false,
            0,
            address(0)
        );

        // Verify initial validator
        assertEq(
            IOwnersManager(_alice).ownerValidators(keyHash),
            Static.ECDSA_VALIDATOR_ADDRESS
        );

        // Create new settings
        uint256 newSettings = OwnersManager(_alice).packSettings(
            true,
            uint40(block.timestamp + 3600),
            address(0)
        );

        // Create a BatchedCall to update validator
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateValidator.selector,
                keyHash,
                Static.PASSKEY_VALIDATOR_ADDRESS,
                newSettings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        // Sign with admin signer
        bytes memory signature = _construct_signature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should succeed and emit event
        vm.expectEmit(true, true, true, true);
        emit ValidatorUpdated(keyHash, Static.PASSKEY_VALIDATOR_ADDRESS);
        IWalletCore(_alice).executeWithRelayer(batchedCall, signature);

        // Verify validator is updated
        assertEq(
            IOwnersManager(_alice).ownerValidators(keyHash),
            Static.PASSKEY_VALIDATOR_ADDRESS
        );
        assertEq(IOwnersManager(_alice).ownerSettings(keyHash), newSettings);
    }

    function test_updateValidator_reverts_for_non_existent_keyHash() public {
        bytes32 nonExistentKeyHash = keccak256(abi.encodePacked("nonexistent"));
        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            0,
            address(0)
        );

        // Create a BatchedCall to update non-existent validator
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateValidator.selector,
                nonExistentKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                settings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        bytes memory signature = _construct_signature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should revert
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ValidatorNotFound.selector)
        );
        IWalletCore(_alice).executeWithRelayer(batchedCall, signature);
    }

    function test_updateValidator_reverts_for_invalid_validator() public {
        // First add a validator to update
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            false,
            0,
            address(0)
        );

        uint256 settings = OwnersManager(_alice).packSettings(
            false,
            0,
            address(0)
        );

        // Create a BatchedCall to update with invalid validator (EOA with no code)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateValidator.selector,
                keyHash,
                _charlie, // EOA address with no code
                settings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        bytes memory signature = _construct_signature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValidatorImpl.selector,
                _charlie
            )
        );
        IWalletCore(_alice).executeWithRelayer(batchedCall, signature);
    }
}
