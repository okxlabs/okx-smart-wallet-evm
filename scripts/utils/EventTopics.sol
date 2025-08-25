// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IAllowanceManager} from "src/interfaces/IAllowanceManager.sol";
import {ISmartWalletFactory} from "src/interfaces/ISmartWalletFactory.sol";

/// @title EventTopics
/// @notice A script for printing the event topics of all contract events
contract EventTopics is Script {
    function run() external pure {
        // ISmartWallet events
        console.log("\n=== ISmartWallet Events ===");
        console.log("StorageInitialized:");
        console.logBytes32(ISmartWallet.StorageInitialized.selector);
        console.log("StorageCreated:");
        console.logBytes32(ISmartWallet.StorageCreated.selector);

        // IOwnersManager events
        console.log("\n=== IOwnersManager Events ===");
        console.log("OwnerAdded:");
        console.logBytes32(IOwnersManager.OwnerAdded.selector);
        console.log("OwnerRemoved:");
        console.logBytes32(IOwnersManager.OwnerRemoved.selector);
        console.log("OwnerUpdated:");
        console.logBytes32(IOwnersManager.OwnerUpdated.selector);

        // INonceManager events
        console.log("\n=== INonceManager Events ===");
        console.log("NonceConsumed:");
        console.logBytes32(INonceManager.NonceConsumed.selector);

        // IAllowanceManager events
        console.log("\n=== IAllowanceManager Events ===");
        console.log("ApproveNative:");
        console.logBytes32(IAllowanceManager.ApproveNative.selector);
        console.log("ApproveToken:");
        console.logBytes32(IAllowanceManager.ApproveToken.selector);
        console.log("TransferFromNative:");
        console.logBytes32(IAllowanceManager.TransferFromNative.selector);
        console.log("TransferFromToken:");
        console.logBytes32(IAllowanceManager.TransferFromToken.selector);
        console.log("NativeAllowanceUpdated:");
        console.logBytes32(IAllowanceManager.NativeAllowanceUpdated.selector);
        console.log("TokenAllowanceUpdated:");
        console.logBytes32(IAllowanceManager.TokenAllowanceUpdated.selector);

        // ISmartWalletFactory events
        console.log("\n=== ISmartWalletFactory Events ===");
        console.log("AccountCreated:");
        console.logBytes32(ISmartWalletFactory.AccountCreated.selector);
    }
}
