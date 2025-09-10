// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {InitialOwner} from "src/Types.sol";

/// @title SetCodeAndInitialize
/// @notice A script for setting code on EOA using EIP-7702 and initializing the SmartWallet
contract SetCodeAndInitialize is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address smartWalletImpl = vm.envAddress("SMART_WALLET");

        vm.startBroadcast(deployerPk);

        address deployer = vm.addr(deployerPk);
        console.log("EOA address: ", deployer);
        console.log(
            "Setting code for EIP7702 account with implementation: ",
            smartWalletImpl
        );

        // Sign and attach delegation to set the EOA's code to the SmartWallet implementation
        // This combines signing the EIP-7702 authorization and attaching it in one step
        vm.signAndAttachDelegation(smartWalletImpl, deployerPk);

        // Now the EOA has the SmartWallet code, initialize it with empty owners
        InitialOwner[] memory initialOwners = new InitialOwner[](0);
        ISmartWallet(deployer).initialize(initialOwners);

        console.log("SmartWallet initialized successfully");

        // Verify the code was set
        bytes memory code = deployer.code;
        console.log("EOA code length after delegation: ", code.length);

        vm.stopBroadcast();
    }
}
