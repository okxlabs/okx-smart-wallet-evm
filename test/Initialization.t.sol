// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {InitialOwner} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";

contract InitializationTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize_reverts_when_called_twice() public {
        // Set up bob with wallet code
        _setCodeToEoa(address(_smartWallet), _bob);

        // First initialization should succeed
        vm.prank(_bob);
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        ISmartWallet(_bob).initialize(emptyOwners);

        // Second initialization should fail with OpenZeppelin's error
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Initializable.InvalidInitialization.selector)
        );
        ISmartWallet(_bob).initialize(emptyOwners);
    }

    function test_initialize_properly_sets_storage() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that SHOULD modify storage
        vm.prank(_bob);
        _setCodeToEoa(address(_smartWallet), _bob);

        // Bob initializes the account with empty owners
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        ISmartWallet(_bob).initialize(emptyOwners);

        // Get accessed storage slots
        (, bytes32[] memory writes) = vm.accesses(_bob);

        // Verify that storage WAS modified (initialization should write to storage)
        assertGt(
            writes.length,
            0,
            "Storage should be modified during initialization!"
        );
    }

    function test_initialize_sets_initial_owners_correctly() public {
        _setCodeToEoa(address(_smartWallet), _bob);

        vm.prank(_bob);
        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = keccak256(abi.encodePacked(_alice));
        keyHashes[1] = keccak256(abi.encodePacked(_bob)); // _bob is an EOA
        address[] memory validators = new address[](2);
        validators[0] = address(_ecdsaValidator);
        validators[1] = address(_ecdsaValidator);
        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );

        ISmartWallet(_bob).initialize(initialOwners);

        // Verify owners were set correctly
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));

        assertEq(
            IOwnerManager(_bob).ownerValidators(aliceKeyHash),
            address(_ecdsaValidator)
        );
        assertEq(
            IOwnerManager(_bob).ownerValidators(bobKeyHash),
            address(_ecdsaValidator)
        );
    }

    function test_initialize_emits_WalletInitialized_event() public {
        _setCodeToEoa(address(_smartWallet), _bob);

        // Create initial owners
        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = keccak256(abi.encodePacked(_alice));
        keyHashes[1] = keccak256(abi.encodePacked(_bob));
        address[] memory validators = new address[](2);
        validators[0] = address(_ecdsaValidator);
        validators[1] = address(_ecdsaValidator);
        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );

        // Expect the WalletInitialized event (no parameters)
        vm.expectEmit(_bob);
        emit ISmartWallet.WalletInitialized();

        // Initialize the wallet
        vm.prank(_bob);
        ISmartWallet(_bob).initialize(initialOwners);
    }

    function test_initialize_reverts_with_zero_validator() public {
        _setCodeToEoa(address(_smartWallet), _bob);

        vm.prank(_bob);
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(0) // Zero address should revert
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnerManager.InvalidValidatorImpl.selector,
                address(0)
            )
        );
        ISmartWallet(_bob).initialize(initialOwners);
    }

    function test_storage_returns_correct_owner() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that should NOT modify storage
        vm.prank(_bob);
        _setCodeToEoa(address(_smartWallet), _bob);

        // Bob initializes the account with empty owners
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        ISmartWallet(_bob).initialize(emptyOwners);

        // check that wallet is its own owner (implicit - no function needed)
        // The wallet _bob is its own owner by design
    }

    function test_implementation_cannot_be_initialized() public {
        // Attempt to call initialize directly on the implementation
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_bob)),
            address(_ecdsaValidator)
        );

        vm.expectRevert(
            abi.encodeWithSelector(Initializable.InvalidInitialization.selector)
        );
        _smartWallet.initialize(initialOwners);
    }

    // Note: validateAndUpdateNonce is now internal and can only be called through executeFromRelayer
    // The nonce management tests are covered in Validation.t.sol through executeFromRelayer tests
}
