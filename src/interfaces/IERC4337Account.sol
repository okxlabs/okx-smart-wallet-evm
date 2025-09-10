// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAccount, PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";

interface IERC4337Account is IAccount {
    // ERRORS
    error NotEntryPoint();

    /// @notice Returns the EntryPoint address
    /// @dev Returns the canonical EntryPoint contract address for ERC-4337
    /// @return The EntryPoint contract address
    function entryPoint() external view returns (address);

    /// @notice Computes the UserOperation hash without chain ID
    /// @dev Used for chainless execution to enable cross-chain compatibility
    /// @param userOp The UserOperation to hash
    /// @return The computed hash without chain ID
    function getUserOpHashWithoutChainId(
        PackedUserOperation calldata userOp
    ) external view returns (bytes32);

    /// @notice Executes a UserOperation from the EntryPoint
    /// @dev Only callable by the EntryPoint contract. Main entry point for ERC-4337 UserOperations.
    /// @param userOp The UserOperation containing calls to execute
    /// @param userOpHash The hash of the UserOperation for validation
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external;
}
