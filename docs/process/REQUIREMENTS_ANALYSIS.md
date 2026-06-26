# REQUIREMENTS_ANALYSIS.md — PRD Coverage & Readiness Index

> Lightweight PRD coverage/readiness index for Stage 2.0. This is **not** a rewritten PRD and **not** the source from which `DESIGN.md` is derived. `DESIGN.md` is generated directly from `docs/process/REQUIREMENTS.md` (the PRD), the EIP draft supplement, the existing code, the technical context, and the selected pattern references. Original PRD ids are preserved; detailed rules stay in the PRD.

Feature: **Account-Level Transfer With Authorization (TWA)** — a new account-level `ITransferWithAuthorization` settle interface on the OKX SmartWallet account.

## 1. PRD Readiness and Source Inventory

| Item | Value |
|------|-------|
| PRD title / version | PRD-账户级离线签名授权转账 (Account-Level Transfer With Authorization) v1.0-fix |
| PRD source path | `docs/process/REQUIREMENTS.md` |
| Contract-specialized PRD | Yes — contains FR/AC/NFR, state semantics, product invariants, data objects, dependencies, risks, success metrics, and a PRD-fixed `_verifyTwaSignature` spec |
| Sections read | §1 overview, §2 background/motivation + interface `ITransferWithAuthorization`, §3 scope, §4 FR-0..FR-5 + goal trace, §5 product state semantics + invariants, §6 NFR-1..4, §7 technical reqs + `_verifyTwaSignature` spec, §8 data, §9 DEP-1..8, §10 metrics, §11 risks R-1..R-7/R-9, §12 PRD-to-TD handoff |
| Target chain / EVM | EVM — Ethereum mainnet (chainId 1), **Cancun** (EIP-1153 transient storage). Flow invariant `chain=evm`. |
| codebase_mode | `existing_code_change` (initial run, first-time adoption; not a rerun, no rework) |
| Authoritative supplement | EIP draft "Account-Level Transfer With Authorization" (`.oli-work/prd-supplements/eip-account-level-transfer-with-authorization.md`, status `fetched`, ~31.6 KB) — normative source for the interface, the 3 typehash constant values, `NATIVE_ASSET`, the nonce model, and `INTERFACE_ID`. |
| Technical context | Circle USDC FiatToken repo (`.oli-work/context/technical/repo/`), canonical EIP-3009 reference (`contracts/v2/EIP3009.sol`). Index/entry files (`index.md`/`context.md`) were not carried into the workspace snapshot; only `repo/` materialized — re-verified this run. No business context. |
| Missing sections / contradictions | None blocking. Noted: (a) EIP reference impl uses ERC-1271 + 20-byte validator envelope, but PRD §7/§12 mandate the opposite (direct typed-data digest + 32-byte `keyHash` envelope) — **PRD wins** (FR-1-AC-8 requires ERC-1271-wrapped digests to fail); (b) PRD §2.1 interface error set differs from the EIP reference impl error set — **PRD §2.1 wins**; (c) `InvalidRecipient(to)` has no firing rule in any FR/AC — resolved as a security-derived guard (see §7). |

## 2. PRD ID Coverage Index

> Ids preserved verbatim; detailed semantics remain in the PRD section cited. "Direct Design Coverage Target" points into `DESIGN.md`.

### Business goals
| PRD ID | Type | Design Relevance | Direct Design Coverage Target | Notes |
|--------|------|------------------|-------------------------------|-------|
| G-1 | Goal | Contract + ABI | FN-001, FN-002, FN-006 | Account-level settle standard interface + ERC-165; gas <120k ECDSA |
| G-2 | Goal | Contract | FN-001/002 settle path | Any ERC-20 + native, no token change |
| G-3 | Goal | Security/Invariant | INV-NONCE-ONCE, INV-RECIPIENT-BOUND, FN-003 | Anti-replay / anti-frontrun |
| G-4 | Goal | Signature | FN-101 `_verifyTwaSignature` + INTERFACE_SPEC §8 | Reuse ECDSA + passkey validators; per-validator envelope layout specified for backend/test (DR-002) |
| G-5 | Goal | Security/Invariant | INV-HOOK-ISOMORPHISM, FN-103 | TWA settlement reuses signing key's hook **and the `_batchCall` self-call guard**, isomorphic with execute (self-target parity, DR-003) |

### Functional requirements & acceptance criteria
| PRD ID | Type | Design Relevance | Direct Design Coverage Target | Notes |
|--------|------|------------------|-------------------------------|-------|
| FR-0 | Flow overview | Contract | DESIGN §4 sequence diagrams | Usage flow (authorize / facilitator settle / receive / cancel) |
| FR-1 (+rules 1-9) | Functional (P0) | Contract | FN-001, FN-102, FN-103 | `executeTransferWithAuthorization`, permissionless |
| FR-1-AC-1 | AC | Test | FN-001 | Happy path → transfer + nonce used + event |
| FR-1-AC-2 | AC | Test | INV-NONCE-ONCE | Reused nonce → `AuthorizationAlreadyUsed`, no fund move |
| FR-1-AC-3 | AC | Test | INV-TIME-WINDOW | Outside `(validAfter, validBefore)` → revert |
| FR-1-AC-4 | AC | Test | FN-101 | Non-owner/unregistered signer → `InvalidSignature`, nonce not consumed |
| FR-1-AC-5 | AC | Test | FN-103 | Insufficient balance → whole-tx revert |
| FR-1-AC-6 | AC | Test | INV-HOOK-ISOMORPHISM | Over-limit/non-whitelisted via hook → hook revert, nonce not consumed |
| FR-1-AC-7 | AC | Test | INV-HOOK-ISOMORPHISM | Within policy → success, hook accounting == same-param execute |
| FR-1-AC-8 | AC | Test (negative) | FN-101 | ERC-1271 message-wrapped digest → MUST fail revert |
| FR-1 boundary 1 | Boundary | Test | FN-101 | `signature.length < SIGNATURE_ENVELOPE_MIN_LENGTH` → `InvalidSignature()` |
| FR-1 boundary 2 | Boundary | Test | FN-101 | `getVerifiedValidator(keyHash)==address(0)` → `InvalidSignature()` |
| FR-2 (+rules 1-3) | Functional (P0) | Contract | FN-002, FN-102, FN-103 | `receiveWithAuthorization`, `msg.sender == to`, distinct typehash |
| FR-2-AC-1 | AC | Test | FN-002 | Payee call within policy → success + event |
| FR-2-AC-2 | AC | Test | FN-002 | `msg.sender != to` → `CallerNotPayee` |
| FR-2-AC-3 | AC | Test (negative) | INV-TYPESEP | Execute-typed auth via receive → verify fail (no cross-type replay) |
| FR-2-AC-4 | AC | Test | INV-HOOK-ISOMORPHISM | Over-limit/non-whitelist via hook → hook revert |
| FR-3 (+rules 1-5) | Functional (P1) | Contract | FN-003 | `cancelTransferAuthorization` form A (signed) + form B (self-call, empty sig) |
| FR-3-AC-1 | AC | Test | FN-003 | Form A valid owner sig → nonce used, `Canceled`, later execute/receive revert |
| FR-3-AC-2 | AC | Test | FN-003 | Empty sig + `msg.sender != address(this)` → revert |
| FR-3-AC-3 | AC | Test | INV-NONCE-ONCE | Already-used nonce → `AuthorizationAlreadyUsed` |
| FR-3-AC-4 | AC | Test | FN-003 | Empty sig + self-call → nonce used, `Canceled` |
| FR-4 | Functional (P2) | Contract | FN-004, FN-005 | `transferAuthorizationState` + `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`; nonce mgmt rules |
| FR-4-AC-1 | AC | Test | FN-004 | Used/canceled nonce → returns true |
| FR-4-AC-2 | AC | Test | FN-004 | Never-used nonce → returns false |
| FR-5 | Functional (P2) | Contract/ABI | FN-006 | ERC-165, `INTERFACE_ID = 0x86c5a9e1` MUST be `public constant` |
| FR-5-AC-1 | AC | Test | FN-006 | `supportsInterface(0x86c5a9e1)` → true |
| FR-5-AC-2 | AC | Test | FN-006 | Unknown id → false |

### State, invariants, NFRs
| PRD ID / Name | Type | Design Relevance | Direct Design Coverage Target | Notes |
|---------------|------|------------------|-------------------------------|-------|
| State: Unused / Used / Canceled | State machine | Contract | DESIGN §10 | Used & Canceled terminal, mutually exclusive |
| Product invariant 1 (one-time; used/canceled terminal) | Invariant | Security | INV-NONCE-ONCE | |
| Product invariant 2 (nonce space isolated from native/4337) | Invariant | Security/Storage | INV-NONCE-ISOLATION | |
| Product invariant 3 (to & value signature-bound) | Invariant | Security | INV-RECIPIENT-BOUND | |
| Product invariant 4 (CEI: nonce used before transfer) | Invariant | Security | INV-CEI | |
| Product invariant 5 (hook-constrained, isomorphic w/ execute) | Invariant | Security | INV-HOOK-ISOMORPHISM | |
| NFR-1 | Non-functional | Gas/bytecode | DESIGN §2, §14, §16 | runtime bytecode ≤ 24,576 (EIP-170); ECDSA ≤ 120,000 gas; passkey separate baseline |
| NFR-2 | Non-functional | Security | INV-CEI, FN-106 lock | anti-replay/frontrun/native-reentrancy (CEI + transient lock) |
| NFR-3 | Non-functional | Permissions | DESIGN §3 access-control, INV-HOOK-ISOMORPHISM | execute permissionless; cancel restricted; TWA MUST NOT bypass per-key hook |
| NFR-4 | Non-functional | Observability | events FN-001/002/003 | all state changes observable via events |

### Technical, data, dependencies, risks, handoff
| PRD ID / Item | Type | Design Relevance | Direct Design Coverage Target | Notes |
|---------------|------|------------------|-------------------------------|-------|
| §7 `_verifyTwaSignature` 7-step spec | Tech (PRD-fixed) | Signature | FN-101 | envelope `keyHash(32)‖ownerSignature`; direct `hashTypedData(structHash)`; no ERC-1271 wrapper |
| §7 typehash visibility (public constant) | Tech (PRD-fixed) | ABI | DESIGN §6 constants | 3 typehashes + `INTERFACE_ID` MUST be `public constant` |
| §7 EIP-712 domain (SmartWallet / 1.1.0) | Tech (PRD-fixed) | Signature | FN-104, FN-005 | reuse account domain; verified in `Static.sol:22-23` |
| §7 UUPS + ERC-7201 namespace | Tech | Storage/Upgrade | DESIGN §8, §13 | new nonce storage in independent namespace |
| §7 evm cancun + transient reentrancy lock | Tech | Security/Build | FN-106, Risk Register | requires `evm_version=cancun` (currently shanghai) |
| §7 single-contract inline (EIP-170) | Tech | Architecture | DESIGN §2, §5 | new mixin compiled inline; no facade/library link |
| §8.1 data objects (transfer authorization / authorization state / token config / spending policy) | Data | Storage | DESIGN §8 | `operationType` = typehash selector, not a signed struct field |
| §8.2 authority boundaries | Data | Source-of-truth | DESIGN §8, §11 | on-chain vs off-chain authority |
| DEP-1..DEP-8 | Dependency | Trust model | DESIGN §12 | all "Confirmed", same-repo on-chain primitives + relayer + cancun chain |
| §10 metrics (8) | Success metric | Test/Audit | DESIGN §16 | gas, replay=0, recipient-tamper=0, hook-bypass=0, token coverage, bytecode, ERC-1271-wrapped-fail=100% |
| R-1..R-7, R-9 (no R-8) | Risk | Security | SECURITY_SPEC §8 | reentrancy, frontrun, wrong-wrapping, storage collision, knowledge, overlap, key-bypass, gas/optimizer |
| §12 PRD-to-TD handoff | Handoff | All | DESIGN §1, §2 | PRD-fixed items vs TD-decided items recorded |

## 3. Contract Scope Classification

| PRD ID | Classification | Contract Responsibility | Off-chain / Backend Responsibility | Reason |
|--------|----------------|-------------------------|------------------------------------|--------|
| FR-1, FR-2 | On-chain | verify sig, check nonce/window, mark used (CEI), run hook, transfer | build EIP-712 payload, collect sig, select/submit relayer | irreversible settlement + custody |
| FR-3 | On-chain | invalidate unused nonce (signed or self-call) | submit cancel tx; decide when to cancel | protocol state, irreversible |
| FR-4 | On-chain (state) / Hybrid (getters) | track nonce state; expose getters | index events; reconstruct domain separator off-chain | public verifiability |
| FR-5 | On-chain | ERC-165 `supportsInterface` | facilitator discovery | public interface detection |
| `_verifyTwaSignature` (§7) | On-chain | validator routing + signature verification | produce owner signature (ECDSA/passkey) | trust-sensitive authorization |
| Spending policy / hook limits (§8.1) | Hybrid | hook contract enforces on-chain; TWA invokes it | configure per-key hook params; provision key with hook | constrained on-chain, configured off-chain |
| NFR-4 observability | On-chain (emit) / Off-chain (index) | emit events | index `TransferAuthorizationUsed`/`Canceled` | reconciliation |
| §3.2 out-of-scope items | Out of scope | none | — | batch auth, on-chain allowedTokens/limits, pause/kill-switch, paymaster, multi-chain-one-signature, standing allowance — see §8 |

## 4. Existing Context-Derived Constraints

> Required because `codebase_mode=existing_code_change`. Evidence: `.oli-work/stage02-analysis/existing-code.md` + direct reads (cited in `DESIGN.md`).

| # | Constraint | Source (file:line) | Design impact |
|---|-----------|--------------------|---------------|
| C-1 | Account is a UUPS-upgradeable modular smart account (ERC-4337 + ERC-7702); state mixins inherited by `SmartWallet`, deployed as `SmartWalletEntry`. | `SmartWallet.sol:29-42`, `SmartWalletEntry.sol:9` | TWA is a new inherited mixin, inline in the single account bytecode |
| C-2 | Hook execution pattern: `_batchCall(Call[],keyHash)` resolves `getHook(_ownerSettings[keyHash])` and runs `preCheck(calls,msg.sender)` / `postCheck(ret,msg.sender)`. | `SmartWallet.sol:146-172`, `OwnerManager.sol:225` | TWA replicates this hook-call semantics keyed by the verified keyHash |
| C-3 | `Call{address target;uint256 value;bytes data}`. `_call` is a raw assembly call with **no return-value check**. | `Types.sol:4`, `ExecutionManager.sol:11-40` | ERC-20 leg of TWA MUST use SafeERC20 (PRD §12 "保留 SafeERC20 返回值校验") |
| C-4 | Validator routing: `getVerifiedValidator(bytes32)→address` (address(this)→ECDSA addr(1), expired→0); `_validateSignature(addr,bytes32,bytes32,bytes)→bool` (ECDSA/passkey/external, fail-closed). | `OwnerManager.sol:173`, `ValidationManager.sol:29` | `_verifyTwaSignature` reuses both verbatim |
| C-5 | EIP-712 is solady-backed; `hashTypedData(structHash)` = `keccak256(0x1901‖domSep‖structHash)`; domain `name="SmartWallet"`, `version="1.1.0"`. | `ERC712.sol:13`, `Static.sol:22-23` | digest derivation matches EIP draft exactly; reuse `hashTypedData` |
| C-6 | `Static.NATIVE_ETH = 0xEeee…EEeE` (ERC-7528) already exists. | `Static.sol:19-20` | reuse as the native sentinel; do not redeclare a conflicting value |
| C-7 | ERC-7201 namespace pattern `keccak256(abi.encode(uint256(keccak256(ns))-1)) & ~0xff`; existing namespace `SmartWallet.ERC7201.CustomStorage` root `0x653ff6dc…`. Whole account uses native `layout at` directive. | `ERC7201.sol`, `Static.sol:24-27`, `SmartWalletEntry.sol:9` | new TWA nonce namespace must be distinct + use an assembly storage accessor |
| C-8 | `onlySelf` = `msg.sender == address(this)`; `_authorizeUpgrade` is `onlySelf`. | `BaseAuthorization.sol:12`, `SmartWallet.sol:366` | cancel form B reuses `onlySelf`; upgrade authority unchanged |
| C-9 | Native execution nonce `mapping(uint192=>uint64)` (NonceManager). | `NonceManager.sol:12` | TWA `mapping(bytes32=>bool)` is a separate space (invariant 2) |
| C-10 | Existing execute/UserOp signature envelope is 38 bytes (`keyHash(32)+validUntil(6)+sig`); `isValidSignature` wraps the digest via `MessageSignLib.hash`. | `SmartWallet.sol:110,124,331,345`, `DecodeLib` | TWA uses a distinct 32-byte envelope (`keyHash(32)+sig`) and MUST NOT use the MessageSignLib wrapper (R-3) |
| C-11 | Build config: `solc 0.8.29`, **`evm_version=shanghai`**, `optimizer_runs=2000`. | `foundry.toml:5-9` | shanghai cannot compile EIP-1153 transient lock → must move to cancun (Risk Register) |
| C-12 | ERC-165 `supportsInterface` is a `virtual` `||` if-chain. | `FallbackHandler.sol:32-44` | extend via override + `super` to add `0x86c5a9e1` |
| C-13 (context) | Circle EIP-3009 uses per-`(address,nonce)` mapping, strictly **open** `(validAfter, validBefore)` window, `receiveWithAuthorization` requires `to==msg.sender`, and a `cancelAuthorization`. | context `contracts/v2/EIP3009.sol` | confirms TWA's open-interval window, receive caller check, and cancel semantics; OKX uses a flat `bytes32` mapping and adds a `token` field |

No conflict between the technical context and the PRD; the context corroborates the EIP-3009-derived semantics the PRD specifies. EIP-draft-vs-PRD discrepancies are resolved in favor of the PRD (see §1 and §7).

## 5. Delta Scope and Preserved Behavior

| Aspect | Detail |
|--------|--------|
| Requested delta | Add the `ITransferWithAuthorization` settle interface to the SmartWallet account (FR-1..FR-5), reusing existing validator routing + hook + EIP-712 domain. |
| Delta type | **Type B** (net-new module) for the TWA logic — specified to full new-code depth. **Type A** (modify-existing) for: `supportsInterface` (add one id), `foundry.toml` (`evm_version` shanghai→cancun), and the `SmartWallet` inheritance list (add mixin). |
| Directly affected | New: `src/interfaces/ITransferWithAuthorization.sol`, `src/TransferWithAuthorization.sol` (mixin). Modified: `src/SmartWallet.sol` (inherit mixin), `src/FallbackHandler.sol` or mixin override (ERC-165), `foundry.toml` (evm_version). |
| Indirectly affected | Bytecode size (EIP-170 budget) → `optimizer_runs` re-tuning; storage layout (new ERC-7201 namespace, must not collide); gas baseline. |
| Must remain unchanged | Existing execute / executeWithRelayer / executeUserOp / validateUserOp behavior; the 38-byte execute signature envelope; existing owner/validator/hook/nonce semantics; existing ERC-7201 `CustomStorage` layout; existing ERC-165 ids; UUPS upgrade authority (`onlySelf`); EIP-712 domain. |
| Evidence of no broader impact | TWA adds only new external functions + one independent storage namespace + one ERC-165 id; it calls existing internal primitives without modifying them. The transient reentrancy lock and `evm_version=cancun` are additive (cancun is a superset of shanghai). Global impact review in `DESIGN.md §2.5`. |

## 6. Design Coverage Targets

| PRD ID | Expected Design Coverage | Canonical Design Owner | Test / Review Target | Status |
|--------|--------------------------|------------------------|----------------------|--------|
| FR-1 | function + nonce + window + sig + hook + transfer + event | FN-001 / FN-102 / FN-103 | unit + fuzz + invariant + integration | covered |
| FR-2 | function + `to==msg.sender` + distinct typehash | FN-002 | unit + negative (cross-type) | covered |
| FR-3 | function + form A/B + nonce invalidation | FN-003 | unit | covered |
| FR-4 | view getters + nonce tracking | FN-004 / FN-005 | unit | covered |
| FR-5 | ERC-165 detection | FN-006 | unit | covered |
| `_verifyTwaSignature` | internal verification per 7-step spec | FN-101 | unit + negative (R-3) | covered |
| Invariants 1-5 | enforcement points | INV-NONCE-ONCE / -ISOLATION / -RECIPIENT-BOUND / -CEI / -HOOK-ISOMORPHISM | invariant tests | covered |
| NFR-1 | bytecode + gas budget | DESIGN §2/§14 | `forge build --sizes`, gas report | covered (validated in Stage 4.0) |
| NFR-2/3/4 | reentrancy lock, permission matrix, events | FN-106 / DESIGN §3 / events | invariant + access-control + event tests | covered |
| Security-derived | `InvalidRecipient(to)` zero-address guard, no-hook-key residual | SD-1.. (SECURITY_SPEC §2/§8) | unit + audit | covered |

## 7. Assumptions, Open Questions, and Blockers

| Item ID | Type | Source | Impact | Decision / Needed Input |
|---------|------|--------|--------|-------------------------|
| A-1 | Assumption | PRD §7 / existing-code | `SIGNATURE_ENVELOPE_MIN_LENGTH = 32` (envelope = `keyHash(32)‖ownerSignature`; TWA validity comes from signed `validAfter`/`validBefore`, so no 6-byte `validUntil` prefix unlike the existing 38-byte execute envelope). | Adopt 32; document; Stage 4.0 confirms |
| A-2 | Assumption | EIP draft + PRD §8.1 | `operationType` (a §8.1 field) is realized as the **choice of typehash** (Execute vs Receive), not a signed struct field; the three signed fields-sets are identical otherwise. | Adopt; document in DESIGN §9 |
| A-3 | Assumption (security-derived) | Security analyst / PRD §2.1 | `InvalidRecipient(to)` — PRD declares the error but gives no firing rule. Adopt: revert when `to == address(0)` (prevents silently burning native ETH via `to.call{value}`). Also recommend rejecting `to == NATIVE_ASSET` sentinel. | Adopt `to==address(0)` (and sentinel) guard; record as security-derived (SD-1/SD-2) |
| A-4 | Assumption | PRD §7 / R-9 | `optimizer_runs` is a dynamic knob; Stage 4.0 binary-searches it to satisfy EIP-170 after adding TWA + public-constant typehash getters. | Stage 4.0 owns the concrete value |
| A-5 | Assumption | PRD §7 / R-4 | New ERC-7201 namespace string (e.g. `SmartWallet.ERC7201.TransferAuthorization`); exact slot computed and storage-layout-verified non-colliding in Stage 4.0. | Stage 4.0 computes + validates |
| A-6 | Assumption | PRD FR-3 / EIP | Cancel form A is authorized by **any registered account key** via `_verifyTwaSignature` (the nonce is account-scoped, not key-scoped), matching the EIP's "owner(s)" and the account's authorization model. | Adopt; griefing residual recorded (SECURITY_SPEC) |
| OQ-1 | **Resolved** (Stage 3.0 rework DR-002) | Backend / interface | How the backend derives `keyHash` per owner/validator and encodes passkey signatures inside `ownerSignature`. | **Resolved in `INTERFACE_SPEC.md` §8 (Validator-Specific Signature Envelope)** — ECDSA `keccak256(abi.encodePacked(addr))` + 65-byte sig; built-in passkey `keccak256(abi.encodePacked(pubKeyX,pubKeyY))` + `abi.encode(PasskeyPubKey)‖abi.encode(WebAuthnAuth,bytes32[])`; external validator-defined. Closes G-4 backend handoff. |
| OQ-2 | Open Question | PRD NFR-1 | passkey-path gas baseline (PRD excludes passkey from the <120k ECDSA target). | Stage 5.0/6.0 measures separately |

No blockers. The PRD is internally sufficient to define safe contract behavior; all open items are TD-level (Stage 4.0) or backend-handoff items, not missing product decisions.

## 8. Off-chain and Out-of-scope Boundaries

| PRD item (§3.2 / §8.2) | Why not on-chain (this delta) |
|------------------------|-------------------------------|
| Batch authorization (multi-transfer in one) | PRD: single-transfer per ERC to reduce complexity/audit surface |
| On-chain `allowedTokens` whitelist / per-account limits | PRD: account layer does not restrict tokens; limits delegated to hook + off-chain |
| On-chain emergency pause / kill-switch | PRD: relies on cancel + off-chain risk control |
| Paymaster / gas sponsorship | PRD: relayer pays gas directly |
| Multi-chain one-signature batching | PRD: covered by existing Merkle path |
| Standing allowance (代扣) | PRD: covered by existing Allowance path |
| Signature payload construction, relayer selection, receive UI metadata, event index history, policy parameter config | PRD §8.2 off-chain authority |

## 9. Stage 3.0 Rework Updates (DR-001 / DR-002 / DR-003)

> Readiness/traceability deltas from the Stage 3.0 design review. The PRD id coverage above is unchanged (no new/removed PRD ids); these are doc-consistency and backend-handoff resolutions. Full Rework Resolution is in `output.md`.

| DR | Affected PRD ids | Resolution | Canonical landing | Coverage/readiness impact |
|----|------------------|------------|-------------------|---------------------------|
| DR-001 | FR-3, FR-4, NFR-4 | Settlement reconciliation must distinguish Used vs Canceled by event; `AuthorizationAlreadyUsed`/`state==true` is not "settled". | INTERFACE_SPEC §6/§6.1; DESIGN §10; SECURITY_SPEC §5/§9(14) | Closes a backend-integration correctness gap on FR-3 cancel semantics; raises readiness for Stage 4.0 handoff. |
| DR-002 | G-4, FR-1, FR-2 (§7 envelope) | Per-validator signature envelope (ECDSA/passkey/external) fully specified; OQ-1 resolved. | INTERFACE_SPEC §8; DESIGN FN-101/§16 | G-4 backend/test path now constructible without reverse-engineering; readiness raised. |
| DR-003 | G-5, FR-1, FR-2, R-7, NFR-3, inv 5 | Self-call guard replicated in TWA settle (FN-103 step 3); INV-HOOK-ISOMORPHISM now holds on the self-target path. | DESIGN FN-103/§15.5/§16; SECURITY_SPEC §2/§3/§9(13); INTERFACE_SPEC §8.4 | Removes an internal-consistency defect in the isomorphism claim; no PRD coverage change. |
