// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Call} from "./Types.sol";

abstract contract ExecutionLogic {
    event ExecuteSuccessEvent(
        bytes32 indexed callHash,
        address sender,
        uint256 nonce
    );

    uint256 private constant MAX_RETURNDATA_SIZE = 256; // Good enough for common customised error

    /// @notice try to call a function
    /// @param call: the call data
    function _call(Call calldata call) internal {
        address target = call.target;
        uint256 value = call.value;
        bytes calldata data = call.data;

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, data.offset, data.length)

            let success := call(
                gas(),
                target,
                value,
                ptr,
                data.length,
                0, // no output ptr
                0 // no output len
            )

            // manually revert truncated data
            if iszero(success) {
                let len := returndatasize()
                if gt(len, MAX_RETURNDATA_SIZE) {
                    len := MAX_RETURNDATA_SIZE
                }
                returndatacopy(ptr, 0x00, len)
                revert(ptr, len)
            }
        }
    }
}
