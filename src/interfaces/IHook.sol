// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Call} from "src/Types.sol";

interface IHook {
    /// @notice Pre-execution hook for validating and preparing calls
    /// @dev Called before executing the main transaction batch
    /// @param calls Array of calls that will be executed
    /// @param executor Address of the account executing the calls
    /// @return preCheckRet Data to be passed to postCheck after execution
    function preCheck(
        Call[] calldata calls,
        address executor
    ) external payable returns (bytes memory preCheckRet);

    /// @notice Post-execution hook for cleanup and verification
    /// @dev Called after successful execution of the main transaction batch
    /// @param preCheckRet Data returned from preCheck
    /// @param executor Address of the account that executed the calls
    function postCheck(
        bytes calldata preCheckRet,
        address executor
    ) external payable;
}
