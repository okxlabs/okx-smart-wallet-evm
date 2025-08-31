// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {ERC712} from "./ERC712.sol";
import {ERC7201} from "./ERC7201.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {OwnersManager} from "./OwnersManager.sol";
import {NonceManager} from "./NonceManager.sol";
import {ValidateManager} from "./ValidateManager.sol";
import {ExecuteManager} from "./ExecuteManager.sol";
import {FallbackHandler} from "./FallbackHandler.sol";
import {Call, BatchedCall, InitialOwner} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {Static} from "./libraries/Static.sol";
import {IHook} from "./interfaces/IHook.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC4337Account, PackedUserOperation} from "./ERC4337Account.sol";
import {BatchedCallLib} from "./libraries/BatchedCallLib.sol";
import {AllowanceManager} from "./AllowanceManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {DecodeLib} from "./libraries/DecodeLib.sol";
import {ChainlessLib} from "./libraries/ChainlessLib.sol";

// Do not set any states in this contract
contract SmartWallet is
    ISmartWallet,
    ERC7201,
    ERC4337Account,
    OwnersManager,
    NonceManager,
    ValidateManager,
    ExecuteManager,
    ERC712,
    FallbackHandler,
    Initializable,
    AllowanceManager,
    UUPSUpgradeable
{
    using ECDSA for bytes32;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using BatchedCallLib for BatchedCall;

    address public immutable IMPLEMENTATION;

    constructor() {
        IMPLEMENTATION = address(this);
        _disableInitializers();
    }

    modifier onlyOwner() {
        // Allow self-calls for EIP-7702 compatibility
        if (msg.sender == address(this)) {
            _;
            return;
        }

        bytes32 keyHash = keccak256(abi.encodePacked(msg.sender));
        if (!hasOwner(keyHash)) {
            revert Errors.InvalidCaller(msg.sender);
        }

        uint256 settings = ownerSettings[keyHash];
        if (settings != 0 && isSettingsExpired(settings)) {
            revert Errors.OwnerExpired();
        }
        _;
    }

    /// @notice Initializes the wallet core with initial owners
    /// @dev Storage is now integrated directly into SmartWallet
    /// @param initialOwners Array of tuples containing keyHash and validator address pairs
    function initialize(
        InitialOwner[] calldata initialOwners
    ) external initializer {
        // Set up initial owners
        // isAdmin = true, expiration = 0 (never expires), hook = address(0)
        uint256 settings = packSettings(true, 0, address(0));
        uint256 len = initialOwners.length;
        for (uint256 i = 0; i < len; i++) {
            bytes32 keyHash = initialOwners[i].keyHash;
            address validator = initialOwners[i].validator;

            _addOwner(keyHash, validator, settings);
        }
    }

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Only callable by the account itself
    /// @param calls Array of Call structs containing destination address, value, and calldata
    function execute(Call[] calldata calls) external onlyOwner {
        _batchCall(calls, keccak256(abi.encodePacked(msg.sender)));
    }

    /// @dev This function is executeable only by the EntryPoint contract, and is the main pathway for UserOperations to be executed.
    /// UserOperations can be executed through the execute function, but another method of authorization (ie through a passed in signature) is required.
    /// userOp.callData is abi.encodePacked(IAccountExecute.executeUserOp.selector, (abi.encode(Call[]))
    /// Note that this contract is only compatible with Entrypoint versions v0.7.0 and v0.8.0. It is not compatible with v0.6.0, as that version does not support the "executeUserOp" selector.
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32
    ) external onlyEntryPoint {
        // Parse the keyHash from the signature. This is the keyHash that has been pre-validated as the correct signer over the UserOp data
        // and must be used to check further on-chain permissions over the call execution.
        bytes32 keyHash = bytes32(userOp.signature[0:32]);

        Call[] calldata calls = DecodeLib.decodeCalls(userOp.callData[4:]);

        _batchCall(calls, keyHash);
    }

    /// @notice  Executes a validated call and subsequent batch of user's calls sent by a relayer.
    /// @dev
    /// 1) The validator must be previously registered and the validation data must be valid
    /// 2) Validator is looked up from keyHash in validatorData
    /// @param batchedCall BatchedCall struct containing calls, nonce, and expiry
    /// @param validatorData Encoded data containing keyHash and signature: pubkeyHash + signatures
    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external {
        // Check transaction expiry
        if (_isExpired(batchedCall.expiry))
            revert Errors.ExpiryPassed(batchedCall.expiry);

        // Validate and update nonce
        if (!validateAndUpdateNonce(batchedCall.nonce))
            revert Errors.InvalidNonce(batchedCall.nonce);

        uint256 nonceKey = batchedCall.nonce >> 64;
        bytes32 dataHash = batchedCall.hash(IMPLEMENTATION);

        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // Validate all calls are allowed to skip chain ID validation
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                revert Errors.InvalidNonceKey(nonceKey);
            }
            dataHash = hashTypedDataSansChainId(dataHash);
        } else {
            dataHash = hashTypedData(dataHash);
        }

        // Extract pubKeyHash and validate validator
        bytes32 pubKeyHash = bytes32(validatorData[:32]);
        address validator = getVerifiedValidator(pubKeyHash);
        if (validator == address(0)) revert Errors.InvalidKeyHash(pubKeyHash);

        // Validate signature
        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                dataHash,
                validatorData[32:]
            )
        ) revert Errors.InvalidSignature();

        _batchCall(batchedCall.calls, pubKeyHash);

        emit ExecuteSuccessEvent(
            keccak256(abi.encode(batchedCall.calls)),
            msg.sender,
            batchedCall.nonce
        );
    }

    /// @notice Simulate a sponsored transaction, measuring gas costs for validation and execution, then reverts with detailed metrics.
    /// @dev Always reverts with `Errors.SimulateExecution` once validation and the sponsor call succeed.
    /// 1) If the simulation fails during validation or the sponsor call, those other errors bubble up directly instead.
    /// 2) "Successful simulation" means both validation and the sponsorship call passed.
    ///    Any failure in the user's batch calls is then captured in `errorData` and surfaced inside the `SimulateExecution` revert.
    /// @param batchedCall BatchedCall struct containing calls, nonce, and expiry
    /// @param validator Validator address intended to be used for validation during execution
    /// @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        address validator,
        bytes calldata validatorData
    ) external {
        // Check transaction expiry
        if (_isExpired(batchedCall.expiry)) {
            // revert Errors.ExpiryPassed(batchedCall.expiry);
        }

        // Validate and update nonce
        if (!validateAndUpdateNonce(batchedCall.nonce)) {
            // revert Errors.InvalidNonce(batchedCall.nonce);
        }

        uint256 nonceKey = batchedCall.nonce >> 64;
        bytes32 dataHash = batchedCall.hash(IMPLEMENTATION);

        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // Validate all calls are allowed to skip chain ID validation
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                // revert Errors.InvalidNonceKey(nonceKey);
            }
            dataHash = hashTypedDataSansChainId(dataHash);
        } else {
            dataHash = hashTypedData(dataHash);
        }

        // Extract pubKeyHash and validate validator
        bytes32 pubKeyHash = bytes32(validatorData[:32]);

        address mockValidator = getVerifiedValidator(pubKeyHash);
        // Use mockValidator to avoid unused variable warning since it is only used for gas measurement
        mockValidator;

        if (validator == address(0)) {
            // revert Errors.InvalidKeyHash(pubKeyHash);
        }

        // Validate signature
        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                dataHash,
                validatorData[32:]
            )
        ) {
            // revert Errors.InvalidSignature();
        }

        _batchCall(batchedCall.calls, pubKeyHash);

        emit ExecuteSuccessEvent(
            keccak256(abi.encode(batchedCall.calls)),
            msg.sender,
            batchedCall.nonce
        );

        revert Errors.SimulateExecution();
    }

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Reverts if any of the calls fail
    /// @param calls Array of Call structs containing destination address, value, and calldata
    function _batchCall(Call[] calldata calls, bytes32 keyHash) internal {
        uint256 settings = ownerSettings[keyHash];
        address hookAddress = getHook(settings);

        // Allow self-calls for EIP-7702 EOAs or admins
        bool allowSelfCall = keyHash ==
            keccak256(abi.encodePacked(address(this))) ||
            isAdmin(settings);

        bytes memory ret;
        if (hookAddress != address(0)) {
            ret = IHook(hookAddress).preCheck(calls, msg.sender);
        }

        for (uint256 i; i < calls.length; i++) {
            if (calls[i].target == address(this) && !allowSelfCall) {
                revert Errors.NonAdminSelfCall();
            }
            _call(calls[i]);
        }

        // Only call postCheck if hook exists
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

        bytes32 pubKeyHash = bytes32(userOp.signature[0:32]);
        address validator = getVerifiedValidator(pubKeyHash);
        if (validator == address(0)) return Static.SIG_VALIDATION_FAILED;

        uint256 nonceKey = userOp.nonce >> 64;

        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // Decode calls from userOp.callData
            Call[] calldata calls = DecodeLib.decodeCalls(userOp.callData[4:]);

            // Validate all calls are allowed to skip chain ID validation
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    calls,
                    address(this)
                )
            ) {
                return Static.SIG_VALIDATION_FAILED;
            }

            userOpHash = getUserOpHashWithoutChainId(userOp);
        }

        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                userOpHash,
                userOp.signature[32:]
            )
        ) return Static.SIG_VALIDATION_FAILED;
        return validationData;
    }

    /// @notice Implements EIP-1271 signature validation standard
    /// @dev There are two types of signatures:
    ///      1. 65 bytes: ECDSA signature for EOA compatibility
    ///      2. >65 bytes: abi.encode(keyHash, signature) for validator-based validation
    /// @dev This function does NOT support chainless validation - all signatures are validated with chain ID
    ///      to prevent cross-chain replay attacks per EIP-1271 security best practices
    /// @param _hash The hash of the data to be validated
    /// @param signature The signature to be validated
    /// @return bytes4 Returns Static.MAGIC_VALUE (0x1626ba7e) if valid, Static.INVALID_VALUE (0xffffffff) if invalid
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

        // Extract pubKeyHash and signature from the input
        if (signature.length > 32) {
            bytes32 pubKeyHash = bytes32(signature[:32]);

            // Create bound hash for EIP-1271 validation
            bytes32 boundHash = keccak256(
                abi.encode(bytes32(block.chainid), address(this), _hash)
            );
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

            // Use _validateSignature with calldata signature directly
            address validator = getVerifiedValidator(pubKeyHash);
            if (validator == address(0)) return Static.INVALID_VALUE;

            return
                _validateSignature(
                    validator,
                    pubKeyHash,
                    digest,
                    signature[32:]
                )
                    ? Static.MAGIC_VALUE
                    : Static.INVALID_VALUE;
        }
        return Static.INVALID_VALUE;
    }

    /// @inheritdoc UUPSUpgradeable
    /// @dev Only allows the wallet itself to authorize upgrades, ensuring that upgrades
    ///      must go through execute() or executeWithRelayer() with proper authorization
    function _authorizeUpgrade(
        address
    ) internal view override(UUPSUpgradeable) onlySelf {}
}
