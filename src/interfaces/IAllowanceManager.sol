// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IERC7914} from "./IERC7914.sol";

/// @title IAllowanceManager
/// @notice Interface for managing both native ETH and ERC20 token allowances
interface IAllowanceManager is IERC7914 {
    /// @notice Emitted when an ERC20 token allowance is set
    event ApproveToken(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when a transient ERC20 token allowance is set
    event ApproveTokenTransient(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when tokens are transferred using allowance
    event TransferFromToken(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when tokens are transferred using transient allowance
    event TransferFromTokenTransient(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a token allowance is updated
    event TokenAllowanceUpdated(
        address indexed token,
        address indexed spender,
        uint256 newAllowance
    );

    /// @notice Error thrown when token transfer fails
    error TokenTransferFailed();

    /// @notice Error thrown when token allowance is exceeded
    error TokenAllowanceExceeded();

    /// @notice Approve a spender to use ERC20 tokens (persistent)
    /// @param token The ERC20 token address
    /// @param spender The address to approve
    /// @param amount The amount to approve
    /// @return success True if approval succeeded
    function approveToken(
        address token,
        address spender,
        uint256 amount
    ) external returns (bool success);

    /// @notice Approve a spender to use ERC20 tokens (transient)
    /// @param token The ERC20 token address
    /// @param spender The address to approve
    /// @param amount The amount to approve
    /// @return success True if approval succeeded
    function approveTokenTransient(
        address token,
        address spender,
        uint256 amount
    ) external returns (bool success);

    /// @notice Transfer tokens from this contract using persistent allowance
    /// @param token The ERC20 token address
    /// @param from The address to transfer from (must be this contract)
    /// @param recipient The address to receive tokens
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromToken(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool success);

    /// @notice Transfer tokens from this contract using transient allowance
    /// @param token The ERC20 token address
    /// @param from The address to transfer from (must be this contract)
    /// @param recipient The address to receive tokens
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromTokenTransient(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool success);

    /// @notice Get the current persistent token allowance
    /// @param token The ERC20 token address
    /// @param spender The spender address
    /// @return allowance The current allowance
    function tokenAllowance(
        address token,
        address spender
    ) external view returns (uint256 allowance);

    /// @notice Get the current transient token allowance
    /// @param token The ERC20 token address
    /// @param spender The spender address
    /// @return allowance The current transient allowance
    function transientTokenAllowance(
        address token,
        address spender
    ) external view returns (uint256 allowance);
}
