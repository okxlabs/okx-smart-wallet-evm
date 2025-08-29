// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/interfaces/ISmartWallet.sol";
import "src/SmartWallet.sol";
import "src/interfaces/IOwnersManager.sol";
import "src/libraries/BatchedCallLib.sol";
import "src/Types.sol";

/// @title SendTxsAsRelayer
/// @notice A script for sending transactions as a relayer using executeWithRelayer
contract SendTxsAsRelayer is Script {
    function run() external {
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(senderPk);

        address payable sender = payable(vm.addr(senderPk));
        console.log("Sender: ", sender);
        console.log("Receiver: ", 0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60);
        
        // First, add the sender as an owner with ECDSAValidator
        _addOwner(sender);
        
        // Then execute the relayer transaction
        _executeRelayerTransaction(sender, senderPk);

        console.log("Completed ExecuteWithRelayer script");
        vm.stopBroadcast();
    }
    
    function _addOwner(address sender) private {
        address ecdsaValidator = vm.envAddress("ECDSA_VALIDATOR");
        console.log("ECDSAValidator address:", ecdsaValidator);
        
        Call[] memory addOwnerCalls = new Call[](1);
        addOwnerCalls[0] = Call({
            target: sender,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnersManager.addOwner.selector,
                keccak256(abi.encodePacked(sender)),
                ecdsaValidator,
                0  // default settings
            )
        });
        
        // Execute addOwner through the SmartWallet
        ISmartWallet(sender).execute(addOwnerCalls);
        console.log("Added sender as owner with ECDSAValidator");
    }
    
    function _executeRelayerTransaction(address payable sender, uint256 senderPk) private {
        // Construct the call data
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60),
            value: 0.00001 ether,
            data: ""
        });

        // Create BatchedCall for executeWithRelayer
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Get typed hash for signing
        address implementation = vm.envAddress("SMART_WALLET");
        console.log("Using SmartWallet implementation from env:", implementation);
        
        bytes32 hash = BatchedCallLib.hash(batchedCall, implementation);
        console.log("BatchedCall hash:", vm.toString(hash));
        
        // Check if the sender has SmartWallet code
        console.log("Sender code length:", sender.code.length);
        
        bytes32 typedHash = SmartWallet(sender).hashTypedData(hash);

        // Sign and prepare validator data
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPk, typedHash);
        bytes memory validatorData = abi.encodePacked(
            keccak256(abi.encodePacked(sender)),
            r,
            s,
            v
        );

        // Execute with relayer
        ISmartWallet(sender).executeWithRelayer(batchedCall, validatorData);
    }
}
