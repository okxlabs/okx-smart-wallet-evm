# EMERGENCY_PLAN.md — TWA Deployment Emergency Response Plan

## Emergency Plan Status: READY

This plan covers the production deployment of the account-level Transfer-With-Authorization (TWA) feature for the `okx-smart-wallet-dev` SmartWallet account on Ethereum mainnet. It is READY: the response procedures are consistent with the audited contract capabilities (no confirmed Critical/High findings), and every documented lever is a real mechanism the contracts actually expose — no invented emergency power.

**Capability reality (read first):** this system has **no operator/admin emergency controls**. All on-chain levers are per-account and user-driven. The primary operator-actionable response is **off-chain** (backend / risk-control / relayer / facilitator).

---

## Related Documents

| Document | Role in an incident |
|----------|---------------------|
| `docs/delivery/DEPLOY_RUNBOOK.md` | Deployment procedure; the intended chain, build command, deploy order, salt, and post-deploy assertions an incident is measured against. |
| `docs/delivery/DEPLOY_CHECK.md` | Readiness checklist; pre-deploy gating items whose failure is itself a stop condition. |
| `docs/delivery/DEPLOY_DRY_RUN.md` | Operator-runnable fork dry-run; the rehearsal whose failure aborts go-live and whose procedures reproduce a suspected on-chain issue safely on a fork. |
| `docs/process/AUDIT_REPORT.md` | Audit findings (M-01/M-03/M-04/M-05; native-reentrancy refutation) carried below as monitoring / residual-risk items. |
| `docs/process/SECURITY_SPEC.md` | Threat model, invariants, access-control matrix, fund-flow rules, and the DR-001 reconciliation rule a response must not violate. |
| `docs/process/DESIGN.md` | §13 upgradeability/governance/admin and §11 fund-flow — the authority for "what powers exist". |
| `docs/delivery/CONTRACT_INTERFACE.md` | Backend ABI/event handoff; the Used-vs-Canceled event-reconciliation contract that backend stop-listing relies on. |

---

## Overview

### Project
Account-level TWA on the OKX SmartWallet account: EIP-712 signed, one-time, time-windowed, recipient-bound ERC-20/native settlement from an account's own balance, plus payee-gated receive, owner cancellation, and ERC-165 discovery. TWA is compiled **inline** into the `SmartWalletEntry` implementation bytecode — no new contract is deployed by the TWA delta (DESIGN §14).

### Chain
Ethereum mainnet, **chainId 1**, **Cancun** EVM (EIP-1153 transient storage). Cancun is a hard precondition: the native-reentrancy transient lock cannot operate on a non-Cancun chain (DESIGN §12/§14, SECURITY_SPEC §7, RR-1). Build: solc `0.8.29`, `evm_version=cancun`, `optimizer=true`, `optimizer_runs=100`.

### Assets at risk
Each smart-wallet account's **own** ERC-20 and native balance. Custody is the account itself (`from = address(this)`); there is **no escrow, no pooled funds, no protocol treasury, no shared vault**. A TWA settle moves exactly `value` to the signature-bound recipient; **no protocol fee, no refund path**. Therefore:
- The blast radius of any single compromised authorization or key is bounded to **one account's** balance — no cross-account contagion through this contract.
- There is no central pool to drain and no treasury an operator could freeze.

### Privileged roles
**None — global.** The central capability fact:
- The **factory** (`SmartWalletFactory`) and the **implementation** (`SmartWalletEntry`) are **ownerless and immutable**. No deployer-bound privilege at deploy time.
- **No global pause, no global kill-switch, no global upgrade admin, no proxy admin.**
- Upgrades are **UUPS**, authorized by `_authorizeUpgrade = onlySelf` **per account** — only the account itself (via an owner-authorized `execute` / UserOp / relayer path) can upgrade its own implementation.
- The ERC-4337 **EntryPoint v0.7** (`0x0000000071727De22E5E9d8BAf0edAc6f37da032`) is the canonical entrypoint; it is not on the TWA settlement path and confers no emergency authority over TWA.
- The EIP-2470 **Singleton Factory** (`0xce0042B868300000d44A59004Da54A005ffdcf9f`) is a stateless CREATE2 deployer used only at deploy time; it holds no ongoing authority and must never appear as an owner/admin.

Per-account roles (account owners = registered keyHashes with admin/expiration/hook settings) are **user-controlled, not operator-controlled**, and bind only to their own account.

### Risk categories
1. **Pre-deploy / deployment-integrity risk** — wrong chain, non-Cancun chain, factory-absent with an unexpected CREATE address, implementation↔factory wiring mismatch, bytecode-size regression (EIP-170), submodule/dependency drift, wrong build scope. Operator-controllable: **abort before broadcast**.
2. **Authorization / fund-flow risk (per account)** — a leaked owner key or an over-wide signed authorization can move that account's funds; bounded by signature binding, nonce terminality, and the open time window.
3. **Account-lifecycle / availability risk** — M-03 last-admin bricking; M-04/M-05 ERC-4337 validation liveness/griefing. No fund loss; degrades account usability.
4. **Off-chain control-plane risk** — backend mis-reconciling Canceled as Used (DR-001), or relayer/facilitator continuing to submit a known-bad authorization.
5. **Unknown contract vulnerability** — a defect not found by audit; because there is no global switch, the response is necessarily off-chain + per-account.

### Operational assumptions
- Off-chain controls (backend / risk-control / relayer / facilitator) are the **documented and primary** mitigation lever (DESIGN §13, SECURITY_SPEC §5/§8) — first responder, not a fallback.
- The backend disambiguates **Used vs Canceled by event** (`TransferAuthorizationUsed` vs `TransferAuthorizationCanceled`) and **never** treats a canceled nonce as paid (DR-001; SECURITY_SPEC §9 item 14; CONTRACT_INTERFACE.md). A regression here is itself an incident.
- Owner keys are managed by account owners/users; the operator cannot sign, cancel, or upgrade on their behalf.
- Restricted (non-admin) keys are expected to be provisioned **with a spending-policy hook**; a hookless non-admin key spending unconstrained is an accepted, documented residual (R-7), not a bug.
- Deployment follows `DEPLOY_RUNBOOK.md`, with secrets supplied only via environment / secrets manager (never embedded or committed).

---

## Severity & Activation Rules

| Severity | Definition (in this system's terms) | Activation |
|----------|-------------------------------------|------------|
| **SEV-1 (Critical)** | Credible evidence of unauthorized fund movement from accounts, a signature/replay break, a TWA hook bypass, native-settlement reentrancy, or storage collision on deployed accounts; OR a confirmed unknown vulnerability with on-chain fund impact. | Immediate. Page `<Security Lead>` + `<Smart Contract On-call>` + `<Backend Risk-Control On-call>`. Trigger the off-chain freeze (stop relayer/facilitator submission, stop co-signing, stop-list affected accounts/nonces) and the unknown-vulnerability runbook. |
| **SEV-2 (High)** | Deployment-integrity failure at/ before go-live (wrong chain / non-Cancun / wiring mismatch / size regression / CREATE-address mismatch); OR widespread account-liveness failure (mass UserOp rejections from M-04/M-05); OR a backend reconciliation regression (DR-001) booking canceled nonces as paid. | Within minutes. **Abort deployment before broadcast** if pre-go-live; otherwise page `<Smart Contract On-call>` + `<Backend Risk-Control On-call>` and apply the relevant known-risk plan. |
| **SEV-3 (Medium)** | A confirmed audit advisory manifesting without fund loss (isolated M-01 bundler-compat rejection, M-03 single-account self-brick, bounded M-05 gas griefing); dependency/build-hygiene drift (M-02) found post-deploy in CI. | Same business day. `<Smart Contract On-call>` triages; monitor and schedule a fix; no emergency freeze. |
| **SEV-4 (Low/Info)** | Cosmetic/documentation, or a single-user operational mistake with a self-service remedy (user signed too-wide a window and wants to revoke) and no systemic signal. | Best effort. Route to support; user uses `cancel` / key rotation. |

**Activation principle (capability honesty):** activation never implies the operator can *halt the contracts*. For every severity the operator-side actions are (a) off-chain freeze of submission/co-signing/listing, (b) communication, and (c) guidance to affected account owners on the per-account self-service levers. There is no global on-chain "stop".

---

## Contacts & Responsibilities

> Role placeholders only — fill with the current on-call roster before go-live. No real names/contacts recorded here.

| Role | Responsibility in an incident |
|------|-------------------------------|
| `<Deployment Operator>` | Executes `DEPLOY_RUNBOOK.md`; holds the authority to abort before broadcasting; performs post-deploy assertions; preserves deployment evidence (logs, predicted vs actual addresses, tx hashes). |
| `<Security Lead>` | Incident commander for SEV-1/SEV-2 security events; decides escalation; owns the unknown-vulnerability response and external-disclosure decisions. |
| `<Smart Contract On-call>` | Reproduces suspected on-chain issues on a fork (per `DEPLOY_DRY_RUN.md`); assesses whether a per-account UUPS fix is warranted; drafts/reviews any fixed implementation. |
| `<Backend Risk-Control On-call>` | Operates the primary lever: halts relayer/facilitator submission, refuses co-signing, stop-lists affected accounts/recipients/nonces, and verifies Used-vs-Canceled reconciliation integrity (DR-001). |
| `<Comms Lead>` | Internal/stakeholder updates and, if required, coordinated user-facing communication and disclosure timing with `<Security Lead>`. |

---

## Unknown Critical Contract Vulnerability Response

Governs a **previously unknown** vulnerability (not surfaced by `AUDIT_REPORT.md`) suspected to allow unauthorized fund movement, signature/replay abuse, hook bypass, reentrancy, or storage corruption on deployed accounts.

**Capability reality — read first.** There is **no operator switch** to pause, freeze, upgrade, or sweep user accounts globally. The factory and implementation are ownerless/immutable; UUPS upgrade is `onlySelf` per account. The only immediate operator-controlled containment is **off-chain**, and the only on-chain remediation is **per-account and user-driven**.

1. **Contain off-chain (immediate, operator-controlled — primary lever).**
   - `<Backend Risk-Control On-call>` halts relayer/facilitator submission of TWA authorizations (stop `executeTransferWithAuthorization` / `receiveWithAuthorization` co-signing and submission).
   - Refuse to co-sign or relay further authorizations; stop-list affected accounts, recipients, tokens, and any known-bad nonces.
   - This does **not** stop a third party from submitting an already-signed authorization directly to the EntryPoint/account (the execute path is permissionless). Containment is therefore best-effort suppression of the facilitated path, not a guarantee — state this to stakeholders explicitly.
2. **Assess & reproduce safely.** `<Smart Contract On-call>` reproduces on a **fork** (per `DEPLOY_DRY_RUN.md`) — never against mainnet accounts. Confirm scope: which accounts, which asset paths (ERC-20 vs native), whether a leaked key is required or it is key-independent.
3. **Per-account remediation (user-driven, the only on-chain fix).**
   - **Revoke pending authorizations:** affected owners call `cancelTransferAuthorization` (owner-signed form A, or self-call form B inside `execute`/UserOp) to terminate any unused/pending nonce so it can never settle. Moves no funds; fastest user-side mitigation for a known-bad pending authorization.
   - **Rotate / remove keys:** owners rotate or remove compromised owner keys via owner management to cut off the signing capability (subject to the M-03 last-admin caution).
   - **Per-account UUPS upgrade to a fixed implementation:** if the defect is in implementation logic, the documented fix is a **per-account** UUPS upgrade authorized by `onlySelf`. `<Smart Contract On-call>` + `<Security Lead>` prepare and review a fixed implementation; **each account must upgrade itself** (owner-authorized). There is **no** mechanism to push an upgrade to all accounts centrally — communicate the upgrade broadly and track adoption.
   - **Move funds out (owner's choice):** an owner may move their own assets to a safe address via a normal owner-authorized transfer if that is fastest for that account.
4. **Communicate.** `<Comms Lead>` + `<Security Lead>` issue guidance to account owners (which lever: cancel / key rotation / self-upgrade / withdraw) and the explicit statement that the operator cannot perform these on the owner's behalf.
5. **Do not deploy new accounts** against a known-vulnerable implementation: gate new factory deployments until a fixed implementation is published.

---

## Known Risk Response Plans

All items are **audit-confirmed advisories with no confirmed Critical/High and no demonstrated direct fund loss** (`AUDIT_REPORT.md`), carried here as monitoring / manual-confirmation / residual-risk handling.

### M-03 — Last-admin removal/downgrade can brick an account's self-call administration (per account)
- **What:** an account admin can `updateOwner`/`removeOwner` the last active admin, after which that account can no longer perform `onlySelf` administration — owner recovery, allowance approvals, **UUPS upgrade**, empty-signature self-cancel. Per-account only; no fund loss.
- **Why it matters here:** a self-bricked account loses its own UUPS-upgrade lever, so the "per-account upgrade to a fixed implementation" remediation above may be unavailable for it.
- **Monitoring:** `<Backend Risk-Control On-call>` monitors owner-lifecycle events for transitions leaving an account with no registered, non-expired admin key.
- **Response:** warn users in tooling before a last-admin removal/downgrade; preserve at least one active admin. An already-bricked account can recover only via the documented recoverable-self-key mode **if it was configured with one**; otherwise administrative recovery is impossible and the account is limited to its remaining non-admin capabilities. State this honestly to the owner.
- **Residual:** accepted; mitigation is operational (provisioning + UI guard + monitoring).

### M-04 — Expiring-owner UserOps use `block.timestamp` in ERC-4337 validation (liveness/compat)
- **What:** for expiring owners, validation branches on `block.timestamp` instead of returning the expiration via validation data; compliant bundlers may reject otherwise-valid UserOps. **No fund loss.**
- **Monitoring:** track bundler rejection rates / UserOp failure telemetry for expiring-owner configs.
- **Response:** SEV-3 (or SEV-2 if widespread liveness loss). Mitigation off-chain (bundler/relayer policy, advise non-expiring keys where appropriate) plus a scheduled code fix (pack effective expiration into validation data). No emergency action, no fund exposure.
- **Residual:** accepted, monitored.

### M-05 — Built-in validators can revert / do unbounded proof work during validation (gas/sim griefing)
- **What:** malformed ECDSA/passkey payloads can revert in decoding; large proof arrays create linear validation work with no local cap. Impact = gas/simulation griefing bounded by `verificationGasLimit` and bundler policy; **no fund loss**.
- **Monitoring:** watch for abnormal validation-gas / simulation-failure patterns and enumerable-keyHash probing.
- **Response:** SEV-3. Bundler/relayer-side rate limiting and gas policy now; scheduled fix (fail-closed decoding + proof-length cap) later. No emergency freeze warranted.
- **Residual:** accepted, monitored.

### M-01 — Non-canonical `SIG_VALIDATION_FAILED` packing (bundler-compat)
- **What:** signature-failure validation data packed into the wrong ERC-4337 field; an **invalid** UserOp may be misclassified as aggregator-based. Bundler-compatibility / misleading simulation only; **no fund loss**.
- **Monitoring:** include in bundler-compatibility regression monitoring.
- **Response:** SEV-3; scheduled code fix (use canonical `1`). No emergency action.
- **Residual:** accepted, monitored.

### Native-recipient reentrancy (audit-refuted; residual = lock correctness)
- **What:** native settlement sends ETH to a user-controlled recipient that can reenter. Audit **refuted** exploitability: bounded by CEI nonce-write-before-transfer, a full-span transient (EIP-1153) reentrancy lock, a checked low-level call, hook wrapping, and the self-call guard; reentrancy tests present.
- **Dependency:** protection **requires Cancun** (EIP-1153) — couples this residual to the deployment precondition (see stop conditions).
- **Monitoring / response:** no active incident expected. A reentrancy-shaped anomaly is treated as a potential unknown vulnerability (SEV-1 path) and verified on a fork. Preserve the native-reentrancy test and the delegate-and-revert simulator documentation in the handoff.
- **Residual:** low (lock correctness only), accepted.

### R-7 — Hookless non-admin key spends unconstrained (accepted provisioning residual)
- **What:** a non-admin key with no hook can spend that account's assets via TWA exactly as via `execute` today. Audit confirmed this is **not a bypass** but an accepted provisioning residual.
- **Response:** operational — provisioning must attach a spending-policy hook to restricted keys. Monitor for restricted keys configured without a hook. Not an incident in itself.

### DR-001 — Backend must not treat Canceled as paid (reconciliation safety)
- **What:** Used and Canceled both set the same on-chain `bool`; `transferAuthorizationState`/`AuthorizationAlreadyUsed` cannot distinguish them. Only the events `TransferAuthorizationUsed` (settlement proof) vs `TransferAuthorizationCanceled` (revocation proof) disambiguate.
- **Why it's here:** the off-chain freeze lever (cancel + stop-listing) **depends** on the backend honoring this. If the backend books a canceled nonce as paid, `cancel` is defeated as a revocation control.
- **Monitoring / response:** verify reconciliation distinguishes the two events (SECURITY_SPEC §9 item 14; CONTRACT_INTERFACE.md). A regression is an incident (SEV-2): halt settlement booking, correct the reconciliation, and re-derive state from events before resuming.

---

## Deployment-Specific Emergency / Stop Conditions

Pre-go-live and at-go-live abort gates. When any condition holds, `<Deployment Operator>` MUST **stop before broadcasting** (do not send the deployment transaction) and escalate. Each maps to a `DEPLOY_RUNBOOK.md` / `DEPLOY_CHECK.md` / `DEPLOY_DRY_RUN.md` check.

1. **Wrong chain / non-Cancun chain — HARD STOP.** Never deploy to a chain that is not the intended target, and never to one without Cancun/EIP-1153 active. The native-reentrancy transient lock is unsupported pre-Cancun (DESIGN §12/§14, SECURITY_SPEC §7, RR-1). Confirm `chainId == 1` and Cancun before broadcast. A non-Cancun deployment is not recoverable in place.
2. **Factory absent + unexpected CREATE address.** Deployment assumes the EIP-2470 factory at `0xce0042B868300000d44A59004Da54A005ffdcf9f` is present (CREATE2, deterministic address). **Stop** if it is unexpectedly missing on a chain where CREATE2 was intended, OR the predicted CREATE2 address does not equal the actual deployed address. Re-confirm factory presence, salt, and initCode (identical compiler settings) first.
3. **Implementation ↔ factory wiring mismatch.** After deploying `SmartWalletEntry` then `SmartWalletFactory(impl)`, assert `SmartWalletFactory.IMPLEMENTATION() == <deployed SmartWalletEntry address>`. If the factory points at the wrong (or zero) implementation, **stop and redeploy** — every account it creates would wire to the wrong implementation. Also assert `entryPoint() == 0x0000000071727De22E5E9d8BAf0edAc6f37da032` and `supportsInterface(0x86c5a9e1) == true`, and that no owner/admin is ever the singleton factory (N/A by ownerless design, asserted by absence).
4. **Bytecode size regression (EIP-170).** `SmartWalletEntry` runtime is 24,510 bytes — only 66 bytes under the 24,576 limit (verified this stage). Re-run `forge build src script --sizes` immediately before deploy. **Stop** if runtime exceeds 24,576, or any source growth has eaten the 66-byte margin without a re-tuned `optimizer_runs` / size mitigation.
5. **Submodule / dependency drift.** Reconcile `lib/` gitlinks before packaging and build **offline** (`FOUNDRY_OFFLINE=true`) so forge does not auto-run `git submodule update` and reset drifted-but-working libs (a known trap for this repo). **Stop** if libraries cannot be reconciled to the audited revisions, or a build mutates submodule state.
6. **Wrong build scope (M-02).** The default `forge build` fails on `test/Recovery.t.sol` (inherited private `smart-wallet-recovery` dependency). Deployment validation MUST use `forge build src script` (which passes) or restore the private dependency. **Stop** if a deployment/CI step relies on an unscoped default build and fails — fix the build scope, do not skip verification.
7. **Salt / cross-chain determinism not pinned.** The operator-supplied `DEPLOY_FACTORY_SALT` (bytes32, from environment) must be recorded; the same salt + identical initCode + factory presence are required for any intended cross-chain identical address. **Stop** if the salt is unset/undocumented when a deterministic address is required.
8. **Dry-run not satisfied.** If the fork dry-run (`DEPLOY_DRY_RUN.md`) — create account → ERC-20 settle → replay-revert, storage-layout non-collision — has not passed on a target-equivalent fork, **do not go live**. (In-stage dry-run was DEFERRED only because no fork RPC was configured; the operator must execute the plan before mainnet broadcast.)
9. **Secrets / static-check violation.** **Stop** if any deployment artifact embeds a private key or an RPC URL literal, carries broadcast/verify/private-key flags on a non-commented line, or would log/commit a secret. Secrets come from environment / secrets manager only. Re-run the bundled secret/static checks clean before broadcast.

**Mid/post-broadcast caveat:** if a stop condition is discovered **after** broadcast (e.g. a wiring mismatch found post-deploy), the deployed factory/implementation are immutable and ownerless — they cannot be paused or patched in place. The response is to (a) not advertise or onboard accounts onto the bad deployment, (b) deploy a corrected implementation/factory at a new address, and (c) communicate the canonical addresses. Accounts already created against a bad implementation can only remediate via their own `onlySelf` UUPS upgrade (subject to M-03).

---

## Recovery & Resume Conditions

Deployment validation / go-live (or post-incident resumption of the facilitated TWA service) may resume only when **all** applicable conditions are met:

1. **Trigger resolved.** The stop condition / incident root cause is fixed and verified (correct chain/Cancun; predicted == actual CREATE2 address; `IMPLEMENTATION()` wiring correct; size ≤ 24,576 with margin; submodules reconciled; build via `forge build src script` clean).
2. **Post-deploy assertions pass (read-only).** `SmartWalletFactory.IMPLEMENTATION() == SmartWalletEntry`; both addresses have non-zero code; `SmartWalletEntry.supportsInterface(0x86c5a9e1) == true`; `entryPoint() == 0x0000000071727De22E5E9d8BAf0edAc6f37da032`; `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` equals the account domain separator; storage-layout shows no collision with `0x653ff6dc…`.
3. **Dry-run green.** The fork dry-run (account creation, ERC-20 settle, replay-revert) passed on a target-equivalent fork.
4. **Off-chain controls verified.** Backend Used-vs-Canceled reconciliation (DR-001) confirmed correct; stop-lists accurate; relayer/facilitator submission re-enabled only after `<Backend Risk-Control On-call>` confirms no known-bad authorizations remain unrevoked.
5. **Per-account remediation tracked (if a SEV-1/unknown-vuln event occurred).** A fixed implementation is published, upgrade instructions communicated, and adoption tracked; new-account deployment re-enabled only against the fixed implementation.
6. **Sign-off.** `<Security Lead>` (security incidents) and `<Deployment Operator>` (deployment-integrity stops) record an explicit go/resume decision with supporting evidence.

**Resume honesty:** because there is no global pause, "resume" means resuming the off-chain facilitated service and/or new-account deployment — there is no on-chain global state to un-pause. Individual accounts remain governed solely by their owners throughout.

---

## Evidence Preservation Requirements

Preserve the following for every incident and every aborted/completed deployment, before any remediation that could overwrite state. Do **not** capture secrets (private keys, tokens, RPC URLs) into evidence; reference them by environment-variable name only.

1. **Deployment record:** exact build command, `forge`/solc versions, `evm_version`, `optimizer_runs`, `--sizes` output (with the recorded SmartWalletEntry size and margin), the `DEPLOY_FACTORY_SALT` value used, predicted vs actual CREATE2 addresses, deploy transaction hashes, chainId/Cancun confirmation, and `lib/` revision state before and after build.
2. **Post-deploy assertion outputs:** the read-only checks in Recovery §2 (factory↔implementation wiring, code presence, `supportsInterface`, `entryPoint`, domain separator, storage-layout diff).
3. **Incident timeline:** detection time, who was paged, actions taken (off-chain freeze toggles, stop-list changes), and decision points with timestamps.
4. **On-chain evidence:** affected account addresses, relevant transaction hashes, and — critically — the relevant **events** (`TransferAuthorizationUsed`, `TransferAuthorizationCanceled`, owner-lifecycle events) needed to reconstruct Used-vs-Canceled state per DR-001. Capture block ranges and EntryPoint UserOp hashes where ERC-4337 paths are implicated (M-04/M-05).
5. **Reproduction artifacts:** the fork block number and the dry-run / reproduction scripts or transcripts used to reproduce a suspected vulnerability (per `DEPLOY_DRY_RUN.md`), so the analysis is replayable.
6. **Backend/control-plane state:** relayer/facilitator submission logs (redacted), stop-list snapshots, and reconciliation outputs proving how Canceled vs Used was classified at incident time.
7. **Communications:** copies of stakeholder/user notices and any disclosure issued by `<Comms Lead>` / `<Security Lead>`.
8. **Chain of custody & retention:** store evidence in a tamper-evident, access-controlled location for the policy retention period; record who collected each artifact and when. Keep evidence free of sensitive credentials.
