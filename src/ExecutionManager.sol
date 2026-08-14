// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Call} from "./Types.sol";

abstract contract ExecutionManager {
    uint256 private constant MAX_RETURNDATA_SIZE = 256; // Good enough for common customised error

    /// @notice Executes a low-level call to a target contract
    /// @param call Call data containing target, value, and calldata
    function _call(Call memory call) internal {
        address target = call.target;
        uint256 value = call.value;
        bytes memory data = call.data;

        assembly {
            let success := call(
                gas(),
                target,
                value,
                add(data, 0x20),
                mload(data),
                0, // no output ptr
                0 // no output len
            )

            // Revert with truncated error data for gas efficiency
            if iszero(success) {
                let len := returndatasize()
                if gt(len, MAX_RETURNDATA_SIZE) {
                    len := MAX_RETURNDATA_SIZE
                }
                returndatacopy(0x00, 0x00, len)
                revert(0x00, len)
            }
        }
    }
}
