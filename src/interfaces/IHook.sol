// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Call} from "src/Types.sol";

interface IHook {
    /// @notice Called before execution of calls to perform pre-execution checks
    /// @dev Can be used for validation, access control, or state preparation
    /// @param calls Array of calls that will be executed
    /// @param executor Address of the executor initiating the calls
    /// @return preCheckRet Data to be passed to postCheck after execution
    function preCheck(
        Call[] calldata calls,
        address executor
    ) external payable returns (bytes memory preCheckRet);

    /// @notice Called after execution of calls to perform post-execution checks
    /// @dev Can be used for state validation, cleanup, or post-processing
    /// @param preCheckRet Data returned from preCheck
    /// @param executor Address of the executor who initiated the calls
    function postCheck(
        bytes calldata preCheckRet,
        address executor
    ) external payable;
}
