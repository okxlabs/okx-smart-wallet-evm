// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Call, BatchedCall} from "../Types.sol";
import {CallLib} from "./CallLib.sol";

library BatchedCallLib {
    bytes32 private constant BATCHED_CALL_TYPEHASH =
        keccak256(
            "BatchedCall(Call[] calls,uint256 nonce,uint256 expiry)Call(address target,uint256 value,bytes data)"
        );

    /**
     * @notice Generates an EIP-712 compliant typed data hash for transaction validation
     * @dev Combines the message hash with the domain separator using EIP-712 standard
     * @param batchedCall BatchedCall struct containing calls, nonce, and expiry
     * @return bytes32 The EIP-712 typed data hash ready for signing
     */
    function hash(
        BatchedCall memory batchedCall
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BATCHED_CALL_TYPEHASH,
                CallLib.hash(batchedCall.calls),
                batchedCall.nonce,
                batchedCall.expiry
            )
        );
    }
}
