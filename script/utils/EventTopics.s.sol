// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IAllowanceManager} from "src/interfaces/IAllowanceManager.sol";
import {ISmartWalletFactory} from "src/interfaces/ISmartWalletFactory.sol";

/// @title EventTopics
/// @notice A script for printing the event topics of all contract events
contract EventTopics is Script {
    function run() external pure {
        // IOwnerManager events
        console.log("\n=== IOwnerManager Events ===");
        console.log("OwnerAdded:");
        console.logBytes32(IOwnerManager.OwnerAdded.selector);
        console.log("OwnerRemoved:");
        console.logBytes32(IOwnerManager.OwnerRemoved.selector);
        console.log("OwnerUpdated:");
        console.logBytes32(IOwnerManager.OwnerUpdated.selector);

        // INonceManager events
        console.log("\n=== INonceManager Events ===");
        console.log("NonceConsumed:");
        console.logBytes32(INonceManager.NonceConsumed.selector);

        // IAllowanceManager events
        console.log("\n=== IAllowanceManager Events ===");
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

        // ISmartWallet events
        console.log("\n=== ISmartWallet Events ===");
        console.log("WalletInitialized:");
        console.logBytes32(ISmartWallet.WalletInitialized.selector);
        console.log("ExecuteSuccessEvent:");
        console.logBytes32(ISmartWallet.ExecuteSuccessEvent.selector);

        // ISmartWalletFactory events
        console.log("\n=== ISmartWalletFactory Events ===");
        console.log("AccountCreated:");
        console.logBytes32(ISmartWalletFactory.AccountCreated.selector);
    }
}
