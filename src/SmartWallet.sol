// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC712} from "./ERC712.sol";
import {ERC7201} from "./ERC7201.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {OwnerManager} from "./OwnerManager.sol";
import {NonceManager} from "./NonceManager.sol";
import {ValidationManager} from "./ValidationManager.sol";
import {ExecutionManager} from "./ExecutionManager.sol";
import {FallbackHandler} from "./FallbackHandler.sol";
import {Call, BatchedCall, InitialOwner} from "./Types.sol";
import {Static} from "./libraries/Static.sol";
import {IHook} from "./interfaces/IHook.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC4337Account} from "./ERC4337Account.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {CallLib, BatchedCallLib} from "./libraries/BatchedCallLib.sol";
import {AllowanceManager} from "./AllowanceManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {DecodeLib} from "./libraries/DecodeLib.sol";
import {ChainlessLib} from "./libraries/ChainlessLib.sol";
import {MessageSignLib} from "./libraries/MessageSignLib.sol";

/// @dev This contract uses UUPS upgradeable pattern. All state is stored via inherited contracts.
abstract contract SmartWallet is
    ISmartWallet,
    ERC7201,
    ERC4337Account,
    OwnerManager,
    NonceManager,
    ValidationManager,
    ExecutionManager,
    ERC712,
    FallbackHandler,
    Initializable,
    AllowanceManager,
    UUPSUpgradeable
{
    using ECDSA for bytes32;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using BatchedCallLib for BatchedCall;

    address public immutable override IMPLEMENTATION;

    /// @notice Initializes the implementation contract and prevents direct initialization
    /// @dev Sets IMPLEMENTATION to this contract's address for proxy pattern identification
    ///      and disables initializers to prevent the implementation from being initialized
    constructor() {
        IMPLEMENTATION = address(this);
        _disableInitializers();
    }

    modifier onlyOwner() {
        bytes32 keyHash = keccak256(abi.encodePacked(msg.sender));
        address validator = getVerifiedValidator(keyHash);

        if (validator == address(0)) {
            revert ISmartWallet.InvalidCaller(msg.sender);
        }

        _;
    }

    /// @notice Initializes the smart wallet with initial owners
    /// @dev Can only be called by factory during deployment. For EIP-7702 scenarios,
    ///      use execute/executeWithRelayer to add owners after delegation
    /// @param initialOwners Array of tuples containing keyHash and validator address pairs
    function initialize(
        InitialOwner[] calldata initialOwners
    ) external initializer onlyFactory {
        // Set up initial owners
        // isAdmin = true, expiration = 0 (never expires), hook = address(0)
        uint256 settings = packSettings(true, 0, address(0));
        uint256 len = initialOwners.length;
        for (uint256 i = 0; i < len; i++) {
            bytes32 keyHash = initialOwners[i].keyHash;
            address validator = initialOwners[i].validator;

            _addOwner(keyHash, validator, settings);
        }

        emit WalletInitialized();
    }

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Only callable by the account owner
    /// @param calls Array of Call structs containing destination address, value, and calldata
    function execute(Call[] calldata calls) external onlyOwner {
        _batchCall(calls, keccak256(abi.encodePacked(msg.sender)));
        emit ExecuteSuccessEvent(CallLib.hash(calls), msg.sender);
    }

    /// @dev This function is executable only by the EntryPoint contract, and is the main pathway for UserOperations to be executed.
    /// UserOperations can be executed through the execute function, but another method of authorization (ie through a passed in signature) is required.
    /// userOp.callData is abi.encodePacked(IAccountExecute.executeUserOp.selector, (abi.encode(Call[]))
    /// Note that this contract is only compatible with Entrypoint versions v0.7.0.
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32
    ) external onlyEntryPoint {
        // Parse the keyHash from the signature. This is the keyHash that has been pre-validated as the correct signer over the UserOp data
        // and must be used to check further on-chain permissions over the call execution.
        // Signature format: pubKeyHash (32) + validUntil (6) + signatures
        (bytes32 keyHash, ) = DecodeLib.decodeSignatureComponents(
            userOp.signature
        );

        Call[] calldata calls = DecodeLib.decodeCalls(userOp.callData[4:]);

        _batchCall(calls, keyHash);
    }

    /// @notice Executes a validated call and subsequent batch of user's calls sent by a relayer
    /// @dev The validator must be previously registered and the validation data must be valid.
    ///      Validator is looked up from keyHash in validatorData.
    /// @param batchedCall BatchedCall struct containing calls and nonce
    /// @param validatorData Encoded data containing keyHash and signature (pubkeyHash + validUntil 6 bytes + signatures)
    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external {
        (bytes32 pubKeyHash, bytes32 dataHash) = _validateAndExtractRelayerData(
            batchedCall,
            validatorData
        );

        _batchCall(batchedCall.calls, pubKeyHash);

        emit RelayerExecuteSuccessEvent(
            dataHash,
            msg.sender,
            batchedCall.nonce
        );
    }

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Reverts if any of the calls fail
    /// @param calls Array of Call structs containing destination address, value, and calldata
    function _batchCall(Call[] calldata calls, bytes32 keyHash) internal {
        uint256 settings = _ownerSettings[keyHash];
        address hookAddress = getHook(settings);

        // Allow self-calls for EIP-7702 EOAs or admins
        // Built-in address(this) owner is treated as admin by default
        bool allowSelfCall = keyHash ==
            keccak256(abi.encodePacked(address(this))) ||
            isAdmin(settings);

        bytes memory ret;
        if (hookAddress != address(0)) {
            ret = IHook(hookAddress).preCheck(calls, msg.sender);
        }

        for (uint256 i; i < calls.length; i++) {
            if (calls[i].target == address(this) && !allowSelfCall) {
                revert ISmartWallet.NonAdminSelfCall();
            }
            _call(calls[i]);
        }

        // Only call postCheck if hook exists
        if (hookAddress != address(0)) {
            IHook(hookAddress).postCheck(ret, msg.sender);
        }
    }

    /// @notice Validates and extracts data for relayer execution
    /// @dev Comprehensive validation function for executeWithRelayer
    /// @param batchedCall The batched call data
    /// @param validatorData The validator data containing pubKeyHash, validUntil, and signature
    /// @return pubKeyHash The extracted public key hash
    /// @return dataHash The computed data hash for event emission
    function _validateAndExtractRelayerData(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) internal returns (bytes32 pubKeyHash, bytes32 dataHash) {
        // Step 1: Validate and consume nonce
        if (!validateAndUpdateNonce(batchedCall.nonce))
            revert ISmartWallet.InvalidNonce(batchedCall.nonce);

        // Minimum length check: 32 bytes (pubKeyHash) + 6 bytes (validUntil) = 38 bytes
        if (validatorData.length < 38) {
            revert ISmartWallet.InvalidValidatorDataLength(
                validatorData.length,
                38
            );
        }
        // Step 2: Extract validation components from validatorData
        uint48 validUntil;
        (pubKeyHash, validUntil) = DecodeLib.decodeSignatureComponents(
            validatorData
        );

        // Step 3: Verify transaction hasn't expired
        if (_isExpired(validUntil))
            revert ISmartWallet.ExpiryPassed(validUntil);

        // Step 4: Verify validator exists and is not expired
        address validator = getVerifiedValidator(pubKeyHash);
        if (validator == address(0))
            revert ISmartWallet.InvalidKeyHash(pubKeyHash);

        // Step 5: Compute the data hash based on nonce type
        uint256 nonceKey = batchedCall.nonce >> 64;
        bytes32 intentHash = batchedCall.hash(validUntil, IMPLEMENTATION);

        // Step 6: Handle chainless execution if applicable
        if (nonceKey == Static.CHAINLESS_NONCE_KEY) {
            // Validate all calls are allowed for chainless execution
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                revert ISmartWallet.InvalidNonceKey(nonceKey);
            }
            // Hash without chain ID for cross-chain compatibility
            dataHash = hashTypedDataSansChainId(intentHash);
        } else {
            // Standard hash with chain ID
            dataHash = hashTypedData(intentHash);
        }

        // Step 7: Validate the signature
        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                dataHash,
                validatorData[38:]
            )
        ) revert ISmartWallet.InvalidSignature();
    }

    /// @notice Validates the user operation
    /// @param userOp User operation to be validated
    /// @param userOpHash Hash of the user operation
    /// @param missingAccountFunds Missing account funds to be paid
    /// @return validationData Validation data in EntryPoint-compatible format
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        // Step 1: Pay the prefund
        _payPrefund(missingAccountFunds);

        // Step 2: Check minimum signature length first
        if (userOp.signature.length < 38) {
            return Static.SIG_VALIDATION_FAILED;
        }

        // Step 3: Extract validation components from signature
        (bytes32 pubKeyHash, uint48 validUntil) = DecodeLib
            .decodeSignatureComponents(userOp.signature);

        // Step 4: Verify validator exists and is not expired
        address validator = getVerifiedValidator(pubKeyHash);
        if (validator == address(0)) return Static.SIG_VALIDATION_FAILED;

        // Step 5: Handle chainless execution if applicable
        uint256 nonceKey = userOp.nonce >> 64;
        if (nonceKey == Static.CHAINLESS_NONCE_KEY) {
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

        // Step 6: Add validUntil and IMPLEMENTATION to hash after chainless processing
        userOpHash = keccak256(
            abi.encode(userOpHash, validUntil, IMPLEMENTATION)
        );

        // Step 7: Validate signature
        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                userOpHash,
                userOp.signature[38:]
            )
        ) return Static.SIG_VALIDATION_FAILED;

        // Step 8: Return the validation data in EntryPoint-compatible format
        return uint256(validUntil) << 160;
    }

    /// @notice Implements EIP-1271 signature validation standard
    /// @dev There are two types of signatures:
    ///      1. 65 bytes: ECDSA signature for EOA compatibility
    ///      2. >65 bytes: abi.encode(keyHash, signature) for validator-based validation
    /// @dev This function does NOT support chainless validation - all signatures are validated with chain ID
    ///      to prevent cross-chain replay attacks per EIP-1271 security best practices
    /// @param _hash Hash of the data to be validated
    /// @param signature Signature to be validated
    /// @return Magic value (0x1626ba7e) if valid, invalid value (0xffffffff) if invalid
    function isValidSignature(
        bytes32 _hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        // 7702 Post upgrade compatibility: try validate signature for EOA sigs
        // Make sure the _signature can be decoded
        if (signature.length == 65) {
            (address recovered, , ) = ECDSA.tryRecover(_hash, signature);
            if (recovered == address(this)) return Static.MAGIC_VALUE;
        }

        // Extract pubKeyHash, validUntil and signature from the input
        // Format: pubKeyHash (32) + validUntil (6) + signatures
        if (signature.length > 38) {
            // Step 1: Extract validation components from signature
            (bytes32 pubKeyHash, uint48 validUntil) = DecodeLib
                .decodeSignatureComponents(signature);

            // Step 2: Verify signature hasn't expired
            if (_isExpired(validUntil)) return Static.INVALID_VALUE;

            // Step 3: Get and verify validator exists
            address validator = getVerifiedValidator(pubKeyHash);
            if (validator == address(0)) return Static.INVALID_VALUE;

            // Step 4: Hash the message with EIP-712 standard
            bytes32 typedDataHash = hashTypedData(
                MessageSignLib.hash(_hash, validUntil, IMPLEMENTATION)
            );

            // Step 5: Validate the signature and return result
            return
                _validateSignature(
                    validator,
                    pubKeyHash,
                    typedDataHash,
                    signature[38:]
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

    /// @notice Simulates a transaction by delegating to a simulation contract
    /// @dev This function delegates the call to a simulation contract that handles the actual simulation logic
    ///      Useful for dry-run testing of SmartWallet operations
    /// @dev References EntryPoint's delegateAndRevert function
    /// @param target Target contract to delegatecall
    /// @param data Calldata to pass to the target
    function delegateAndRevert(address target, bytes calldata data) external {
        (bool success, bytes memory ret) = target.delegatecall(data);
        revert ISmartWallet.DelegateAndRevert(success, ret);
    }
}
