// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IAllowanceManager} from "./interfaces/IAllowanceManager.sol";
import {OwnersManager} from "./OwnersManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Static} from "./libraries/Static.sol";

/// @title AllowanceManager
/// @notice Abstract contract providing allowance management for both native ETH and ERC20 tokens
/// @dev Provides persistent allowance management for both native ETH and ERC20 tokens using a unified mapping
abstract contract AllowanceManager is IAllowanceManager, OwnersManager {
    using SafeERC20 for IERC20;

    /// @notice Unified mapping of token => spender => allowance for both native ETH and ERC20 tokens
    /// @dev Native ETH is identified by Static.NATIVE_ETH address
    mapping(address token => mapping(address spender => uint256 allowance))
        public tokenAllowance;

    /// @notice Batch approve multiple spenders for multiple tokens (native ETH and ERC20)
    /// @dev All arrays must have the same length.
    /// @param tokens Array of token addresses (use Static.NATIVE_ETH for native ETH)
    /// @param spenders Array of spender addresses
    /// @param amounts Array of amounts to approve
    /// @return success True if all approvals succeeded
    function batchApproveToken(
        address[] calldata tokens,
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external onlySelf returns (bool) {
        uint256 length = tokens.length;
        if (length != spenders.length || length != amounts.length) {
            revert BatchLengthMismatch();
        }

        for (uint256 i = 0; i < length; ) {
            tokenAllowance[tokens[i]][spenders[i]] = amounts[i];

            // Emit appropriate event based on token type
            if (tokens[i] == Static.NATIVE_ETH) {
                emit ApproveNative(address(this), spenders[i], amounts[i]);
            } else {
                emit ApproveToken(tokens[i], spenders[i], amounts[i]);
            }

            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @notice Transfer native ETH from this contract using persistent allowance
    /// @dev This function is meant to be called by the spender after his allowance is approved
    function transferFromNative(
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (amount == 0) return true;
        _transferFromNative(from, recipient, amount);
        emit TransferFromNative(address(this), recipient, amount);
        return true;
    }

    /// @notice Transfer tokens from this contract using persistent allowance
    /// @dev This function is meant to be called by the spender after his allowance is approved
    function transferFromToken(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (amount == 0) return true;
        _transferFromToken(token, from, recipient, amount);
        emit TransferFromToken(token, recipient, amount);
        return true;
    }

    /// @dev Internal function to validate and execute native ETH transfers
    /// @param from The address to transfer from
    /// @param recipient The address to receive the funds
    /// @param amount The amount to transfer
    function _transferFromNative(
        address from,
        address recipient,
        uint256 amount
    ) internal {
        // Validate inputs
        if (from != address(this)) revert IncorrectSender();

        // Check allowance
        uint256 currentAllowance = tokenAllowance[Static.NATIVE_ETH][
            msg.sender
        ];
        if (currentAllowance < amount) revert NativeAllowanceExceeded();

        // Update allowance
        if (currentAllowance < type(uint256).max) {
            uint256 newAllowance;
            unchecked {
                newAllowance = currentAllowance - amount;
            }
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
    /// @param from The address to transfer from
    /// @param recipient The address to receive the tokens
    /// @param amount The amount to transfer
    function _transferFromToken(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) internal {
        // Validate inputs
        if (from != address(this)) revert IncorrectSender();

        // Check allowance
        uint256 currentAllowance = tokenAllowance[token][msg.sender];
        if (currentAllowance < amount) revert TokenAllowanceExceeded();

        // Update allowance
        if (currentAllowance < type(uint256).max) {
            uint256 newAllowance;
            unchecked {
                newAllowance = currentAllowance - amount;
            }
            tokenAllowance[token][msg.sender] = newAllowance;
            emit TokenAllowanceUpdated(token, msg.sender, newAllowance);
        }

        // Execute transfer
        try IERC20(token).transfer(recipient, amount) returns (bool success) {
            if (!success) revert TokenTransferFailed();
        } catch {
            revert TokenTransferFailed();
        }
    }

    /// @notice Get the current persistent native ETH allowance
    /// @param spender The spender address
    /// @return allowance The current allowance
    function nativeAllowance(
        address spender
    ) external view returns (uint256 allowance) {
        return tokenAllowance[Static.NATIVE_ETH][spender];
    }
}
