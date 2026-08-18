// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IValidator} from "./interfaces/IValidator.sol";
import {ECDSAValidatorLib} from "./libraries/ECDSAValidatorLib.sol";
import {PasskeyValidatorLib} from "./libraries/PasskeyValidatorLib.sol";
import {Static} from "./libraries/Static.sol";

abstract contract ValidationManager {
    /// @notice Validates expiry has not passed
    /// @dev Checks if the given expiry timestamp is in the past
    /// @param expiry Unix timestamp expiry
    /// @return bool True if expired, false otherwise
    function _isExpired(uint48 expiry) internal view virtual returns (bool) {
        return expiry != 0 && expiry < block.timestamp;
    }

    /// @notice Computes the effective ERC-4337 expiration for a signed operation
    /// @dev A zero value means no expiration and is therefore treated as infinity.
    ///      Returns zero only when both inputs are zero; otherwise returns the
    ///      finite input or the earlier of the two finite expirations.
    /// @param validUntil Expiration authenticated by the operation signature
    /// @param keyExpiration Expiration configured for the signing owner
    /// @return effectiveValidUntil The upper time bound to encode in validationData
    function _getEffectiveValidUntil(
        uint48 validUntil,
        uint48 keyExpiration
    ) internal pure returns (uint48 effectiveValidUntil) {
        if (validUntil == 0) return keyExpiration;
        if (keyExpiration == 0) return validUntil;
        return validUntil > keyExpiration ? keyExpiration : validUntil;
    }

    /// @notice Validates a signature using built-in validators or external validator contracts
    /// @dev Three validation methods are supported:
    ///      1. ECDSA validation (when validator == address(1)): Uses ECDSAValidatorLib for validation
    ///      2. Passkey validation (when validator == address(2)): Uses PasskeyValidatorLib for P256 validation
    ///      3. External validator (any other address): Calls the validator contract
    /// @param validator Address of the validator to use (1 for ECDSA, 2 for Passkey, or external contract)
    /// @param keyHash The public key hash to look up
    /// @param typedDataHash typed data hash to be validated
    /// @param validationData Signature data specific to the validator type
    /// @return bool True if validation succeeds, false otherwise
    /// @custom:security Ensure validator contracts are properly verified and authorized before use
    function _validateSignature(
        address validator,
        bytes32 keyHash,
        bytes32 typedDataHash,
        bytes calldata validationData
    ) internal view returns (bool) {
        // Use built-in ECDSA validator
        if (validator == Static.ECDSA_VALIDATOR_ADDRESS) {
            return
                ECDSAValidatorLib.validateSignature(
                    keyHash,
                    typedDataHash,
                    validationData
                );
        }

        // Use built-in Passkey validator
        if (validator == Static.PASSKEY_VALIDATOR_ADDRESS) {
            return
                PasskeyValidatorLib.validateSignature(
                    keyHash,
                    typedDataHash,
                    validationData
                );
        }

        // Use external validator contract
        try
            IValidator(validator).validateSignature(
                keyHash,
                typedDataHash,
                validationData
            )
        returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
}
