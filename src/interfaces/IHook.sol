// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Call} from "src/Types.sol";

interface IHook {
    function preCheck(
        Call[] calldata calls,
        bytes calldata hookData,
        address executor
    ) external payable returns (bytes calldata preCheckRet);

    function postCheck(
        bytes calldata preCheckRet,
        bytes calldata hookData,
        address executor
    ) external payable;
}
