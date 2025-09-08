// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IStakeManager} from "account-abstraction/interfaces/IStakeManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {HelperLib} from "scripts/utils/Helper.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";

/// @title WithdrawWithPasskey
/// @notice A script for withdrawing funds from EntryPoint using Passkey signature
contract WithdrawWithPasskey is Script {
    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    function run() external {
        // Get user wallet address from environment
        address payable userWallet = payable(vm.envAddress("USER_WALLET"));
        
        // Get deployer as relayer
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address relayer = vm.addr(deployerPk);
        
        vm.startBroadcast(deployerPk);
        
        console.log("=== EntryPoint Withdrawal with Passkey ===");
        console.log("User wallet: ", userWallet);
        console.log("Relayer: ", relayer);
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
        
        // Create the withdrawal call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: ENTRYPOINT_ADDRESS,
            value: 0,
            data: abi.encodeWithSelector(
                IStakeManager.withdrawTo.selector,
                payable(userWallet),
                withdrawAmount
            )
        });
        
        // Get current nonce
        uint64 currentNonce = INonceManager(userWallet).getNonce(0);
        
        // Create BatchedCall
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: currentNonce
        });
        
        // Prepare validation data (no expiry)
        uint48 validUntil = 0;
        
        // Get implementation address for hash calculation
        address implementation = SmartWallet(userWallet).IMPLEMENTATION();
        
        // Calculate the hash to sign
        bytes32 hash = BatchedCallLib.hash(batchedCall, validUntil, implementation);
        bytes32 typedHash = SmartWallet(userWallet).hashTypedData(hash);
        
        console.log("Typed hash for withdrawal:");
        console.logBytes32(typedHash);
        
        // Get Passkey credentials from environment
        uint256 passkeyPrivateKey = vm.envUint("PASSKEY_PRIVATE_KEY");
        uint256 passkeyPubX = vm.envUint("PASSKEY_PUB_X");
        uint256 passkeyPubY = vm.envUint("PASSKEY_PUB_Y");
        
        // Create Passkey signature
        bytes memory validatorData = _createPasskeyValidatorData(
            passkeyPrivateKey,
            passkeyPubX,
            passkeyPubY,
            typedHash
        );
        
        console.log("Executing withdrawal with Passkey signature...");
        
        // Execute with relayer
        ISmartWallet(userWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Check balance after withdrawal
        uint256 balanceAfter = entryPoint.balanceOf(userWallet);
        console.log("\nNew EntryPoint balance: ", balanceAfter, "wei");
        console.log("Successfully withdrawn: ", balanceBefore - balanceAfter, "wei");
        
        // Check the wallet's ETH balance to confirm receipt
        uint256 walletBalance = userWallet.balance;
        console.log("User wallet balance: ", walletBalance, "wei");
        
        console.log("\n=== Withdrawal Complete ===");
        
        vm.stopBroadcast();
    }
    
    function _createPasskeyValidatorData(
        uint256 signerPrivateKey,
        uint256 signerPubX,
        uint256 signerPubY,
        bytes32 messageHash
    ) private view returns (bytes memory) {
        uint48 validUntil = 0; // No expiry
        // Calculate keyHash
        bytes32 keyHash = keccak256(abi.encodePacked(signerPubX, signerPubY));
        
        // Generate Passkey signature
        (string memory clientDataJson, , bytes32 passkeyMessageHash) = 
            HelperLib.getPasskeyMessageHash(messageHash);
        
        // Sign with P256 curve
        (bytes32 r, bytes32 s) = vm.signP256(signerPrivateKey, passkeyMessageHash);
        
        // Create WebAuthnAuth structure
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: HelperLib.AUTHENTICATOR_DATA,
            clientDataJSON: clientDataJson,
            typeIndex: HelperLib.TYPE_INDEX,
            challengeIndex: HelperLib.CHALLENGE_LOCATION,
            r: uint256(r),
            s: uint256(s)
        });
        
        // Encode the signature (no merkle proofs)
        bytes memory sig = abi.encode(auth, new bytes32[](0));
        
        // Create validatorData: keyHash + validUntil + PasskeyPubKey + sig
        bytes memory validatorData = abi.encodePacked(
            keyHash,
            validUntil,
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: signerPubX,
                    pubKeyY: signerPubY
                })
            ),
            sig
        );
        
        return validatorData;
    }
}