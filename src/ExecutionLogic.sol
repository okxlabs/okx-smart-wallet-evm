// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import {Call} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {IHook} from "./interfaces/IHook.sol";

abstract contract ExecutionLogic {
    uint256 private constant MAX_RETURNDATA_SIZE = 256; // Good enough for common customised error

    /**
     * @notice Executes a call at given index
     * @dev Reverts the `CallFailed` error, the return bytes copyed from returndatacopy is capped to MAX_RETURNDATA_SIZE
     * @param calls Array of Call structs containing destination address, value, and calldata
     * @param index index number for the call
     */
    function _call(Call[] calldata calls, uint256 index) internal {
        address target = calls[index].target;
        uint256 value = calls[index].value;
        bytes calldata data = calls[index].data;
        bytes4 selector = Errors.CallFailed.selector;

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
                let originalLength := returndatasize()
                let truncatedLength := originalLength
                if gt(truncatedLength, MAX_RETURNDATA_SIZE) {
                    truncatedLength := MAX_RETURNDATA_SIZE
                }

                // free memory pointer
                ptr := mload(0x40)
                // append sel
                mstore(ptr, selector)
                // append index: (sel) = 4 bytes || index
                mstore(add(ptr, 0x04), index)
                // append originalLength: (sel + index) = 36 bytes || originalLength
                mstore(add(ptr, 0x24), originalLength)
                // append dynamic-offset: (sel + index + originalLength) = 68 bytes || start-of-dynamic-bytes (index + originalLength + dynamic-offset = 96 bytes)
                mstore(add(ptr, 0x44), 0x60)
                // append length of truncated data: (sel + index + originalLength + dynamic-offset = 100 bytes) || truncatedLength
                mstore(add(ptr, 0x64), truncatedLength)
                // copy truncatedLength bytes of returndata: (sel + index + originalLength + dynamic-offset + truncatedLength = 132 bytes) || ...returndata capped to truncatedLength...
                returndatacopy(add(ptr, 0x84), 0, truncatedLength)
                // rounding the returndata size up to the next 32-byte boundary
                let roundedLength := and(add(truncatedLength, 0x1f), not(0x1f))
                // compute total size: 4(sel) + 96(index + originalLength + dynamic-offset) + 32(truncatedLength) + roundedLength
                let totalSize := add(0x84, roundedLength)

                // revert error blob
                revert(ptr, totalSize)
            }
        }
    }
}
