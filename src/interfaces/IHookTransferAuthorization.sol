// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title IHookTransferAuthorization
/// @notice The spending-policy hook surface for TransferWithAuthorization (TWA) settlement. Distinct
///         from the execute-path `IHook.preCheck`/`postCheck(Call[], executor)`.
/// @dev TWA settlement invokes these callbacks only when the authorizing key opts into the new hook
///      interfaces (the `sigHookFlag` in owner settings, see `OwnerManager.checkHookFlag`) AND the hook
///      advertises this interface via ERC-165 `supportsInterface`. A hook that wants to enforce a TWA
///      policy MUST therefore both implement these callbacks and return true from `supportsInterface`
///      for `type(IHookTransferAuthorization).interfaceId`, and the key must be installed with the
///      signature-hook flag set. Legacy hooks (flag unset) are left untouched — the callbacks are
///      skipped rather than reverting — so existing owners are not broken by this interface.
///      Compared to `preCheck`, this surface passes the *authorizing* `keyHash` and the typed transfer
///      fields (token / to / value) directly — the hook does not re-decode a synthesized `Call`, and
///      knows it is being invoked from the permissionless TWA path rather than a normal batch execute.
///      A hook shared with the execute path must implement BOTH `IHook` and this interface.
interface IHookTransferAuthorization {
    /// @notice Pre-settlement check for a TWA transfer, mirroring `IHook.preCheck`'s pre/post pairing.
    /// @param keyHash  The signing key that authorized this transfer (routes both the validator and
    ///                 this hook). This is the true authorizer — NOT `caller`, which is an arbitrary
    ///                 permissionless relayer.
    /// @param token    Token being settled; the native-asset sentinel (ERC-7528) for ETH.
    /// @param to       Recipient of the transfer.
    /// @param value    Amount being transferred.
    /// @param caller   `msg.sender` of the TWA call (the relayer / facilitator). Untrusted.
    /// @return preRet  Opaque data forwarded verbatim to `postTransferWithAuthorization`.
    function preTransferWithAuthorization(
        bytes32 keyHash,
        address token,
        address to,
        uint256 value,
        address caller
    ) external payable returns (bytes memory preRet);

    /// @notice Post-settlement check, run after the transfer, mirroring `IHook.postCheck`.
    /// @param preRet  The value returned by `preTransferWithAuthorization`.
    /// @param caller  `msg.sender` of the TWA call (the relayer / facilitator). Untrusted.
    function postTransferWithAuthorization(
        bytes calldata preRet,
        address caller
    ) external payable;
}
