// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title INonceManager
/// @notice Interface for nonce management functionality
interface INonceManager {
    // EVENTS
    event NonceConsumed(uint192 key, uint64 nonce);

    /// @notice Returns the current nonce value for a specific key
    /// @param key Nonce key to query
    /// @return Current nonce value for this key
    function getNonce(uint192 key) external view returns (uint64);
}
