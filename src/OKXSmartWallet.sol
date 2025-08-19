// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {ERC4337Account} from "./ERC4337Account.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

contract OKXSmartWallet is
    ISmartWallet,
    ERC4337Account,
    UUPSUpgradeable,
    Initializable
{
    constructor() {
        _disableInitializers();
    }

    modifier onlyEntryPointOrSelf() {
        if (msg.sender != entryPoint() && msg.sender != address(this)) {
            revert Unauthorized();
        }
        _;
    }

    function initilize(
        bytes32[] calldata owners,
        address[] calldata validators
    ) external initializer {}

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyEntryPointOrSelf {}

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override onlyEntryPointOrSelf returns (uint256 validationData) {}
}
