// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MerkleProofProcessor
 * @notice Library for processing Merkle proofs in validator data
 * @dev Provides unified Merkle proof processing for all validators that support batch operations
 */
library MerkleProofProcessor {
    // process merkle proofs and return the root hash
    // if proofs is empty, return the message hash
    // if proofs is not empty, return the computed root hash
    // @param proofs: the merkle proofs
    // @param messageHash: the message hash
    // @return rootHash: the root hash
    function processWithMerkleProof(
        bytes32[] memory proofs,
        bytes32 messageHash
    ) internal pure returns (bytes32 rootHash) {
        uint256 len = proofs.length;
        if (len > 0) {
            // Compute Merkle root using the provided proofs and messageHash as leaf
            bytes32 computedRoot = MerkleProof.processProof(
                proofs,
                messageHash
            );

            // Use computed root as the processed message hash
            rootHash = computedRoot;
        } else {
            // No proofs present, use original messageHash and entire validatorData as signature
            rootHash = messageHash;
        }
    }
}
