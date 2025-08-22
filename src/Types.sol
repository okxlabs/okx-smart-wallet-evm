// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

struct BatchedCall {
    Call[] calls;
    uint256 nonce;
    uint48 expiry;
}

struct InitialOwner {
    bytes32 keyHash;
    address validator;
}
