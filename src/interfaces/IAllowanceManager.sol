// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

/// @title IAllowanceManager
/// @notice Interface for managing both native ETH and ERC20 token allowances
interface IAllowanceManager {
    /// @notice Emitted when a native ETH allowance is set
    event ApproveNative(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when an ERC20 token allowance is set
    event ApproveToken(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when native ETH is transferred using allowance
    event TransferFromNative(
        address indexed owner,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when tokens are transferred using allowance
    event TransferFromToken(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a native ETH allowance is updated
    event NativeAllowanceUpdated(
        address indexed spender,
        uint256 newAllowance
    );

    /// @notice Emitted when a token allowance is updated
    event TokenAllowanceUpdated(
        address indexed token,
        address indexed spender,
        uint256 newAllowance
    );

    /// @notice Error thrown when sender is incorrect
    error IncorrectSender();

    /// @notice Error thrown when native ETH transfer fails
    error TransferNativeFailed();

    /// @notice Error thrown when native ETH allowance is exceeded
    error NativeAllowanceExceeded();

    /// @notice Error thrown when token transfer fails
    error TokenTransferFailed();

    /// @notice Error thrown when token allowance is exceeded
    error TokenAllowanceExceeded();

    /// @notice Approve a spender to use native ETH (persistent)
    /// @param spender The address to approve
    /// @param amount The amount to approve
    /// @return success True if approval succeeded
    function approveNative(
        address spender,
        uint256 amount
    ) external returns (bool success);

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

    /// @notice Transfer native ETH from this contract using persistent allowance
    /// @param from The address to transfer from (must be this contract)
    /// @param recipient The address to receive ETH
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromNative(
        address from,
        address recipient,
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

    /// @notice Get the current persistent native ETH allowance
    /// @param spender The spender address
    /// @return allowance The current allowance
    function nativeAllowance(
        address spender
    ) external view returns (uint256 allowance);

    /// @notice Get the current persistent token allowance
    /// @param token The ERC20 token address
    /// @param spender The spender address
    /// @return allowance The current allowance
    function tokenAllowance(
        address token,
        address spender
    ) external view returns (uint256 allowance);
}
