// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IValidation} from "./interfaces/IValidation.sol";
import {IOwnersManager} from "./interfaces/IOwnersManager.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {ECDSAValidatorLib} from "./libraries/ECDSAValidatorLib.sol";
import {PasskeyValidatorLib} from "./libraries/PasskeyValidatorLib.sol";

import {Call, BatchedCall} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {Static} from "./libraries/Static.sol";

abstract contract ValidationLogic is IValidation {
    using Clones for address;
    using ECDSA for bytes32;

    bytes32 private constant BATCHED_CALL_TYPEHASH =
        keccak256(
            "BatchedCall(address wallet,Call[] calls,uint256 nonce,uint256 expiry)Call(address target,uint256 value,bytes data)"
        );
    bytes32 private constant CALL_TYPEHASH =
        keccak256("Call(address target,uint256 value,bytes data)");

    /**
     * @notice Generates an EIP-712 compliant typed data hash for transaction validation
     * @dev Combines the message hash with the domain separator using EIP-712 standard
     * @param batchedCall BatchedCall struct containing calls, nonce, and expiry
     * @return bytes32 The EIP-712 typed data hash ready for signing
     */
    function getValidationTypedHash(
        BatchedCall calldata batchedCall
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                BATCHED_CALL_TYPEHASH,
                _walletImplementation(),
                _getCallsHash(batchedCall.calls),
                batchedCall.nonce,
                batchedCall.expiry
            )
        );
        return _hashTypedDataV4(structHash);
    }

    /**
     * @notice Computes a keccak256 hash over an array of Call structs.
     * @dev Iterates through the calls and encodes each individual call hash, then hashes the concatenation.
     * @param calls Array of Call structs to hash.
     * @return Hash representing the full sequence of calls.
     */
    function _getCallsHash(
        Call[] calldata calls
    ) private pure returns (bytes32) {
        bytes memory encoded;
        for (uint i = 0; i < calls.length; i++) {
            encoded = abi.encodePacked(encoded, _getCallHash(calls[i]));
        }
        return keccak256(encoded);
    }

    /**
     * @notice Computes a keccak256 hash for a single Call struct.
     * @dev Encodes the call using EIP-712-style struct hashing.
     * @param call A single Call struct including target, value, and calldata.
     * @return Hash of the call.
     */
    function _getCallHash(Call calldata call) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CALL_TYPEHASH,
                    call.target,
                    call.value,
                    keccak256(call.data)
                )
            );
    }

    /**
     * @notice Validates expiry has not passed
     * @dev Checks if the given expiry timestamp is in the past
     * @param expiry Unix timestamp expiry
     * @return bool True if expired, false otherwise
     */
    function isExpired(uint256 expiry) internal view returns (bool) {
        return expiry != 0 && expiry < block.timestamp;
    }

    /// @notice Returns the address of the current wallet implementation contract
    /// @return address The address of this contract used as the implementation
    function _walletImplementation() internal view virtual returns (address);

    /// @notice Creates the EIP-712 typed data hash for signing
    /// @param structHash The struct hash to wrap with the domain separator
    /// @return bytes32 The final EIP-712 typed data hash ready to be signed
    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view virtual returns (bytes32);

    /**
     * @notice Validates a signature using built-in validators or external validator contracts
     * @dev Three validation methods are supported:
     *      1. ECDSA validation (when validator == address(1)): Uses ECDSAValidatorLib for validation
     *      2. Passkey validation (when validator == address(2)): Uses PasskeyValidatorLib for P256 validation
     *      3. External validator (any other address): Calls the validator contract
     * @param validator Address of the validator to use (1 for ECDSA, 2 for Passkey, or external contract)
     * @param keyHash The public key hash to look up
     * @param typedDataHash EIP-712 typed data hash of the data to be validated
     * @param validationData Signature data specific to the validator type
     * @return bool True if validation succeeds, false otherwise
     * @custom:security Ensure validator contracts are properly verified and authorized before use
     */
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
