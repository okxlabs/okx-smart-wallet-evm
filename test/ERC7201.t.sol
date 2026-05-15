// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";

contract ERC7201Test is Base {
    /// @notice Test the namespaceAndVersion function
    function test_NamespaceAndVersion_Success() external view {
        assertEq(_smartWallet.namespace(), "SmartWallet.ERC7201.CustomStorage");
    }

    /// @notice Test that CUSTOM_STORAGE_ROOT is correctly calculated using ERC7201 formula
    function test_CUSTOM_STORAGE_ROOT_Calculation() external view {
        // Calculate according to ERC7201 formula:
        // keccak256(abi.encode(uint256(keccak256(namespaceAndVersion)) - 1)) & ~bytes32(uint256(0xff))

        // Step 1: Calculate namespace hash
        bytes32 namespaceHash = keccak256(bytes(_smartWallet.namespace()));

        // Step 2: Subtract 1 from the namespace hash (as uint256)
        uint256 namespaceHashMinus1 = uint256(namespaceHash) - 1;

        // Step 3: Encode and hash
        bytes32 encodedHash = keccak256(abi.encode(namespaceHashMinus1));

        // Step 4: Apply mask to clear the last byte (& ~0xff)
        bytes32 calculatedRoot = encodedHash & ~bytes32(uint256(0xff));

        assertEq(calculatedRoot, _smartWallet.CUSTOM_STORAGE_ROOT());
    }
}
