// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {ERC712} from "./ERC712.sol";
import {ERC7201} from "./ERC7201.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {OwnersManager} from "./OwnersManager.sol";
import {NonceManager} from "./NonceManager.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {ExecutionLogic} from "./ExecutionLogic.sol";
import {FallbackHandler} from "./FallbackHandler.sol";
import {Call, BatchedCall, InitialOwner} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {Static} from "./libraries/Static.sol";
import {IHook} from "./interfaces/IHook.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC4337Account} from "./ERC4337Account.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {BatchedCallLib} from "./libraries/BatchedCallLib.sol";
import {AllowanceManager} from "./AllowanceManager.sol";

// Do not set any states in this contract
contract SmartWallet is
    ISmartWallet,
    ERC7201,
    ERC4337Account,
    OwnersManager,
    NonceManager,
    ValidationLogic,
    ExecutionLogic,
    ERC712,
    FallbackHandler,
    Initializable,
    AllowanceManager
{
    using ECDSA for bytes32;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using BatchedCallLib for BatchedCall;

    uint256 private constant SIG_VALIDATION_FAILED = 1 << 96;

    address public immutable IMPLEMENTATION;

    constructor() {
        IMPLEMENTATION = address(this);
        _disableInitializers();
    }

    modifier onlyOwnerOrEntryPoint() override {
        if (msg.sender == entryPoint() || msg.sender == address(this)) {
            _;
            return;
        }
        
        bytes32 keyHash = keccak256(abi.encodePacked(msg.sender));
        address validator = ownerValidators[keyHash];
        
        if (validator == address(0)) {
            revert Errors.NotFromSelf();
        }
        
        uint256 settings = ownerSettings[keyHash];
        if (settings != 0 && isSettingsExpired(settings)) {
            revert Errors.OwnerExpired();
        }
        _;
    }

    /**
     * @notice Initializes the SmartWallet with initial owners
     * @dev Storage is now integrated directly into SmartWallet
     * @param initialOwners Array of tuples containing keyHash and validator address pairs
     */
    function initialize(
        InitialOwner[] calldata initialOwners
    ) public initializer {
        // Set up initial owners
        // isAdmin = true, expiration = 0 (never expires), hook = address(0)
        uint256 settings = packSettings(true, 0, address(0));
        uint256 len = initialOwners.length;
        if (len == 0) {
            /// revert Errors.InvalidOwnersAndValidatorsLength();
        }
        for (uint256 i = 0; i < len; i++) {
            bytes32 keyHash = initialOwners[i].keyHash;
            address validator = initialOwners[i].validator;

            if (validator == address(0)) {
                revert Errors.InvalidValidatorImpl(validator);
            }

            // Set admin settings for initial owners
            _setValidatorWithSettings(keyHash, validator, settings);
        }
    }

    /**
     * @notice Executes multiple contract calls in a single transaction
     * @dev Only callable by the account itself
     * @param calls Array of Call structs containing destination address, value, and calldata
     */
    function execute(Call[] calldata calls) external onlyOwnerOrEntryPoint {
        _batchCall(calls, keccak256(abi.encodePacked(msg.sender)));
    }

    /**
     * @notice  Executes a validated call and subsequent batch of user's calls sent by a relayer.
     * @dev
     * 1) The validator must be previously registered and the validation data must be valid
     * 2) Validator is looked up from keyHash in validatorData
     * @param batchedCall BatchedCall struct containing calls, nonce, and expiry
     * @param validatorData Encoded data containing keyHash and signature: pubkeyHash + signatures
     */
    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external {
        // Check transaction expiry
        if (isExpired(batchedCall.expiry))
            revert Errors.ExpiryPassed(batchedCall.expiry);

        // Validate and update nonce
        if (!validateAndUpdateNonce(batchedCall.nonce))
            revert Errors.InvalidNonce(batchedCall.nonce);

        // Extract keyHash and validate validator
        bytes32 keyHash = bytes32(validatorData[:32]);
        address validator = getVerifiedValidator(keyHash);
        if (validator == address(0)) revert Errors.InvalidKeyHash(keyHash);

        // Validate signature
        if (
            !_validateSignature(
                validator,
                keyHash,
                hashTypedData(batchedCall.hash()),
                validatorData[32:]
            )
        ) revert Errors.InvalidSignature();

        _batchCall(batchedCall.calls, keyHash);

        emit ExecuteSuccessEvent(
            keccak256(abi.encode(batchedCall.calls)),
            msg.sender,
            batchedCall.nonce
        );
    }

    /**
     * @notice Simulate a sponsored transaction, measuring gas costs for validation and execution, then reverts with detailed metrics.
     * @dev Always reverts with `Errors.SimulateExecution` once validation and the sponsor call succeed.
     * 1) If the simulation fails during validation or the sponsor call, those other errors bubble up directly instead.
     * 2) "Successful simulation" means both validation and the sponsorship call passed.
     *    Any failure in the user’s batch calls is then captured in `errorData` and surfaced inside the `SimulateExecution` revert.
     * @param batchedCall BatchedCall struct containing calls, nonce, and expiry
     * @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
     */
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external {
        // Check transaction expiry
        if (isExpired(batchedCall.expiry)) {
            // revert Errors.ExpiryPassed(batchedCall.expiry);
        }

        // Validate and update nonce
        if (!validateAndUpdateNonce(batchedCall.nonce)) {
            // revert Errors.InvalidNonce(batchedCall.nonce);
        }

        // Extract keyHash and validate validator
        bytes32 keyHash = bytes32(validatorData[:32]);
        address validator = getVerifiedValidator(keyHash);

        if (validator == address(0)) {
            // revert Errors.InvalidKeyHash(keyHash);
        }

        // Validate signature
        if (
            !_validateSignature(
                validator,
                keyHash,
                hashTypedData(batchedCall.hash()),
                validatorData[32:]
            )
        ) {
            // revert Errors.InvalidSignature();
        }

        _batchCall(batchedCall.calls, keyHash);

        emit ExecuteSuccessEvent(
            keccak256(abi.encode(batchedCall.calls)),
            msg.sender,
            batchedCall.nonce
        );
        revert Errors.SimulateExecution();
    }

    /**
     * @notice Executes multiple contract calls in a single transaction
     * @dev Reverts if any of the calls fail
     * @param calls Array of Call structs containing destination address, value, and calldata
     */
    function _batchCall(Call[] calldata calls, bytes32 keyHash) internal {
        uint256 settings = ownerSettings[keyHash];
        address hookAddress = getHook(settings);

        bool isAdmin = isAdmin(settings);

        bytes memory ret;

        if (hookAddress != address(0)) {
            ret = IHook(hookAddress).preCheck(calls, msg.sender);
        }

        for (uint256 i; i < calls.length; i++) {
            if (calls[i].target == address(this) && !isAdmin) {
                revert Errors.NonAdminSelfCall();
            }
            _call(calls[i]);
        }

        if (hookAddress != address(0)) {
            IHook(hookAddress).postCheck(ret, msg.sender);
        }
    }

    /// @notice Validate the user operation
    /// @param userOp The user operation to be validated
    /// @param userOpHash The hash of the user operation
    /// @param missingAccountFunds The missing account funds
    /// @return validationData The validation data
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        _payPrefund(missingAccountFunds);

        bytes32 keyHash = bytes32(userOp.signature[0:32]);
        address validator = getVerifiedValidator(keyHash);
        if (validator == address(0)) return SIG_VALIDATION_FAILED;

        if (
            !_validateSignature(
                validator,
                keyHash,
                userOpHash,
                userOp.signature[32:]
            )
        ) return SIG_VALIDATION_FAILED;
        return validationData;
    }

    /**
     * @notice Implements EIP-1271 signature validation standard
     * @dev There are two types of signatures:
     *      1. 65 bytes: ECDSA signature for EOA compatibility
     *      2. >65 bytes: abi.encode(keyHash, signature) for validator-based validation
     * @param _hash The hash of the data to be validated
     * @param signature The signature to be validated
     * @return bytes4 Returns Static.MAGIC_VALUE (0x1626ba7e) if valid, Static.INVALID_VALUE (0xffffffff) if invalid
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
            if (recovered == address(this)) return Static.MAGIC_VALUE;
        }

        // Extract keyHash and signature from the input
        if (signature.length > 32) {
            bytes32 keyHash = bytes32(signature[:32]);

            // Create bound hash for EIP-1271 validation
            bytes32 boundHash = keccak256(
                abi.encode(bytes32(block.chainid), address(this), _hash)
            );
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

            // Use _validateSignature with calldata signature directly
            address validator = getVerifiedValidator(keyHash);
            if (validator == address(0)) return Static.INVALID_VALUE;

            return
                _validateSignature(validator, keyHash, digest, signature[32:])
                    ? Static.MAGIC_VALUE
                    : Static.INVALID_VALUE;
        }
        return Static.INVALID_VALUE;
    }
}
