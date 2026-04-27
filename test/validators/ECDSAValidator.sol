// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IValidator} from "../../src/interfaces/IValidator.sol";
import {ECDSAValidatorLib} from "../../src/libraries/ECDSAValidatorLib.sol";

contract ECDSAValidator is IValidator {
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) external pure returns (bool) {
        return
            ECDSAValidatorLib.validateSignature(
                keyHash,
                messageHash,
                validatorData
            );
    }
}
