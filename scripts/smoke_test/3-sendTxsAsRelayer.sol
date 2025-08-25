// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/interfaces/ISmartWallet.sol";
import "src/SmartWallet.sol";
import "src/interfaces/INonceManager.sol";
import "src/libraries/BatchedCallLib.sol";
import "src/Types.sol";

/// @title CreateDeployFactory
/// @notice A script for creating a deploy factory
contract SendTxsAsRelayer is Script {
    function run() external {
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(senderPk);

        address payable sender = payable(vm.addr(senderPk));
        address receiver = address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60);
        console.log("Sender: ", sender);
        console.log("Receiver: ", receiver);

        // Construct the call data for the SmartWallet.execute() function
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: receiver, value: 0.00001 ether, data: ""});
        // calls[1] = Call({target: receiver, value: 0.00002 ether, data: ""});

        // Create BatchedCall for executeWithRelayer
        uint256 nonce = 0; // First transaction should use nonce 0
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: nonce,
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Get typed hash for signing using BatchedCallLib
        // Get the implementation address from the SmartWallet
        address implementation = SmartWallet(payable(sender)).IMPLEMENTATION();
        bytes32 hash = BatchedCallLib.hash(batchedCall, implementation);
        console.log("BatchedCall hash:", vm.toString(hash));
        
        // Ensure the sender has SmartWallet code
        bytes memory code = sender.code;
        console.log("Sender code length:", code.length);
        require(code.length > 0, "Sender does not have contract code");
        
        bytes32 typedHash = SmartWallet(payable(sender)).hashTypedData(hash);

        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPk, typedHash);
        bytes32 keyHash = keccak256(abi.encodePacked(sender));
        bytes memory validatorData = abi.encodePacked(keyHash, r, s, v);

        // Execute with relayer
        ISmartWallet(sender).executeWithRelayer(batchedCall, validatorData);

        console.log("Completed ExecuteWithValidator script");
        vm.stopBroadcast();
    }
}
