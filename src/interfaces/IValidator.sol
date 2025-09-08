// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IValidator {
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) external view returns (bool);
}
