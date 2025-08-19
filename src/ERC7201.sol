// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IERC7201} from "./interfaces/IERC7201.sol";

/// @title ERC7201
contract ERC7201 is IERC7201 {
    /// @inheritdoc IERC7201
    function namespaceAndVersion() external pure returns (string memory) {
        return "OKX.SmartWallet.1.0.0";
    }

    /// @notice The calculated storage root of the contract according to ERC7201
    /// equivalent to keccak256(abi.encode(uint256(keccak256("OKX.SmartWallet.1.0.0")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant CUSTOM_STORAGE_ROOT = 0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00;
}
