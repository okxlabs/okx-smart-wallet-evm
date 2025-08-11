// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Session} from "src/Types.sol";

interface IExecutor {
    function getSessionTypedHash(
        Session calldata session
    ) external view returns (bytes32);

    function validateSession(Session calldata session) external view;
}
