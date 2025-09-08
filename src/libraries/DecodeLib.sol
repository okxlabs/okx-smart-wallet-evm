// SPDX-License-Identifier: MIT
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

    /// @notice Decode signature components (pubKeyHash and validUntil) from signature bytes
    /// @dev Signature format: pubKeyHash (32 bytes) + validUntil (6 bytes) + actual signature data
    /// @param signature The signature bytes containing pubKeyHash and validUntil
    /// @return pubKeyHash The extracted public key hash (first 32 bytes)
    /// @return validUntil The extracted validity timestamp (bytes 32-38 as uint48)
    function decodeSignatureComponents(
        bytes calldata signature
    ) internal pure returns (bytes32 pubKeyHash, uint48 validUntil) {
        pubKeyHash = bytes32(signature[:32]);
        validUntil = uint48(bytes6(signature[32:38]));
    }
}
