// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SmartWallet} from "./SmartWallet.sol";

/// @notice Uses custom storage layout according to ERC7201
/// @custom:storage-location erc7201:OKX.SmartWallet.1.0.0
/// @dev keccak256(abi.encode(uint256(keccak256("OKX.SmartWallet.1.0.0")) - 1)) & ~bytes32(uint256(0xff))
contract OKXSmartWalletEntry is SmartWallet layout at 0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00 {}
