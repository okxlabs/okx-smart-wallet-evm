// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

struct Session {
    uint256 id;
    address executor;
    uint256 validUntil;
    uint256 validAfter;
    bytes preHook;
    bytes postHook;
    bytes signature;
}
