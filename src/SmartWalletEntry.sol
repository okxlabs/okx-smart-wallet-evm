// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SmartWallet} from "./SmartWallet.sol";

/// @notice Uses custom storage layout according to ERC7201
/// @custom:storage-location erc7201:SmartWallet.ERC7201.CustomStorage
/// @dev keccak256(abi.encode(uint256(keccak256("SmartWallet.ERC7201.CustomStorage")) - 1)) & ~bytes32(uint256(0xff))
contract SmartWalletEntry is SmartWallet layout at 0x653ff6dcbda533c3c7d8ffb646da3e510d0de40f237170c4da3f874472aecb00 {}