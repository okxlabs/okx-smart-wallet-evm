// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IValidator {
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) external view returns (bool);
}
