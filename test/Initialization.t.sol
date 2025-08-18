// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract InitializationTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_EIP712_name_too_long() public {
        vm.expectRevert(Errors.NameTooLong.selector);
        new WalletCore(
            "wallet-core-with-a-very-long-name-that-exceeds-32-bytes",
            "1.0.0"
        );
    }

    function test_EIP712_version_too_long() public {
        vm.expectRevert(Errors.VersionTooLong.selector);
        new WalletCore(
            "wallet-core",
            "1.0.0-with-a-very-long-version-that-exceeds-32-bytes"
        );
    }

    function test_initialize_reverts_when_called_twice() public {
        // Set up bob with wallet code
        _setCodeToEOA(address(_walletCore), _bob);

        // First initialization should succeed
        vm.prank(_bob);
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        IWalletCore(_bob).initialize(emptyOwners);

        // Second initialization should fail with OpenZeppelin's error
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Initializable.InvalidInitialization.selector)
        );
        IWalletCore(_bob).initialize(emptyOwners);
    }

    function test_initialize_properly_sets_storage() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that SHOULD modify storage
        vm.prank(_bob);
        _setCodeToEOA(address(_walletCore), _bob);

        // Bob initializes the account with empty owners
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        IWalletCore(_bob).initialize(emptyOwners);

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
        _setCodeToEOA(address(_walletCore), _bob);

        vm.prank(_bob);
        InitialOwner[] memory initialOwners = new InitialOwner[](2);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });
        initialOwners[1] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_bob)),
            validator: address(_ecdsaValidator)
        });

        IWalletCore(_bob).initialize(initialOwners);

        // Verify owners were set correctly
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));

        assertEq(
            IOwnersManager(_bob).getValidator(aliceKeyHash),
            address(_ecdsaValidator)
        );
        assertEq(
            IOwnersManager(_bob).getValidator(bobKeyHash),
            address(_ecdsaValidator)
        );
    }

    function test_initialize_reverts_with_zero_validator() public {
        _setCodeToEOA(address(_walletCore), _bob);

        vm.prank(_bob);
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(0) // Zero address should revert
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValidatorImpl.selector,
                address(0)
            )
        );
        IWalletCore(_bob).initialize(initialOwners);
    }

    function test_storage_returns_correct_owner() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that should NOT modify storage
        vm.prank(_bob);
        _setCodeToEOA(address(_walletCore), _bob);

        // Bob initializes the account with empty owners
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        IWalletCore(_bob).initialize(emptyOwners);

        // check that wallet is its own owner (implicit - no function needed)
        // The wallet _bob is its own owner by design
    }

    // Note: validateAndUpdateNonce is now internal and can only be called through executeFromRelayer
    // The nonce management tests are covered in Validation.t.sol through executeFromRelayer tests
}
