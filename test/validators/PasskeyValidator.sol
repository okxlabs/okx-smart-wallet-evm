// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IValidator} from "../../src/interfaces/IValidator.sol";
import {PasskeyValidatorLib} from "../../src/libraries/PasskeyValidatorLib.sol";

contract PasskeyValidator is IValidator {
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) external view returns (bool) {
        return
            PasskeyValidatorLib.validateSignature(
                keyHash,
                messageHash,
                validatorData
            );
    }
}
