// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {DeployInitHelper} from "./DeployInitHelper.sol";
import {DeployFactory} from "src/test/DeployFactory.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

/// @title DeployInit
/// @notice A script for deploying, initializing, and setting the access controls
contract DeployInit is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address deployOwner = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        console.log("Deploy owner: %s", deployOwner);

        // Create a new DeployFactory for local testing instead of using pre-deployed one
        DeployFactory deployFactory = new DeployFactory();
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");
        console.log("Deploy factory address: %s", address(deployFactory));
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);

        string memory smartWalletName = "smart-wallet";
        string memory smartWalletVersion = "1.0.0";
        console.log("SmartWallet name: %s", smartWalletName);
        console.log("SmartWallet version: %s", smartWalletVersion);

        // Deploy the contracts using DeployInitHelper
        (
            ECDSAValidator ecdsaValidator_,
            SmartWallet smartWallet_,
            SmartWalletFactory factory_
        ) = DeployInitHelper.deployContracts(
                deployFactory,
                deployFactorySalt
            );

        console.log("SmartWallet address: %s", address(smartWallet_));
        console.log("SmartWalletFactory address: %s", address(factory_));
        console.log("ECDSAValidator address: %s", address(ecdsaValidator_));
        console.log("Completed DeployInit script");
        vm.stopBroadcast();
    }
}
