// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Call} from "../Types.sol";

import "../interfaces/IHook.sol";

contract MockHook is IHook {
    bytes4 public constant TRANSFER_SELECTOR = 0xa9059cbb;

    function preCheck(
        Call[] calldata calls,
        bytes calldata hookData,
        address // executor
    ) external payable returns (bytes memory preCheckRet) {
        (address token, uint256 maxTotalAmount) = abi.decode(
            hookData,
            (address, uint256)
        );

        uint256 initialBalance = IERC20(token).balanceOf(msg.sender);
        uint256 totalAmount = 0;

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
        bytes calldata, // hookData
        address // executor
    ) external payable {
        (address token, uint256 initialBalance, uint256 totalAmount) = abi
            .decode(preHookRet, (address, uint256, uint256));

        uint256 finalBalance = IERC20(token).balanceOf(msg.sender);
        require(
            initialBalance - finalBalance == totalAmount,
            "Balance mismatch: transfer amounts do not match"
        );
    }
}
