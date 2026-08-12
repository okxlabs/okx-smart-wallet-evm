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

    // ERC-4337 nonce layout:
    // [chainless prefix: 160 bits][operation type: 16 bits][queue id: 16 bits][sequence: 64 bits]
    uint256 public constant CHAINLESS_NONCE_KEY = 196;

    // EIP-1271 signature validation return values
    uint256 public constant SIG_VALIDATION_FAILED = 1 << 96;

    address public constant NATIVE_ETH =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public constant ROOT_KEY_SETTINGS = 1 << 200;

    string public constant ERC712_NAMESPACE = "SmartWallet";
    string public constant ERC712_VERSION = "2.0.0";
    string public constant ERC7201_NAMESPACE =
        "SmartWallet.ERC7201.CustomStorage";
    bytes32 public constant ERC7201_CUSTOM_STORAGE_ROOT =
        0x653ff6dcbda533c3c7d8ffb646da3e510d0de40f237170c4da3f874472aecb00;
}
