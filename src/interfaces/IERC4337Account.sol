// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IAccount, PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";

interface IERC4337Account is IAccount {
    /// @notice Returns the EntryPoint address
    function entryPoint() external view returns (address);

    function getUserOpHashWithoutChainId(
        PackedUserOperation calldata userOp
    ) external view returns (bytes32);

    /// @notice Execute a UserOperation
    /// @param userOp The UserOperation to execute
    /// @param userOpHash The hash of the UserOperation
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external;
}
