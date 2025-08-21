// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/SmartWallet.sol";
import "src/interfaces/IOwnersManager.sol";
import "src/ValidationLogic.sol";
import "src/Types.sol";

/// @title CreateDeployFactory
/// @notice A script for creating a deploy factory
contract InitializeTemplate is Script {
    function run() external {
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(senderPk);

        address smartWallet = vm.envAddress("SMART_WALLET");
        InitialOwner[] memory emptyInitialOwners;
        SmartWallet(payable(smartWallet)).initialize(emptyInitialOwners);

        console.log("Completed InitializeTemplate script");
        vm.stopBroadcast();
    }
}
