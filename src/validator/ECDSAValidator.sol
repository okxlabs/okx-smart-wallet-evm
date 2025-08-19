// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IValidator} from "../interfaces/IValidator.sol";
import {ECDSAValidatorLib} from "../libraries/ECDSAValidatorLib.sol";

/**
 * @title ECDSAValidator
 * @notice Validator contract for ECDSA signature validation
 * @dev Implements IValidator interface using ECDSAValidatorLib for actual validation logic
 */
contract ECDSAValidator is IValidator {
    /**
     * @notice Validates a signature by checking if the recovered signer's hash matches keyHash
     * @dev Delegates validation to ECDSAValidatorLib
     * @param keyHash The hash of the expected public key/address
     * @param messageHash The hash of the message being validated
     * @param validatorData The ECDSA signature to verify
     * @return bool True if recovered address hash matches keyHash
     */
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
