// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Errors} from "./libraries/Errors.sol";

/// @title BaseAuthorization
/// @notice A base contract that provides a modifier to restrict access to the contract itself
contract BaseAuthorization {
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Errors.NotFromSelf();
        }
        _;
    }
}
