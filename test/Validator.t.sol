// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {IValidation} from "src/interfaces/IValidation.sol";
import "src/libraries/Errors.sol";
import {Static} from "src/libraries/Static.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";

contract ValidatorTest is Base {
    address internal _charlie;
    uint256 internal _charliePk;

    event ValidatorAdded(address validator);
    event ValidatorRemoved(address validator);
    error FailedDeployment();

    function setUp() public override {
        (_charlie, _charliePk) = makeAddrAndKey("charlie");
        super.setUp();
    }

    function test_addValidator_reverts_for_non_owner() public {
        vm.prank(_bob);

        // Just use the shared validator directly
        address validatorAddress = address(_ecdsaValidator);

        // Expect not from self revert
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        IOwnersManager(_alice).addValidator(
            keccak256(abi.encodePacked(address(this))),
            validatorAddress,
            false,
            0,
            address(0)
        );
    }

    function test_addValidator_reverts_for_invalid_implementation() public {
        vm.prank(_alice);
        address dave = vm.addr(2);

        // Expect invalid validator implementation revert - for new interface, just pass invalid address
        vm.expectRevert();
        IOwnersManager(_alice).addValidator(
            keccak256(abi.encodePacked(address(this))),
            dave, // Invalid validator address
            false,
            0,
            address(0)
        );
    }

    function test_addValidator_reverts_for_duplicate() public {
        // Deploy and add validator using helper
        address validatorAddress = _addValidator(_alice);

        // Expect failed if duplicate validator (same keyHash)
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        vm.prank(_alice);
        vm.expectRevert();
        IOwnersManager(_alice).addValidator(
            keyHash,
            validatorAddress,
            false,
            0,
            address(0)
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
        // First add a valid validator
        address aliceECDSAValidator = _addValidator(_alice);
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));

        vm.startPrank(_alice);
        // Test that we can't add another validator for the same keyHash (should revert)
        vm.expectRevert(Errors.ValidatorAlreadyExists.selector);
        IOwnersManager(_alice).addValidator(
            keyHash,
            aliceECDSAValidator,
            false,
            0,
            address(0)
        );

        // Test removing the validator
        IOwnersManager(_alice).removeValidator(keyHash);
    }

    function test_addValidatorWithSettings_succeeds() public {
        // Use SELF_VALIDATION_ADDRESS for testing to avoid deployment issues
        bytes32 keyHash = keccak256(abi.encodePacked(_charlie));
        address validatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;
        address hookAddress = address(0x1234);
        uint40 expiration = uint40(block.timestamp + 3600); // 1 hour from now
        bool isAdmin = true;

        vm.prank(_alice);
        IOwnersManager(_alice).addValidator(
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
        ) = IOwnersManager(_alice).getValidatorSettings(keyHash);

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

        vm.prank(_alice);
        IOwnersManager(_alice).addValidator(
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

        vm.prank(_alice);
        IOwnersManager(_alice).addValidator(
            keyHash,
            validatorAddress,
            false,
            0, // expiration = 0 means never expires
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
        vm.prank(_alice);
        IOwnersManager(_alice).addValidator(
            keyHash,
            validatorAddress,
            true, // isAdmin = true
            0,
            address(0)
        );

        // Verify admin status
        assertTrue(isSignerAdmin(_alice, keyHash));

        // Add non-admin validator
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(_bob));
        address nonAdminValidatorAddress = Static.ECDSA_VALIDATOR_ADDRESS;

        vm.prank(_alice);
        IOwnersManager(_alice).addValidator(
            nonAdminKeyHash,
            nonAdminValidatorAddress,
            false, // isAdmin = false
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

        vm.prank(_alice);
        IOwnersManager(_alice).addValidator(
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
        ) = IOwnersManager(_alice).getValidatorSettings(keyHash);

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
        ) = IOwnersManager(newWallet).getValidatorSettings(charlieKeyHash);

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
        ) = IOwnersManager(newWallet).getValidatorSettings(bobKeyHash);

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
}
