// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Call} from "../Types.sol";

library DecodeLib {
    /// @notice Decode `Call[]` from function params (WITHOUT selector)
    /// @dev Expects input like `bytes params = callData[4:]` or `abi.encode(calls)`
    function decodeCalls(
        bytes calldata callData
    ) internal pure returns (Call[] calldata calls) {
        assembly ("memory-safe") {
            let dataPointer := add(
                callData.offset,
                calldataload(callData.offset)
            )

            // Extract Calls
            calls.offset := add(dataPointer, 32)
            calls.length := calldataload(dataPointer)
        }
    }
}
