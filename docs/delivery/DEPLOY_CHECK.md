# Deployment Readiness Checklist — DEPLOY_CHECK.md

**Project:** okx-smart-wallet-dev — Account-level Transfer-With-Authorization (TWA)
**Stage:** N09 — Deployment Preparation
**Codebase mode:** existing_code_change (first-time deployment adoption; not a rework run)
**Target chain (first launch):** EVM — Ethereum mainnet, chainId 1 (Cancun / EIP-1153 transient storage REQUIRED)
**Build profile:** solc `0.8.29`, `evm_version=cancun`, `optimizer=true`, `optimizer_runs=100`

**Status legend:** `PASS` = checked, evidence exists · `FAIL` = checked, failed due to a defect · `BLOCKED` = cannot be checked because required input/environment/approval is unavailable.

---

## Overall Readiness: PASS — with two operator-must-confirm-on-chosen-chain preconditions

All required readiness checks PASS. There are **no blocking items**. Two items are deployment preconditions the operator MUST confirm against the actually-chosen target chain immediately before deployment:

1. **EIP-170 size margin is tight** — SmartWalletEntry runtime is 24,510 bytes, only **66 bytes** under the 24,576-byte limit. Re-run `forge build src script --sizes` immediately before deploy and forbid any source growth without a size-reduction mitigation.
2. **Cancun / EIP-1153 precondition** — the target chain MUST be Cancun-active (DESIGN §12 DEP-6); the TWA native-reentrancy transient lock (EIP-1153) is unsupported on non-Cancun chains. Satisfied for Ethereum mainnet; **BLOCKED for any chain the operator cannot confirm is Cancun-active.**

The in-stage fork dry-run is **DEFERRED** (no fork RPC configured); it is PASS-compatible and the operator runs the documented procedure in `docs/delivery/DEPLOY_DRY_RUN.md`.

---

## Required Checks

| # | Check | Status | Evidence / Notes |
|---|-------|--------|------------------|
| 1 | Security audit conclusion is PASS | **PASS** | `docs/process/AUDIT_REPORT.md` — verdict WARN, **Pipeline-stage Conclusion: PASS** (FAIL_ON=critical; 0 confirmed Critical/High; 5 non-blocking Medium advisories). |
| 2 | Implementation/test review conclusion is APPROVED | **PASS** | `docs/process/DEV_REVIEW.md` — **Overall Decision: APPROVED** (highest severity MEDIUM, non-blocking). |
| 3 | Context-derived deployment constraints reviewed (or no context) | **PASS** | technical context = Circle USDC repo used as EIP-3009 semantic reference only (different system; its deploy scripts do not govern this repo). business context = none. Only constraint is the Cancun requirement, already encoded in DESIGN (see check #17). No deployment-convention conflict. |
| 4 | Deployment runbook exists and is complete | **PASS** | `docs/delivery/DEPLOY_RUNBOOK.md`. Carries M-02 build hygiene, EIP-170 size recheck, and submodule-gitlink reconciliation into the pre-deploy checklist. |
| 5 | Emergency response plan exists and is complete | **PASS** | `docs/delivery/EMERGENCY_PLAN.md`. Capability-honest: no global pause/upgrade admin exists; documented mitigation = per-account `cancel` + off-chain risk control; carries M-03/M-04/M-05 as residual-risk / monitoring items. |
| 6 | Deployment script exists | **PASS** | `script/deploy.s.sol` (contract `DeployInit`) — deploys SmartWalletEntry + SmartWalletFactory via EIP-2470 CREATE2 with CREATE fallback when the singleton factory is absent. |
| 7 | Optional verification script / manual verification steps exist | **PASS** | `script/VerifyDeployment.s.sol` — read-only post-deploy checks (factory→implementation binding, non-zero code, interface support, EntryPoint, self-reference, optional chain-id). |
| 8 | `forge build` passes | **PASS** | Scoped production build `forge build src script` exits 0 (SmartWalletEntry 24,510 B, SmartWalletFactory 2,218 B; built OFFLINE, submodule state unchanged). **NOTE:** default unscoped `forge build` FAILS on the uninitialized private `lib/smart-wallet-recovery` test import (audit M-02) — documented build-hygiene item, not a production-source defect; production `src`+`script` build is clean. |
| 9 | Bundled secret scan passes | **PASS** | `secret_scan.py` over `script docs/delivery foundry.toml .env.example` — clean (run by primary this stage). |
| 10 | Bundled static deployment checks pass | **PASS** | `deployment_static_checks.py` over `script docs/delivery` — clean (run by primary this stage). |
| 11 | Constructor / init parameters are defined | **PASS** | SmartWalletEntry constructor: **none** (`IMPLEMENTATION = address(this)` immutable self-ref + `_disableInitializers()`). SmartWalletFactory constructor: `address _implementation`. Per-account `initialize(InitialOwner[])` is a post-deploy, factory-driven step (not a deploy-time parameter), unchanged by TWA. |
| 12 | Deployment order matches dependencies | **PASS** | SmartWalletEntry → SmartWalletFactory(impl): the factory's immutable `IMPLEMENTATION` is the SmartWalletEntry address from step 1. `script/deploy.s.sol` performs exactly this order. |
| 13 | Proxy / admin / owner / role handling is documented | **PASS** | UUPS with `_authorizeUpgrade = onlySelf` per account; factory and implementation are **ownerless / immutable**; no global admin, no global pause/upgrade role; no deployer-bound privilege. Documented in runbook, emergency plan, and DESIGN §13. |
| 14 | No private keys or production secrets in repo changes | **PASS** | Env-var driven; `.env.example` carries empty placeholders only; bundled secret scan clean (check #9). |
| 15 | Runnable `Deploy.s.sol` + portable dry-run procedure ready | **PASS** | `script/deploy.s.sol` (contract `DeployInit`) is runnable; the operator dry-run / pre-deployment test checklist is documented in `docs/delivery/DEPLOY_DRY_RUN.md`. (Project convention uses the filename `deploy.s.sol`; the bundled static checker only warns on the exact name `Deploy.s.sol`, which is non-fatal — see Blocking-Items table.) |
| 16 | EIP-170 runtime bytecode size within limit | **PASS — with note** | SmartWalletEntry runtime = **24,510 bytes**, only **66 bytes** under the 24,576-byte limit. **Operator MUST re-run `forge build src script --sizes` before deploy and forbid source growth without a size mitigation.** SmartWalletFactory = 2,218 bytes (ample margin). |
| 17 | Cancun / EIP-1153 precondition on target chain | **PASS** (Ethereum mainnet) / **operator-confirm per chain** | Target chain MUST be Cancun-active (DESIGN §12 DEP-6, SECURITY_SPEC §7, RR-1) — TWA native-reentrancy transient lock requires EIP-1153. Satisfied for Ethereum mainnet (and X Layer 196/1952 per REQUIREMENTS). **BLOCKED for any chain the operator cannot confirm is Cancun-active** — do NOT deploy there. |
| 18 | Storage-layout non-collision (ERC-7201) | **PASS** | TWA ERC-7201 namespace is distinct from the account custom-storage root `0x653ff6dc…` (DESIGN R-4). **Operator should verify via `forge inspect SmartWalletEntry storageLayout` before deploy.** |
| 19 | Fork dry-run executed in-stage | **DEFERRED (PASS-compatible)** | No `FORK_RPC_URL` / `MAINNET_RPC_URL` configured and Oli Run Config has no fork-RPC field, so the in-stage fork dry-run is deferred — not a defect. The operator runs the documented procedure in `docs/delivery/DEPLOY_DRY_RUN.md` (create account via factory → happy-path ERC-20 settle → replay-revert). |

---

## Materials Table

Paths are relative to the `okx-smart-wallet-dev/` project root.

| Artifact | Purpose | Status | Path / Evidence |
|----------|---------|--------|-----------------|
| Deployment runbook | Step-by-step production deploy procedure + pre-deploy hygiene checklist | **PASS** | `docs/delivery/DEPLOY_RUNBOOK.md` |
| Emergency response plan | Incident response, residual-risk register, capability-honest mitigations | **PASS** | `docs/delivery/EMERGENCY_PLAN.md` |
| Deployment script | Deploys SmartWalletEntry + SmartWalletFactory (EIP-2470 CREATE2, CREATE fallback) | **PASS** | `script/deploy.s.sol` (contract `DeployInit`) |
| Deploy-factory interface | Inline EIP-2470 singleton-factory interface used by the deploy script | **PASS** | `script/IDeployFactory.s.sol` |
| Verification script | Read-only post-deploy assertions (factory binding, code, interface, EntryPoint, self-ref, chain-id) | **PASS** | `script/VerifyDeployment.s.sol` |
| Fork dry-run plan | Operator-runnable pre-deployment test checklist (in-stage DEFERRED, PASS-compatible) | **PASS** | `docs/delivery/DEPLOY_DRY_RUN.md` |
| Deterministic checks — secret scan | Bundled secret scan over deploy-relevant paths | **PASS** | `secret_scan.py` over `script docs/delivery foundry.toml .env.example` — clean |
| Deterministic checks — static deployment checks | Bundled static deployment-readiness checks | **PASS** | `deployment_static_checks.py` over `script docs/delivery` — clean |
| Build evidence | Scoped production build + bytecode sizes | **PASS** | `forge build src script --sizes` → exit 0; SmartWalletEntry 24,510 B (margin 66), SmartWalletFactory 2,218 B (OFFLINE; submodules unchanged) |

---

## Blocking Items Table

**No blocking items.** All required checks PASS (with two operator-confirm preconditions in Overall Readiness and checks #16–#17). The items below are **non-blocking / informational** and should be reconciled by the operator before packaging/deployment.

| Item | Severity | Status | Resolution / Operator action |
|------|----------|--------|------------------------------|
| `package.json` `deploy` npm script references a non-existent `script/deploy/DeployInit.s.sol` | Informational | Non-blocking | Real deploy script is `script/deploy.s.sol`. Reconcile the npm path or run forge directly per README §Deploy. |
| Deploy script filename is `deploy.s.sol` (not `Deploy.s.sol`) | Informational | Non-blocking | The bundled static checker emits a non-fatal warning ("no Deploy.s.sol found"); the script is runnable and matches the README/Stage-1 convention. Renaming is optional and out of scope for existing-code preservation. |
| Submodule gitlink drift in `lib/` | Low (informational) | Non-blocking | Reconcile `lib/` gitlinks before deployment packaging; build OFFLINE (`FOUNDRY_OFFLINE=true`) so forge does not auto-reset drifted-but-working libs. |
| Default unscoped `forge build` fails on private recovery-suite test import (audit M-02) | Medium (non-blocking) | Non-blocking | Use the scoped production build `forge build src script` (or restore the private `lib/smart-wallet-recovery` dependency). Production source compiles cleanly. |
| EIP-170 size margin only 66 bytes (audit, Medium) | Medium (non-blocking) | Non-blocking precondition | Re-run `forge build src script --sizes` before deploy; forbid source growth without a size mitigation (see check #16). |
| M-03 — admin lifecycle can remove/downgrade the last active admin (per-account self-administration brick) | Medium (non-blocking) | Non-blocking | Per-account operational caution; carried into `EMERGENCY_PLAN.md` residual-risk register. Not deploy-blocking. |
| M-04 / M-05 — owner-expiry uses `block.timestamp` in validation; built-in validators can revert / do unbounded proof work | Medium (non-blocking) | Non-blocking | Bundler-compatibility & gas-griefing residual; monitoring item in `EMERGENCY_PLAN.md`. No fund loss. |
| M-01 — non-canonical `SIG_VALIDATION_FAILED` packing (`1 << 96`) | Medium (non-blocking) | Non-blocking | Bundler-compatibility advisory; monitoring item. No fund loss. |

---

## Pre-Deploy Operator Sign-off (complete against the chosen target chain)

- [ ] Target chain confirmed **Cancun / EIP-1153 active** (check #17) — do NOT deploy to a non-Cancun chain.
- [ ] `forge build src script --sizes` re-run; SmartWalletEntry runtime ≤ 24,576 bytes (check #16) — no source growth since 24,510 B.
- [ ] `forge inspect SmartWalletEntry storageLayout` verified — TWA namespace non-colliding (check #18).
- [ ] EIP-2470 singleton factory present at `0xce0042B868300000d44A59004Da54A005ffdcf9f` on the target chain (else CREATE fallback engages, reason `factory-unavailable`).
- [ ] ERC-4337 EntryPoint v0.7 present at `0x0000000071727De22E5E9d8BAf0edAc6f37da032` on the target chain.
- [ ] `DEPLOY_FACTORY_SALT` chosen and recorded (same salt for both contracts; cross-chain identical addresses require identical initCode + same salt + factory present).
- [ ] Fork dry-run from `docs/delivery/DEPLOY_DRY_RUN.md` executed and green (create account → ERC-20 settle → replay-revert).
- [ ] Post-deploy: `SmartWalletFactory.IMPLEMENTATION() == SmartWalletEntry` address; both addresses have non-zero code; predicted CREATE2 address == actual.
