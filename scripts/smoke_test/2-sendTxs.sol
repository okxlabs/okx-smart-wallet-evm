// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/interfaces/IWalletCore.sol";
import "src/Types.sol";

/// @title CreateDeployFactory
/// @notice A script for creating a deploy factory
contract SendTxs is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address sender = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address receiver = address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60);
        console.log("Sender: ", sender);
        console.log("Receiver: ", receiver);

        // Construct the call data for the WalletCore.execute() function
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: receiver, value: 0.00001 ether, data: ""});
        // calls[1] = Call({target: receiver, value: 0.00002 ether, data: ""});

        IWalletCore(sender).executeFromSelf(calls);

        console.log("Completed ExecuteFromSelf script");
        vm.stopBroadcast();
    }
}
