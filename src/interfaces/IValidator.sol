// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IValidator {
    function validate(
        bytes32 msgHash,
        bytes calldata validatorData
    ) external view returns (bool);
}
