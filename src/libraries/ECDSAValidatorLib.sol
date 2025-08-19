// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProofProcessor} from "./MerkleProofProcessor.sol";

/**
 * @title ECDSAValidatorLib
 * @notice Library for ECDSA signature validation with Merkle proof support
 * @dev Provides static validation functions for ECDSA signatures
 */
library ECDSAValidatorLib {
    using ECDSA for bytes32;

    /**
     * @notice Validates a signature by checking if the recovered signer's hash matches keyHash
     * @dev Uses ECDSA recovery to verify the signature matches the message hash
     * @param keyHash The hash of the expected public key/address
     * @param messageHash The hash of the message being validated
     * @param validatorData The ECDSA signature to verify
     * @return bool True if recovered address hash matches keyHash
     */
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) internal pure returns (bool) {
        // Process Merkle proofs if present (ECDSA signatures are 65 bytes)
        (
            bytes32 processedMessageHash,
            bytes memory signature
        ) = MerkleProofProcessor.processWithMerkleProof(
                validatorData,
                messageHash,
                65 // Standard ECDSA signature length
            );

        // Recover signer and verify against keyHash
        (address recoveredSigner, , ) = processedMessageHash.tryRecover(
            signature
        );
        return keccak256(abi.encodePacked(recoveredSigner)) == keyHash;
    }
}
