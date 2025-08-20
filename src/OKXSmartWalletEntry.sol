// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.29;

import {WalletCore} from "./WalletCore.sol";

/// @notice Uses custom storage layout according to ERC7201
/// @custom:storage-location erc7201:OKX.SmartWallet.1.0.0
/// @dev keccak256(abi.encode(uint256(keccak256("OKX.SmartWallet.1.0.0")) - 1)) & ~bytes32(uint256(0xff))
contract OKXSmartWalletEntry is WalletCore {}
