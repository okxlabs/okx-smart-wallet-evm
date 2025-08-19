// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.29;

import {OKXSmartWallet} from "./OKXSmartWallet.sol";

/// @notice Uses custom storage layout according to ERC7201
/// keccak256(abi.encode(uint256(keccak256("OKX.SmartSallet.1.0.0")) - 1)) & ~bytes32(uint256(0xff));
/// Storage slot: 0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00
contract OKXSmartWalletEntry is OKXSmartWallet layout at 0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00 {}
