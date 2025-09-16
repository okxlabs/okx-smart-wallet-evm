// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {console} from "forge-std/console.sol";

contract ERC7201Test is Base {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Test the namespaceAndVersion function
    function test_NamespaceAndVersion_Success() external view {
        assertEq(
            _smartWallet.namespaceAndVersion(),
            "SmartWallet.ERC7201.CustomStorage"
        );
    }

    /// @notice Test that CUSTOM_STORAGE_ROOT is correctly calculated using ERC7201 formula
    function test_CUSTOM_STORAGE_ROOT_Calculation() external view {
        // Calculate according to ERC7201 formula:
        // keccak256(abi.encode(uint256(keccak256(namespaceAndVersion)) - 1)) & ~bytes32(uint256(0xff))

        // Step 1: Calculate namespace hash
        bytes32 namespaceHash = keccak256(
            bytes(_smartWallet.namespaceAndVersion())
        );
        console.log("Namespace hash:");
        console.logBytes32(namespaceHash);

        // Step 2: Subtract 1 from the namespace hash (as uint256)
        uint256 namespaceHashMinus1 = uint256(namespaceHash) - 1;
        console.log("Namespace hash - 1:", namespaceHashMinus1);

        // Step 3: Encode and hash
        bytes32 encodedHash = keccak256(abi.encode(namespaceHashMinus1));
        console.log("Encoded hash:");
        console.logBytes32(encodedHash);

        // Step 4: Apply mask to clear the last byte (& ~0xff)
        bytes32 calculatedRoot = encodedHash & ~bytes32(uint256(0xff));
        console.log("Calculated storage root:");
        console.logBytes32(calculatedRoot);

        // Verify it matches the constant in the contract
        console.log("Expected storage root:");
        console.logBytes32(_smartWallet.CUSTOM_STORAGE_ROOT());

        assertEq(calculatedRoot, _smartWallet.CUSTOM_STORAGE_ROOT());
    }
}
