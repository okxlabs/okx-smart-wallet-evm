// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {INonceManager} from "./interfaces/INonceManager.sol";
import {ChainlessLib} from "./libraries/ChainlessLib.sol";

/// @title NonceManager
/// @notice Abstract contract providing nonce management functionality
/// @dev Handles nonce validation, updates, and expiry checking
abstract contract NonceManager is INonceManager {
    /// @dev Uses an isolated slot so adding the queue watermark does not shift
    ///      the storage layout of contracts inheriting NonceManager.
    bytes32 private constant CHAINLESS_QUEUE_STORAGE_SLOT =
        keccak256("okx.smart-wallet.nonce-manager.chainless-queue");

    /// @dev Recommended operation-type convention (not enforced on-chain):
    ///      0 = addOwner, 1 = upgradeToAndCall.
    struct ChainlessQueueStorage {
        mapping(uint16 operationType => uint16) queueFloors;
    }

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

        unchecked {
            emit NonceConsumed(key, nonce);
            return nonce == _nonces[key]++;
        }
    }

    /// @notice Advances the chainless queue watermark for one operation type
    /// @dev Once queue N is accepted, every queue id <= N is permanently invalid
    ///      for that operation type only. The caller must ensure `packedNonce`
    ///      belongs to the chainless nonce namespace.
    function _validateAndUpdateChainlessQueue(
        uint256 packedNonce
    ) internal returns (bool) {
        uint16 operationType = ChainlessLib.operationType(packedNonce);
        uint16 queueId = ChainlessLib.queueId(packedNonce);
        ChainlessQueueStorage storage $ = _getChainlessQueueStorage();

        if (
            queueId < $.queueFloors[operationType] || queueId == type(uint16).max
        ) return false;

        $.queueFloors[operationType] = queueId + 1;
        emit ChainlessQueueInvalidated(operationType, queueId);
        return true;
    }

    /// @notice Returns the current nonce value for a specific key
    /// @param key The nonce key to query
    /// @return The current nonce value for this key
    function getNonce(uint192 key) external view override returns (uint64) {
        return _nonces[key];
    }

    /// @inheritdoc INonceManager
    function getChainlessQueueState(
        uint16 operationType
    ) external view override returns (uint16 nextQueueId) {
        ChainlessQueueStorage storage $ = _getChainlessQueueStorage();
        return $.queueFloors[operationType];
    }

    function _getChainlessQueueStorage()
        private
        pure
        returns (ChainlessQueueStorage storage $)
    {
        bytes32 slot = CHAINLESS_QUEUE_STORAGE_SLOT;
        assembly ("memory-safe") {
            $.slot := slot
        }
    }
}
