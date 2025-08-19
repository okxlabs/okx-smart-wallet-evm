// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Call} from "src/Types.sol";

interface IHook {
    function preCheck(
        Call[] calldata calls,
        address executor
    ) external payable returns (bytes memory preCheckRet);

    function postCheck(
        bytes calldata preCheckRet,
        address executor
    ) external payable;
}
