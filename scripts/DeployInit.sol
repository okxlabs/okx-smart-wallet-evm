// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {DeployInitHelper} from "./DeployInitHelper.sol";
import {DeployFactory} from "src/test/DeployFactory.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {SmartWallet} from "src/SmartWallet.sol";

/// @title DeployInit
/// @notice A script for deploying, initializing, and setting the access controls
contract DeployInit is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address deployOwner = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        console.log("Deploy owner: %s", deployOwner);

        DeployFactory deployFactory = DeployFactory(
            vm.envAddress("DEPLOY_FACTORY_ADDRESS")
        );
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");
        console.log("Deploy factory address: %s", address(deployFactory));
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);

        string memory walletCoreName = "wallet-core";
        string memory walletCoreVersion = "1.0.0";
        console.log("WalletCore name: %s", walletCoreName);
        console.log("WalletCore version: %s", walletCoreVersion);

        (
            Storage storage_,
            ECDSAValidator ecdsaValidator_,
            WalletCore walletCore_
        ) = DeployInitHelper.deployContracts(
                deployFactory,
                deployFactorySalt,
                walletCoreName,
                walletCoreVersion
            );

        console.log("WalletCore address: %s", address(walletCore_));
        console.log("Storage address: %s", address(storage_));
        console.log("ECDSAValidator address: %s", address(ecdsaValidator_));
        console.log("Completed DeployInit script");
        vm.stopBroadcast();
    }
}
