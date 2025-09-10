// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title BaseAuthorization
/// @notice A base contract that provides a modifier to restrict access to the contract itself
abstract contract BaseAuthorization {
    error NotFromSelf();

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert NotFromSelf();
        }
        _;
    }
}
