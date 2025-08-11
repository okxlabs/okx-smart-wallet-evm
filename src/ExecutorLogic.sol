// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IExecutor} from "./interfaces/IExecutor.sol";
import {IHook} from "./interfaces/IHook.sol";
import {IStorage} from "./interfaces/IStorage.sol";

import {Call, Session} from "./Types.sol";
import {Errors} from "./libraries/Errors.sol";

abstract contract ExecutorLogic is IExecutor {
    bytes32 public constant SESSION_TYPEHASH =
        keccak256(
            "Session(address wallet,uint256 id,address executor,uint256 validUntil,uint256 validAfter,bytes preHook,bytes postHook)"
        );

    /**
     * @notice Restricts function access to the authorized executor with a valid session and executes hooks
     * @dev Performs two checks:
     *      1. Caller must match the session's executor
     *      2. Session must be valid (not expired, not invalidated)
     * @dev Hook address is extracted from first 20 bytes of hook data
     * @dev Remaining bytes are passed as hook parameters
     * @param session The session data containing executor permissions and hook configurations
     * @param calls Array of calls to be executed
     * @custom:hooks PreHook runs before execution, PostHook runs after with preHook return data
     */
    modifier onlyValidSession(Session calldata session, Call[] calldata calls) {
        validateSession(session);

        bytes memory ret;

        if (session.preHook.length >= 20)
            ret = IHook(address(bytes20(session.preHook[:20]))).preCheck(
                calls,
                session.preHook[20:],
                msg.sender
            );

        _;

        if (session.postHook.length >= 20)
            IHook(address(bytes20(session.postHook[:20]))).postCheck(
                ret,
                session.postHook[20:],
                msg.sender
            );
    }

    /**
     * @notice Validates a session's time bounds, status, and signature
     * @dev Checks four conditions:
     *      1. Current time is within session's time bounds
     *      2. Session is not invalidated in storage
     *      3. Validator exists and is registered via keyHash
     *      4. Session signature is valid using keyHash-derived validator
     * @param session The session data to validate
     */
    function validateSession(Session calldata session) public view {
        // Check executor authorization
        if (msg.sender != session.executor) revert Errors.InvalidExecutor();

        // Check time bounds
        if (
            session.validAfter > block.timestamp ||
            block.timestamp > session.validUntil
        ) revert Errors.InvalidSession();

        // Extract keyHash and signature directly from session.signature
        bytes32 keyHash = bytes32(session.signature[:32]);
        bytes calldata signature = session.signature[32:];
        // Look up validator address from keyHash
        address validator = getMainStorage().getValidator(keyHash);
        if (validator == address(0)) revert Errors.InvalidValidator(validator);

        // Check invalidSessionId in storage
        if (!getMainStorage().validateSession(session.id)) {
            revert Errors.InvalidSession();
        }

        // Validate signature using keyHash-derived validator
        bytes32 hash = getSessionTypedHash(session);
        bool isValid = _validate(validator, hash, signature);
        if (!isValid) revert Errors.InvalidSignature();
    }

    /**
     * @notice Creates an EIP-712 typed data hash for session validation
     * @dev Combines session data with domain separator using EIP-712 standard
     * @param session The session data containing ID, executor, validator, time bounds, and hooks
     * @return bytes32 The EIP-712 compliant hash for signature verification
     */
    function getSessionTypedHash(
        Session calldata session
    ) public view returns (bytes32) {
        return _hashTypedDataV4(_getSessionHash(session));
    }

    /**
     * @notice Creates a hash of session parameters for EIP-712 struct hashing
     * @dev Packs session data with SESSION_TYPEHASH using keccak256
     * @param session Session data
     * @return bytes32 The packed and hashed session data
     */
    function _getSessionHash(
        Session calldata session
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SESSION_TYPEHASH,
                    _walletImplementation(),
                    session.id,
                    session.executor,
                    session.validUntil,
                    session.validAfter,
                    keccak256(session.preHook),
                    keccak256(session.postHook)
                )
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
     * @param validatorData For ECDSA: the 65-byte signature; For external validators: custom validation data
     * @return bool True if validation succeeds, false otherwise
     * @custom:security Ensure validator contracts are properly verified and authorized before use
     */
    function _validate(
        address validator,
        bytes32 typedDataHash,
        bytes calldata validatorData
    ) internal view virtual returns (bool);
}
