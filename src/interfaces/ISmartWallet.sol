// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface ISmartWallet {

    error Unauthorized();
    function initilize(bytes32[] calldata owners, address[] calldata validators) external;
}