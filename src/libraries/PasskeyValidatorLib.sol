// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {MerkleProofProcessor} from "./MerkleProofProcessor.sol";

/**
 * @title PasskeyValidatorLib
 * @notice Library for Passkey signature validation using P256 verification
 * @dev Provides static validation functions for P256 signatures with SmartAccount compatibility
 */
library PasskeyValidatorLib {
    // Simplified struct for direct P256 signature verification
    struct PasskeySignature {
        uint256 pubKeyX;
        uint256 pubKeyY;
        uint256 r;
        uint256 s;
    }

    /**
     * @notice Validates a Passkey signature using P256 verification with optional Merkle proof support
     * @dev Verifies that:
     *      1. Processes Merkle proofs if present in validatorData
     *      2. The provided public key matches the registered keyHash
     *      3. The P256 signature is valid for SHA256(messageHash) - required for crypto.createSign compatibility
     * @param keyHash The hash of the registered public key (keccak256(abi.encodePacked(pubKeyX, pubKeyY)))
     * @param messageHash The hash of the message being validated (will be SHA256 hashed internally)
     * @param validatorData Encoded Passkey signature data (PasskeySignature struct + optional Merkle proofs)
     * @return bool True if the signature is valid
     */
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) internal view returns (bool) {
        // Process Merkle proofs if present (using fixed signature length approach)
        (
            bytes32 processedMessageHash,
            bytes memory signatureData
        ) = MerkleProofProcessor.processWithMerkleProof(
                validatorData,
                messageHash,
                128 // Standard r1 signature length
            );

        // Decode the Passkey signature data from processed signature portion
        PasskeySignature memory sig = abi.decode(
            signatureData,
            (PasskeySignature)
        );

        // Verify that the provided public key matches the registered keyHash
        if (keccak256(abi.encodePacked(sig.pubKeyX, sig.pubKeyY)) != keyHash) {
            return false;
        }

        // Hash the processed messageHash to match crypto.createSign("RSA-SHA256") behavior
        // This is required for compatibility with existing Passkey signing libraries
        bytes32 hashedMessage = sha256(abi.encodePacked(processedMessageHash));

        // Verify the P256 signature using the hashed message
        return
            P256.verify(
                hashedMessage,
                bytes32(sig.r),
                bytes32(sig.s),
                bytes32(sig.pubKeyX),
                bytes32(sig.pubKeyY)
            );
    }
}
