// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {IWalletCore} from "src/interfaces/IWalletCore.sol";

/// @title EventTopics
/// @notice A script for printing the event topics of a contract
contract EventTopics is Script {
    function run() external pure {
        console.log("Event topics StorageInitialized:");
        console.logBytes32(IWalletCore.StorageInitialized.selector);

        console.log("Event topics StorageCreated:");
        console.logBytes32(IWalletCore.StorageCreated.selector);
    }
}
