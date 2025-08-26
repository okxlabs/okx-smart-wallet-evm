// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Static} from "src/libraries/Static.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {IValidator} from "src/interfaces/IValidator.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";

contract ValidatorTest is Base {
    address internal _charlie;
    uint256 internal _charliePk;
    address internal _dave;
    uint256 internal _davePk;

    // External validators for testing
    ECDSAValidator internal externalEcdsaValidator;
    PasskeyValidator internal externalPasskeyValidator;
    MockValidator internal mockValidator;

    event OwnerAdded(address validator);
    event OwnerRemoved(bytes32 keyHash);
    event OwnerUpdated(bytes32 keyHash, address newValidator);
    error FailedDeployment();

    function setUp() public override {
        (_charlie, _charliePk) = makeAddrAndKey("charlie");
        (_dave, _davePk) = makeAddrAndKey("dave");
        super.setUp();

        // Deploy external validator contracts
        externalEcdsaValidator = new ECDSAValidator();
        externalPasskeyValidator = new PasskeyValidator();
        mockValidator = new MockValidator();
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
                OwnersManager.addOwner.selector,
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
        bytes32 keyHash = keccak256(abi.encodePacked(_aliceEOA));

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

        // Expect owner added event
        vm.expectEmit();
        emit OwnerAdded(charlieValidator);

        // Deploy and add validator using the helper
        _addValidator(_alice, _charlie);
    }

    function test_new_validator_can_validate_transactions() public {
        // Deploy and add validator using helper
        _addValidator(_alice, _charlie);

        Call[] memory calls = constructCallsData();

        // Relayer executes with Charlie signature
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _charlie,
            _charliePk,
            hash
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_validator_management_succeeds() public {
        // Alice already has a validator from initialization
        bytes32 keyHash = keccak256(abi.encodePacked(_aliceEOA));

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
        _setCodeToEOA(address(_smartWallet), newWallet);

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
        ISmartWallet(newWallet).initialize(initialOwners);

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
        _setCodeToEOA(address(_smartWallet), newWallet);

        // Initialize with empty array
        InitialOwner[] memory initialOwners = new InitialOwner[](0);

        vm.prank(newWallet);
        ISmartWallet(newWallet).initialize(initialOwners);

        // Should succeed without errors
        // No signers should be set
        bytes32 testKeyHash = keccak256(abi.encodePacked(_aliceEOA));
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
            abi.encodeWithSelector(OwnersManager.removeOwner.selector, keyHash)
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
                OwnersManager.removeOwner.selector,
                keyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        // Sign with non-admin signer (_bob)
        bytes memory signature = constructSignature(
            batchedCall,
            _alice,
            _bobPk
        );

        // Should revert with NonAdminSelfCall
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonAdminSelfCall.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, signature);
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
                OwnersManager.addOwner.selector,
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
        bytes memory signature = constructSignature(
            batchedCall,
            _alice,
            _bobPk
        );

        // Should revert with NonAdminSelfCall
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonAdminSelfCall.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, signature);
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
                OwnersManager.removeOwner.selector,
                keyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        // Sign with admin signer (default initial owner is admin)
        bytes memory signature = constructSignature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should succeed
        vm.expectEmit(true, true, true, true);
        emit OwnerRemoved(keyHash);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, signature);

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
                OwnersManager.updateOwner.selector,
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
        bytes memory signature = constructSignature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should succeed and emit event
        vm.expectEmit(true, true, true, true);
        emit OwnerUpdated(keyHash, Static.PASSKEY_VALIDATOR_ADDRESS);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, signature);

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
                OwnersManager.updateOwner.selector,
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

        bytes memory signature = constructSignature(
            batchedCall,
            _alice,
            _alicePk
        );

        // Should revert
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ValidatorNotFound.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, signature);
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
                OwnersManager.updateOwner.selector,
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

        bytes memory signature = constructSignature(
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
        ISmartWallet(_alice).executeWithRelayer(batchedCall, signature);
    }

    function test_getVerifiedValidator_no_fallback() public {
        // Test that there's no longer an EIP-7702 fallback
        // When keyHash equals keccak256(abi.encodePacked(address(this))), it should return address(0)

        // Create a new wallet to test cleanly
        (address newWallet, ) = makeAddrAndKey("newWallet");
        vm.deal(newWallet, 10 ether);
        _setCodeToEOA(address(_smartWallet), newWallet);

        // Initialize with empty owners
        vm.prank(newWallet);
        InitialOwner[] memory initialOwners = new InitialOwner[](0);
        ISmartWallet(newWallet).initialize(initialOwners);

        // Generate keyHash for wallet's own address using unified abi.encodePacked
        bytes32 selfKeyHash = keccak256(abi.encodePacked(newWallet));

        // This keyHash should NOT be a registered owner
        assertFalse(IOwnersManager(newWallet).hasOwner(selfKeyHash));

        // getVerifiedValidator should return address(0) (no fallback)
        address validator = IOwnersManager(newWallet).getVerifiedValidator(
            selfKeyHash
        );
        assertEq(validator, address(0));
    }

    function test_unified_encoding_design() public {
        // This test validates the unified abi.encodePacked design for all keyHash generation

        // Create a fresh wallet to test cleanly
        (address freshWallet, ) = makeAddrAndKey("freshWallet");
        vm.deal(freshWallet, 10 ether);
        _setCodeToEOA(address(_smartWallet), freshWallet);

        // Initialize with alice as admin so we can test adding the selfKeyHash
        vm.prank(freshWallet);
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_aliceEOA)),
            validator: address(_ecdsaValidator)
        });
        ISmartWallet(freshWallet).initialize(initialOwners);

        // Now both regular owners and EIP-7702 use the same encoding method
        bytes32 selfKeyHash = keccak256(abi.encodePacked(freshWallet));

        // This keyHash should NOT be a registered owner
        assertFalse(IOwnersManager(freshWallet).hasOwner(selfKeyHash));

        // Without fallback, should return address(0)
        address validator = IOwnersManager(freshWallet).getVerifiedValidator(
            selfKeyHash
        );
        assertEq(validator, address(0));

        // Test that we can add this same keyHash as a regular owner
        // Use executeWithRelayer with alice's signature since alice is admin
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: freshWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                selfKeyHash,
                address(_ecdsaValidator),
                OwnersManager(freshWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(freshWallet),
            expiry: 0
        });

        bytes memory signature = constructSignature(
            batchedCall,
            freshWallet,
            _alicePk
        );

        ISmartWallet(freshWallet).executeWithRelayer(batchedCall, signature);

        // Now it should be a registered owner
        assertTrue(IOwnersManager(freshWallet).hasOwner(selfKeyHash));

        // And getVerifiedValidator should return the registered validator
        address registeredValidator = IOwnersManager(freshWallet)
            .getVerifiedValidator(selfKeyHash);
        assertEq(registeredValidator, address(_ecdsaValidator));
    }

    // ============ External Validator Tests ============

    function test_external_ecdsa_validator_deployment() public view {
        assertEq(address(externalEcdsaValidator).code.length > 0, true);
    }

    function test_external_ecdsa_validator_integration() public {
        // Add charlie as validator using external ECDSA validator
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            charlieKeyHash,
            address(externalEcdsaValidator),
            false,
            0,
            address(0)
        );

        // Verify validator was added
        address addedValidator = IOwnersManager(_alice).ownerValidators(
            charlieKeyHash
        );
        assertEq(addedValidator, address(externalEcdsaValidator));

        // Test executing transaction with external validator
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, typedDataHash);

        bytes memory validatorData = abi.encodePacked(
            charlieKeyHash,
            abi.encodePacked(r, s, v)
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_mock_validator_integration_success() public {
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            charlieKeyHash,
            address(mockValidator),
            false,
            0,
            address(0)
        );

        mockValidator.setValidationResult(true);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes memory validatorData = abi.encodePacked(
            charlieKeyHash,
            "mock signature data"
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_mock_validator_integration_failure() public {
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            charlieKeyHash,
            address(mockValidator),
            false,
            0,
            address(0)
        );

        mockValidator.setValidationResult(false);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes memory validatorData = abi.encodePacked(
            charlieKeyHash,
            "mock signature data"
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    // ============ Edge Case Tests ============

    function test_validator_signature_boundaries() public {
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            charlieKeyHash,
            address(externalEcdsaValidator),
            false,
            0,
            address(0)
        );

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Test 1: Empty signature should fail
        bytes memory emptyValidatorData = abi.encodePacked(
            charlieKeyHash,
            bytes("")
        );
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
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
            oversizedSignature
        );
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
            batchedCall,
            oversizedValidatorData
        );

        // Test 3: Insufficient signature data should fail
        bytes memory insufficientValidatorData = abi.encodePacked(
            charlieKeyHash,
            bytes32(
                0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
            )
        );
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
            batchedCall,
            insufficientValidatorData
        );
    }

    function test_validator_invalid_keyhash() public {
        // Use zero keyHash (invalid)
        bytes32 invalidKeyHash = bytes32(0);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, typedDataHash);

        bytes memory validatorData = abi.encodePacked(
            invalidKeyHash, // Invalid keyHash
            abi.encodePacked(r, s, v)
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidKeyHash.selector,
                invalidKeyHash
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    // ============ UserOp Edge Case Tests ============

    function test_validateUserOp_signature_too_short() public {
        vm.prank(_alice);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: aliceKeyHash,
            validator: address(externalEcdsaValidator)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(address(account), 1 ether);

        PackedUserOperation memory userOp;
        // Signature too short (less than 32 bytes)
        userOp.signature = abi.encodePacked(
            bytes16(0x1234567890abcdef1234567890abcdef)
        );

        bytes32 userOpHash = keccak256("test");
        uint256 missingAccountFunds = 100;

        // Should revert due to array bounds error when trying to access signature[0:32]
        vm.expectRevert();
        _testValidateUserOp(
            address(account),
            userOp,
            userOpHash,
            missingAccountFunds
        );
    }

    function test_validateUserOp_empty_signature() public {
        vm.prank(_alice);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: aliceKeyHash,
            validator: address(externalEcdsaValidator)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(address(account), 1 ether);

        PackedUserOperation memory userOp;
        // Empty signature
        userOp.signature = bytes("");

        bytes32 userOpHash = keccak256("test");
        uint256 missingAccountFunds = 100;

        // Should revert due to array bounds error when trying to access signature[0:32]
        vm.expectRevert();
        _testValidateUserOp(
            address(account),
            userOp,
            userOpHash,
            missingAccountFunds
        );
    }

    function test_validateUserOp_malformed_keyhash_in_signature() public {
        vm.prank(_alice);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: aliceKeyHash,
            validator: address(externalEcdsaValidator)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
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

    function test_external_validator_revert_returns_false() public {
        // Deploy a RevertingValidator that always reverts
        RevertingValidator revertingValidator = new RevertingValidator();

        // Add the reverting validator
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            address(revertingValidator),
            false,
            0,
            address(0)
        );

        // Create a BatchedCall and try to execute with the reverting validator
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: 0
        });

        // Create signature data - the actual signature doesn't matter since validator will revert
        bytes32 hash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, hash);
        bytes memory validatorData = abi.encodePacked(keyHash, r, s, v);

        // The transaction should revert with InvalidSignature because the validator reverts
        // and _validateSignature returns false when external validator reverts
        vm.expectRevert(Errors.InvalidSignature.selector);
        vm.prank(_alice);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_external_validator_returns_false() public {
        // Deploy a MockValidator and set it to return false
        MockValidator testMockValidator = new MockValidator();
        testMockValidator.setValidationResult(false);

        // Add the mock validator
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        _executeAddValidator(
            _alice,
            keyHash,
            address(testMockValidator),
            false,
            0,
            address(0)
        );

        // Create a BatchedCall and try to execute with the failing validator
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: 0
        });

        // Create signature data
        bytes32 hash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_charliePk, hash);
        bytes memory validatorData = abi.encodePacked(keyHash, r, s, v);

        // The transaction should revert with InvalidSignature because validator returns false
        vm.expectRevert(Errors.InvalidSignature.selector);
        vm.prank(_alice);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }
}

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
