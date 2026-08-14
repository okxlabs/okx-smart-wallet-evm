# SECURITY_SPEC.md — Security Specification (TWA)

> Security overlay over `DESIGN.md`. Binding implementation contract: every invariant, access-control rule, fund-flow rule, and state-machine safety rule below MUST be implemented (or marked N/A with reason). References canonical ids (`FN-*`, `INV-*`) and sections from `DESIGN.md`; does not re-derive full behavior. Evidence: `.oli-work/stage02-analysis/security.md`.

Severity uses the flow's canonical schema (`oli-contract-common`): CRITICAL / HIGH / MEDIUM / LOW / INFO.

## 1. Threat Model

- **Attacker capabilities**:
  - Mempool front-runner: can extract a signed authorization and submit it before the intended facilitator. Outcome-neutral — `to`/`value` are signature-bound (INV-RECIPIENT-BOUND); attacker only pays gas. For contract payees needing atomic receipt, `receiveWithAuthorization` (`msg.sender==to`) is the defense (R-2).
  - Malicious relayer: arbitrary submitter; cannot alter recipient/amount/nonce; cannot reuse a settled nonce.
  - Malicious / non-standard ERC-20 (e.g. USDT no-return, fee-on-transfer, reentrant `transfer`): handled via SafeERC20 return-value check (FN-103) and the reentrancy lock.
  - Reentrant native recipient: `to.call{value}` forwards gas and can reenter. Bounded by CEI (FN-102 step 5) + transient lock (FN-106).
  - Restricted session/agent key: may attempt to use TWA to bypass its own per-key hook limit (R-7). Blocked structurally — the keyHash that authorizes the signature is the same keyHash that selects the hook (INV-HOOK-ISOMORPHISM).
  - Cross-chain / cross-account / cross-type replayer: blocked by EIP-712 domain (chainId + verifyingContract) and distinct typehashes (INV-TYPESEP).
- **Privileged-actor assumptions**: owners are registered `keyHash`es (varying admin/expiration/hook). Validators are trusted, fail-closed (try/catch in `_validateSignature`). EntryPoint is not on the TWA path. `address(this)` self-call is the only authority for cancel form B and UUPS upgrade.
- **User mistakes / malicious user**: signing with too-wide a window, or to a wrong/zero recipient — mitigated by `InvalidRecipient` guard (SD-1) and wallet-UI display of typed data (EIP "Phishing Risks").
- **External dependency failures**: a buggy/malicious per-key hook (owner-configured, semi-trusted) can only block its own key's spends (griefing of that key), never exceed account authority. A failing validator returns false (fail-closed).
- **Chain-specific surface**: requires Cancun for EIP-1153 transient storage (DEP-6, RR-1); native-asset reentrancy (ERC-7528 caveat).

## 2. Security Invariants

| ID | Statement | Related state | Related functions | Why it matters | Stage 5.0 test |
|----|-----------|---------------|-------------------|----------------|----------------|
| INV-NONCE-ONCE | Each `authorizationNonce` is consumed at most once; Used and Canceled are terminal and mutually exclusive (PRD inv 1). | `authorizationStates` | FN-102, FN-003 | prevents double-spend / replay | invariant: never settle the same nonce twice |
| INV-NONCE-ISOLATION | TWA nonce space is fully isolated from the native/4337 nonce (PRD inv 2). | TWA ERC-7201 namespace vs `NonceManager._nonces` | FN-105 | normal account ops cannot invalidate payments and vice-versa | storage-layout + invariant (no path writes both) |
| INV-RECIPIENT-BOUND | `to` and `value` are cryptographically bound in the signature; no submitter can change the settlement outcome (PRD inv 3). | signed digest | FN-101, FN-104 | anti-tamper / anti-front-run | fuzz: mutate to/value ⇒ verify fails |
| INV-CEI | The nonce flag is set before the transfer; on any settle revert it rolls back (PRD inv 4). | `authorizationStates` | FN-102 (step 5 before step 6), FN-106 | prevents reentrancy replay | reentrancy + invariant |
| INV-HOOK-ISOMORPHISM | A successful TWA settle invokes the keyHash-selected hook with a byte-identical `Call` **and applies the same self-call rule as `_batchCall`** — `Call.target == address(this)` reverts `NonAdminSelfCall` unless the verified signing keyHash is admin or the built-in `address(this)` key — identically to a same-parameter `execute` (PRD inv 5, G-5, R-7; DR-003). Two declared, intentional non-divergences only: (i) hook `executor` = relayer under TWA vs key-EOA under `execute`; (ii) ERC-20 leg via SafeERC20 vs raw `_call` — neither affects hook accounting or the self-call decision. | `_ownerSettings[keyHash].hook`, `_ownerSettings[keyHash]` (isAdmin) | FN-103 (steps 3-6) | a restricted key cannot bypass its hook via TWA, and cannot reach a privileged self-call path that `execute` would block | hook test: TWA-vs-`execute` parity; bypass attempts revert; self-target parity {admin,non-admin}×{native,token==self} + control test (DESIGN §16) |
| INV-TIME-WINDOW | Settlement only within the open interval `(validAfter, validBefore)`. | — | FN-102 step 2 | bounded validity | boundary tests (`==` edges revert) |
| INV-TYPESEP | Execute / Receive / Cancel authorizations are non-interchangeable (distinct typehashes). | typehash constants | FN-001/002/003, FN-104 | no cross-type replay | negative: cross-type submit fails |
| INV-NO-NATIVE-BURN (SD-1) | `to == address(0)` is rejected, preventing a silent native-ETH burn via `to.call{value}` to zero. | — | FN-001, FN-002 | the frozen interface's otherwise-unused `InvalidRecipient` is the anti-burn guard | unit: zero recipient reverts `InvalidRecipient` |
| INV-VALUE-CONSERVATION | A settle moves exactly `value` to `to` on success; any failure reverts the whole tx, leaving balances unchanged. | account balance | FN-103 step 5, FN-102 | no partial/over settlement, no stuck funds | unit + invariant |

## 3. Access-control Matrix

| Function | Role / Signer Required | Allowed | Must Revert When | Notes |
|----------|------------------------|---------|------------------|-------|
| FN-001 `executeTransferWithAuthorization` | none (permissionless) + valid owner-key signature | any caller with a valid signed authorization | bad/expired/reused nonce; outside window; invalid signature; `to==0`; **non-admin key self-target (`NonAdminSelfCall`: native `to==self` or ERC-20 `token==self`; FN-103 step 3, DR-003)**; hook policy violated; transfer fails; reentrancy | NFR-3 "execute MUST be permissionless"; self-call guard mirrors `_batchCall` |
| FN-002 `receiveWithAuthorization` | `msg.sender == to` + valid signature (RECEIVE typehash) | only the payee | `msg.sender != to` (`CallerNotPayee`); + all FN-001 conditions; cross-type sig | R-2 anti-front-run |
| FN-003 `cancelTransferAuthorization` (form A) | any registered account key signature (CANCEL typehash) | relayer-submitted | nonce already used/canceled; invalid signature | account-scoped nonce (A-6); griefing residual (§8) |
| FN-003 `cancelTransferAuthorization` (form B) | `msg.sender == address(this)` | account self-call (inside execute/UserOp) | empty sig and `msg.sender != address(this)` (`NotFromSelf`) | reuses `onlySelf` |
| FN-004 / FN-005 (getters) | none (view) | anyone | — | no state change |
| FN-006 `supportsInterface` | none (view) | anyone | — | — |
| `_authorizeUpgrade` (existing) | `onlySelf` | account self only | non-self upgrade | unchanged; no new role (PRD §7) |

## 4. Fund-flow Safety Rules

- **Inflow**: none added by TWA.
- **Outflow authorization**: every outflow requires a valid owner signature over the bound `{token,to,value,window,nonce}`, an unused nonce, the open time window, and (if configured) passing the per-key hook (FN-101→FN-102→FN-103).
- **Accounting before transfer**: nonce flag set before transfer (CEI, FN-102 step 5).
- **Fee/refund**: none (exact `value`, no protocol fee).
- **Stuck-fund prevention**: TWA holds no funds; failed transfers revert the whole tx (INV-VALUE-CONSERVATION).
- **Token/native assumptions**: ERC-20 via `SafeERC20.safeTransfer` (return-value checked, USDT-safe; PRD §12); native via checked `to.call{value}`. `token == NATIVE_ASSET` selects the native path. Fee-on-transfer/rebasing tokens settle the nominal `value` (account-level, no internal accounting assumption beyond the nonce flag).

## 5. State-machine Safety Rules

- Valid transitions: Unused→Used (FN-001/002), Unused→Canceled (FN-003). See `DESIGN.md §10`.
- Rejected transitions: Used/Canceled→anything ⇒ `AuthorizationAlreadyUsed`.
- Terminal protection: a single `bool` per nonce; once `true` it is never cleared (no function sets it back to false).
- Idempotency/replay: CEI + transient lock; a reverted settle leaves the nonce Unused (FR-1-AC-6).
- **Used vs Canceled are on-chain-indistinguishable (DR-001):** both set the same `bool`; `transferAuthorizationState(nonce)` and the `AuthorizationAlreadyUsed` revert do **not** reveal which terminal state was reached. The distinction exists **only** as the distinct events `TransferAuthorizationUsed` vs `TransferAuthorizationCanceled` (NFR-4). This is a business-control / off-chain-accounting safety rule: backend settlement reconciliation MUST disambiguate by event and MUST NOT treat a canceled nonce as paid (binding integration contract in `INTERFACE_SPEC.md` §6.1). On-chain fund safety is unaffected — `cancel` moves no funds and `INV-NONCE-ONCE` holds — but mis-reading canceled-as-settled off-chain would defeat `cancel` as a revocation control.

## 6. External Call / Dependency Risks

- **ERC-20 `transfer`**: external call; SafeERC20 handles non-standard returns; reentrant tokens bounded by the lock.
- **Native `to.call{value}`**: reentrancy surface; CEI + transient lock; gas forwarded to recipient.
- **Per-key hook `preCheck`/`postCheck`**: owner-configured, semi-trusted; reverts roll back the settle; cannot escalate authority. `preCheck` is `payable` in the existing `IHook` — TWA forwards no value to it (matches `_batchCall`). **Executor caveat:** under TWA the `executor` argument is the relayer (`msg.sender`), not the signing key; the constrained key is identified by the keyHash-based hook selection, not by `executor`. A hook that keys limits off `executor` would diverge from `execute` (where executor = the key's EOA) — see §9 item 12.
- **Validator contract**: external `validateSignature` wrapped in try/catch (fail-closed) by `_validateSignature`.
- **Dependency failure**: missing/invalid validator ⇒ `getVerifiedValidator` returns 0 ⇒ `InvalidSignature` (correct deny).

## 7. Chain-specific Security Requirements (EVM)

- **CEI**: mandatory ordering — checks, mark-nonce-used (effect), transfer (interaction) (FN-102).
- **SafeERC20**: required for the ERC-20 leg (FN-103); preserves return-value check that the raw `_call` path lacks (RR-2).
- **Reentrancy**: transient (EIP-1153) lock on FN-001/FN-002 (FN-106); requires `evm_version=cancun` (RR-1).
- **Signature domain separation**: EIP-712 domain includes chainId + verifyingContract (account); direct `hashTypedData(structHash)` digest, no ERC-1271/MessageSignLib wrapper (R-3).
- **Upgradeability storage safety**: new ERC-7201 namespace, append-safe, non-colliding with `0x653ff6dc…`; verified via `forge inspect storageLayout` (R-4).
- **Decimals/rounding**: N/A — TWA transfers an exact `value`, no conversion/pricing.
- **Low-level call handling**: native send checks success and reverts on failure; ERC-20 via SafeERC20.

## 8. Known Risks and Mitigations

| Risk (PRD) | Description | Severity | Mitigation | Residual | Must test/audit |
|-----------|-------------|----------|------------|----------|-----------------|
| R-1 | native-transfer reentrancy | HIGH | CEI + transient lock (FN-102/FN-106) | low (lock correctness) | reentrancy + invariant (test + audit) |
| R-2 | execute front-runs payee's atomic flow | MEDIUM | `to` bound + `receiveWithAuthorization` (`msg.sender==to`) + distinct typehash | low | cross-type + receive tests |
| R-3 | wrong signature wrapping (ERC-1271/MessageSignLib) | HIGH | direct `hashTypedData(structHash)`; FN-101; ERC-1271-wrapped-digest must-fail regression (FR-1-AC-8, §10 metric) | low | negative regression (test + audit) |
| R-4 | upgrade storage collision | MEDIUM | independent ERC-7201 namespace + storage-layout check | low | storage-layout gate |
| R-5 | knowledge concentration | LOW | PRD + DESIGN + EIP draft + full test coverage | low | docs/review |
| R-6 | overlap with executeWithRelayer / Allowance | MEDIUM | positioned as additive standard layer (random independent nonce, receive pull, isomorphic policy) | low | design review |
| R-7 | restricted key bypasses its hook via TWA | HIGH | same keyHash routes validator + selects hook (INV-HOOK-ISOMORPHISM) | **accepted residual: a non-admin key with NO hook configured spends unconstrained on TWA — identical to `execute` today; depends on the "provision keys with a hook" operational invariant** | hook parity + bypass tests (test + audit) |
| R-9 | inline + low optimizer_runs raises gas / EIP-170 | HIGH | optimizer_runs binary-search; re-measure NFR-1 (<120k) + bytecode (≤24,576) after any size-affecting change | medium (Stage 4.0 tuning) | `--sizes` + gas report |

### Security-derived requirements (zero-address / sentinel sweep — distinct from PRD-authored items)

Every address-typed input/slot the TWA delta introduces or consumes was swept:

| ID | Address input / slot | Guard required? | Decision |
|----|----------------------|-----------------|----------|
| SD-1 | `to` (FN-001/FN-002 param) | **Yes** | revert `InvalidRecipient(to)` when `to == address(0)` — closes a silent native-ETH burn (`to.call{value}` to zero returns success). Severity of omission: CRITICAL (fund loss). This supplies the firing rule the PRD omits for `InvalidRecipient`. |
| SD-2 | `to == NATIVE_ASSET` sentinel | Recommended | also reject `to == NATIVE_ASSET` (0xEeee…EEeE) — a non-sensical recipient; revert `InvalidRecipient(to)`. |
| SD-3 | `token` (FN-001/FN-002 param) | Implicit | `token == address(0)` (not the sentinel) routes to the ERC-20 path; `SafeERC20.safeTransfer` to a codeless address reverts — no extra guard strictly required, but Stage 4.0 SHOULD confirm the revert is clean. |
| SD-4 | `validator` (from `getVerifiedValidator(keyHash)`) | **Yes (existing)** | `validator == address(0)` ⇒ `InvalidSignature()` (FN-101 step 3) — already enforced. |
| SD-5 | per-key `hook` (from `getHook(settings)`) | No (by design) | `hook == address(0)` means "no hook" ⇒ skip — intended; the no-hook residual is recorded under R-7. |
| SD-6 | `from` (= `address(this)`) | No | derived, never zero for a deployed account. |

**Self-call guard vs recipient sweep (DR-003).** The FN-103 self-call guard (`Call.target == address(this)` ⇒ `NonAdminSelfCall` for non-admin keys) is **orthogonal** to SD-1/SD-2: SD-1 (`to == address(0)`) and SD-2 (`to == NATIVE_ASSET`) run in FN-001/FN-002 **before** settle and constrain `to`; the self-call guard runs **inside** FN-103 (after recipient checks and signature verification) and constrains the built `Call.target` (`to` for native, `token` for ERC-20). `address(this)` is a distinct value from `0`/the sentinel, so there is no overlap, double-revert, or gap. The guard additionally closes the residual "native self-send as no-op" that SD-1/SD-2 do not cover. CEI/reentrancy are unaffected — a guard revert rolls back the CEI nonce write like any other settle revert.

## 9. Security Assumptions for Review and Audit (Stage 3.0 / 7.0 / 8.0 must verify)

1. The keyHash returned by `_verifyTwaSignature` is the **same** value used to select the hook in `_settleWithHook` (no path lets routing and hook-selection diverge) — the structural anti-bypass for R-7/G-5.
2. CEI ordering holds on all paths: the nonce flag is written before any external transfer; a revert anywhere rolls it back (FR-1-AC-6).
3. The digest fed to `_validateSignature` is the **direct** `hashTypedData(structHash)`; no ERC-1271/`MessageSignLib` wrapping anywhere on the TWA path (R-3); the wrapped-digest regression fails.
4. The transient reentrancy lock is correctly set/cleared across the full settle span and `evm_version=cancun` is configured (RR-1).
5. The TWA ERC-7201 namespace does not collide with `0x653ff6dc…` and is append-safe across upgrades (R-4); `forge inspect storageLayout` confirms.
6. ERC-20 settlement uses SafeERC20 (return-value checked), not the raw `_call` (RR-2); USDT-style tokens settle correctly (G-2).
7. The open-interval window `(validAfter, validBefore)` is enforced with strict `<`/`>` semantics (boundary `==` reverts).
8. Distinct typehashes make execute/receive/cancel authorizations non-interchangeable (INV-TYPESEP).
9. `SIGNATURE_ENVELOPE_MIN_LENGTH` (=32) and the `keyHash(32)‖ownerSignature` envelope match the verification slicing; a short envelope reverts `InvalidSignature` (FR-1 boundary 1).
10. The no-hook-key residual (R-7) is an accepted, documented behavior (identical to `execute`), not a silent gap — provisioning must attach a hook to restricted keys.
11. Cancel form A authority (any registered key on an account-scoped nonce, A-6) is acceptable; its worst case is griefing (canceling a pending payment), never fund loss; key management mitigates.
12. The per-key SpendingPolicyHook derives the constrained key from its own configuration / the keyHash-based selection, **not** from the `executor` argument (which under TWA is the relayer, not the signer). Stage 7.0/8.0 must verify the hook does not key spending limits off `executor`; otherwise TWA-vs-`execute` accounting diverges and INV-HOOK-ISOMORPHISM would not hold for that hook (`DESIGN.md` FN-103 design note 2).
13. **Self-call guard (DR-003):** the TWA settle self-call guard (`DESIGN.md` FN-103 step 3) computes `allowSelfCall` from the **verified keyHash's** `_ownerSettings` (`isAdmin` or built-in `address(this)` key), **not** from `msg.sender`/`executor` (the relayer). Stage 7.0/8.0 must verify: a non-admin key's self-targeted settle (native `to == address(this)`, or ERC-20 `token == address(this)`) reverts `NonAdminSelfCall` exactly like `execute`; an admin/self key may self-target; and a legitimate self-receive (`token` = external ERC-20, `to` = the account) is **not** blocked (control case). This guard is what makes INV-HOOK-ISOMORPHISM hold on the self-target path; the ERC-20 leg's guard is for reason-uniformity (the `transfer`-selector fallback already reverts) and must not be removed.
14. **Settlement reconciliation (DR-001):** backend reconciliation disambiguates Used vs Canceled by event (`TransferAuthorizationUsed` vs `TransferAuthorizationCanceled`), **not** by `transferAuthorizationState`/`AuthorizationAlreadyUsed` (§5; `INTERFACE_SPEC.md` §6.1). Stage 7.0/8.0 must verify the backend interface/handoff doc does not instruct treating a bare `AuthorizationAlreadyUsed` (or `state==true`) as "settled", and that the Stage 4.0 `docs/delivery/CONTRACT_INTERFACE.md` carries the same event-reconciliation rule.
