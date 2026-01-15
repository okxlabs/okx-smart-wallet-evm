// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7201} from "./interfaces/IERC7201.sol";
import {Static} from "./libraries/Static.sol";

/// @title ERC7201
abstract contract ERC7201 is IERC7201 {
    /// @inheritdoc IERC7201
    function namespaceAndVersion() external pure returns (string memory) {
        return Static.ERC7201_NAMESPACE_AND_VERSION;
    }

    /// @notice The calculated storage root of the contract according to ERC7201
    /// equivalent to keccak256(abi.encode(uint256(keccak256("SmartWallet.ERC7201.CustomStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant CUSTOM_STORAGE_ROOT =
        Static.ERC7201_CUSTOM_STORAGE_ROOT;
}
