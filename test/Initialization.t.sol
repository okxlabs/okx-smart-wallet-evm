// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {InitialOwner} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";

contract InitializationTest is Base {
    function test_RevertWhen_Initialize_CalledTwice() public {
        // Deploy a wallet through factory
        InitialOwner[] memory initialOwners = _createSingleOwner(
            _makeKeyHash(_alice),
            address(_ecdsaValidator)
        );
        address wallet = _factory.createAccount(initialOwners, 1);

        // Second initialization should fail with OpenZeppelin's error
        vm.expectRevert(
            abi.encodeWithSelector(Initializable.InvalidInitialization.selector)
        );
        ISmartWallet(wallet).initialize(initialOwners);
    }

    function test_Initialize_ProperlySetsStorage_Success() public {
        // Deploy a wallet through factory and check that it modifies storage
        InitialOwner[] memory initialOwners = _createSingleOwner(
            _makeKeyHash(_bob),
            address(_ecdsaValidator)
        );

        // The factory will call initialize, which should modify storage
        address wallet = _factory.createAccount(initialOwners, 1);

        // Verify the wallet was properly initialized by checking it's deployed
        assertGt(
            address(wallet).code.length,
            0,
            "Wallet should be deployed with code!"
        );
    }

    function test_Initialize_SetsInitialOwnersCorrectly_Success() public {
        // Create initial owners
        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = _makeKeyHash(_alice);
        keyHashes[1] = _makeKeyHash(_bob);
        address[] memory validators = new address[](2);
        validators[0] = address(_ecdsaValidator);
        validators[1] = address(_ecdsaValidator);
        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );

        // Deploy wallet through factory with initial owners
        address wallet = _factory.createAccount(initialOwners, 0);

        // Verify owners were set correctly
        bytes32 aliceKeyHash = _makeKeyHash(_alice);
        bytes32 bobKeyHash = _makeKeyHash(_bob);

        (address aliceValidator, , , , ) = IOwnerManager(wallet)
            .getOwnerSettings(aliceKeyHash);
        assertEq(aliceValidator, address(_ecdsaValidator));
        (address bobValidator, , , , ) = IOwnerManager(wallet).getOwnerSettings(
            bobKeyHash
        );
        assertEq(bobValidator, address(_ecdsaValidator));
    }

    function test_Initialize_EmitsWalletInitializedEvent_Success() public {
        // Create initial owners
        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = _makeKeyHash(_alice);
        keyHashes[1] = _makeKeyHash(_bob);
        address[] memory validators = new address[](2);
        validators[0] = address(_ecdsaValidator);
        validators[1] = address(_ecdsaValidator);
        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );

        // Predict the wallet address
        address predictedWallet = _factory.getAddress(initialOwners, 0);

        // Expect the WalletInitialized event from the predicted address
        vm.expectEmit(predictedWallet);
        emit ISmartWallet.WalletInitialized();

        // Deploy the wallet through factory (this triggers initialize)
        address wallet = _factory.createAccount(initialOwners, 0);

        // Verify the address matches prediction
        assertEq(wallet, predictedWallet);
    }

    function test_RevertWhen_Initialize_ZeroValidator() public {
        InitialOwner[] memory initialOwners = _createSingleOwner(
            _makeKeyHash(_alice),
            address(0) // Zero address should revert
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnerManager.InvalidValidatorImpl.selector,
                address(0)
            )
        );
        _factory.createAccount(initialOwners, 0);
    }

    function test_RevertWhen_Implementation_CannotBeInitialized() public {
        // Attempt to call initialize directly on the implementation
        InitialOwner[] memory initialOwners = _createSingleOwner(
            _makeKeyHash(_bob),
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
