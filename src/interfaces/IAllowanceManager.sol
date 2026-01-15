// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title IAllowanceManager
/// @notice Interface for managing both native ETH and ERC20 token allowances using a unified mapping
/// @dev Native ETH allowances are stored using Static.NATIVE_ETH as the token address
interface IAllowanceManager {
    /// @notice Event emitted when token allowance is approved (both native ETH and ERC20 tokens)
    event ApproveToken(
        address indexed owner,
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when native ETH is transferred using allowance
    event TransferFromNative(
        address indexed owner,
        address indexed spender,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when tokens are transferred using allowance
    event TransferFromToken(
        address indexed owner,
        address indexed spender,
        address indexed token,
        address recipient,
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

    /// @notice Error thrown when native ETH transfer fails
    error TransferNativeFailed();

    /// @notice Error thrown when native ETH allowance is exceeded
    error NativeAllowanceExceeded();

    /// @notice Error thrown when token allowance is exceeded
    error TokenAllowanceExceeded();

    /// @notice Error thrown when attempting to use native ETH in token transfer function
    error InvalidTokenForTransfer();

    /// @notice Error thrown when attempting to use an invalid spender
    error InvalidSpender();

    /// @notice Struct for encapsulating approval data
    struct ApprovalInfo {
        address token;
        address spender;
        uint256 amount;
    }

    /// @notice Batch approve multiple spenders for multiple tokens (native ETH and ERC20)
    /// @param approvals Array of ApprovalInfo structs
    /// @return success True if all approvals succeeded
    function batchApproveToken(
        ApprovalInfo[] calldata approvals
    ) external returns (bool success);

    /// @notice Transfer native ETH from this contract using persistent allowance
    /// @param recipient The address to receive ETH
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromNative(
        address recipient,
        uint256 amount
    ) external returns (bool success);

    /// @notice Transfer tokens from this contract using persistent allowance
    /// @param token The ERC20 token address
    /// @param recipient The address to receive tokens
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromToken(
        address token,
        address recipient,
        uint256 amount
    ) external returns (bool success);

    /// @notice Get the current token allowance (for both native ETH and ERC20 tokens)
    /// @param token The token address (use Static.NATIVE_ETH for native ETH)
    /// @param spender The spender address
    /// @return allowance The current allowance
    function getTokenAllowance(
        address token,
        address spender
    ) external view returns (uint256 allowance);
}
