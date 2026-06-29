// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ITransferWithAuthorization} from "./interfaces/ITransferWithAuthorization.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {IHook} from "./interfaces/IHook.sol";
import {OwnerManager} from "./OwnerManager.sol";
import {ValidationManager} from "./ValidationManager.sol";
import {ERC712} from "./ERC712.sol";
import {Call} from "./Types.sol";
import {Static} from "./libraries/Static.sol";
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

    /// @notice EIP-712 typehash for an execute-style transfer authorization.
    /// @dev Computed at compile time from the type string so the value can never drift from its preimage.
    ///      `from` is bound to the account address (not a function arg) when the struct is hashed.
    bytes32 public constant EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        keccak256(
            "ExecuteTransferWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
        );
    /// @notice EIP-712 typehash for a receive-style (payee-pulled) transfer authorization.
    /// @dev Computed at compile time from the type string so the value can never drift from its preimage.
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        keccak256(
            "ReceiveWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
        );
    /// @notice EIP-712 typehash for a cancel authorization.
    /// @dev Computed at compile time from the type string so the value can never drift from its preimage.
    bytes32 public constant CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH =
        keccak256("CancelTransferAuthorization(bytes32 authorizationNonce)");
    /// @notice ERC-165 interface id for this settlement surface
    ///         (executeTransferWithAuthorization.selector ^ receiveWithAuthorization.selector).
    bytes4 public constant INTERFACE_ID = 0x86c5a9e1;
    /// @notice Sentinel `token` value selecting the native-asset (ETH) settlement path (ERC-7528).
    address public constant NATIVE_ASSET = Static.NATIVE_ETH;
    /// @notice Minimum on-chain `signature` length: the 32-byte `keyHash` envelope prefix.
    uint256 public constant SIGNATURE_ENVELOPE_MIN_LENGTH = 32;

    /// @dev Dedicated ERC-7201 storage root for the TWA nonce namespace, independent of the account's
    ///      `CustomStorage` region. Verified non-colliding via `forge inspect storageLayout`.
    ///      keccak256(abi.encode(uint256(keccak256("SmartWallet.ERC7201.TransferAuthorization")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _TWA_STORAGE_SLOT =
        0xd0d1bd54e9d038badf8c6e8604633a46480fa6b609616e73025b209a31512900;

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
    function cancelTransferAuthorization(
        bytes32 authorizationNonce,
        bytes calldata signature
    ) external {
        TransferAuthorizationStorage
            storage $ = _getTransferAuthorizationStorage();
        if ($.authorizationStates[authorizationNonce]) {
            revert AuthorizationAlreadyUsed(authorizationNonce);
        }

        if (signature.length == 0) {
            // Self-call form: only the account itself may cancel without a signature.
            if (msg.sender != address(this)) revert NotFromSelf();
        } else {
            // Signed form: any registered account key may cancel; the nonce is account-scoped.
            bytes32 structHash = keccak256(
                abi.encode(
                    CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH,
                    authorizationNonce
                )
            );
            _verifyTwaSignature(structHash, signature);
        }

        $.authorizationStates[authorizationNonce] = true;
        emit TransferAuthorizationCanceled(address(this), authorizationNonce);
    }

    /// @inheritdoc ITransferWithAuthorization
    function transferAuthorizationState(
        bytes32 authorizationNonce
    ) external view returns (bool used) {
        return
            _getTransferAuthorizationStorage().authorizationStates[
                authorizationNonce
            ];
    }

    /// @inheritdoc ITransferWithAuthorization
    function TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()
        external
        view
        returns (bytes32)
    {
        return _domainSeparator();
    }

    /// @dev Verifies the `keyHash(32) || ownerSignature` envelope against the direct EIP-712 typed-data
    ///      digest of `structHash`, reusing the account's validator routing. Reverts `InvalidSignature`
    ///      on a short envelope, an unregistered/expired key, or an invalid signature. The digest is the
    ///      direct typed-data hash with no ERC-1271 / message-sign wrapping.
    /// @param structHash The EIP-712 struct hash being authorized.
    /// @param signature The `keyHash(32) || ownerSignature` envelope.
    /// @return keyHash The verified signing key hash, used downstream to select the spending-policy hook.
    function _verifyTwaSignature(
        bytes32 structHash,
        bytes calldata signature
    ) internal view returns (bytes32 keyHash) {
        if (signature.length < SIGNATURE_ENVELOPE_MIN_LENGTH)
            revert ISmartWallet.InvalidSignature();

        keyHash = bytes32(signature[:SIGNATURE_ENVELOPE_MIN_LENGTH]);
        address validator = getVerifiedValidator(keyHash);
        if (validator == address(0)) revert ISmartWallet.InvalidSignature();

        bytes32 digest = hashTypedData(structHash);
        if (
            !_validateSignature(
                validator,
                keyHash,
                digest,
                signature[SIGNATURE_ENVELOPE_MIN_LENGTH:]
            )
        ) {
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
        TransferAuthorizationStorage
            storage $ = _getTransferAuthorizationStorage();
        if ($.authorizationStates[authorizationNonce]) {
            revert AuthorizationAlreadyUsed(authorizationNonce);
        }
        if (block.timestamp <= validAfter)
            revert AuthorizationNotYetValid(validAfter);
        if (block.timestamp >= validBefore)
            revert AuthorizationExpired(validBefore);

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                token,
                address(this),
                to,
                value,
                validAfter,
                validBefore,
                authorizationNonce
            )
        );
        bytes32 keyHash = _verifyTwaSignature(structHash, signature);

        // Effect before interaction: a later revert rolls this write back, leaving the nonce unused.
        $.authorizationStates[authorizationNonce] = true;

        _settleWithHook(keyHash, token, to, value);

        emit TransferAuthorizationUsed(
            token,
            address(this),
            to,
            value,
            authorizationNonce
        );
    }

    /// @dev Settles a single transfer through the spending-policy hook selected by the verified signing
    ///      key. The ERC-20 leg uses SafeERC20 (return-value checked); the native leg uses a checked
    ///      low-level call that bubbles up any recipient revert. No self-call guard is applied: the native
    ///      path always carries empty calldata (constructed here, not caller-supplied), so targeting
    ///      address(this) is a plain ETH deposit with no privileged dispatch surface.
    function _settleWithHook(
        bytes32 keyHash,
        address token,
        address to,
        uint256 value
    ) private {
        address hookAddress = getHook(_ownerSettings[keyHash]);
        bool isNative = token == NATIVE_ASSET;

        bytes memory ret;
        if (hookAddress != address(0)) {
            Call[] memory calls = new Call[](1);
            if (isNative) {
                calls[0] = Call({target: to, value: value, data: ""});
            } else {
                calls[0] = Call({
                    target: token,
                    value: 0,
                    data: abi.encodeCall(IERC20.transfer, (to, value))
                });
            }
            ret = IHook(hookAddress).preCheck(calls, msg.sender);
        }

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

        if (hookAddress != address(0)) {
            IHook(hookAddress).postCheck(ret, msg.sender);
        }
    }

    /// @dev ERC-7201 storage accessor for the TWA authorization-nonce namespace.
    function _getTransferAuthorizationStorage()
        private
        pure
        returns (TransferAuthorizationStorage storage $)
    {
        assembly ("memory-safe") {
            $.slot := _TWA_STORAGE_SLOT
        }
    }
}
