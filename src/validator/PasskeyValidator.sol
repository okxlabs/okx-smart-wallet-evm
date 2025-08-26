// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IValidator} from "../interfaces/IValidator.sol";
import {PasskeyValidatorLib} from "../libraries/PasskeyValidatorLib.sol";

/// @title PasskeyValidator
/// @notice Validator contract for Passkey signatures using P256 verification
/// @dev Implements IValidator interface using PasskeyValidatorLib for actual validation logic
contract PasskeyValidator is IValidator {
    /// @notice Validates a Passkey signature using P256 verification with optional Merkle proof support
    /// @dev Delegates validation to PasskeyValidatorLib
    /// @param keyHash The hash of the registered public key (keccak256(abi.encodePacked(pubKeyX, pubKeyY)))
    /// @param messageHash The hash of the message being validated (will be SHA256 hashed internally)
    /// @param validatorData Encoded Passkey signature data (PasskeySignature struct + optional Merkle proofs)
    /// @return bool True if the signature is valid
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
