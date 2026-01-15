// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";

/// @title SendTxsAsRelayer
/// @notice A script for sending transactions as a relayer using executeWithRelayer
contract SendTxsAsRelayer is Script {
    function run() external {
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(senderPk);

        address payable sender = payable(vm.addr(senderPk));
        console.log("Sender: ", sender);
        console.log("Receiver: ", 0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60);

        // Use a test address for addOwner
        address testOwner = 0x9E7Fb24ac887d77C6Fc52D41A58fA87DbeA0d517;
        console.log("Adding test owner: ", testOwner);
        
        // Add the test address as an owner with ECDSAValidator
        _addOwner(testOwner);

        // Then execute the relayer transaction using the original sender
        _executeRelayerTransaction(sender, senderPk);

        console.log("Completed ExecuteWithRelayer script");
        vm.stopBroadcast();
    }

    function _addOwner(address testOwner) private {
        address ecdsaValidator = Static.ECDSA_VALIDATOR_ADDRESS;
        console.log("ECDSAValidator address:", ecdsaValidator);
        
        // Get the sender address to call execute on
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable sender = payable(vm.addr(senderPk));

        Call[] memory addOwnerCalls = new Call[](1);
        addOwnerCalls[0] = Call({
            target: sender,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                keccak256(abi.encodePacked(testOwner)),
                ecdsaValidator,
                0 // default settings
            )
        });

        // Execute addOwner through the SmartWallet
        ISmartWallet(sender).execute(addOwnerCalls);
        console.log("Added test address as owner with ECDSAValidator");
    }

    function _executeRelayerTransaction(
        address payable sender,
        uint256 senderPk
    ) private {
        // Construct the call data
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60),
            value: 0.00001 ether,
            data: ""
        });

        // Create BatchedCall for executeWithRelayer
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        // Prepare validation data (validUntil = 1 hour from now)
        uint48 validUntil = uint48(block.timestamp + 1 hours);

        // Get typed hash for signing - use implementation address since that's what the contract uses
        address implementation = vm.envAddress("SMART_WALLET");
        console.log(
            "Using SmartWallet implementation from env:",
            implementation
        );

        // The third parameter should match what executeWithRelayer uses: IMPLEMENTATION constant
        bytes32 hash = BatchedCallLib.hash(
            batchedCall,
            validUntil,
            implementation
        );
        console.log("BatchedCall hash:", vm.toString(hash));

        // Check if the sender has SmartWallet code
        console.log("Sender code length:", sender.code.length);

        bytes32 typedHash = SmartWallet(sender).hashTypedData(hash);

        // Sign and prepare validator data
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPk, typedHash);
        bytes memory validatorData = abi.encodePacked(
            keccak256(abi.encodePacked(sender)), // pubKeyHash
            validUntil, // validUntil (6 bytes)
            r,
            s,
            v
        );

        // Execute with relayer
        ISmartWallet(sender).executeWithRelayer(batchedCall, validatorData);
    }
}
