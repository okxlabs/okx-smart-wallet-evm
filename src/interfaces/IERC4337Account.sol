// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAccount, PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";

interface IERC4337Account is IAccount {
    /// @notice Returns the EntryPoint address
    function entryPoint() external view returns (address);

    /// @notice Computes the UserOperation hash without chain ID for cross-chain compatibility
    /// @dev Used in chainless mode to enable signature reuse across different chains
    /// @param userOp Packed UserOperation to hash
    /// @return UserOperation hash excluding chain ID from the domain separator
    function getUserOpHashWithoutChainId(
        PackedUserOperation calldata userOp
    ) external view returns (bytes32);

    /// @notice Execute a UserOperation
    /// @param userOp UserOperation to execute
    /// @param userOpHash Hash of the UserOperation
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external;
}
