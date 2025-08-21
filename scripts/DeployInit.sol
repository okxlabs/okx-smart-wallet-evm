// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {DeployInitHelper} from "./DeployInitHelper.sol";
import {DeployFactory} from "src/test/DeployFactory.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {WalletCore} from "src/WalletCore.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

/// @title DeployInit
/// @notice A script for deploying, initializing, and setting the access controls
contract DeployInit is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address deployOwner = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        console.log("Deploy owner: %s", deployOwner);

        // Deploy the DeployFactory first
        DeployFactory deployFactory = new DeployFactory();
        bytes32 deployFactorySalt = bytes32(uint256(0x120)); // Use a default salt
        console.log("Deploy factory address: %s", address(deployFactory));
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);

        // Deploy the contracts using DeployInitHelper
        (
            ECDSAValidator ecdsaValidator_,
            WalletCore walletCore_,
            SmartWalletFactory smartWalletFactory_
        ) = DeployInitHelper.deployContracts(
                deployFactory,
                deployFactorySalt
            );

        console.log("WalletCore address: %s", address(walletCore_));
        console.log("ECDSAValidator address: %s", address(ecdsaValidator_));
        console.log("SmartWalletFactory address: %s", address(smartWalletFactory_));
        console.log("Completed DeployInit script");
        vm.stopBroadcast();
    }
}
