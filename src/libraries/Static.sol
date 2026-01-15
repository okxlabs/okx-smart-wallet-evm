// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice A library to store constant values that are used across the SmartWallet contracts
library Static {
    // Validator addresses for built-in validators
    address public constant ECDSA_VALIDATOR_ADDRESS = address(1);
    address public constant PASSKEY_VALIDATOR_ADDRESS = address(2);

    // EIP-1271 signature validation return values
    bytes4 public constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 public constant INVALID_VALUE = 0xffffffff;

    uint256 public constant CHAINLESS_NONCE_KEY = 196;

    // EIP-1271 signature validation return values
    uint256 public constant SIG_VALIDATION_FAILED = 1 << 96;

    address public constant NATIVE_ETH =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    string public constant ERC712_NAMESPACE = "SmartWallet";
    string public constant ERC712_VERSION = "1.0.0";
    string public constant ERC7201_NAMESPACE_AND_VERSION =
        "SmartWallet.ERC7201.CustomStorage";
    bytes32 public constant ERC7201_CUSTOM_STORAGE_ROOT =
        0x653ff6dcbda533c3c7d8ffb646da3e510d0de40f237170c4da3f874472aecb00;
}
