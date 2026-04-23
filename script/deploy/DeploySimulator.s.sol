// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {IDeployFactory} from "./IDeployFactory.s.sol";
import {SimulatePasskeyValidator} from "script/estimategas/SimulatePasskeyValidator.sol";
import {SimulateECDSAValidator} from "script/estimategas/SimulateECDSAValidator.sol";
import {SmartWalletSimulator} from "script/estimategas/SmartWalletSimulator.sol";

/// @title DeployInit
/// @notice A script for deploying, initializing, and setting the access controls
contract DeploySimulator is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address deployOwner = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        console.log("Deploy owner: %s", deployOwner);

        // Use the fixed EIP-2470 Singleton Factory through the interface
        // address is uniform across all chains
        IDeployFactory deployFactory = IDeployFactory(
            0xFaC897544659Fb136C064d5428947f5BC9cC1Fa2
        );
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");
        console.log("Deploy factory address: %s", address(deployFactory));
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);

        // Deploy the contracts using DeployInitHelper
        // deploy SmartWallet
        address simulateECDSAValidator = deployFactory.deploy(
            type(SimulateECDSAValidator).creationCode,
            deployFactorySalt
        );

        address simulatePasskeyValidator = deployFactory.deploy(
            type(SimulatePasskeyValidator).creationCode,
            deployFactorySalt
        );
        
        address smartWalletSimulator = deployFactory.deploy(
            abi.encodePacked(
                type(SmartWalletSimulator).creationCode,
                abi.encode(simulateECDSAValidator, simulatePasskeyValidator)
            ),
            deployFactorySalt
        );

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("=== Deployment Verification ===");
        
        // Log deployment summary for verification commands
        console.log("=== Deployment Summary ===");
        console.log("Deployer:", deployOwner);
        console.log("simulateECDSAValidator:", simulateECDSAValidator);
        console.log("simulatePasskeyValidator:", simulatePasskeyValidator);
        console.log("smartWalletSimulator:", smartWalletSimulator);
        
        console.log("DeployInit script completed successfully");
    }
}
