// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Call} from "../Types.sol";
import {IHook} from "../interfaces/IHook.sol";
import {IHookTransferAuthorization} from "../interfaces/IHookTransferAuthorization.sol";
import {ITransferWithAuthorization} from "../interfaces/ITransferWithAuthorization.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/// @title HookLib
/// @notice Single home for the account's spending-policy hook interactions, so the ERC-165 probing and
///         dispatch of the three hook call sites stay consistent and auditable in one place:
///         - Execute path (`IHook.preCheck`/`postCheck`): invoked unconditionally when a hook is set.
///         - TWA settlement (`IHookTransferAuthorization`): fail-closed — a configured hook MUST advertise
///           the interface via ERC-165, otherwise the operation reverts.
///         - EIP-1271 (`IHook.isValidSignatureCheck`): fail-closed — a configured hook MUST advertise
///           `IHook` and approve, otherwise the signature is rejected.
/// @dev All functions are `internal` and inline into the account, so `msg.sender` semantics are preserved;
///      callers pass the intended `executor`/`caller` explicitly. The pre/post helpers no-op when `hook`
///      is `address(0)`, so callers need no zero-address branch.
library HookLib {
    /// @notice Execute-path pre-check. Unconditional (no ERC-165 gate), matching batch-execution semantics.
    /// @param hook The key's configured hook (`address(0)` ⇒ no-op).
    /// @param calls The batch being executed.
    /// @param executor `msg.sender` of the execute call.
    /// @return preRet Opaque data to forward to {postCheck}.
    function preCheck(
        address hook,
        Call[] calldata calls,
        address executor
    ) internal returns (bytes memory preRet) {
        if (hook == address(0)) return "";
        return IHook(hook).preCheck(calls, executor);
    }

    /// @notice Execute-path post-check. No-ops when no hook is set.
    function postCheck(address hook, bytes memory preRet, address executor) internal {
        if (hook == address(0)) return;
        IHook(hook).postCheck(preRet, executor);
    }

    /// @notice TWA-path pre-check. Fails closed: a configured hook that does not advertise
    ///         `IHookTransferAuthorization` reverts, so a key's spending policy cannot be bypassed via TWA.
    /// @param hook The authorizing key's configured hook (`address(0)` ⇒ no-op).
    /// @return preRet Opaque data to forward to {postTransferWithAuthorization}.
    function preTransferWithAuthorization(
        address hook,
        bytes32 keyHash,
        address token,
        address to,
        uint256 value,
        address caller
    ) internal returns (bytes memory preRet) {
        if (hook == address(0)) return "";
        if (
            !ERC165Checker.supportsERC165InterfaceUnchecked(
                hook,
                type(IHookTransferAuthorization).interfaceId
            )
        ) {
            revert ITransferWithAuthorization.HookNotTransferAuthorizationCompatible(keyHash, hook);
        }
        return
            IHookTransferAuthorization(hook).preTransferWithAuthorization(keyHash, token, to, value, caller);
    }

    /// @notice TWA-path post-check. No-ops when no hook is set (a non-zero hook was already asserted
    ///         TWA-compatible in {preTransferWithAuthorization}).
    function postTransferWithAuthorization(address hook, bytes memory preRet, address caller) internal {
        if (hook == address(0)) return;
        IHookTransferAuthorization(hook).postTransferWithAuthorization(preRet, caller);
    }

    /// @notice EIP-1271 approval gate for the signing key's spending-policy hook. It mirrors the hook
    ///         callback name per this library's wrap-and-name-alike convention (`preCheck`, `postCheck`,
    ///         …), but it is NOT a raw forwarder: it DECIDES whether the 1271 signature is approved, and
    ///         fails closed —
    ///         - `hook == address(0)` ⇒ approved (the key has no policy to enforce);
    ///         - otherwise the hook MUST advertise `IHook` via ERC-165 AND return `true` from
    ///           `IHook.isValidSignatureCheck`, else the signature is rejected.
    ///         A non-advertising hook, a failed staticcall, or an empty / wrong-length return are treated
    ///         as rejection.
    /// @param hook The signing key's configured hook (`address(0)` ⇒ no hook, approved).
    /// @param caller `msg.sender` of the `isValidSignature` call, forwarded to the hook.
    /// @param hash The 1271 message hash.
    /// @param signature The full 1271 signature envelope.
    /// @return approved True iff there is no hook, or the hook advertises `IHook` and explicitly approves.
    function isValidSignatureCheck(
        address hook,
        address caller,
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool approved) {
        if (hook == address(0)) return true;
        if (!ERC165Checker.supportsERC165InterfaceUnchecked(hook, type(IHook).interfaceId)) {
            return false;
        }
        (bool ok, bytes memory ret) = hook.staticcall(
            abi.encodeCall(IHook.isValidSignatureCheck, (caller, hash, signature))
        );
        return ok && ret.length == 32 && abi.decode(ret, (bool));
    }
}
