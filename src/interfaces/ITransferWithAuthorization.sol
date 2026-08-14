// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title ITransferWithAuthorization
/// @notice Account-level, signature-authorized asset settlement interface for the SmartWallet account.
/// @dev An owner signs an off-chain EIP-712 authorization binding {token, from, to, value, time window,
///      random nonce}; a relayer (or the payee) submits it on-chain to move funds out of the account
///      exactly once. Native ETH is selected with the `NATIVE_ASSET` sentinel; any other `token` is an
///      ERC-20. Function/event/error signatures are stable backend ABI surface and must not change.
interface ITransferWithAuthorization {
    /// @notice Emitted exactly once when an authorization settles, via `executeTransferWithAuthorization`
    ///         or `receiveWithAuthorization`, carrying the full transfer detail. `token`, `from`, and `to`
    ///         are indexed so consumers can filter by asset or counterparty; `value` and
    ///         `authorizationNonce` are in the data section (the nonce is a topic only on cancellation).
    /// @param token The asset transferred (`NATIVE_ASSET` for native ETH, else the ERC-20 address).
    /// @param from The paying account (always this account).
    /// @param to The recipient that received `value`.
    /// @param value The amount moved, in wei or token base units.
    /// @param authorizationNonce The authorization nonce that was consumed (now terminal).
    event TransferAuthorizationUsed(
        address indexed token, address indexed from, address indexed to, uint256 value, bytes32 authorizationNonce
    );

    /// @notice Emitted when an unused authorization is revoked via `cancelTransferAuthorization`. The nonce
    ///         is indexed and becomes terminal — it can no longer settle, exactly as if it had been used.
    /// @param authorizationNonce The authorization nonce that was canceled (now terminal).
    event TransferAuthorizationCanceled(bytes32 indexed authorizationNonce);

    /// @notice The authorization nonce is already in a terminal state (settled or canceled).
    error AuthorizationAlreadyUsed(bytes32 authorizationNonce);
    /// @notice The current block timestamp has not reached the authorization's `validAfter` bound.
    error AuthorizationNotYetValid(uint256 validAfter);
    /// @notice The current block timestamp has reached or passed the authorization's `validBefore` bound.
    error AuthorizationExpired(uint256 validBefore);
    /// @notice `receiveWithAuthorization` was not called by the authorized payee (`to`).
    error CallerNotPayee(address caller, address to);
    /// @notice The signing key has a spending-policy hook configured, but that hook does not advertise
    ///         `IHookTransferAuthorization` via ERC-165, so the TWA settlement path cannot enforce it.
    ///         Settlement fails closed rather than silently bypassing the key's spending policy.
    error HookNotTransferAuthorizationCompatible(bytes32 keyHash, address hook);

    /// @notice Settles an owner-signed transfer authorization. Permissionless: any relayer may submit.
    /// @param token The asset to transfer (`NATIVE_ASSET` for native ETH, else an ERC-20 address).
    /// @param to The recipient.
    /// @param value The amount to transfer, in wei or token base units.
    /// @param validAfter Unix timestamp; settlement is only valid strictly after this bound.
    /// @param validBefore Unix timestamp; settlement is only valid strictly before this bound.
    /// @param authorizationNonce A random, single-use authorization nonce.
    /// @param signature The envelope `keyHash(32) || ownerSignature` over the EIP-712 execute digest.
    function executeTransferWithAuthorization(
        address token,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authorizationNonce,
        bytes calldata signature
    ) external;

    /// @notice Settles an owner-signed receive authorization; callable only by the payee (`msg.sender == to`).
    /// @dev Signed under a distinct typehash, so a receive authorization cannot be replayed as an execute
    ///      authorization and vice-versa.
    /// @param token The asset to transfer (`NATIVE_ASSET` for native ETH, else an ERC-20 address).
    /// @param to The recipient; must equal `msg.sender` for `receiveWithAuthorization`.
    /// @param value The amount to transfer, in wei or token base units.
    /// @param validAfter Unix timestamp; settlement is only valid strictly after this bound.
    /// @param validBefore Unix timestamp; settlement is only valid strictly before this bound.
    /// @param authorizationNonce A random, single-use authorization nonce.
    /// @param signature The envelope `keyHash(32) || ownerSignature` over the EIP-712 receive digest.
    function receiveWithAuthorization(
        address token,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authorizationNonce,
        bytes calldata signature
    ) external;

    /// @notice Cancels (revokes) an unused authorization nonce, making it terminal.
    /// @dev Two forms: a non-empty `signature` is an owner-key authorization over the cancel digest and may
    ///      be relayed by anyone; an empty `signature` requires the caller to be the account itself.
    /// @param authorizationNonce The authorization nonce to cancel.
    /// @param signature The envelope `keyHash(32) || ownerSignature` over the EIP-712 cancel digest, or empty for a self-call.
    function cancelTransferAuthorization(bytes32 authorizationNonce, bytes calldata signature) external;

    /// @notice Returns whether an authorization nonce is terminal (settled or canceled).
    /// @param authorizationNonce The authorization nonce to query.
    /// @return used True if the nonce has been settled or canceled, false if still unused.
    function transferAuthorizationState(bytes32 authorizationNonce) external view returns (bool used);
}
