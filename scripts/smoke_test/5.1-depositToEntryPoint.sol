// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

/// @title DepositToEntryPoint
/// @notice A script for depositing funds to EntryPoint for a SmartWallet account
contract DepositToEntryPoint is Script {
    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS =
        0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        // Get user wallet address from environment
        address payable userWallet = payable(vm.envAddress("USER_WALLET"));

        // Get deployer private key for broadcasting
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        console.log("=== EntryPoint Deposit Script ===");
        console.log("User wallet: ", userWallet);
        console.log("Depositor (deployer): ", deployer);
        console.log("EntryPoint address: ", ENTRYPOINT_ADDRESS);

        // Get EntryPoint instance
        IEntryPoint entryPoint = IEntryPoint(ENTRYPOINT_ADDRESS);

        // Check current balance before deposit
        uint256 balanceBefore = entryPoint.balanceOf(userWallet);
        console.log("\nCurrent EntryPoint balance: ", balanceBefore, "wei");

        // Deposit amount (0.01 ETH should be enough for several operations)
        uint256 depositAmount = 0.03 ether;
        console.log("Depositing: ", depositAmount, "wei (0.01 ETH)");

        // Perform the deposit
        entryPoint.depositTo{value: depositAmount}(userWallet);

        // Check balance after deposit
        uint256 balanceAfter = entryPoint.balanceOf(userWallet);
        console.log("\nNew EntryPoint balance: ", balanceAfter, "wei");
        console.log(
            "Successfully deposited: ",
            balanceAfter - balanceBefore,
            "wei"
        );

        vm.stopBroadcast();
    }
}
