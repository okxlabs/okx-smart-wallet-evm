// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call} from "src/Types.sol";

/// @title SendTxs
/// @notice A script for sending transactions through SmartWallet
contract SendTxs is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address sender = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address receiver = address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60);
        console.log("Sender: ", sender);
        console.log("Receiver: ", receiver);

        // Construct the call data for the SmartWallet.execute() function
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: receiver, value: 0.00001 ether, data: ""});
        // calls[1] = Call({target: receiver, value: 0.00002 ether, data: ""});

        ISmartWallet(sender).execute(calls);

        console.log("Completed ExecuteFromSelf script");
        vm.stopBroadcast();
    }
}
