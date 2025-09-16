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

    /// @notice Restricts initialization to factory only
    /// @dev Only allows initialization by the factory address stored in immutable args
    /// @dev For EIP-7702 scenarios, owners should be added via execute/executeWithRelayer
    modifier onlyFactory() {
        if (msg.sender != getImmutableFactory()) {
            revert ISmartWallet.UnauthorizedInitialization();
        }
        _;
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
