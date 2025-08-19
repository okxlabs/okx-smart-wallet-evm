// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {INonceManager} from "./interfaces/INonceManager.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title NonceManager
 * @notice Abstract contract providing nonce management functionality
 * @dev Handles nonce validation, updates, and expiry checking
 */
abstract contract NonceManager is INonceManager {
    // ============ Storage Variables ============
    mapping(uint192 => uint64) public _nonces; // nonceKey => nonce value

    // ============ Nonce Management ============
    /**
     * @notice Validates the provided nonce matches the stored value and increments it
     * @dev Reverts if nonce doesn't match. Internal use only.
     * @param fullNonce The full nonce containing nonceKey (upper 192 bits) and expectedNonce (lower 64 bits)
     */
    function validateAndUpdateNonce(uint256 fullNonce) internal {
        uint192 key = uint192(fullNonce >> 64);
        uint64 expectedNonce = uint64(fullNonce);

        if (_nonces[key] != expectedNonce) {
            revert Errors.InvalidNonce(key, expectedNonce, _nonces[key]);
        }
        unchecked {
            _nonces[key]++;
            emit NonceConsumed(key, expectedNonce);
        }
    }

    /**
     * @notice Simulates nonce validation and update without reverting
     * @dev Used for gas estimation in simulateRelayerExecution. Continues execution even with invalid nonce. Internal use only.
     * @param fullNonce The full nonce containing nonceKey (upper 192 bits) and expectedNonce (lower 64 bits)
     */
    function simulateValidateAndUpdateNonce(uint256 fullNonce) internal {
        uint192 key = uint192(fullNonce >> 64);
        uint64 expectedNonce = uint64(fullNonce);

        if (_nonces[key] != expectedNonce) {
            // Continue simulation
        }
        unchecked {
            _nonces[key]++;
            emit NonceConsumed(key, expectedNonce);
        }
    }

    /**
     * @notice Returns the current nonce value for a specific key
     * @param key The nonce key to query
     * @return The current nonce value for this key
     */
    function getNonce(uint192 key) external view override returns (uint64) {
        return _nonces[key];
    }
}
