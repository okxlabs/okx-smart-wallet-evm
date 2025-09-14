// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAllowanceManager} from "./interfaces/IAllowanceManager.sol";
import {BaseAuthorization} from "./BaseAuthorization.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Static} from "./libraries/Static.sol";

/// @title AllowanceManager
/// @notice Abstract contract providing allowance management for both native ETH and ERC20 tokens
/// @dev Provides persistent allowance management for both native ETH and ERC20 tokens using a unified mapping
abstract contract AllowanceManager is IAllowanceManager, BaseAuthorization {
    using SafeERC20 for IERC20;

    /// @notice Unified mapping of token => spender => allowance for both native ETH and ERC20 tokens
    /// @dev Native ETH is identified by Static.NATIVE_ETH address
    mapping(address token => mapping(address spender => uint256 allowance))
        private tokenAllowance;

    /// @notice Batch approve multiple spenders for multiple tokens (native ETH and ERC20)
    /// @dev More readable and less error-prone using struct encapsulation
    /// @param approvals Array of ApprovalInfo structs
    /// @return success True if all approvals succeeded
    function batchApproveToken(
        ApprovalInfo[] calldata approvals
    ) external onlySelf returns (bool) {
        uint256 length = approvals.length;

        for (uint256 i = 0; i < length; ) {
            ApprovalInfo calldata approval = approvals[i];
            tokenAllowance[approval.token][approval.spender] = approval.amount;

            // Emit event for all approvals (both native ETH and ERC20 tokens)
            emit ApproveToken(
                address(this),
                approval.token,
                approval.spender,
                approval.amount
            );

            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @notice Transfer native ETH from this contract using persistent allowance
    /// @dev This function is meant to be called by the spender after his allowance is approved
    function transferFromNative(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (amount == 0) return true;
        _transferFromNative(recipient, amount);
        emit TransferFromNative(address(this), msg.sender, recipient, amount);
        return true;
    }

    /// @notice Transfer tokens from this contract using persistent allowance
    /// @dev This function is meant to be called by the spender after his allowance is approved
    function transferFromToken(
        address token,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (amount == 0) return true;
        _transferFromToken(token, recipient, amount);
        emit TransferFromToken(
            address(this),
            msg.sender,
            token,
            recipient,
            amount
        );
        return true;
    }

    /// @dev Internal function to validate and execute native ETH transfers
    /// @param recipient The address to receive the funds
    /// @param amount The amount to transfer
    function _transferFromNative(address recipient, uint256 amount) internal {
        // Check allowance
        uint256 currentAllowance = tokenAllowance[Static.NATIVE_ETH][
            msg.sender
        ];
        if (currentAllowance < amount) revert NativeAllowanceExceeded();

        // Update allowance
        if (currentAllowance < type(uint256).max) {
            uint256 newAllowance = currentAllowance - amount;
            tokenAllowance[Static.NATIVE_ETH][msg.sender] = newAllowance;
            emit NativeAllowanceUpdated(msg.sender, newAllowance);
        }

        // Execute transfer
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert TransferNativeFailed();
        }
    }

    /// @dev Internal function to validate and execute token transfers
    /// @param token The ERC20 token address
    /// @param recipient The address to receive the tokens
    /// @param amount The amount to transfer
    function _transferFromToken(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        // Validate inputs
        if (token == Static.NATIVE_ETH) revert InvalidTokenForTransfer();

        // Check allowance
        uint256 currentAllowance = tokenAllowance[token][msg.sender];
        if (currentAllowance < amount) revert TokenAllowanceExceeded();

        // Update allowance
        if (currentAllowance < type(uint256).max) {
            uint256 newAllowance = currentAllowance - amount;
            tokenAllowance[token][msg.sender] = newAllowance;
            emit TokenAllowanceUpdated(token, msg.sender, newAllowance);
        }

        // Execute transfer using SafeERC20
        IERC20(token).safeTransfer(recipient, amount);
    }

    /// @notice Get the current token allowance (for both native ETH and ERC20 tokens)
    /// @param token The token address (use Static.NATIVE_ETH for native ETH)
    /// @param spender The spender address
    /// @return allowance The current allowance
    function getTokenAllowance(
        address token,
        address spender
    ) external view returns (uint256 allowance) {
        return tokenAllowance[token][spender];
    }
}
