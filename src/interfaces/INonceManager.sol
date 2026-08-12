// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title INonceManager
/// @notice Interface for nonce management functionality
interface INonceManager {
    // EVENTS
    event NonceConsumed(uint192 key, uint64 nonce);
    event ChainlessQueueInvalidated(
        uint16 indexed operationType,
        uint16 indexed queueId
    );

    /// @notice Returns the current nonce value for a specific key
    /// @param key Nonce key to query
    /// @return Current nonce value for this key
    function getNonce(uint192 key) external view returns (uint64);

    /// @notice Returns the chainless queue state for an operation type
    /// @param operationType The chainless operation type
    /// @return nextQueueId The smallest queue id that may be used next
    function getChainlessQueueState(
        uint16 operationType
    ) external view returns (uint16 nextQueueId);
}
