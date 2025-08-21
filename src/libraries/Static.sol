// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

/// @notice A library to store constant values that are used across the SmartWallet contracts
library Static {
    // Validator addresses for built-in validators
    address public constant ECDSA_VALIDATOR_ADDRESS = address(1);
    address public constant PASSKEY_VALIDATOR_ADDRESS = address(2);

    // EIP-1271 signature validation return values
    bytes4 public constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 public constant INVALID_VALUE = 0xffffffff;
}
