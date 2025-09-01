// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {DeployInitHelper} from "./DeployInitHelper.sol";
import {IDeployFactory} from "../utils/IDeployFactory.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

/// @title DeployInit
/// @notice A script for deploying, initializing, and setting the access controls
contract DeployInit is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address deployOwner = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        console.log("Deploy owner: %s", deployOwner);

        // Use the EIP-2470 Singleton Factory through the interface
        IDeployFactory deployFactory = IDeployFactory(
            vm.envAddress("DEPLOY_FACTORY_ADDRESS")
        );
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");
        console.log("Deploy factory address: %s", address(deployFactory));
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);

        // Deploy the contracts using DeployInitHelper
        (
            SmartWallet smartWallet_,
            SmartWalletFactory factory_
        ) = DeployInitHelper.deployContracts(deployFactory, deployFactorySalt);

        console.log("SmartWallet address: %s", address(smartWallet_));
        console.log("SmartWalletFactory address: %s", address(factory_));
        console.log("Completed DeployInit script");
        vm.stopBroadcast();
    }
}
