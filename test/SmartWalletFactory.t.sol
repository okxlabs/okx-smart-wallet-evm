// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";

contract FactoryTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_create_wallet_with_factory() external {
        vm.prank(_alice);

        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(1)
        });
        ISmartWallet wallet = ISmartWallet(
            _factory.createAccount(address(_smartWallet), initialOwners, 0)
        );

        assertEq(
            IOwnersManager(address(wallet)).hasOwner(
                keccak256(abi.encodePacked(_alice))
            ),
            true
        );
    }

    function test_predict_address() external {
        vm.prank(_alice);

        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(1)
        });
        address wallet = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        address predictedAddress = _factory.getAddress(
            address(_smartWallet),
            initialOwners,
            0
        );

        assertEq(wallet, predictedAddress);
    }
}
