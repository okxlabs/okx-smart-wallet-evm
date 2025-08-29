// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

/// @title IAllowanceManager
/// @notice Interface for managing both native ETH and ERC20 token allowances using a unified mapping
/// @dev Native ETH allowances are stored using Static.NATIVE_ETH as the token address
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
    event NativeAllowanceUpdated(address indexed spender, uint256 newAllowance);

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

    /// @notice Error thrown when batch operation arrays have mismatched lengths
    error BatchLengthMismatch();

    /// @notice Batch approve multiple spenders for multiple tokens (native ETH and ERC20)
    /// @param tokens Array of token addresses (use Static.NATIVE_ETH for native ETH)
    /// @param spenders Array of spender addresses
    /// @param amounts Array of amounts to approve
    /// @return success True if all approvals succeeded
    function batchApproveToken(
        address[] calldata tokens,
        address[] calldata spenders,
        uint256[] calldata amounts
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
