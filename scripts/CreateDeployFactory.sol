// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {DeployFactory} from "src/test/DeployFactory.sol";

/// @title CreateDeployFactory
/// @notice A script for creating a deploy factory
contract CreateDeployFactory is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address deployOwner = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeployFactory deployFactory = new DeployFactory();

        console.log("Deploy owner: %s", deployOwner);
        console.log("Deploy factory address: %s", address(deployFactory));
        console.log("Completed DeployFactory script");
        vm.stopBroadcast();
    }
}
