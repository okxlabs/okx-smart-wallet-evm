# INTERFACE_SPEC.md — Backend Integration Specification (TWA)

> Backend integration overlay over `DESIGN.md`. References canonical function ids (`FN-*`), events, and errors from `DESIGN.md`; it does **not** redefine contract behavior. Audience: Java backend engineers who construct EIP-712 payloads, collect owner signatures, select/submit relayers, and index events for the OKX SmartWallet TWA feature.

## 1. Interface Spec Status

| Field | Value |
|-------|-------|
| status | `DESIGN_DRAFT` |
| target chain | EVM — Ethereum mainnet (chainId 1), Cancun |
| source documents | `docs/process/DESIGN.md`, `docs/process/REQUIREMENTS.md` (PRD §2.1/FR-0..FR-5/§7/§8), EIP draft supplement |
| expected final handoff | `docs/delivery/CONTRACT_INTERFACE.md` (Stage 4.0) |
| expected machine-readable artifacts | `docs/delivery/abi/SmartWalletEntry.abi.json` (or `ITransferWithAuthorization.abi.json`) when produced in Stage 4.0 |
| change type | additive to the existing account ABI (new functions/events/errors + one ERC-165 id); existing surfaces preserved |

## 2. Backend Integration Overview

- **Backend / facilitator calls** `executeTransferWithAuthorization` (FN-001) — permissionless settlement of an owner-signed authorization; the relayer pays gas.
- **Payee contract calls** `receiveWithAuthorization` (FN-002) — only the `to` address can settle (`msg.sender == to`); used when a contract payee must land the payment atomically inside its own flow.
- **User/owner wallet (off-chain)** produces the EIP-712 signature (ECDSA or passkey). The backend never holds owner keys.
- **Admin / account self-call** uses `cancelTransferAuthorization` form B (empty signature) inside an `execute`/UserOp; form A (signed) can be submitted by any relayer.
- **Index-only** (no transactional call): `TransferAuthorizationUsed`, `TransferAuthorizationCanceled` events; read-only `transferAuthorizationState` / `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`.
- **Off-chain state / idempotency**: the backend must track which `authorizationNonce`s it has issued and their settlement status (settled / canceled / outstanding); settlement is verifiable via `eth_call` simulation before submit and via the emitted events. The random 32-byte nonce makes authorizations independent and settleable in any order (no sequence tracking). **A nonce being "consumed" on-chain is NOT proof of settlement:** `transferAuthorizationState(nonce) == true` (and the `AuthorizationAlreadyUsed` revert) is set by **both** a successful settle **and** a `cancel` (FR-3/FR-4 collapse them onto the same flag). A payment may be treated as paid **only** after observing a matching `TransferAuthorizationUsed` event — see §6.1 Settlement reconciliation.

**Most load-bearing integration fact:** the on-chain `signature` argument is an **envelope** = `keyHash (32 bytes) ‖ ownerSignature` (`DESIGN.md` FN-101, `SIGNATURE_ENVELOPE_MIN_LENGTH = 32`). The account recovers `keyHash = bytes32(signature[:32])`, routes the validator via `getVerifiedValidator(keyHash)`, then validates `signature[32:]` over the **direct** EIP-712 digest `hashTypedData(structHash)`. This is **not** the existing 38-byte execute envelope (which has a 6-byte `validUntil`), and **not** the EIP draft's 20-byte validator-address example. The backend must prepend the 32-byte `keyHash` to the owner signature **after** signing, and MUST NOT ERC-1271/MessageSignLib-wrap the digest.

## 3. Contract List

| Contract | Purpose | Backend Relevance | Notes |
|----------|---------|-------------------|-------|
| `SmartWalletEntry` (account, implements `ITransferWithAuthorization`) | account-level TWA settle | callable + index | **modified** (new TWA surface inline) |
| `ITransferWithAuthorization` | frozen ABI for facilitators | ABI source | **new** |
| Per-key Spending Policy Hook | per-key limit enforcement | index/observe (config off-chain) | existing; affects whether a settle succeeds |

## 4. Backend-callable Functions

> Canonical behavior in `DESIGN.md`. Only backend-integration detail here.

### `executeTransferWithAuthorization` — FN-001 — change type: new
- Signature: `executeTransferWithAuthorization(address token, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce, bytes signature)`
- Caller/role: any address (facilitator/relayer). Not payable; native funded from the account balance.
- Params (chain-native types / meaning): `token` = ERC-20 address or `NATIVE_ASSET` (`0xEeee…EEeE`) for native; `to` = recipient (MUST be non-zero — `InvalidRecipient`); `value` = amount (wei / token base units); `validAfter`/`validBefore` = open-interval unix bounds; `authorizationNonce` = random `bytes32`; `signature` = `keyHash(32) ‖ ownerSignature`.
- Returns: none.
- State changes: marks nonce used (CEI) then transfers (`DESIGN.md` FN-102/FN-103).
- Events: `TransferAuthorizationUsed`.
- Errors: `AuthorizationAlreadyUsed`, `AuthorizationNotYetValid`, `AuthorizationExpired`, `InvalidRecipient`, `InvalidSignature`, hook revert, transfer failure (see §6).
- Preconditions: unused nonce, within window, valid owner signature, sufficient account balance, within per-key hook policy.
- Idempotency/replay: each nonce settles at most once; re-submitting a **settled** nonce reverts `AuthorizationAlreadyUsed`. Front-running does not change the outcome (`to`/`value` are signature-bound) — see §6. **Caveat:** `AuthorizationAlreadyUsed` also fires for a **canceled** nonce, so the revert alone does not mean "paid" — reconcile via events (§6.1).
- Off-chain PREPARE: EIP-712 typed data (§7-style fields), pick `validAfter`/`validBefore`, generate a random 32-byte nonce, collect the owner signature, assemble the keyHash envelope (per-validator layout in §8).
- Off-chain STORE/INDEX: nonce → {token,to,value,window,account,status}; the resulting tx hash; the `TransferAuthorizationUsed` log (the authoritative proof of settlement).
- Security/misuse: simulate via `eth_call` before submit; never wrap the digest; on `AuthorizationAlreadyUsed` do not retry — and do **not** assume settled: confirm via the `TransferAuthorizationUsed` event before marking the payment paid (§6.1).

### `receiveWithAuthorization` — FN-002 — change type: new
- Same shape as FN-001, **plus** `msg.sender == to` (else `CallerNotPayee`). Signed under the **distinct** `RECEIVE` typehash — an execute-typed authorization cannot be replayed here and vice-versa.
- Backend role: the payee **contract** calls this from within its own logic; the backend supplies the signed receive authorization to that contract.

### `cancelTransferAuthorization` — FN-003 — change type: new
- Signature: `cancelTransferAuthorization(bytes32 authorizationNonce, bytes signature)`.
- Form A (signature non-empty): any relayer submits; signed under the `CANCEL` typehash by a registered account key (envelope `keyHash(32) ‖ ownerSignature`).
- Form B (signature empty, length 0): callable only by the account itself (`msg.sender == address(this)`), i.e. nested inside an `execute`/UserOp.
- Errors: `AuthorizationAlreadyUsed` (already used/canceled), `NotFromSelf` (form B from non-self).
- Off-chain: decide when to cancel an outstanding authorization; index `TransferAuthorizationCanceled`.

### `transferAuthorizationState` — FN-004 — change type: new (view)
- `transferAuthorizationState(bytes32) returns (bool used)` — true if used **or** canceled. Use for read-only reconciliation (`eth_call`).

### `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` — FN-005 — change type: new (view)
- Returns the account's EIP-712 domain separator. The backend MAY read it for convenience but can also reconstruct it from the domain fields (`name="SmartWallet"`, `version="1.1.0"`, `chainId`, `verifyingContract=account`).

### `supportsInterface` — FN-006 — change type: modified
- `supportsInterface(0x86c5a9e1) == true`; existing ids preserved. Facilitators use this to detect TWA support before integrating.

## 5. Events / Logs for Backend Indexing

| Event | Emitted By | When Emitted | Indexed / Queryable Fields | Backend Usage |
|-------|------------|--------------|----------------------------|---------------|
| `TransferAuthorizationUsed(address token, address from, address to, uint256 value, bytes32 authorizationNonce)` | FN-001 / FN-002 | on successful settle | `token`, `from`, `to` indexed; `value`, `authorizationNonce` in **data** (not topic-filterable) | **Authoritative proof of settlement** — a payment may be marked paid only when this event exists for the nonce. **Note:** cannot `getLogs`-filter by `authorizationNonce` (it is not indexed on this event) — filter by `from`(account)/`to` and read+match the nonce from data. |
| `TransferAuthorizationCanceled(address authorizer, bytes32 authorizationNonce)` | FN-003 | on cancel | `authorizer`, `authorizationNonce` both indexed (`authorizer` is always the account `address(this)`, not the cancelling key) | **Authoritative proof of cancellation** — a nonce with this event was revoked and MUST NOT be marked paid. Topic-filterable by nonce (one-shot `getLogs` by indexed nonce). |

## 6. Error Handling Contract

| Error / Revert | Meaning | Backend Handling |
|----------------|---------|------------------|
| `AuthorizationAlreadyUsed(bytes32)` | nonce is in a terminal state — **used OR canceled** (the contract collapses both onto one flag, FR-3/FR-4) | **do not retry.** Do **NOT** treat as settled by default. The same revert fires for a settled nonce (front-run by another relayer) *and* for a canceled nonce. Reconcile via events (§6.1): a matching `TransferAuthorizationUsed` ⇒ settled (mark paid); a `TransferAuthorizationCanceled`, or no `Used` event ⇒ canceled / never-settled (MUST NOT mark paid; surface as canceled). |
| `AuthorizationNotYetValid(uint256 validAfter)` | `block.timestamp <= validAfter` | retry after `validAfter`; or re-sign with a corrected window |
| `AuthorizationExpired(uint256 validBefore)` | `block.timestamp >= validBefore` | do not retry; request a fresh authorization (new nonce + window) |
| `InvalidRecipient(address to)` | `to == address(0)` (and/or native sentinel) | do not retry; fix the payload (operator/data error) |
| `CallerNotPayee(address caller, address to)` | `receiveWithAuthorization` not called by `to` | do not retry; route through the payee contract |
| `NonAdminSelfCall()` (reused base `ISmartWallet` error) | settle targets the account itself with a **non-admin** key — native `to == account`, or ERC-20 `token == account` (mirrors `execute`/`_batchCall`; see §8.4) | do not retry; operator/data error — fix `to`/`token`, or sign with an admin key. A normal payment whose `to` is the account but `token` is an external ERC-20 is **not** affected. |
| `InvalidSignature()` | bad envelope length / unregistered or expired keyHash / signature invalid / wrapped digest | do not retry as-is; re-derive keyHash, re-sign with the **direct** digest, verify the validator is registered/active |
| hook revert (custom error from the hook) | per-key spending policy violated (over-limit / non-whitelist) | do not retry; user-visible "policy limit" error; operator may adjust policy off-chain |
| transfer failure (token revert / insufficient balance / native send fail) | settlement could not complete | do not retry until balance/token issue resolved; user-visible |

### 6.1 Settlement reconciliation: distinguishing **Used** from **Canceled** (binding)

The contract stores a single `bool` per nonce; `transferAuthorizationState(nonce)` returns `true` and `AuthorizationAlreadyUsed` reverts for **both** a successful settle **and** a `cancel` (PRD FR-3 rule 4 "canceled nonce treated as used"; FR-4; `DESIGN.md` §8.1/§10). On-chain state therefore **cannot** distinguish settled from canceled — only the two distinct events can (PRD NFR-4). The backend MUST follow this rule before recording any payment as paid:

1. **A payment is "settled" only if a matching `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` event exists** for that nonce. Because `authorizationNonce` is **not** indexed on `TransferAuthorizationUsed`, filter by `from`(=account)/`to` and match the `authorizationNonce` from the event **data**.
2. **A `TransferAuthorizationCanceled(authorizer=account, authorizationNonce)` event means the authorization was revoked** and MUST NOT be marked paid. This event has the nonce **indexed**, so it is a one-shot `getLogs` lookup by topic — the cheapest discriminator.
3. `transferAuthorizationState(nonce) == true` (or an `AuthorizationAlreadyUsed` revert) **alone is insufficient** to conclude "paid"; it only means "terminal". If neither event is found for a terminal nonce (e.g. mid-reorg/indexing lag), treat status as **unknown/pending**, not paid.

Rationale: treating a canceled nonce as settled would mis-mark a revoked payment as paid, breaking off-chain accounting and defeating `cancel` as a business control.

## 7. Java Integration Notes (design-level; placeholders only)

- **EIP-712 signing**: build typed data with web3j `StructuredDataEncoder` (or equivalent) using the `types`/`domain`/`primaryType` in §7-style below; the **owner** signs (ECDSA via the owner key, or passkey via the wallet). After signing, **prepend the 32-byte `keyHash`** to produce the on-chain `signature` envelope. Do **not** apply any ERC-1271 / personal_sign / MessageSignLib wrapping. The exact per-validator `ownerSignature` byte layout (ECDSA / built-in passkey / external validator) and the keyHash derivation are specified in **§8 (Validator-Specific Signature Envelope)** — note the TWA prefix is **32 bytes (keyHash only)**, NOT the 38-byte `keyHash‖validUntil` prefix used by `executeWithRelayer`/UserOp.
- **Typed data** (normative field order matches the typehash strings in `DESIGN.md §6`):
  - domain: `{ name: "SmartWallet", version: "1.1.0", chainId: <chainId>, verifyingContract: <accountAddress> }`
  - `ExecuteTransferWithAuthorization` / `ReceiveWithAuthorization` fields: `token (address)`, `from (address)`, `to (address)`, `value (uint256)`, `validAfter (uint256)`, `validBefore (uint256)`, `authorizationNonce (bytes32)` — `from` MUST equal the account address.
  - `CancelTransferAuthorization` fields: `authorizationNonce (bytes32)`.
- **Submission**: use a transaction manager / raw call to `executeTransferWithAuthorization`; the submitting EOA (relayer) is arbitrary and unrelated to the owner key.
- **Pre-submit simulation**: `eth_call` the function first (per EIP "Settlement"); success implies valid signature, sufficient balance, unused nonce, and passing hook policy.
- **Reads**: use read-only `eth_call` for `transferAuthorizationState` and `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`; use event filters for `TransferAuthorizationUsed`/`Canceled` (mind that `authorizationNonce` is non-indexed on `Used`).
- **No secrets**: never embed production private keys, real RPC URLs, API keys, or real deployer/admin addresses; use placeholders (`<accountAddress>`, `<chainId>`, `<relayerKey>`).

## 8. Validator-Specific Signature Envelope (`keyHash ‖ ownerSignature`)

> Closes OQ-1 / OQ-2 / OQ-3 (PRD G-4). Source of truth: `src/ValidationManager.sol`, `src/libraries/ECDSAValidatorLib.sol`, `src/libraries/PasskeyValidatorLib.sol`, `src/OwnerManager.sol`, `lib/webauthn-sol/src/WebAuthn.sol`. Canonical verification path: `DESIGN.md` FN-101 `_verifyTwaSignature`.

The on-chain `signature` argument is **always** `keyHash (32 bytes) ‖ ownerSignature`. The contract recovers `keyHash = bytes32(signature[:32])`, routes the validator via `getVerifiedValidator(keyHash)` (`OwnerManager.sol:173`), and passes `ownerSignature = signature[32:]` **verbatim** to `_validateSignature(validator, keyHash, hashTypedData(structHash), ownerSignature)` (`ValidationManager.sol:29`). There is **no** `validUntil` field: TWA validity is the signed `validAfter`/`validBefore`, so the prefix is **32 bytes (keyHash only)** — **NOT** the 38-byte `keyHash(32)‖validUntil(6)` prefix used by `executeWithRelayer`/`validateUserOp`/`isValidSignature` (`SmartWallet.sol:188-199, 233-240`; `DecodeLib`).

> ⚠ **Most common backend pitfall:** copying the 38-byte execute/relayer envelope. The extra 6 `validUntil` bytes shift `ownerSignature` by 6 and every TWA signature then fails `InvalidSignature`. Use a 32-byte prefix.

`keyHash` selects the registered validator: `address(1)` = built-in ECDSA, `address(2)` = built-in passkey, any other registered contract = external validator (`Static.sol:7-8`). The built-in `address(this)` key always routes to ECDSA. The digest is the **direct** `hashTypedData(structHash)` — never ERC-1271/`MessageSignLib`-wrapped (R-3, FR-1-AC-8).

### 8.1 ECDSA — built-in validator `address(1)`
- **keyHash** = `keccak256(abi.encodePacked(ownerEOA))` — keccak of the 20-byte owner address (`ECDSAValidatorLib.sol:47`).
- **ownerSignature** = 65-byte `r(32) ‖ s(32) ‖ v(1)` over the direct digest (`ECDSAValidatorLib.sol:13,30,43`).
- **Full envelope** = `keyHash(32) ‖ r,s,v(65)` = **97 bytes**.
- Optional Merkle tail `… ‖ abi.encode(bytes32[] proofs)` lets one signature authorize a batch (`ECDSAValidatorLib.sol:31-40`); a single TWA settle uses **no** proofs (97 bytes exactly).
- Copyable reference: `Base.t.sol::_signHash` → `abi.encodePacked(keyHash, abi.encodePacked(r,s,v))`.

### 8.2 Passkey — built-in validator `address(2)`
- **keyHash** = `keccak256(abi.encodePacked(pubKeyX, pubKeyY))` — keccak of the two 32-byte P-256 coordinates, **packed** (`PasskeyValidatorLib.sol:60`). ⚠ An *external* passkey-validator test uses `keccak256(abi.encode([x,y]))` (a different hash); for the built-in validator use the **`abi.encodePacked`** form.
- **ownerSignature** = `abi.encode(PasskeyValidatorLib.PasskeyPubKey{uint256 pubKeyX, uint256 pubKeyY})` **(64 bytes)** ‖ `abi.encode(WebAuthn.WebAuthnAuth webAuthnAuth, bytes32[] proofs)` (`PasskeyValidatorLib.sol:39-51`).
  - `WebAuthnAuth = { bytes authenticatorData; string clientDataJSON; uint256 challengeIndex; uint256 typeIndex; uint256 r; uint256 s }` (`webauthn-sol/WebAuthn.sol:22-37`).
  - The WebAuthn **challenge** is `abi.encode(rootHash)`, where `rootHash = MerkleProofProcessor.processWithMerkleProof(proofs, digest)`. With empty `proofs`, `rootHash == digest` (the TWA `hashTypedData(structHash)`), so the passkey effectively signs over `abi.encode(digest)` embedded (base64url) in `clientDataJSON` (`PasskeyValidatorLib.sol:54-72`). The on-chain pubkey MUST hash to `keyHash`.
- **Full envelope** = `keyHash(32) ‖ abi.encode(pubKeyX,pubKeyY)(64) ‖ abi.encode(WebAuthnAuth, bytes32[] proofs)`.
- Copyable reference: `HelperLib.getPasskeyMessageHash` / `HelperLib.getWebAuthnAuth` (`test/utils/Helper.s.sol:19-58`) + `PasskeyValidator.t.sol::_createBuiltinPasskeySignature` (`:714-749`). The **only** change for TWA is dropping the `uint48(0) validUntil` that helper prepends at `:737` (TWA has no validUntil). Passkey gas is excluded from the <120k ECDSA target (NFR-1); its baseline is measured in Stage 5.0/6.0 (OQ-4).

### 8.3 External validator — any other registered address
- **keyHash** and **ownerSignature** layout are defined by that validator's own registration / `validateSignature(keyHash, digest, validationData)` contract; the account forwards `ownerSignature = signature[32:]` verbatim, wrapped in try/catch (fail-closed) (`ValidationManager.sol:56-66`). The backend must consult the specific external validator's spec; this design fixes only the outer `keyHash(32) ‖ ownerSignature` envelope.

### 8.4 Self-target settle edge (closes OQ-6; DR-003)
A settle whose **built `Call.target == address(this)`** — native `to == address(this)`, or ERC-20 `token == address(this)` — reverts `NonAdminSelfCall` for a **non-admin** key, mirroring `execute`/`_batchCall` (`SmartWallet.sol:152-164`; `DESIGN.md` FN-103 design note 3, `SECURITY_SPEC.md` INV-HOOK-ISOMORPHISM). Admin / built-in `address(this)` keys may self-target (a native self-send is a net-zero no-op). A normal ERC-20 payment to the account itself (`token = <external ERC-20>`, `to = account`) is **not** a self-call (the built Call's target is `token`, not the account) and settles normally. The backend should never construct a self-targeted settle payload.

## 9. Open Integration Questions

| # | Question | Status / Resolution |
|---|----------|---------------------|
| OQ-1 | How does the backend derive `keyHash` for a given owner/validator (ECDSA vs passkey)? | **Resolved** — §8.1/§8.2 (ECDSA `keccak256(abi.encodePacked(addr))`; built-in passkey `keccak256(abi.encodePacked(pubKeyX,pubKeyY))`). |
| OQ-2 | Exact encoding of a passkey signature inside `ownerSignature` (P-256 / WebAuthn payload)? | **Resolved** — §8.2 (full layout + WebAuthnAuth fields + copyable test references). |
| OQ-3 | Final `SIGNATURE_ENVELOPE_MIN_LENGTH` | **Resolved** — 32 (keyHash-only prefix; `DESIGN.md` FN-101). |
| OQ-6 | Native-asset settle and the `to == address(this)` edge | **Resolved** — §8.4 / DR-003 (non-admin self-target reverts `NonAdminSelfCall`; admin self-target = no-op). |
| OQ-4 | Gas estimation including the hook path; passkey-path gas baseline (NFR-1 excludes passkey from <120k) | **Open (non-blocking)** — measured in Stage 5.0/6.0. |
| OQ-5 | Whether the backend reads the on-chain `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` getter or reconstructs the domain locally | **Open (non-blocking, backend preference)** — both are valid; the getter (FN-005) is provided for convenience, or reconstruct from `{name:"SmartWallet", version:"1.1.0", chainId, verifyingContract:account}`. |

All design-blocking integration questions are resolved; remaining items (OQ-4/OQ-5) are non-blocking operational/preference items. A safe backend integration boundary **is** definable from the PRD + §8 + assumptions above.
