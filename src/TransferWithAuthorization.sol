// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ITransferWithAuthorization} from "./interfaces/ITransferWithAuthorization.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {OwnerManager} from "./OwnerManager.sol";
import {ValidationManager} from "./ValidationManager.sol";
import {ERC712} from "./ERC712.sol";
import {Static} from "./libraries/Static.sol";
import {HookLib} from "./libraries/HookLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title TransferWithAuthorization
/// @notice Account-level signature-authorized settlement mixin for the SmartWallet account.
/// @dev Inherited by `SmartWallet` and compiled inline into the account bytecode. Reuses the account's
///      existing key/validator routing (`OwnerManager`, `ValidationManager`), EIP-712 domain (`ERC712`),
///      and per-key spending-policy hook. Owns only a single ERC-7201-namespaced nonce mapping; reentrancy
///      protection is provided by OZ ReentrancyGuardTransient (EIP-1153 transient storage).
abstract contract TransferWithAuthorization is
    ITransferWithAuthorization,
    OwnerManager,
    ValidationManager,
    ERC712,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20;

    // keccak256("ExecuteTransferWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)")
    bytes32 constant EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0xe751bf1b144414a77b82ede1d2a433edc347fef283ab5e53e96f438392517b3c;

    // keccak256("ReceiveWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)")
    bytes32 constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd8a04c474fcb45b6fb4b17a80506c180af4818903f1ace6c1ff59053338529fd;

    // keccak256("CancelTransferAuthorization(bytes32 authorizationNonce)")
    bytes32 constant CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH =
        0xf30be15aedf9b01d0dac5525241af3753865a4968ffb9fb1a7ad6d2553d29f8e;

    /// @notice Minimum on-chain `signature` length: the 32-byte `keyHash` envelope prefix.
    uint256 public constant SIGNATURE_ENVELOPE_MIN_LENGTH = 32;

    /// @dev Dedicated ERC-7201 storage root for the TWA nonce namespace, independent of the account's
    ///      `CustomStorage` region. Verified non-colliding via `forge inspect storageLayout`.
    ///      keccak256(abi.encode(uint256(keccak256("SmartWallet.ERC7201.TransferAuthorization")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _TWA_STORAGE_SLOT = 0xd0d1bd54e9d038badf8c6e8604633a46480fa6b609616e73025b209a31512900;

    /// @custom:storage-location erc7201:SmartWallet.ERC7201.TransferAuthorization
    struct TransferAuthorizationStorage {
        mapping(bytes32 => bool) authorizationStates;
    }

    /// @inheritdoc ITransferWithAuthorization
    function executeTransferWithAuthorization(
        address token,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authorizationNonce,
        bytes calldata signature
    ) external nonReentrant {
        _authorizeAndSettle(
            EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            token,
            to,
            value,
            validAfter,
            validBefore,
            authorizationNonce,
            signature
        );
    }

    /// @inheritdoc ITransferWithAuthorization
    function receiveWithAuthorization(
        address token,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authorizationNonce,
        bytes calldata signature
    ) external nonReentrant {
        if (msg.sender != to) revert CallerNotPayee(msg.sender, to);
        _authorizeAndSettle(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            token,
            to,
            value,
            validAfter,
            validBefore,
            authorizationNonce,
            signature
        );
    }

    /// @inheritdoc ITransferWithAuthorization
    function cancelTransferAuthorization(bytes32 authorizationNonce, bytes calldata signature) external {
        TransferAuthorizationStorage storage $ = _getTransferAuthorizationStorage();
        if ($.authorizationStates[authorizationNonce]) {
            revert AuthorizationAlreadyUsed(authorizationNonce);
        }

        if (signature.length == 0) {
            // Self-call form: only the account itself may cancel without a signature.
            if (msg.sender != address(this)) revert NotFromSelf();
        } else {
            // Signed form: any registered account key may cancel; the nonce is account-scoped.
            bytes32 structHash = keccak256(abi.encode(CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH, authorizationNonce));
            _verifyTwaSignature(structHash, signature);
        }

        $.authorizationStates[authorizationNonce] = true;
        emit TransferAuthorizationCanceled(authorizationNonce);
    }

    /// @inheritdoc ITransferWithAuthorization
    function transferAuthorizationState(bytes32 authorizationNonce) external view returns (bool used) {
        return _getTransferAuthorizationStorage().authorizationStates[authorizationNonce];
    }

    /// @dev Verifies the `keyHash(32) || ownerSignature` envelope against the direct EIP-712 typed-data
    ///      digest of `structHash`, reusing the account's validator routing. Reverts `InvalidSignature`
    ///      on a short envelope, an unregistered/expired key, or an invalid signature. The digest is the
    ///      direct typed-data hash with no ERC-1271 / message-sign wrapping.
    /// @param structHash The EIP-712 struct hash being authorized.
    /// @param signature The `keyHash(32) || ownerSignature` envelope.
    /// @return keyHash The verified signing key hash, used downstream to select the spending-policy hook.
    /// @return settings The verified signing key's packed settings.
    function _verifyTwaSignature(bytes32 structHash, bytes calldata signature)
        internal
        view
        returns (bytes32 keyHash, uint256 settings)
    {
        if (signature.length < SIGNATURE_ENVELOPE_MIN_LENGTH) {
            revert ISmartWallet.InvalidSignature();
        }

        keyHash = bytes32(signature[:SIGNATURE_ENVELOPE_MIN_LENGTH]);
        address validator;
        (validator, settings) = getOwnerConfig(keyHash);
        if (validator == address(0)) revert ISmartWallet.InvalidSignature();

        bytes32 digest = hashTypedData(structHash);
        if (!_validateSignature(validator, keyHash, digest, signature[SIGNATURE_ENVELOPE_MIN_LENGTH:])) {
            revert ISmartWallet.InvalidSignature();
        }
    }

    /// @dev Shared settlement core for the execute and receive paths. Validates nonce freshness and the
    ///      open time window, verifies the owner signature over the bound struct, marks the nonce used
    ///      before transferring (checks-effects-interactions), settles through the signing key's hook,
    ///      and emits the settlement event.
    function _authorizeAndSettle(
        bytes32 typeHash,
        address token,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authorizationNonce,
        bytes calldata signature
    ) private {
        TransferAuthorizationStorage storage $ = _getTransferAuthorizationStorage();
        if ($.authorizationStates[authorizationNonce]) {
            revert AuthorizationAlreadyUsed(authorizationNonce);
        }
        if (block.timestamp <= validAfter) {
            revert AuthorizationNotYetValid(validAfter);
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationExpired(validBefore);
        }

        bytes32 structHash = keccak256(
            abi.encode(typeHash, token, address(this), to, value, validAfter, validBefore, authorizationNonce)
        );
        (bytes32 keyHash, uint256 settings) = _verifyTwaSignature(
            structHash,
            signature
        );

        // Effect before interaction: a later revert rolls this write back, leaving the nonce unused.
        $.authorizationStates[authorizationNonce] = true;

        _settleWithHook(keyHash, settings, token, to, value);

        emit TransferAuthorizationUsed(token, address(this), to, value, authorizationNonce);
    }

    /// @dev Settles a single transfer through the spending-policy hook selected by the verified signing
    ///      key. The ERC-20 leg uses SafeERC20 (return-value checked); the native leg uses a checked
    ///      low-level call that bubbles up any recipient revert. No self-call guard is applied: the native
    ///      path always carries empty calldata (constructed here, not caller-supplied), so targeting
    ///      address(this) is a plain ETH deposit with no privileged dispatch surface.
    ///
    ///      The hook is invoked through {HookLib}, which forwards the authorizing `keyHash` and the typed
    ///      transfer fields (token / to / value) to the dedicated `IHookTransferAuthorization` callbacks.
    ///      The TWA path fails closed: if the key has a spending-policy hook configured, that hook MUST
    ///      advertise `IHookTransferAuthorization` via ERC-165, otherwise {HookLib.preTransferWithAuthorization}
    ///      reverts `HookNotTransferAuthorizationCompatible`. This keeps the TWA path symmetric with the
    ///      execute path — a key's spending policy can never be silently bypassed by routing through TWA.
    function _settleWithHook(
        bytes32 keyHash,
        uint256 settings,
        address token,
        address to,
        uint256 value
    ) private {
        address hookAddress = getHook(settings);
        bool isNative = token == Static.NATIVE_ETH;

        bytes memory ret =
            HookLib.preTransferWithAuthorization(hookAddress, keyHash, token, to, value, msg.sender);

        if (isNative) {
            (bool ok, bytes memory returndata) = to.call{value: value}("");
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(returndata, 0x20), mload(returndata))
                }
            }
        } else {
            IERC20(token).safeTransfer(to, value);
        }

        HookLib.postTransferWithAuthorization(hookAddress, ret, msg.sender);
    }

    /// @dev ERC-7201 storage accessor for the TWA authorization-nonce namespace.
    function _getTransferAuthorizationStorage() private pure returns (TransferAuthorizationStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _TWA_STORAGE_SLOT
        }
    }
}
