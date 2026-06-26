# CONTRACT_INTERFACE.md — Backend Contract Interface Handoff (Transfer With Authorization)

## 1. Interface Handoff Status

| Field | Value |
|-------|-------|
| status | `IMPLEMENTATION_MATCHED` |
| target chain | EVM — Ethereum mainnet (chainId 1), Cancun (EIP-1153 required) |
| compiler / framework | Solidity `0.8.29`, Foundry; `evm_version = cancun`, `optimizer = true`, `optimizer_runs = 100` |
| source contracts | `src/interfaces/ITransferWithAuthorization.sol` (frozen ABI), `src/TransferWithAuthorization.sol` (mixin), inlined into the deployable account `src/SmartWalletEntry.sol` (`SmartWalletEntry`) |
| ABI files | `docs/delivery/abi/ITransferWithAuthorization.abi.json` (the transfer-with-authorization surface). The complete account ABI is produced under `out/SmartWalletEntry.sol/SmartWalletEntry.json` at build time. |
| build command used | `forge build` |
| relationship to interface spec | Implements the backend integration overlay in `docs/process/INTERFACE_SPEC.md` exactly; function/event/error signatures are unchanged from that spec and from `docs/process/DESIGN.md`. |
| commit | TBD (final commit created by the delivery stage) |

The account ABI change is **purely additive**: new external functions, two new events, five new custom errors, and one new ERC-165 interface id (`0x86c5a9e1`). No existing function, event, error, or storage layout was changed or removed.

## 2. Backend Integration Summary

- **Contract responsibilities:** the smart-wallet account settles a single owner-signed asset transfer (any ERC-20, or native ETH) out of its own balance, exactly once per random authorization nonce, inside a signed time window, optionally constrained by the signing key's spending-policy hook. It also lets an owner revoke an unused authorization and exposes read-only state/domain discovery.
- **Backend-callable (transaction-sending) flows:**
  - `executeTransferWithAuthorization` — permissionless settlement; any relayer/facilitator submits an owner-signed authorization and pays gas.
  - `receiveWithAuthorization` — only the payee (`msg.sender == to`) settles; used when a contract payee must land the payment atomically inside its own flow.
  - `cancelTransferAuthorization` — revoke an unused nonce; form A (signed) may be relayed by anyone, form B (empty signature) is an account self-call nested inside the account's own execute path.
- **Read-only query flows (eth_call):** `transferAuthorizationState`, `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`, `supportsInterface(0x86c5a9e1)`, and the public typehash/constant getters (`EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH`, `RECEIVE_WITH_AUTHORIZATION_TYPEHASH`, `CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH`, `INTERFACE_ID`, `NATIVE_ASSET`, `SIGNATURE_ENVELOPE_MIN_LENGTH`).
- **Event/log indexing flows:** `TransferAuthorizationUsed` (settlement) and `TransferAuthorizationCanceled` (revocation).
- **Admin / operator-only flows:** `cancelTransferAuthorization` form B requires the account itself as caller; there is no new admin role — upgrade authority is unchanged.
- **Frontend / user-wallet-only (backend must NOT call directly):** producing the EIP-712 owner signature. The backend never holds owner keys; the user wallet (ECDSA or passkey) signs, and the backend only assembles the envelope and submits.

**Most load-bearing fact:** the on-chain `signature` argument is an **envelope** = `keyHash (32 bytes) || ownerSignature`. The account recovers `keyHash = signature[:32]`, routes the validator, and validates `signature[32:]` over the **direct** EIP-712 digest. This is a **32-byte** prefix — NOT the 38-byte `keyHash||validUntil` prefix used by the existing relayer/UserOp paths, and the digest must **not** be ERC-1271 / personal-sign wrapped.

## 3. Contract Addresses

| Environment | Contract | Address | Source |
|-------------|----------|---------|--------|
| local / fork | `SmartWalletEntry` (account, implements `ITransferWithAuthorization`) | TBD | deployment dry-run |
| testnet | `SmartWalletEntry` | TBD | operator-provided |
| mainnet | `SmartWalletEntry` | TBD | operator-provided |

Each TWA authorization is bound to one specific account address (the `verifyingContract` in the EIP-712 domain) and one chain id. The backend must use the actual account address as both the call target and the `from` field of the signed authorization.

## 4. Function Reference

### `executeTransferWithAuthorization`

| Field | Content |
|-------|---------|
| Contract | `SmartWalletEntry` (via `ITransferWithAuthorization`) |
| Function | `executeTransferWithAuthorization` |
| Signature | `executeTransferWithAuthorization(address token,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce,bytes signature)` |
| Selector | `0x0e720282` |
| Mutability / Access Type | nonpayable; permissionless (any caller) |
| Required caller / signer | caller = any relayer/facilitator; signer = a registered owner key of the account |
| Required role | none for the caller; the signature must be from a registered (non-expired) account key |
| Parameters | `token`: ERC-20 address, or `NATIVE_ASSET` (`0xEeee…EEeE`) for native ETH. `to`: recipient, must be non-zero and not the native sentinel. `value`: amount (wei / token base units). `validAfter`/`validBefore`: open-interval unix bounds (valid strictly between). `authorizationNonce`: random `bytes32`, single-use. `signature`: `keyHash(32) || ownerSignature`. |
| Returns | none |
| Value sent | none (must not send `msg.value`; native is funded from the account balance) |
| State changes | marks `authorizationNonce` used (before transfer), then transfers `value` of `token` from the account to `to` |
| Events / Logs | `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` |
| Errors / Reverts | `AuthorizationAlreadyUsed`, `AuthorizationNotYetValid`, `AuthorizationExpired`, `InvalidRecipient`, `InvalidSignature`, `NonAdminSelfCall`, `ReentrantSettle`, hook revert, token/native transfer failure |
| Backend handling | simulate with `eth_call` before submit; index `TransferAuthorizationUsed` as the authoritative settlement proof; do not retry on terminal-state reverts; treat each nonce as settle-at-most-once |
| Security notes | `to`/`value` are signature-bound — front-running cannot change the outcome; never wrap the digest; the 32-byte prefix is mandatory |

### `receiveWithAuthorization`

| Field | Content |
|-------|---------|
| Contract | `SmartWalletEntry` (via `ITransferWithAuthorization`) |
| Function | `receiveWithAuthorization` |
| Signature | `receiveWithAuthorization(address token,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce,bytes signature)` |
| Selector | `0x88b7ab63` |
| Mutability / Access Type | nonpayable; restricted (`msg.sender == to`) |
| Required caller / signer | caller MUST be the payee `to` (typically a payee contract); signer = a registered owner key |
| Required role | caller must equal `to`; otherwise `CallerNotPayee` |
| Parameters | identical to `executeTransferWithAuthorization`, but signed under the **distinct** receive typehash |
| Returns | none |
| Value sent | none |
| State changes | as `executeTransferWithAuthorization` |
| Events / Logs | `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` |
| Errors / Reverts | `CallerNotPayee`, plus all `executeTransferWithAuthorization` conditions; a receive authorization cannot be replayed through execute and vice-versa |
| Backend handling | the payee contract calls this from within its own logic; the backend supplies the signed receive authorization to that contract |
| Security notes | distinct typehash isolates receive from execute; anti-front-run for atomic-receipt payees |

### `cancelTransferAuthorization`

| Field | Content |
|-------|---------|
| Contract | `SmartWalletEntry` (via `ITransferWithAuthorization`) |
| Function | `cancelTransferAuthorization` |
| Signature | `cancelTransferAuthorization(bytes32 authorizationNonce,bytes signature)` |
| Selector | `0xeca10231` |
| Mutability / Access Type | nonpayable |
| Required caller / signer | Form A: caller = any relayer, signed under the cancel typehash by a registered account key. Form B: empty `signature`, caller = the account itself (`address(this)`), nested in the account's execute path. |
| Required role | Form A: a registered account key signature. Form B: account self-call (`NotFromSelf` otherwise). |
| Parameters | `authorizationNonce`: nonce to revoke. `signature`: `keyHash(32) || ownerSignature` for form A, or empty (`0x`) for form B. |
| Returns | none |
| Value sent | none (moves no funds) |
| State changes | marks `authorizationNonce` terminal (treated as used) |
| Events / Logs | `TransferAuthorizationCanceled(authorizer=account, authorizationNonce)` |
| Errors / Reverts | `AuthorizationAlreadyUsed` (already used or canceled), `InvalidSignature` (form A), `NotFromSelf` (form B from non-self) |
| Backend handling | index `TransferAuthorizationCanceled`; a canceled nonce MUST NOT be marked paid |
| Security notes | the nonce is account-scoped, so any registered key may cancel; worst case is griefing (canceling a pending payment), never fund loss |

### `transferAuthorizationState`

| Field | Content |
|-------|---------|
| Contract | `SmartWalletEntry` (via `ITransferWithAuthorization`) |
| Function | `transferAuthorizationState` |
| Signature | `transferAuthorizationState(bytes32 authorizationNonce)` |
| Selector | `0xb69f0bd9` |
| Mutability / Access Type | view |
| Required caller / signer | none |
| Parameters | `authorizationNonce`: nonce to query |
| Returns | `bool used` — true if the nonce is terminal (settled **or** canceled), false if still unused |
| State changes | none |
| Backend handling | read-only reconciliation; `true` means terminal but does **not** by itself mean "settled" — see §6.1 |
| Security notes | cannot distinguish settled from canceled — disambiguate by event |

### `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`

| Field | Content |
|-------|---------|
| Contract | `SmartWalletEntry` (via `ITransferWithAuthorization`) |
| Function | `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` |
| Signature | `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` |
| Selector | `0x925a29fd` |
| Mutability / Access Type | view |
| Required caller / signer | none |
| Returns | `bytes32` — the account's EIP-712 domain separator |
| State changes | none |
| Backend handling | read for convenience, or reconstruct locally from `{name:"SmartWallet", version:"1.1.0", chainId, verifyingContract:account}` |
| Security notes | binds authorizations to this account and chain |

### `supportsInterface` (modified)

| Field | Content |
|-------|---------|
| Contract | `SmartWalletEntry` |
| Function | `supportsInterface` |
| Signature | `supportsInterface(bytes4 interfaceId)` |
| Selector | `0x01ffc9a7` |
| Mutability / Access Type | view |
| Returns | `bool` — `supportsInterface(0x86c5a9e1) == true`; all previously supported ids (ERC-165 `0x01ffc9a7`, ERC-1271 `0x1626ba7e`, ERC-721/1155 receivers) are preserved |
| Backend handling | detect transfer-with-authorization support before integrating |

### Public constant getters (read-only)

`EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH()` → `0xe751bf1b…7b3c`; `RECEIVE_WITH_AUTHORIZATION_TYPEHASH()` → `0xd8a04c47…29fd`; `CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH()` → `0xf30be15a…9f8e`; `INTERFACE_ID()` → `0x86c5a9e1`; `NATIVE_ASSET()` → `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`; `SIGNATURE_ENVELOPE_MIN_LENGTH()` → `32`. The backend MAY read these to validate its off-chain typed-data construction.

## 5. Events, Logs, and Indexing

| Event | Topic0 | When Emitted | Indexed / Queryable | Backend Usage |
|-------|--------|--------------|---------------------|---------------|
| `TransferAuthorizationUsed(address token, address from, address to, uint256 value, bytes32 authorizationNonce)` | `0xfce4059e…02ae` | on a successful settle (`executeTransferWithAuthorization` / `receiveWithAuthorization`) | `token`, `from`, `to` indexed; `value`, `authorizationNonce` in **data** (not topic-filterable) | **Authoritative proof of settlement.** Because `authorizationNonce` is not indexed here, filter by `from`(=account)/`to` and match the nonce from the event data. |
| `TransferAuthorizationCanceled(address authorizer, bytes32 authorizationNonce)` | `0x2e1fec16…8787` | on `cancelTransferAuthorization` | `authorizer`, `authorizationNonce` both indexed (`authorizer` is always the account address) | **Authoritative proof of cancellation.** Topic-filterable by nonce (one-shot `getLogs` by indexed topic). A nonce with this event MUST NOT be marked paid. |

## 6. Custom Errors and Revert Handling

| Error / Revert | Selector | Meaning | Backend Handling |
|----------------|----------|---------|------------------|
| `AuthorizationAlreadyUsed(bytes32 authorizationNonce)` | `0x232555ae` | nonce is terminal — **settled OR canceled** (one flag for both) | do not retry; do **not** assume settled — reconcile via events (§6.1) |
| `AuthorizationNotYetValid(uint256 validAfter)` | `0x7a4df079` | `block.timestamp <= validAfter` | retry after `validAfter`, or re-sign with a corrected window |
| `AuthorizationExpired(uint256 validBefore)` | `0x3d91b05f` | `block.timestamp >= validBefore` | do not retry; request a fresh authorization (new nonce + window) |
| `InvalidRecipient(address to)` | `0x17858bbe` | `to == address(0)` or `to == NATIVE_ASSET` | do not retry; fix the payload (operator/data error) |
| `CallerNotPayee(address caller, address to)` | `0xa54718e8` | `receiveWithAuthorization` not called by `to` | do not retry; route through the payee contract |
| `InvalidSignature()` | `0x8baa579f` | short envelope (`< 32`), unregistered/expired keyHash, invalid signature, or a wrapped digest | do not retry as-is; re-derive keyHash, re-sign over the **direct** digest, verify the key is registered/active |
| `NonAdminSelfCall()` | `0x6d9677b1` | settle targets the account itself with a non-admin key (native `to == account`, or ERC-20 `token == account`) | do not retry; operator/data error — fix `to`/`token` or sign with an admin key. A normal payment whose `to` is the account but `token` is an external ERC-20 is **not** affected. |
| `ReentrantSettle()` | `0x66395e90` | a settle was reentered before the in-progress settle completed | do not retry the nested call; indicates a reentrant recipient |
| `NotFromSelf()` | `0xa575ba1c` | `cancelTransferAuthorization` form B (empty signature) called by a non-account address | do not retry; route the empty-signature cancel through the account's own execute path |
| hook revert (custom error from the configured hook) | (hook-defined) | per-key spending policy violated (over-limit / non-whitelist) | do not retry; user-visible "policy limit"; operator may adjust policy off-chain |
| transfer failure (token revert / insufficient balance / native send fail) | (token/native-defined) | settlement could not complete | do not retry until balance/token issue resolved; user-visible |

### 6.1 Settlement reconciliation: distinguishing Used from Canceled (binding)

On-chain, a single boolean tracks each nonce; `transferAuthorizationState(nonce) == true` and the `AuthorizationAlreadyUsed` revert fire for **both** a successful settle **and** a cancel. On-chain state therefore **cannot** distinguish settled from canceled — only the two distinct events can. The backend MUST follow this rule before recording any payment as paid:

1. A payment is **settled** only if a matching `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` event exists for that nonce. Since `authorizationNonce` is not indexed on this event, filter by `from`(=account)/`to` and match the nonce from the event **data**.
2. A `TransferAuthorizationCanceled(authorizer=account, authorizationNonce)` event means the authorization was **revoked** and MUST NOT be marked paid. The nonce is indexed here, so it is a cheap one-shot `getLogs` lookup by topic.
3. `transferAuthorizationState(nonce) == true` (or an `AuthorizationAlreadyUsed` revert) **alone is insufficient** to conclude "paid"; it only means "terminal". If neither event is found for a terminal nonce (e.g. mid-reorg / indexing lag), treat status as **unknown/pending**, not paid.

Treating a canceled nonce as settled would mis-mark a revoked payment as paid and defeat cancellation as a business control.

## 7. Java Integration Demo (web3j, placeholders only)

> Placeholders: `<accountAddress>`, `<chainId>`, `<rpcUrl>`, `<relayerKey>`, `<tokenAddress>`, `<payeeAddress>`. Never embed production keys, real RPC URLs, or real deployer/admin addresses.

**Build the EIP-712 typed data and owner signature (user wallet signs; backend never holds owner keys):**

```java
// Domain: name="SmartWallet", version="1.1.0", chainId=<chainId>, verifyingContract=<accountAddress>
// Primary type "ExecuteTransferWithAuthorization" (or "ReceiveWithAuthorization") fields, in order:
//   address token, address from, address to, uint256 value,
//   uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce
//   -> "from" MUST equal <accountAddress>
byte[] ownerSignature = walletSignsTypedData(typedDataJson); // 65-byte r||s||v for ECDSA owner keys
byte[] keyHash = Hash.sha3(addressBytes(ownerEoa));          // ECDSA: keccak256(abi.encodePacked(ownerAddress))
// On-chain envelope = keyHash(32) || ownerSignature   (32-byte prefix, NOT 38)
byte[] signatureEnvelope = concat(keyHash, ownerSignature);
```

**Read-only call (eth_call):**

```java
Function stateFn = new Function(
    "transferAuthorizationState",
    Arrays.asList(new Bytes32(authorizationNonce)),
    Arrays.asList(new TypeReference<Bool>() {}));
boolean terminal = decodeBool(web3j.ethCall(
    Transaction.createEthCallTransaction(caller, "<accountAddress>", FunctionEncoder.encode(stateFn)),
    DefaultBlockParameterName.LATEST).send());
// terminal == true means settled OR canceled -> confirm by event (see 6.1) before marking paid
```

**Transaction call (relayer submits; relayer key is unrelated to the owner key):**

```java
Function execFn = new Function(
    "executeTransferWithAuthorization",
    Arrays.asList(
        new Address("<tokenAddress>"),   // or NATIVE_ASSET 0xEeee...EEeE
        new Address("<payeeAddress>"),
        new Uint256(value),
        new Uint256(validAfter),
        new Uint256(validBefore),
        new Bytes32(authorizationNonce),
        new DynamicBytes(signatureEnvelope)),
    Collections.emptyList());
// Pre-submit simulation first (eth_call); success implies valid signature, sufficient balance,
// unused nonce, and passing hook policy. Then send with a relayer-managed nonce/gas.
String txHash = sendRawTransaction("<rpcUrl>", "<relayerKey>", "<accountAddress>",
    FunctionEncoder.encode(execFn));
```

**Event / log parsing:**

```java
// TransferAuthorizationUsed: topics[0]=keccak256("TransferAuthorizationUsed(address,address,address,uint256,bytes32)")
//   topics[1]=token, topics[2]=from(account), topics[3]=to; data = value(uint256) || authorizationNonce(bytes32)
// Filter by from(account)/to, then match authorizationNonce from data.
// TransferAuthorizationCanceled: topics[1]=authorizer(account), topics[2]=authorizationNonce (filterable by nonce).
```

## 8. Compatibility and Versioning

- **ABI compatibility:** additive only — new functions/events/errors and one new ERC-165 id. All existing account surfaces (execute, relayer execution, UserOp validation, EIP-1271, owner management, allowance) keep their signatures, events, and errors.
- **Upgrade / proxy implications:** the account is UUPS-upgradeable; existing accounts adopt this feature via a standard upgrade authorized by the account itself. No new upgrade role is introduced. The new authorization-nonce storage lives in its own namespace and does not move or overlap existing storage.
- **What backend must re-check after redeploy / upgrade / address change:** confirm `supportsInterface(0x86c5a9e1) == true` and that `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` matches the expected `{name, version, chainId, verifyingContract}`; re-pin the account address used as both call target and signed `from`.
- **Stale-ABI detection:** the backend should verify `supportsInterface(0x86c5a9e1)` and the three typehash getters against the values it compiled against; a mismatch indicates a stale ABI or a different account version, and signing/encoding must be refreshed before submitting.
