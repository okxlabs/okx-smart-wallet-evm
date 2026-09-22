// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Call} from "../Types.sol";

library CallLib {
    bytes32 private constant CALL_TYPEHASH =
        keccak256("Call(address target,uint256 value,bytes data)");

    /// @notice Computes a keccak256 hash over an array of Call structs.
    /// @dev Iterates through the calls and encodes each individual call hash, then hashes the concatenation.
    /// @param calls Array of Call structs to hash.
    /// @return result Hash representing the full sequence of calls.
    function hash(Call[] memory calls) internal pure returns (bytes32 result) {
        uint256 length = calls.length;
        bytes32[] memory callHashes = new bytes32[](length);

        for (uint256 i; i < length; ++i) {
            callHashes[i] = hash(calls[i]);
        }
        // Equivalent to keccak256(abi.encodePacked(callHashes)),
        // without allocating and copying an additional bytes buffer.
        assembly ("memory-safe") {
            result := keccak256(
                add(callHashes, 0x20),
                shl(5, length)
            )
        }
    }

    /// @notice Computes a keccak256 hash for a single Call struct.
    /// @dev Encodes the call using EIP-712-style struct hashing.
    /// @param call A single Call struct including target, value, and calldata.
    /// @return Hash of the call.
    function hash(Call memory call) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CALL_TYPEHASH,
                    call.target,
                    call.value,
                    keccak256(call.data)
                )
            );
    }
}
