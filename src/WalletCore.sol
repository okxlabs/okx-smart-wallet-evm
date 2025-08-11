// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IWalletCore} from "./interfaces/IWalletCore.sol";
import {IStorage} from "./interfaces/IStorage.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {ExecutionLogic} from "./ExecutionLogic.sol";
import {ExecutorLogic} from "./ExecutorLogic.sol";
import {FallbackHandler} from "./FallbackHandler.sol";
import {Call, Session} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {GasEstimateUtil} from "./libraries/GasEstimateUtil.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {Static} from "./libraries/Static.sol";

// Do not set any states in this contract
contract WalletCore is
    IWalletCore,
    ValidationLogic,
    ExecutionLogic,
    ExecutorLogic,
    FallbackHandler,
    EIP712
{
    using Clones for address;
    using ECDSA for bytes32;

    // EIP-1271
    bytes4 private constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 private constant INVALID_VALUE = 0xffffffff;

    address public immutable ADDRESS_THIS;
    address public immutable MAIN_STORAGE_IMPL;

    constructor(
        address mainStorageImpl,
        string memory name,
        string memory version
    ) EIP712(name, version) {
        // Check name/version lengths, assure remain stateless
        if (bytes(name).length >= 32) {
            revert Errors.NameTooLong();
        }
        if (bytes(version).length >= 32) {
            revert Errors.VersionTooLong();
        }
        ADDRESS_THIS = address(this);
        MAIN_STORAGE_IMPL = mainStorageImpl;
    }

    /**
     * @notice Initializes the wallet core
     * @dev Can only be called once during account creation with each storage version
     */
    function initialize() public returns (address storageAddress) {
        storageAddress = _getStorage(MAIN_STORAGE_IMPL);
        if (storageAddress.code.length != 0) {
            return storageAddress;
        }

        // immutable args
        bytes memory owner = abi.encode(address(this));

        MAIN_STORAGE_IMPL.cloneDeterministicWithImmutableArgs(
            owner,
            Static.STORAGE_SALT
        );

        emit StorageCreated(storageAddress);
        return storageAddress;
    }

    /**
     * @notice Executes multiple contract calls in a single transaction
     * @dev Only callable by the account itself
     * @param calls Array of Call structs containing destination address, value, and calldata
     */
    function executeFromSelf(Call[] calldata calls) external onlySelf {
        _batchCall(calls);
    }

    /**
     * @notice  Executes a validated call and subsequent batch of user's calls sent by a relayer.
     * @dev
     * 1) The validator must be previously registered and the validation data must be valid
     * 2) Validator is looked up from keyHash in validatorData
     * @param calls Array of Call structs to be executed, each containing destination address, value, and calldata
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    function executeFromRelayer(
        Call[] calldata calls,
        bytes calldata validatorData
    ) external {
        // Extract keyHash directly from calldata to get validator address for nonce
        bytes32 keyHash = bytes32(validatorData[:32]);
        address validator = getMainStorage().getValidator(keyHash);
        if (validator == address(0)) revert Errors.InvalidValidator(validator);

        uint256 nonce = IStorage(initialize()).readAndUpdateNonce(validator);

        _validateCall(nonce, calls, validatorData);

        _batchCall(calls);
    }

    /**
     * @notice Simulate a sponsored transaction, measuring gas costs for validation and execution, then reverts with detailed metrics.
     * @dev Always reverts with `Errors.SimulateExecution` once validation and the sponsor call succeed.
     * 1) If the simulation fails during validation or the sponsor call, those other errors bubble up directly instead.
     * 2) "Successful simulation" means both validation and the sponsorship call passed.
     *    Any failure in the user’s batch calls is then captured in `errorData` and surfaced inside the `SimulateExecution` revert.
     * @param calls Array of Call structs to be executed, each containing destination address, value, and calldata
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    function simulateExecuteFromRelayer(
        Call[] calldata calls,
        bytes calldata validatorData
    ) external {
        uint256 gasStart;
        uint256 gasEnd;
        uint256 totalGas;
        bytes memory returnData;
        bytes memory payload = abi.encodeWithSelector(
            this.simulateSponsoredTxn.selector,
            0,
            calls,
            validatorData
        );

        // measure gas used through external call
        assembly {
            gasStart := gas()
            pop(
                call(
                    gasStart,
                    address(), // address(this)
                    0, // value
                    add(payload, 0x20), // payload mem location
                    mload(payload), // payload size
                    0, // output location
                    0 // output size, to copy manually
                )
            )
            gasEnd := gas()
            let retSz := returndatasize() // get how much data was returned
            returnData := mload(0x40) // load free memory pointer
            mstore(returnData, retSz) // store length in the first slot of returnData
            returndatacopy(add(returnData, 0x20), 0, retSz) // copy returned data right after the length slot
            // update free-memory pointer: round up to nearest 32 bytes
            // roundUpTo32(retSz) ≡ (retSz + 31) & ~31
            mstore(
                0x40,
                add(add(returnData, 0x20), and(add(retSz, 0x1f), not(0x1f)))
            )
        }

        // decode gas estimation result
        if (bytes4(returnData) != Errors.GasEstimates.selector)
            revert Errors.SimulateExecution(0, 0, returnData);

        (uint256 executionGas, bytes memory errorData) = GasEstimateUtil
            .decodeGasEstimates(returnData);

        totalGas =
            21000 +
            GasEstimateUtil.intrinsicGas(payload) +
            (gasStart - gasEnd);

        revert Errors.SimulateExecution(executionGas, totalGas, errorData);
    }

    /**
     * @notice Simulates validation and execution of a sponsored transaction.
     * - Called via low-level `call(address(this), ...)` from `simulateExecuteWithSponsor` to simulate an  on-chain transaction.
     * - This setup enables accurate gas measurement, proper context for validation, and revert data capturing.
     * @param calls The user's batch of contract calls.
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    function simulateSponsoredTxn(
        Call[] calldata calls,
        bytes calldata validatorData
    ) external {
        // Extract keyHash directly from calldata for simulation
        bytes32 keyHash = bytes32(validatorData[:32]);
        address validator = getMainStorage().getValidator(keyHash);
        if (validator == address(0)) revert Errors.InvalidValidator(validator);

        uint256 nonce = IStorage(initialize()).readAndUpdateNonce(validator);

        _simulateValidateCall(nonce, calls, validatorData);
        _batchCall(calls);
    }

    /**
     * @notice Executes a batch of calls through a registered executor using a valid session
     * @dev Only callable by pre-signed sessions with valid signatures
     * @dev Executes hooks before and after the batch call if specified in the session
     * @param calls Array of Call structs to be executed, each containing destination address, value, and calldata
     * @param session Session struct containing executor details, permissions, and hook configurations
     */
    function executeFromExecutor(
        Call[] calldata calls,
        Session calldata session
    ) external onlyValidSession(session, calls) {
        _batchCall(calls);
    }

    /**
     * @notice Registers a validator contract and associates it with a keyHash
     * @dev Only callable by the wallet itself
     * @param keyHash The public key hash to associate with this validator
     * @param validator The address of the validator contract to be registered
     */
    function addValidator(
        bytes32 keyHash,
        address validator
    ) external onlySelf {
        // Check if keyHash is already registered
        address existingValidator = getMainStorage().getValidator(keyHash);
        if (existingValidator != address(0)) {
            revert Errors.ValidatorAlreadyExists();
        }

        // Allow SELF_VALIDATION_ADDRESS, but check other addresses have contract code
        if (
            validator != Static.SELF_VALIDATION_ADDRESS &&
            validator.code.length == 0
        ) {
            revert Errors.InvalidValidatorImpl(validator);
        }

        getMainStorage().setValidator(keyHash, validator);
        emit ValidatorAdded(validator);
    }

    /**
     * @notice Implements EIP-1271 signature validation standard
     * @dev There are two types of signatures:
     *      1. 65 bytes: ECDSA signature for EOA compatibility
     *      2. >65 bytes: abi.encode(keyHash, signature) for validator-based validation
     * @param _hash The hash of the data to be validated
     * @param signature The signature to be validated
     * @return bytes4 Returns MAGIC_VALUE (0x1626ba7e) if valid, INVALID_VALUE (0xffffffff) if invalid
     */
    function isValidSignature(
        bytes32 _hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        // 7702 Post upgrade compatibility: try validate signature for EOA sigs
        // Make sure the _signature can be decoded
        if (signature.length == 65) {
            // Create bound hash for EIP-1271 validation (same as validator path)
            bytes32 boundHash = keccak256(
                abi.encode(bytes32(block.chainid), address(this), _hash)
            );
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

            (address recovered, , ) = ECDSA.tryRecover(digest, signature);
            if (recovered == address(this)) return MAGIC_VALUE;
        }

        if (signature.length <= 65) return INVALID_VALUE;

        // Extract keyHash and signature from the input
        if (signature.length > 32) {
            bytes32 keyHash = bytes32(signature[:32]);

            // Look up validator from keyHash
            address validator = getMainStorage().getValidator(keyHash);
            if (validator == address(0)) return INVALID_VALUE;
            // Create bound hash for EIP-1271 validation
            bytes32 boundHash = keccak256(
                abi.encode(bytes32(block.chainid), address(this), _hash)
            );
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

            // Use _validate with calldata signature directly
            return
                _validate(validator, digest, signature[32:])
                    ? MAGIC_VALUE
                    : INVALID_VALUE;
        }
        return INVALID_VALUE;
    }

    /**
     * @notice Returns the address of the wallet's storage contract
     * @dev Uses deterministic deployment to calculate the storage contract address.
     *      This contract only stores core wallet states. For additional states,
     *      create and query new dedicated storage contracts instead of modifying
     *      this one.
     * @return address The deployed storage contract address for this wallet
     * @custom:architecture New features requiring additional storage should:
     *      1. Deploy a new dedicated storage contract
     *      2. Implement separate getter methods for the new storage
     */
    function getMainStorage()
        public
        view
        override(IWalletCore, ExecutorLogic, ValidationLogic)
        returns (IStorage)
    {
        return IStorage(_getStorage(MAIN_STORAGE_IMPL));
    }

    /**
     * @notice Creates a typed data hash following EIP-712 standard
     * @param structHash The hash of the struct data to be signed
     * @return The final EIP-712 typed data hash that can be signed by a wallet
     */
    function _hashTypedDataV4(
        bytes32 structHash
    )
        internal
        view
        override(EIP712, ExecutorLogic, ValidationLogic)
        returns (bytes32)
    {
        return EIP712._hashTypedDataV4(structHash);
    }

    /**
     * @notice Returns the address of the current wallet implementation
     * @dev This function is used in the proxy pattern to identify the implementation contract
     * @return ADDRESS_THIS The address of this contract, which serves as the implementation
     */
    function _walletImplementation()
        internal
        view
        override(ExecutorLogic, ValidationLogic)
        returns (address)
    {
        return ADDRESS_THIS;
    }

    /**
     * @notice Returns the current nonce value
     * @dev Can be called by anyone
     * @return uint256 The current nonce value
     */
    function getNonce() external view returns (uint256) {
        return getMainStorage().getNonce();
    }

    /**
     * @notice Computes the deterministic address of the wallet's storage contract
     * @dev Uses OpenZeppelin's Clones library to predict the address before deployment
     * @param storageImpl The implementation address of the storage contract
     * @return address The deterministic address where the storage clone will be deployed
     * @custom:args The immutable arguments encoded are:
     *  - address(this): The wallet address that owns this storage
     * @custom:salt A unique salt derived from STORAGE_SALT
     */
    function _getStorage(address storageImpl) internal view returns (address) {
        return
            storageImpl.predictDeterministicAddressWithImmutableArgs(
                abi.encode(address(this)),
                Static.STORAGE_SALT,
                address(this)
            );
    }

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
    ) internal view override(ExecutorLogic, ValidationLogic) returns (bool) {
        if (validator == Static.SELF_VALIDATION_ADDRESS) {
            (address recoveredSigner, , ) = typedDataHash.tryRecover(signature);
            return recoveredSigner == address(this);
        }

        if (validator == address(0)) {
            return false;
        }

        try IValidator(validator).validate(typedDataHash, signature) returns (
            bool result
        ) {
            return result;
        } catch {
            return false;
        }
    }

    /**
     * @notice Validates that a signature was signed by this contract
     * @param typedDataHash The hash of the data that was signed
     * @param signature The ECDSA signature to verify
     * @return bool True if the validation passes, false otherwise
     * @dev Reverts with INVALID_SIGNATURE if the signer is not account itself
     */
    function _validateSelf(
        bytes32 typedDataHash,
        bytes calldata signature
    ) internal view returns (bool) {
        (address recoveredSigner, , ) = typedDataHash.tryRecover(signature);
        return recoveredSigner == address(this);
    }

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
    ) internal view override(ValidationLogic) returns (bool) {
        if (validator == Static.SELF_VALIDATION_ADDRESS) {
            (address recoveredSigner, , ) = typedDataHash.tryRecover(signature);
            return recoveredSigner == address(this);
        }

        if (validator == address(0)) {
            return false;
        }

        try IValidator(validator).validate(typedDataHash, signature) returns (
            bool result
        ) {
            return result;
        } catch {
            return false;
        }
    }

    /**
     * @notice Creates a unique deployment salt by combining validator implementation and init code
     * @param validatorImpl The validator implementation address
     * @param initHash Hash of the validator's initialization code
     * @return bytes32 The computed salt for deterministic deployment
     */
    function computeCreationSalt(
        address validatorImpl,
        bytes32 initHash
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(validatorImpl, initHash));
    }
}
