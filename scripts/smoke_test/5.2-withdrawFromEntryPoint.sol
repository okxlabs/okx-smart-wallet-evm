// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IStakeManager} from "account-abstraction/interfaces/IStakeManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call} from "src/Types.sol";

/// @title WithdrawFromEntryPoint
/// @notice A script for withdrawing funds from EntryPoint for a SmartWallet account
contract WithdrawFromEntryPoint is Script {
    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    function run() external {
        // Get user wallet address from environment
        address payable userWallet = payable(vm.envAddress("USER_WALLET"));
        
        // Get deployer private key for broadcasting
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        
        vm.startBroadcast(deployerPk);
        
        console.log("=== EntryPoint Withdrawal Script ===");
        console.log("User wallet: ", userWallet);
        console.log("Caller (deployer): ", deployer);
        console.log("EntryPoint address: ", ENTRYPOINT_ADDRESS);
        
        // Get EntryPoint instance
        IEntryPoint entryPoint = IEntryPoint(ENTRYPOINT_ADDRESS);
        
        // Check current balance before withdrawal
        uint256 balanceBefore = entryPoint.balanceOf(userWallet);
        console.log("\nCurrent EntryPoint balance: ", balanceBefore, "wei");
        
        if (balanceBefore == 0) {
            console.log("No funds to withdraw from EntryPoint");
            vm.stopBroadcast();
            return;
        }
        
        // Calculate withdrawal amount (withdraw all funds)
        uint256 withdrawAmount = balanceBefore;
        console.log("Withdrawing: ", withdrawAmount, "wei");
        
        // Create the withdrawal call data
        // The SmartWallet will call EntryPoint.withdrawTo() 
        bytes memory withdrawCallData = abi.encodeWithSelector(
            IStakeManager.withdrawTo.selector,
            payable(userWallet), // withdraw to the wallet itself
            withdrawAmount
        );
        
        // Create Call struct for SmartWallet.execute
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: ENTRYPOINT_ADDRESS,
            value: 0,
            data: withdrawCallData
        });
        
        // Execute the withdrawal through SmartWallet
        // This requires the deployer to be an owner of the SmartWallet
        console.log("Executing withdrawal through SmartWallet...");
        ISmartWallet(userWallet).execute(calls);
        
        // Check balance after withdrawal
        uint256 balanceAfter = entryPoint.balanceOf(userWallet);
        console.log("\nNew EntryPoint balance: ", balanceAfter, "wei");
        console.log("Successfully withdrawn: ", balanceBefore - balanceAfter, "wei");
        
        // Check the wallet's ETH balance to confirm receipt
        uint256 walletBalance = userWallet.balance;
        console.log("User wallet ETH balance: ", walletBalance, "wei");
        
        console.log("\n=== Withdrawal Complete ===");
        console.log("All funds have been withdrawn from EntryPoint to your SmartWallet");
        
        vm.stopBroadcast();
    }
}