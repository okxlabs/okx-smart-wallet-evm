#!/usr/bin/env ts-node

// @ts-ignore
import ecPem from "ec-pem";
import { ethers } from 'ethers';
import { keccak256, solidityPacked } from 'ethers';
import { bufferToHex, sha256 } from "ethereumjs-util";
import crypto from 'crypto';

/**
 * Generates P256 signature using SmartAccount approach: ec-pem + crypto.createSign("RSA-SHA256")
 * This exactly matches the working implementation from SmartAccount project
 */

// Fixed Passkey private key for consistent testing
const PASSKEY_PRIVATE_KEY = "a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5";

/**
 * Signs message using SmartAccount method: ec-pem + crypto.createSign("RSA-SHA256")
 */
function signWithSmartAccountMethod(messageData: string) {
    console.log("🔑 Signing message data using SmartAccount method:", messageData);
    console.log("");
    
    // 1. Set up key pair with ec-pem (exactly like SmartAccount)
    let keyPair = ecPem(null, "prime256v1");
    keyPair.setPrivateKey(PASSKEY_PRIVATE_KEY, "hex");
    
    // 2. Extract public key coordinates (exactly like SmartAccount)
    const publicKeyHex = keyPair.getPublicKey("hex");
    const pubKeyX = BigInt("0x" + publicKeyHex.slice(2, 66));
    const pubKeyY = BigInt("0x" + publicKeyHex.slice(-64));
    
    console.log("📋 Using Fixed P256 Key Pair (ec-pem):");
    console.log("Private Key:", PASSKEY_PRIVATE_KEY);
    console.log("Public Key X:", '0x' + pubKeyX.toString(16).padStart(64, '0'));
    console.log("Public Key Y:", '0x' + pubKeyY.toString(16).padStart(64, '0'));
    console.log("");
    
    // 3. Process message exactly like SmartAccount: Buffer.from() then SHA256
    let message = Buffer.from(ethers.getBytes(messageData));
    const messageHash = bufferToHex(sha256(message));
    
    console.log("📊 Message Processing (SmartAccount method):");
    console.log("Original messageData:", messageData);
    console.log("Message buffer length:", message.length);
    console.log("Message buffer:", message.toString('hex'));
    console.log("Message hash (after SHA256):", messageHash);
    console.log("Note: SmartAccount requires this SHA256 step for crypto.createSign to work");
    console.log("");
    
    // 4. Sign the hashed message (exactly like SmartAccount)
    const signer = crypto.createSign("RSA-SHA256");
    signer.update(message);
    let sigString = signer.sign(keyPair.encodePrivateKey(), "hex");
    
    console.log("🔐 Signature Generation:");
    console.log("Raw signature string length:", sigString.length);
    console.log("Raw signature string:", sigString);
    console.log("");
    
    // 5. Parse DER signature to extract r and s values (exactly like SmartAccount)
    // @ts-ignore
    const xlength = 2 * ("0x" + sigString.slice(6, 8));
    sigString = sigString.slice(8);
    
    const signatureArray = [
        BigInt("0x" + sigString.slice(0, xlength)), 
        BigInt("0x" + sigString.slice(xlength + 4))
    ];
    
    console.log("✍️  P256 Signature (SmartAccount method):");
    console.log("Signature r:", '0x' + signatureArray[0].toString(16).padStart(64, '0'));
    console.log("Signature s:", '0x' + signatureArray[1].toString(16).padStart(64, '0'));
    console.log("");
    
    // 6. Generate keyHash for our validator
    const keyHashInput = solidityPacked(
        ['uint256', 'uint256'], 
        [pubKeyX.toString(), pubKeyY.toString()]
    );
    const keyHash = keccak256(keyHashInput).slice(2);
    
    console.log("🔑 Key Hash (for registration):", '0x' + keyHash);
    console.log("");
    
    // 7. Output Solidity test data
    console.log("📝 Solidity Test Constants:");
    console.log("uint256 internal constant TEST_PUBKEY_X =", pubKeyX.toString() + ';');
    console.log("uint256 internal constant TEST_PUBKEY_Y =", pubKeyY.toString() + ';');
    console.log("uint256 internal constant TEST_SIG_R =", signatureArray[0].toString() + ';');
    console.log("uint256 internal constant TEST_SIG_S =", signatureArray[1].toString() + ';');
    console.log("bytes32 internal constant REAL_KEY_HASH = 0x" + keyHash + ';');
    console.log("");
    console.log("// Message data that was signed");
    console.log("bytes32 internal constant SIGNED_MESSAGE_HASH = " + messageData + ';');
    console.log("");
    
    return {
        keyHash: '0x' + keyHash,
        publicKey: { x: pubKeyX, y: pubKeyY },
        signature: { r: signatureArray[0], s: signatureArray[1] },
        messageData
    };
}

// Main execution
function main() {
    console.log("🎯 SmartAccount Method P256 Signature Generator");
    console.log("===============================================");
    console.log("");
    
    // Use the REAL typedDataHash from our Foundry test
    const realTypedDataHash = "0xaf3e6e2b4fa4e69e53dd0379334775177e5832e037b2712757d3cf64d8b25c77";
    
    console.log("📄 Generating signature for REAL typedDataHash using SmartAccount method:");
    console.log("TypedData Hash:", realTypedDataHash);
    console.log("");
    
    // Generate signature using SmartAccount approach
    signWithSmartAccountMethod(realTypedDataHash);
    
    console.log("✅ Signature generation complete!");
    console.log("This signature should verify with P256.verify() using SmartAccount method!");
}

// Run if called directly
if (require.main === module) {
    main();
}

export { signWithSmartAccountMethod };