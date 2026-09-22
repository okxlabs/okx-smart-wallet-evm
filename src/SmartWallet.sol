// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC7201} from "./ERC7201.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {NonceManager, ChainlessLib} from "./NonceManager.sol";
import {ExecutionManager} from "./ExecutionManager.sol";
import {
    TransferWithAuthorization,
    ERC712,
    OwnerManager,
    ValidationManager
} from "./TransferWithAuthorization.sol";
import {FallbackHandler} from "./FallbackHandler.sol";
import {Call, BatchedCall, InitialOwner} from "./Types.sol";
import {Static} from "./libraries/Static.sol";
import {HookLib} from "./libraries/HookLib.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC4337Account} from "./ERC4337Account.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {CallLib, BatchedCallLib} from "./libraries/BatchedCallLib.sol";
import {AllowanceManager} from "./AllowanceManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {DecodeLib} from "./libraries/DecodeLib.sol";
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
    TransferWithAuthorization,
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

    /// @inheritdoc TransferWithAuthorization
    function _getWalletImplementation() internal view override returns (address) {
        return IMPLEMENTATION;
    }

    /// @notice Initializes the smart wallet with initial owners
    /// @dev Can only be called by factory during deployment. For EIP-7702 scenarios,
    ///      use execute/executeWithRelayer to add owners after delegation
    /// @param initialOwners Array of tuples containing keyHash and validator address pairs
    function initialize(
        InitialOwner[] calldata initialOwners
    ) external initializer onlyFactory {
        // Set up initial owners
        uint256 settings = Static.ROOT_KEY_SETTINGS;
        uint256 len = initialOwners.length;
        if (len == 0) {
            revert InitialOwnersLengthIsZero();
        }
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
    function execute(Call[] memory calls) external {
        bytes32 keyHash = keccak256(abi.encodePacked(msg.sender));
        (address validator, uint256 settings) = getOwnerConfig(keyHash);
        if (validator == address(0) || isSettingsExpired(settings)) {
            revert ISmartWallet.InvalidCaller(msg.sender);
        }
        _batchCall(calls, settings);
        emit ExecuteSuccessEvent(CallLib.hash(calls), msg.sender);
    }

    /// @dev This function is executable only by the EntryPoint contract, and is the main pathway for UserOperations to be executed.
    /// validateUserOp requires this execution selector for both regular and chainless UserOperations.
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

        (address validator, uint256 settings) = getOwnerConfig(keyHash);
        if (validator == address(0) || isSettingsExpired(settings)) {
            revert ISmartWallet.InvalidKeyHash(keyHash);
        }

        Call[] memory calls = abi.decode(userOp.callData[4:], (Call[]));

        _batchCall(calls, settings);
    }

    /// @notice Executes a validated call and subsequent batch of user's calls sent by a relayer
    /// @dev The validator must be previously registered and the validation data must be valid.
    ///      Validator is looked up from keyHash in validatorData.
    /// @param batchedCall BatchedCall struct containing calls and nonce
    /// @param validatorData Encoded data containing keyHash and signature (pubkeyHash + validUntil 6 bytes + signatures)
    function executeWithRelayer(
        BatchedCall memory batchedCall,
        bytes calldata validatorData
    ) external {
        (uint256 settings, bytes32 dataHash) = _validateAndExtractRelayerData(
            batchedCall,
            validatorData
        );

        _batchCall(batchedCall.calls, settings);

        emit RelayerExecuteSuccessEvent(
            dataHash,
            msg.sender,
            batchedCall.nonce
        );
    }

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Reverts if any of the calls fail
    /// @param calls Array of Call structs containing destination address, value, and calldata
    function _batchCall(Call[] memory calls, uint256 settings) internal {
        address hookAddress = getHook(settings);
        bool canSelfCall = isAdmin(settings);

        bytes memory ret = HookLib.preCheck(hookAddress, calls, msg.sender);

        // Allow self-calls for EIP-7702 EOAs or admins
        // Built-in address(this) owner is treated as admin by default
        for (uint256 i; i < calls.length; i++) {
            if (calls[i].target == address(this) && !canSelfCall) {
                revert ISmartWallet.NonAdminSelfCall();
            }
            _call(calls[i]);
        }

        HookLib.postCheck(hookAddress, ret, msg.sender);
    }

    /// @notice Validates and extracts data for relayer execution
    /// @dev Comprehensive validation function for executeWithRelayer
    /// @param batchedCall The batched call data
    /// @param validatorData The validator data containing pubKeyHash, validUntil, and signature
    /// @return settings The verified owner's packed settings
    /// @return dataHash The computed data hash for event emission
    function _validateAndExtractRelayerData(
        BatchedCall memory batchedCall,
        bytes calldata validatorData
    ) internal returns (uint256 settings, bytes32 dataHash) {
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
        (bytes32 pubKeyHash, uint48 validUntil) = DecodeLib.decodeSignatureComponents(
            validatorData
        );

        // Step 3: Verify transaction hasn't expired
        if (_isExpired(validUntil))
            revert ISmartWallet.ExpiryPassed(validUntil);

        // Step 4: Verify validator exists and is not expired
        address validator;
        (validator, settings) = getOwnerConfig(pubKeyHash);
        if (validator == address(0) || isSettingsExpired(settings)) {
            revert ISmartWallet.InvalidKeyHash(pubKeyHash);
        }

        // Step 5: Compute the data hash based on nonce type
        bytes32 intentHash = batchedCall.hash(validUntil, IMPLEMENTATION);

        // Step 6: Handle chainless execution if applicable
        if (ChainlessLib.isChainlessNonce(batchedCall.nonce)) {
            // Chainless queues control privileged owner-management and upgrade
            // operations, so non-admin owners must not be able to advance them.
            if (!isAdmin(settings)) {
                revert ISmartWallet.InvalidNonceKey(
                    batchedCall.nonce >> 96
                );
            }

            // Validate all calls are allowed for chainless execution
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                revert ISmartWallet.InvalidNonceKey(
                    batchedCall.nonce >> 96
                );
            }

            if (!_validateAndUpdateChainlessQueue(batchedCall.nonce)) {
                revert ISmartWallet.InvalidNonceKey(
                    batchedCall.nonce >> 96
                );
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

        // Require the same execution path for regular and chainless UserOperations.
        if (
            userOp.callData.length < 4 ||
            bytes4(userOp.callData[:4]) != this.executeUserOp.selector
        ) {
            return Static.SIG_VALIDATION_FAILED;
        }

        // Step 2: Check minimum signature length
        if (userOp.signature.length < 38) {
            return Static.SIG_VALIDATION_FAILED;
        }

        // Step 3: Extract validation components from signature
        (bytes32 pubKeyHash, uint48 validUntil) = DecodeLib
            .decodeSignatureComponents(userOp.signature);

        // Step 4: Verify validator exists and is not expired
        (address validator, uint256 settings) = getOwnerConfig(pubKeyHash);
        if (validator == address(0)) return Static.SIG_VALIDATION_FAILED;

        // Step 5: Handle chainless execution if applicable
        if (ChainlessLib.isChainlessNonce(userOp.nonce)) {
            // Reject before updating the queue floor: EntryPoint validation
            // state persists even when the subsequent execution fails.
            if (!isAdmin(settings)) return Static.SIG_VALIDATION_FAILED;

            // Decode calls from userOp.callData
            Call[] memory calls = abi.decode(userOp.callData[4:], (Call[]));

            // Validate all calls are allowed to skip chain ID validation
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    calls,
                    address(this)
                )
            ) {
                return Static.SIG_VALIDATION_FAILED;
            }

            // EntryPoint owns the 64-bit sequence, while the wallet owns the
            // per-operation-type chainless queue watermark.
            if (!_validateAndUpdateChainlessQueue(userOp.nonce)) {
                return Static.SIG_VALIDATION_FAILED;
            }

            userOpHash = getUserOpHashWithoutChainId(userOp);
        }

        // Step 6: Add validUntil and IMPLEMENTATION to hash after chainless processing
        userOpHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encode(userOpHash, validUntil, IMPLEMENTATION))
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

        validationData = uint256(_getEffectiveValidUntil(validUntil, uint48(getExpiration(settings)))) << 160;
    }

    /// @notice Implements EIP-1271 signature validation standard
    /// @dev There are two types of signatures:
    ///      1. Exactly 65 bytes: ECDSA signature over _hash; the recovered signer must be address(this).
    ///      2. >38 bytes (except 65): packed pubKeyHash (32 bytes) + validUntil (6 bytes) + validator signature.
    /// @dev Validator-based signatures bind the chain ID through EIP-712; the 65-byte EOA path
    ///      validates _hash directly without adding a domain separator.
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
            (address recovered, , ) = ECDSA.tryRecoverCalldata(_hash, signature);
            return
                recovered == address(this)
                    ? Static.MAGIC_VALUE
                    : Static.INVALID_VALUE;
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
            (address validator, uint256 settings) = getOwnerConfig(pubKeyHash);
            if (validator == address(0) || isSettingsExpired(settings)) return Static.INVALID_VALUE;

            // Step 4: Hash the message with EIP-712 standard
            bytes32 typedDataHash = hashTypedData(
                MessageSignLib.hash(_hash, validUntil, IMPLEMENTATION)
            );

            // Step 5: Cryptographic validation first (cheap fail-fast, before any hook staticcall).
            if (
                !_validateSignature(
                    validator,
                    pubKeyHash,
                    typedDataHash,
                    signature[38:]
                )
            ) {
                return Static.INVALID_VALUE;
            }

            // Step 6: Fail closed — if the signing key has a spending-policy hook, that hook MUST
            //         advertise `IHook` and approve this EIP-1271 signature, otherwise it is rejected.
            //         This stops a restricted key from using EIP-1271 (e.g. a Permit) as an escape
            //         hatch around the policy its hook enforces on the execute / TWA paths.
            address hookAddress = getHook(settings);
            if (!HookLib.isValidSignatureCheck(hookAddress, msg.sender, _hash, signature)) {
                return Static.INVALID_VALUE;
            }
            return Static.MAGIC_VALUE;
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
