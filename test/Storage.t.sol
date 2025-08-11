// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";

contract StorageTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_EIP712_name_too_long() public {
        vm.expectRevert(Errors.NameTooLong.selector);
        new WalletCore(
            address(_storageImpl),
            "wallet-core-with-a-very-long-name-that-exceeds-32-bytes",
            "1.0.0"
        );
    }

    function test_EIP712_version_too_long() public {
        vm.expectRevert(Errors.VersionTooLong.selector);
        new WalletCore(
            address(_storageImpl),
            "wallet-core",
            "1.0.0-with-a-very-long-version-that-exceeds-32-bytes"
        );
    }

    function test_initialize_reverts_when_called_twice() public {
        vm.prank(_alice);
        vm.expectCall(_alice, abi.encodeCall(IWalletCore.initialize, ()));
        IWalletCore(_alice).initialize();
    }

    function test_walletCore_does_not_modify_storage() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that should NOT modify storage
        vm.prank(_bob);
        _setCodeToEOA(address(_walletCore), _bob);

        // Bob initializes the account
        IWalletCore(_bob).initialize();

        // Get accessed storage slots
        (, bytes32[] memory writes) = vm.accesses(_bob);

        // Verify that NO storage writes occurred
        assertEq(writes.length, 0, "Storage should not be modified!");
    }

    function test_storage_returns_correct_owner() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that should NOT modify storage
        vm.prank(_bob);
        _setCodeToEOA(address(_walletCore), _bob);

        // Bob initializes the account
        IWalletCore(_bob).initialize();

        // check owner in Storage
        vm.prank(_bob);
        address owner = IStorage(WalletCore(payable(_bob)).getMainStorage())
            .getOwner();
        assertEq(owner, _bob, "invalid owner");
    }

    function test_readAndUpdateNonce_succeeds_for_owner() public {
        address storageAddress = address(
            WalletCore(payable(_alice)).getMainStorage()
        );
        uint256 nonceBefore = IStorage(storageAddress).getNonce();
        vm.prank(_alice);
        uint256 nonceUsed = IStorage(storageAddress).readAndUpdateNonce(
            address(1)
        );
        uint256 nonceAfter = IStorage(storageAddress).getNonce();
        assertEq(nonceBefore, nonceUsed);
        assertEq(nonceAfter, nonceBefore + 1);
    }

    function test_readAndUpdateNonce_reverts_for_non_owner() public {
        // Start tracking storage access
        vm.record();

        // Execute the function that should NOT modify storage
        _setCodeToEOA(address(_walletCore), _bob);

        vm.prank(_bob);
        IStorage aliceStorage = IStorage(
            WalletCore(payable(_alice)).getMainStorage()
        );
        vm.expectRevert(Errors.InvalidOwner.selector);
        aliceStorage.readAndUpdateNonce(address(1));
    }
}
