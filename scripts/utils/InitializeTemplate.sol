// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/WalletCore.sol";
import "src/interfaces/IStorage.sol";
import "src/ValidationLogic.sol";
import "src/Types.sol";

/// @title CreateDeployFactory
/// @notice A script for creating a deploy factory
contract InitializeTemplate is Script {
    function run() external {
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(senderPk);

        address walletCore = vm.envAddress("WALLET_CORE");
        WalletCore(payable(walletCore)).initialize();

        console.log("Completed InitializeTemplate script");
        vm.stopBroadcast();
    }
}
