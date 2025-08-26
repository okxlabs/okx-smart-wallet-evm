// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Call} from "../Types.sol";

import "../interfaces/IHook.sol";

contract MockHook is IHook {
    bytes4 public constant TRANSFER_SELECTOR = 0xa9059cbb;

    function preCheck(
        Call[] calldata calls,
        address // executor
    ) external payable returns (bytes memory preCheckRet) {
        // For mock purposes, we'll use hardcoded values or extract from first call
        // In real implementation, these would come from storage or other sources
        address token = calls.length > 0 ? calls[0].target : address(0);
        uint256 maxTotalAmount = 100 ether; // Hardcoded limit for testing

        uint256 initialBalance = 0;
        uint256 totalAmount = 0;

        // Check if there is a valid token address
        if (token != address(0)) {
            initialBalance = IERC20(token).balanceOf(msg.sender);
        }

        for (uint256 i = 0; i < calls.length; i++) {
            require(calls[i].target == token, "Invalid token address");

            bytes4 selector = bytes4(calls[i].data[:4]);
            require(selector == TRANSFER_SELECTOR, "Invalid operation");

            (address recipientCalled, uint256 amount) = abi.decode(
                calls[i].data[4:],
                (address, uint256)
            );

            require(recipientCalled != address(0), "Invalid recipient address");
            totalAmount += amount;
        }

        require(
            totalAmount <= maxTotalAmount,
            "Total transfer amount exceeds limit"
        );

        return abi.encode(token, initialBalance, totalAmount);
    }

    function postCheck(
        bytes calldata preHookRet,
        address // executor
    ) external payable {
        (address token, uint256 initialBalance, uint256 totalAmount) = abi
            .decode(preHookRet, (address, uint256, uint256));
        
        // Include token address check otherwise empty calls will revert
        if (token != address(0)) {
            uint256 finalBalance = IERC20(token).balanceOf(msg.sender);
            require(
                initialBalance - finalBalance == totalAmount,
                "Balance mismatch: transfer amounts do not match"
            );
        }
    }
}
