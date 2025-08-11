// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IWalletCore} from "../interfaces/IWalletCore.sol";
import {IStorage} from "../interfaces/IStorage.sol";
import {IExecutor} from "../interfaces/IExecutor.sol";
import {Session, Call} from "../Types.sol";

contract MockExecutor {
    IWalletCore account;

    constructor(IWalletCore _account) {
        account = _account;
    }

    function execute(
        Call[] calldata calls,
        Session calldata session
    ) external payable {
        account.executeFromExecutor(calls, session);
    }

    function validateSession(Session calldata session) external view {
        IExecutor(address(account)).validateSession(session);
    }
}
