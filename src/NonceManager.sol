// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {INonceManager} from "./interfaces/INonceManager.sol";

/// @title NonceManager
/// @notice Abstract contract providing nonce management functionality
/// @dev Handles nonce validation, updates, and expiry checking
abstract contract NonceManager is INonceManager {
    // State Variables

    mapping(uint192 => uint64) private _nonces; // nonceKey => nonce value

    // Nonce Management Functions
    /// @notice Validates the provided nonce matches the stored value and increments it
    /// @dev Returns true if nonce is valid, false otherwise. Always updates nonce and emits event.
    ///      Nonce is always incremented optimistically - if validation fails, the outer function reverts,
    ///      undoing this change.
    /// @param packedNonce The packed nonce containing nonceKey (upper 192 bits) and nonce (lower 64 bits)
    /// @return bool True if nonce validation passed, false if nonce was invalid
    function validateAndUpdateNonce(
        uint256 packedNonce
    ) internal returns (bool) {
        uint192 key = uint192(packedNonce >> 64);
        uint64 nonce = uint64(packedNonce);

        emit NonceConsumed(key, nonce);
        return nonce == _nonces[key]++;
    }

    /// @notice Returns the current nonce value for a specific key
    /// @param key The nonce key to query
    /// @return The current nonce value for this key
    function getNonce(uint192 key) external view override returns (uint64) {
        return _nonces[key];
    }
}
