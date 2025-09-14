// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {DeployInitHelper} from "./DeployInitHelper.s.sol";
import {IDeployFactory} from "../utils/IDeployFactory.s.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {SmartWalletSimulator} from "../utils/SmartWalletSimulator.s.sol";

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
            SmartWalletFactory factory_,
            SmartWalletSimulator simulator_
        ) = DeployInitHelper.deployContracts(deployFactory, deployFactorySalt);

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("=== Deployment Verification ===");
        require(factory_.IMPLEMENTATION() == address(smartWallet_), "Factory implementation not set correctly");
        console.log("SmartWallet implementation address verified on SmartWalletFactory!");
        
        // Log deployment summary for verification commands
        console.log("=== Deployment Summary ===");
        console.log("Deployer:", deployOwner);
        console.log("SmartWallet Implementation address:", address(smartWallet_));
        console.log("SmartWalletFactory address:", address(factory_));
        console.log("SmartWalletSimulator address:", address(simulator_));
        console.log("DeployInit script completed successfully");
    }
}
