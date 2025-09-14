// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7201} from "./interfaces/IERC7201.sol";

/// @title ERC7201
abstract contract ERC7201 is IERC7201 {
    /// @inheritdoc IERC7201
    function namespaceAndVersion() external pure returns (string memory) {
        return "SmartWallet.1.0.0";
    }

    /// @notice The calculated storage root of the contract according to ERC7201
    /// equivalent to keccak256(abi.encode(uint256(keccak256("SmartWallet.1.0.0")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant CUSTOM_STORAGE_ROOT =
        0xd2f25270280c292d8930a730093bb680163a837f93acc639d858c440b5c53800;
}
