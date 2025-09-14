// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {LibClone} from "solady/utils/LibClone.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";

/// @title BaseAuthorization
/// @notice A base contract that provides modifiers to restrict access to the contract
abstract contract BaseAuthorization {
    error NotFromSelf();

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert NotFromSelf();
        }
        _;
    }

    /// @notice Restricts initialization to authorized callers only
    /// @dev Allows initialization by:
    /// @dev 1. Self (EIP-7702 scenario where EOA delegates to this code)
    /// @dev 2. Factory address stored in immutable args (traditional deployment)
    modifier onlyFactoryOrSelf() {
        // Path 1: Self-initialization (EIP-7702)
        if (msg.sender == address(this)) {
            _;
            return;
        }

        // Path 2: Factory initialization (traditional deployment)
        address immutableFactory = getImmutableFactory();
        if (immutableFactory != address(0) && msg.sender == immutableFactory) {
            _;
            return;
        }

        // If neither condition is met, initialization is unauthorized
        revert ISmartWallet.UnauthorizedInitialization();
    }

    /// @notice Reads the factory address from immutable args if present
    /// @dev Public function to allow external verification of the factory address
    /// @return Factory address if deployed with immutable args, address(0) otherwise
    function getImmutableFactory() public view returns (address) {
        // Read immutable args from bytecode using LibClone
        // The factory address is stored as the first 32 bytes
        bytes memory args = LibClone.argsOnERC1967(address(this), 0, 32);

        // If we have exactly 32 bytes, decode as address
        if (args.length == 32) {
            return abi.decode(args, (address));
        }

        // No immutable args present (e.g., direct deployment or EIP-7702)
        return address(0);
    }
}
