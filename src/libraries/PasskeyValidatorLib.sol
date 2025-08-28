// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {MerkleProofProcessor} from "./MerkleProofProcessor.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";

/// @title PasskeyValidatorLib
/// @notice Library for Passkey signature validation using P256 verification
/// @dev Provides static validation functions for P256 signatures with SmartAccount compatibility
library PasskeyValidatorLib {
    // the length of the Passkey signature with public key
    uint256 constant PASSKEY_PUBKEY_LENGTH = 64;

    // Simplified struct for direct P256 signature verification
    struct PasskeyPubKey {
        uint256 pubKeyX;
        uint256 pubKeyY;
    }

    /// @notice Validates a Passkey signature using P256 verification with optional Merkle proof support
    /// @dev Verifies that:
    ///      1. Processes Merkle proofs if present in validatorData
    ///      2. The provided public key matches the registered keyHash
    ///      3. The P256 signature is valid for SHA256(messageHash) - required for crypto.createSign compatibility
    /// @param keyHash The hash of the registered public key (keccak256(abi.encodePacked(pubKeyX, pubKeyY)))
    /// @param messageHash The hash of the message being validated (will be SHA256 hashed internally)
    /// @param validatorData Encoded Passkey signature data (PasskeySignature struct + optional Merkle proofs)
    /// @return bool True if the signature is valid
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) internal view returns (bool) {
        if (validatorData.length < PASSKEY_PUBKEY_LENGTH) {
            return false;
        }

        // decode the Passkey signature data from the validatorData
        PasskeyPubKey memory sig = abi.decode(
            validatorData[:PASSKEY_PUBKEY_LENGTH],
            (PasskeyPubKey)
        );

        // decode the WebAuthn authentication data from the validatorData
        (
            WebAuthn.WebAuthnAuth memory webAuthnAuth,
            bytes32[] memory proofs
        ) = abi.decode(
                validatorData[PASSKEY_PUBKEY_LENGTH:],
                (WebAuthn.WebAuthnAuth, bytes32[])
            );

        // Process Merkle proofs if present (using fixed signature length approach)
        bytes32 rootHash = MerkleProofProcessor.processWithMerkleProof(
            proofs,
            messageHash
        );

        // Verify that the provided public key matches the registered keyHash
        if (keccak256(abi.encodePacked(sig.pubKeyX, sig.pubKeyY)) != keyHash) {
            return false;
        }

        // verify the Passkey signature using the WebAuthn authentication data
        return
            WebAuthn.verify({
                challenge: abi.encode(rootHash),
                requireUV: false,
                webAuthnAuth: webAuthnAuth,
                x: sig.pubKeyX,
                y: sig.pubKeyY
            });
    }
}
