// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

/// @title GasEstimateUtil
/// @notice Library to provide helper functions for simualtion and gas calculation
library GasEstimateUtil {
    /// @notice Decode `GasEstimates(uint256,bytes)` error data from raw revert `returnData`
    /// @param returnData The raw revert data (selector + encoded arguments)
    /// @return executionGas The uint256 (execution gas estimate)
    /// @return errorData The dynamic `bytes` payload of the error
    function decodeGasEstimates(
        bytes memory returnData
    ) internal pure returns (uint256 executionGas, bytes memory errorData) {
        bytes memory payload;
        assembly {
            // rcompute payload length = returnData.length − 4
            let dataLen := sub(mload(returnData), 0x04)

            // reserve mem space for payload, and advance free mem pointer: round up to nearest 32 bytes
            let ptr := mload(0x40)
            mstore(ptr, dataLen)
            mstore(
                0x40,
                add(add(ptr, 0x20), and(add(dataLen, 0x1f), not(0x1f)))
            )

            // copy the bytes from returnData[4:] into payload[0:] in trunk of 32 bytes
            let src := add(add(returnData, 0x20), 0x04)
            let dst := add(ptr, 0x20)
            for {
                let i := 0
            } lt(i, dataLen) {
                i := add(i, 0x20)
            } {
                mstore(add(dst, i), mload(add(src, i)))
            }
            payload := ptr
        }

        // decode the 3 fields in order
        (executionGas, errorData) = abi.decode(payload, (uint256, bytes));
    }

    /// @notice Compute intrinsic calldata-expansion gas: 16 per non-zero byte, 4 per zero byte
    /// @param data The memory blob you want to cost
    /// @return gasCost The total intrinsic gas for that calldata
    function intrinsicGas(
        bytes memory data
    ) internal pure returns (uint256 gasCost) {
        uint256 len = data.length;
        uint256 zeroCount;
        assembly {
            // pointer to first byte of `data` in memory
            let ptr := add(data, 0x20)
            let end := add(ptr, len)
            let word

            // scan 32 bytes at a time
            for {} lt(ptr, end) {
                ptr := add(ptr, 0x20)
            } {
                word := mload(ptr)
                // count zeros in this 32-byte word
                for {
                    let j := 0
                } lt(j, 0x20) {
                    j := add(j, 0x01)
                } {
                    zeroCount := add(zeroCount, iszero(byte(j, word)))
                }
            }

            // adjust for any overshoot past the end
            let overshoot := sub(ptr, end)
            if gt(overshoot, 0) {
                // subtract erroneous zero counts beyond `len`
                for {
                    let i := 0
                } lt(i, overshoot) {
                    i := add(i, 0x01)
                } {
                    let b := byte(sub(0x1f, i), word)
                    zeroCount := sub(zeroCount, iszero(b))
                }
            }
        }

        // every byte costs 16; zero bytes save 12
        gasCost = len * 16 - zeroCount * 12;
    }
}
