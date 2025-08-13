// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

contract SelfAuthorization {
    /// @notice An error that is thrown when an unauthorized address attempts to call a function
    error Unauthorized();

    /// @notice A modifier that restricts access to the contract itself
    modifier onlySelf() {
        if (msg.sender != address(this)) revert Unauthorized();
        _;
    }
}