// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";

/// @title EventTopics
/// @notice A script for printing the event topics of a contract
contract EventTopics is Script {
    function run() external pure {
        console.log("Event topics StorageInitialized:");
        console.logBytes32(ISmartWallet.StorageInitialized.selector);

        console.log("Event topics StorageCreated:");
        console.logBytes32(ISmartWallet.StorageCreated.selector);
    }
}
