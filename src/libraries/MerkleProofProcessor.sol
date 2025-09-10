// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title MerkleProofProcessor
/// @notice Library for processing Merkle proofs in validator data
/// @dev Provides unified Merkle proof processing for all validators that support batch operations
library MerkleProofProcessor {
    /// @notice Processes Merkle proofs to compute the root hash or returns the original message hash
    /// @dev If proofs array is empty, returns the message hash directly for single signature validation.
    ///      If proofs are provided, computes the Merkle root for batch operation validation.
    /// @param proofs Array of Merkle proof hashes for batch validation (empty for single operations)
    /// @param messageHash The leaf hash to verify against the Merkle tree
    /// @return rootHash The computed Merkle root (if proofs provided) or original message hash (if no proofs)
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
