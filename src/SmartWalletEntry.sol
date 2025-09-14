// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SmartWallet} from "./SmartWallet.sol";

/// @notice Uses custom storage layout according to ERC7201
/// @custom:storage-location erc7201:SmartWallet.1.0.0
/// @dev keccak256(abi.encode(uint256(keccak256("SmartWallet.1.0.0")) - 1)) & ~bytes32(uint256(0xff))
contract SmartWalletEntry is SmartWallet layout at 0xd2f25270280c292d8930a730093bb680163a837f93acc639d858c440b5c53800 {}