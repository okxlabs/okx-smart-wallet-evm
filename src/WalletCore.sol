// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IWalletCore} from "./interfaces/IWalletCore.sol";
import {IOwnersManager} from "./interfaces/IOwnersManager.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {OwnersManager} from "./OwnersManager.sol";
import {NonceManager} from "./NonceManager.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {ExecutionLogic} from "./ExecutionLogic.sol";
import {FallbackHandler} from "./FallbackHandler.sol";
import {Call, BatchedCall, InitialOwner} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";
import {GasEstimateUtil} from "./libraries/GasEstimateUtil.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {Static} from "./libraries/Static.sol";
import {IHook} from "./interfaces/IHook.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC4337Account, PackedUserOperation} from "./ERC4337Account.sol";

// Do not set any states in this contract
contract WalletCore is
    IWalletCore,
    ERC4337Account,
    OwnersManager,
    NonceManager,
    ValidationLogic,
    ExecutionLogic,
    FallbackHandler,
    EIP712,
    Initializable
{
    using ECDSA for bytes32;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    // EIP-1271
    bytes4 private constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 private constant INVALID_VALUE = 0xffffffff;

    uint256 private constant SIG_VALIDATION_FAILED = 1 << 96;

    address public immutable IMPLEMENTATION;

    // TODO: change to IEntryPoint
    address public immutable ENTRY_POINT;

    constructor(
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
        IMPLEMENTATION = address(this);

        _disableInitializers();
    }

    modifier onlyOwnerOrEntryPoint() {
        bytes32 keyHash = keccak256(abi.encode(msg.sender));
        if (
            msg.sender != address(this) &&
            !_ownerKeys.contains(keyHash) &&
            msg.sender != address(ENTRY_POINT)
        ) revert Errors.NotFromSelf();
        _;
    }

    /**
     * @notice Initializes the wallet core with initial owners
     * @dev Storage is now integrated directly into WalletCore
     * @param initialOwners Array of tuples containing keyHash and validator address pairs
     */
    function initialize(
        InitialOwner[] calldata initialOwners
    ) public initializer {
        // Set up initial owners
        // isAdmin = true, expiration = 0 (never expires), hook = address(0)
        uint256 settings = _packSettings(true, 0, address(0));
        for (uint256 i = 0; i < initialOwners.length; i++) {
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
                getValidationTypedHash(batchedCall),
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
     * @param validatorData Encoded data containing keyHash and signature: abi.encode(keyHash, signature)
     */
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external {
        uint256 gasStart;
        uint256 gasEnd;
        uint256 totalGas;
        bytes memory returnData;
        bytes memory payload = abi.encodeWithSelector(
            this.simulateRelayerExecution.selector,
            0,
            batchedCall,
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
     * @param batchedCall BatchedCall struct containing calls, nonce, and expiry
     * @param validatorData Encoded data containing keyHash and signature: pubkeyHash + signatures
     */
    function simulateRelayerExecution(
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
                getValidationTypedHash(batchedCall),
                validatorData[32:]
            )
        ) {
            // revert Errors.InvalidSignature();
        }

        _batchCall(batchedCall.calls, keyHash);
        revert ("");
    }

    /**
     * @notice Executes multiple contract calls in a single transaction
     * @dev Reverts if any of the calls fail
     * @param calls Array of Call structs containing destination address, value, and calldata
     */
    function _batchCall(Call[] calldata calls, bytes32 keyHash) internal {
        uint256 settings = _getSettings(keyHash);
        address hookAddress = _getHook(settings);
        bytes memory ret;

        if (hookAddress != address(0)) {
            ret = IHook(hookAddress).preCheck(calls, msg.sender);
        }

        for (uint256 i; i < calls.length; i++) {
            if (calls[i].target == address(this) && !_isAdmin(settings)) {
                revert Errors.NonAdminSelfCall();
            }
            _callWithRevert(calls[i]);
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
    ) external returns (uint256 validationData) {
        _payPrefund(missingAccountFunds);

        bytes32 keyHash = bytes32(userOp.signature[0:32]);
        address validator = getValidator(keyHash);
        validateValidatorAndExpiry(validator, type(uint256).max);

        if(!_validateSignature(validator, keyHash, userOpHash, userOp.signature[32:])) return SIG_VALIDATION_FAILED;
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

    /**
     * @notice Creates a typed data hash following EIP-712 standard
     * @param structHash The hash of the struct data to be signed
     * @return The final EIP-712 typed data hash that can be signed by a wallet
     */
    function _hashTypedDataV4(
        bytes32 structHash
    ) internal view override(EIP712, ValidationLogic) returns (bytes32) {
        return EIP712._hashTypedDataV4(structHash);
    }

    /**
     * @notice Returns the address of the current wallet implementation
     * @dev This function is used in the proxy pattern to identify the implementation contract
     * @return IMPLEMENTATION The address of this contract, which serves as the implementation
     */
    function _walletImplementation()
        internal
        view
        override(ValidationLogic)
        returns (address)
    {
        return IMPLEMENTATION;
    }
}
