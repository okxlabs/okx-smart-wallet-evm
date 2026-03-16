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
    /// @dev WARNING: Only valid when called on an ERC1967 proxy deployed via LibClone with immutable args.
    /// On direct deployment, returns dirty bytecode data; on EIP-7702, reverts.
    /// @return Factory address embedded in proxy bytecode if valid
    function getImmutableFactory() public view returns (address) {
        bytes memory args = LibClone.argsOnERC1967(address(this), 0, 32);

        if (args.length == 32) {
            return abi.decode(args, (address));
        }

        return address(0);
    }
}
