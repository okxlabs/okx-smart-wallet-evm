// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

struct BatchedCall {
    Call[] calls;
    uint256 nonce;
}

struct InitialOwner {
    bytes32 keyHash;
    address validator;
}
