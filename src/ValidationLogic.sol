// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IValidation} from "./interfaces/IValidation.sol";
import {IStorage} from "./interfaces/IStorage.sol";
import {IValidator} from "./interfaces/IValidator.sol";

import {Call} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {Static} from "./libraries/Static.sol";

abstract contract ValidationLogic is IValidation {
    using Clones for address;
    using ECDSA for bytes32;

    bytes32 private constant CALLS_TYPEHASH =
        keccak256(
            "Calls(address wallet,uint256 nonce,Call[] calls)Call(address target,uint256 value,bytes data)"
        );
    bytes32 private constant CALL_TYPEHASH =
        keccak256("Call(address target,uint256 value,bytes data)");

    /**
     * @notice Modifier that simulates validation of a sponsored transaction using keyHash-based validator lookup
     * @dev Reads and updates the nonce from storage, then performs a simulation validation
     * @param calls Array of calls to be simulated
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    modifier simulateValidateCalls(
        Call[] calldata calls,
        bytes calldata validatorData
    ) {
        {
            // Extract keyHash directly from calldata
            bytes32 keyHash = bytes32(validatorData[:32]);
            address validator = getMainStorage().getValidator(keyHash);
            if (validator == address(0))
                revert Errors.InvalidValidator(validator);

            uint256 nonce = getMainStorage().readAndUpdateNonce(validator);
            _simulateValidateCall(nonce, calls, validatorData);
        }
        _;
    }

    /**
     * @notice Validates a signature using the provided validator.
     * @dev Performs validator authorization check and constructs an EIP-191 digest bound to the chain and contract.
     *      Returns false if the validator is not authorized via `getMainStorage().validateValidator(...)`.
     * @param validator The address of the validator contract.
     * @param _hash The original message hash to be signed (pre-bound).
     * @param signature The signature data to validate against the digest.
     * @return isValid True if the signature is valid and the validator is authorized, false otherwise.
     */
    function _validateSignature(
        address validator,
        bytes32 _hash,
        bytes calldata signature
    ) internal view returns (bool) {
        if (validator == address(0)) {
            return false;
        }

        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), address(this), _hash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

        return _validate(validator, digest, signature);
    }

    /**
     * @notice Generates an EIP-712 compliant typed data hash for transaction validation
     * @dev Combines the message hash with the domain separator using EIP-712 standard
     * @param nonce Current transaction nonce used to prevent replay attacks
     * @param calls Array of calls to be validated
     * @return bytes32 The EIP-712 typed data hash ready for signing
     */
    function getValidationTypedHash(
        uint256 nonce,
        Call[] calldata calls
    ) public view returns (bytes32) {
        return _hashTypedDataV4(_getValidationHash(nonce, calls));
    }

    /**
     * @notice Computes the deterministic address of a validator
     * @dev Uses the validator implementation and signer to calculate the expected address
     * @param validatorImpl The implementation contract address for the validator
     * @param immutableArgs The initialization code of the validator
     * @return address The predicted validator contract address
     */
    function computeValidatorAddress(
        address validatorImpl,
        bytes calldata immutableArgs
    ) public view returns (address) {
        return
            _computeValidatorAddress(
                validatorImpl,
                immutableArgs,
                Static.VALIDATOR_SALT,
                address(this)
            );
    }

    /**
     * @notice Internal function to validate a sponsored transaction using keyHash-based validator lookup
     * @dev Decodes validatorData to extract keyHash and signature, then looks up the validator
     * @param nonce Current transaction nonce from storage (passed from caller)
     * @param calls Array of calls to be validated
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    function _validateCall(
        uint256 nonce,
        Call[] calldata calls,
        bytes calldata validatorData
    ) internal view {
        // Extract keyHash and signature directly from calldata
        bytes32 keyHash = bytes32(validatorData[:32]);
        bytes calldata signature = validatorData[32:];

        // Look up validator address from keyHash
        address validator = getMainStorage().getValidator(keyHash);
        if (validator == address(0)) revert Errors.InvalidValidator(validator);

        bytes32 typedDataHash = getValidationTypedHash(nonce, calls);
        // Call the validation function directly
        bool isValid = _validate(validator, typedDataHash, signature);
        if (!isValid) revert Errors.InvalidSignature();
    }

    /**
     * @notice Simulates a validator's on‐chain validation using keyHash-based validator lookup
     * @dev Decodes validatorData to extract keyHash and signature, then looks up the validator
     * @param nonce Current transaction nonce from storage
     * @param calls Array of calls to be validated
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    function _simulateValidateCall(
        uint256 nonce,
        Call[] calldata calls,
        bytes calldata validatorData
    ) internal view {
        // Extract keyHash and signature directly from calldata
        bytes32 keyHash = bytes32(validatorData[:32]);
        bytes calldata signature = validatorData[32:];

        // Look up validator address from keyHash
        address validator = getMainStorage().getValidator(keyHash);
        if (validator == address(0)) revert Errors.InvalidValidator(validator);

        bytes32 typedDataHash = getValidationTypedHash(nonce, calls);
        bool isValid = _simulateValidate(validator, typedDataHash, signature);

        if (!isValid) {
            revert Errors.NoncompliantValidator();
        }
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
     * @notice Creates a hash of the transaction data for validation
     * @dev Combines nonce and calls into a single hash using EIP-712 encoding
     * @param nonce Transaction nonce for replay protection
     * @param calls Array of calls to execute
     * @return bytes32 Hash of the transaction data
     */
    function _getValidationHash(
        uint256 nonce,
        Call[] calldata calls
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CALLS_TYPEHASH,
                    _walletImplementation(),
                    nonce,
                    _getCallsHash(calls)
                )
            );
    }

    /**
     * @notice Computes the deterministic address of a validator contract before deployment
     * @param validatorImpl The implementation address of the validator
     * @param immutableArgs The initialization data for the validator
     * @param creationSalt A unique salt for deterministic deployment
     * @param deployer The address that will deploy the validator
     * @return The predicted address where the validator will be deployed
     */
    function _computeValidatorAddress(
        address validatorImpl,
        bytes calldata immutableArgs,
        bytes32 creationSalt,
        address deployer
    ) internal pure returns (address) {
        return
            validatorImpl.predictDeterministicAddressWithImmutableArgs(
                immutableArgs,
                creationSalt,
                deployer
            );
    }

    /// @notice Returns the main storage contract interface
    /// @return IStorage The IStorage contract instance used by the wallet
    function getMainStorage() public view virtual returns (IStorage);

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
     * @notice Validates a transaction or operation using either ECDSA signatures or an external validator contract
     * @dev Two validation methods are supported:
     *      1. ECDSA validation (when validator == address(1)): Recovers signer from signature and verifies it matches the wallet address
     *      2. External validator (any other address): Calls the validator contract and checks if it's authorized to validate
     * @param validator Address of the validator to use (address(1) for ECDSA signature validation)
     * @param typedDataHash EIP-712 typed data hash of the data to be validated
     * @param signature For ECDSA: the 65-byte signature; For external validators: custom validation data
     * @return bool True if validation succeeds, false otherwise
     * @custom:security Ensure validator contracts are properly verified and authorized before use
     */
    function _validate(
        address validator,
        bytes32 typedDataHash,
        bytes calldata signature
    ) internal view virtual returns (bool);

    /**
     * @notice Simulates gas estimation for a validator without executing state changes.
     * @dev Two validation methods are supported:
     *      1. ECDSA validation (when validator == address(1)): Recovers signer from signature and verifies it matches the wallet address
     *      2. External validator (any other address): Calls the validator contract and checks if it's authorized to validate
     * @param validator Address of the validator to use (address(1) for ECDSA signature validation)
     * @param typedDataHash EIP-712 typed data hash of the data to be validated
     * @param signature For ECDSA: the 65-byte signature; For external validators: custom validation data
     */
    function _simulateValidate(
        address validator,
        bytes32 typedDataHash,
        bytes calldata signature
    ) internal view virtual returns (bool);
}
