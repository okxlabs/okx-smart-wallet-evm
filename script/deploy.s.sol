// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {IDeployFactory} from "./IDeployFactory.s.sol";
import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

/// @title DeployInit
/// @notice A script for deploying SmartWalletEntry and SmartWalletFactory via EIP-2470 Singleton Factory
contract DeployInit is Script {

    // EIP-2470 Singleton Factory — same address on all chains
    address constant DEPLOY_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        address deployOwner = vm.addr(deployerKey);
        console.log("Deployer: %s", deployOwner);
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);

        vm.startBroadcast(deployerKey);

        IDeployFactory deployFactory = IDeployFactory(DEPLOY_FACTORY);

        address payable smartWalletAddr = deployFactory.deploy(
            type(SmartWalletEntry).creationCode,
            deployFactorySalt
        );

        address payable factoryAddr = deployFactory.deploy(
            abi.encodePacked(
                type(SmartWalletFactory).creationCode,
                abi.encode(smartWalletAddr)
            ),
            deployFactorySalt
        );

        vm.stopBroadcast();

        console.log("=== Deployment Verification ===");
        require(
            SmartWalletFactory(factoryAddr).IMPLEMENTATION() == smartWalletAddr,
            "Factory implementation mismatch"
        );
        console.log("SmartWallet implementation address verified on SmartWalletFactory!");

        console.log("=== Deployment Summary ===");
        console.log("Deployer:", deployOwner);
        console.log("SmartWallet Implementation address:", smartWalletAddr);
        console.log("SmartWalletFactory address:", factoryAddr);
        console.log("DeployInit script completed successfully");
    }
}
