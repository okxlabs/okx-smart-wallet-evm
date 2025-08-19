// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MerkleProofProcessor
 * @notice Library for processing Merkle proofs in validator data
 * @dev Provides unified Merkle proof processing for all validators that support batch operations
 */
library MerkleProofProcessor {
    /**
     * @notice Processes validator data that may contain Merkle proofs
     * @dev If validatorData contains proofs (length > signatureLength), processes them to get the Merkle root
     * @param validatorData The complete validator data (signature + optional Merkle proofs)
     * @param messageHash The original message hash to be processed
     * @param signatureLength The expected length of the signature part (e.g., 65 for ECDSA)
     * @return processedMessageHash The message hash (original or Merkle root if proofs present)
     * @return signatureData The signature portion extracted from validatorData
     */
    function processWithMerkleProof(
        bytes calldata validatorData,
        bytes32 messageHash,
        uint256 signatureLength
    )
        internal
        pure
        returns (bytes32 processedMessageHash, bytes memory signatureData)
    {
        if (validatorData.length > signatureLength) {
            // Extract Merkle proofs from the end of validatorData
            bytes32[] memory proofs = abi.decode(
                validatorData[signatureLength:],
                (bytes32[])
            );

            // Compute Merkle root using the provided proofs and messageHash as leaf
            bytes32 computedRoot = MerkleProof.processProof(
                proofs,
                messageHash
            );

            // Use computed root as the processed message hash
            processedMessageHash = computedRoot;

            // Extract signature from the beginning of validatorData
            signatureData = validatorData[:signatureLength];
        } else {
            // No proofs present, use original messageHash and entire validatorData as signature
            processedMessageHash = messageHash;
            signatureData = validatorData;
        }
    }
}
