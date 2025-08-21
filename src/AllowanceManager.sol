// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IAllowanceManager} from "./interfaces/IAllowanceManager.sol";
import {ERC7914} from "./ERC7914.sol";
import {TransientTokenAllowance} from "./libraries/TransientTokenAllowance.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AllowanceManager
 * @notice Abstract contract providing allowance management for both native ETH and ERC20 tokens
 * @dev Extends ERC7914 with ERC20 token support and transient storage capabilities
 */
abstract contract AllowanceManager is IAllowanceManager, ERC7914 {
    using SafeERC20 for IERC20;

    /// @notice Mapping of token => spender => allowance for persistent ERC20 allowances
    mapping(address token => mapping(address spender => uint256 allowance))
        public tokenAllowance;

    /// @notice Approve a spender to use ERC20 tokens (persistent)
    function approveToken(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwnerOrEntryPoint returns (bool) {
        tokenAllowance[token][spender] = amount;
        emit ApproveToken(token, spender, amount);
        return true;
    }

    /// @notice Approve a spender to use ERC20 tokens (transient)
    function approveTokenTransient(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwnerOrEntryPoint returns (bool) {
        TransientTokenAllowance.set(token, spender, amount);
        emit ApproveTokenTransient(token, spender, amount);
        return true;
    }

    /// @notice Transfer tokens from this contract using persistent allowance
    function transferFromToken(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (amount == 0) return true;
        _transferFromToken(token, from, recipient, amount, false);
        emit TransferFromToken(token, recipient, amount);
        return true;
    }

    /// @notice Transfer tokens from this contract using transient allowance
    function transferFromTokenTransient(
        address token,
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (amount == 0) return true;
        _transferFromToken(token, from, recipient, amount, true);
        emit TransferFromTokenTransient(token, recipient, amount);
        return true;
    }

    /// @notice Get the current transient token allowance
    function transientTokenAllowance(
        address token,
        address spender
    ) external view returns (uint256) {
        return TransientTokenAllowance.get(token, spender);
    }

    /// @dev Internal function to validate and execute token transfers
    /// @param token The ERC20 token address
    /// @param from The address to transfer from
    /// @param recipient The address to receive the tokens
    /// @param amount The amount to transfer
    /// @param isTransient Whether this is transient allowance or not
    function _transferFromToken(
        address token,
        address from,
        address recipient,
        uint256 amount,
        bool isTransient
    ) internal {
        // Validate inputs
        if (from != address(this)) revert IncorrectSender();

        // Check allowance
        uint256 currentAllowance = isTransient
            ? TransientTokenAllowance.get(token, msg.sender)
            : tokenAllowance[token][msg.sender];

        if (currentAllowance < amount) revert TokenAllowanceExceeded();

        // Update allowance
        if (currentAllowance < type(uint256).max) {
            uint256 newAllowance;
            unchecked {
                newAllowance = currentAllowance - amount;
            }
            if (isTransient) {
                TransientTokenAllowance.set(token, msg.sender, newAllowance);
            } else {
                tokenAllowance[token][msg.sender] = newAllowance;
                emit TokenAllowanceUpdated(token, msg.sender, newAllowance);
            }
        }

        // Execute transfer
        try IERC20(token).transfer(recipient, amount) returns (bool success) {
            if (!success) revert TokenTransferFailed();
        } catch {
            revert TokenTransferFailed();
        }
    }
}
