# OKX Smart Wallet — Account-Level Transfer With Authorization (TWA)

Chinese documentation: [docs/cn/README.md](docs/cn/README.md)

---

## Overview

This repository contains the OKX Smart Wallet smart-contract codebase. The delivery in this branch (`feature/aa-auth-4.0`) adds **Account-Level Transfer With Authorization (TWA)** — an owner-signed, permissionless ERC-20 and native-ETH settlement interface for the OKX Smart Wallet account, based on EIP-712 signed typed data.

Key capabilities delivered by this change:
- `executeTransferWithAuthorization` — permissionless (relayer/facilitator) settlement of a signed transfer within a time window.
- `receiveWithAuthorization` — payee-gated settlement (prevents front-run for contract payees).
- `cancelTransferAuthorization` — owner-signed or account-self-call revocation of an unused authorization.
- `transferAuthorizationState` and domain-separator getter for read-only queries.
- ERC-165 discovery (`INTERFACE_ID = 0x86c5a9e1`).

PRD: [账户级离线签名授权转账 (TWA)](https://okg-block.sg.larksuite.com/docx/SfcUdiiF3oC7Cax0Xh1lnFu2gIf)  
Codebase mode: `existing_code_change` (additive delta on the existing OKX Smart Wallet)  
Target chain: EVM — Ethereum mainnet (chain ID 1, Cancun/EIP-1153 required)

---

## Contract Architecture

Source: [`docs/process/DESIGN.md`](docs/process/DESIGN.md)

The TWA feature is implemented as a mixin added to the deployable `SmartWalletEntry` account:

| Contract / File | Role |
|---|---|
| `src/interfaces/ITransferWithAuthorization.sol` | Frozen ABI surface — the interface all backends integrate against |
| `src/TransferWithAuthorization.sol` | TWA mixin — state, EIP-712 logic, settlement, cancellation, ERC-165 |
| `src/SmartWallet.sol` | Core account — existing; modified to inherit TWA mixin |
| `src/FallbackHandler.sol` | Fallback logic — existing; unchanged |
| `script/deploy.s.sol` | Deployment script — `DeployInit` for `SmartWalletEntry` + `SmartWalletFactory` |
| `script/VerifyDeployment.s.sol` | Post-deployment on-chain verification script |

The signature envelope accepted by all TWA functions is `keyHash (32 bytes) || ownerSignature`. The account recovers `keyHash = signature[:32]`, routes through the registered validator, and verifies over the **direct** EIP-712 typed-data digest. This is a 32-byte prefix — **not** the 38-byte `keyHash||validUntil` prefix used by the existing relayer/UserOp paths. ERC-1271/personal-sign-wrapped digests are explicitly rejected.

Core security invariants:
- **INV-NONCE-ONCE**: each `authorizationNonce` is terminal (Used or Canceled); double-spend is impossible.
- **INV-CEI**: nonce flag is set before the transfer; any revert rolls it back.
- **INV-HOOK-ISOMORPHISM**: TWA invokes the same keyHash-selected hook with the same self-call guard as `execute`; restricted keys cannot bypass per-key policy via TWA.
- **INV-RECIPIENT-BOUND**: `to` and `value` are cryptographically bound in the signature.
- Native settlement is protected by a transient reentrancy lock (EIP-1153).

Dependencies (Foundry submodules — do not commit `lib/` file content; restore from `.gitmodules`/`foundry.lock`):
- `lib/account-abstraction` — ERC-4337 v0.7 interfaces
- `lib/forge-std` — Foundry test library
- `lib/openzeppelin-contracts` — SafeERC20, ERC165
- `lib/openzeppelin-contracts-upgradeable` — UUPS upgrade base
- `lib/solady` — gas-optimized utilities

---

## Security Model

Source: [`docs/process/SECURITY_SPEC.md`](docs/process/SECURITY_SPEC.md), [`docs/process/AUDIT_REPORT.md`](docs/process/AUDIT_REPORT.md)

**Audit Verdict: WARN / PASS** (no Critical findings; 5 Medium non-blocking advisories)

| Severity | Confirmed | Disposition |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 0 | 3 false positives rejected |
| MEDIUM | 5 | Non-blocking advisories; review before mainnet deployment |
| LOW | 0 | 1 false positive rejected |

Medium findings summary (see `AUDIT_REPORT.md` for full details):
1. ERC-4337 validation-data packing is non-canonical.
2. Expiring owner keys use `block.timestamp` during UserOp validation.
3. Malformed built-in validator payloads can revert rather than cleanly fail.
4. Last-admin lifecycle can brick future self-call administration.
5. Default `forge build` fails on inherited private recovery-suite dependency (build `src script` passes).

The TWA core fund-flow, signature scheme, nonce isolation, reentrancy protection, and hook-isomorphism design all held up under adversarial verification.

---

## Backend Contract Interface

Source: [`docs/delivery/CONTRACT_INTERFACE.md`](docs/delivery/CONTRACT_INTERFACE.md)  
ABI: [`docs/delivery/abi/ITransferWithAuthorization.abi.json`](docs/delivery/abi/ITransferWithAuthorization.abi.json)

Interface status: **IMPLEMENTATION_MATCHED**

Backend-callable flows:
- `executeTransferWithAuthorization(address token, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce, bytes signature)` — selector `0x0e720282`; permissionless settlement.
- `receiveWithAuthorization(address token, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce, bytes signature)` — payee-gated (`msg.sender == to`).
- `cancelTransferAuthorization(bytes32 authorizationNonce, bytes signature)` — signed or self-call revocation.
- `transferAuthorizationState(bytes32 nonce)` → `bool` and `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` — read-only.
- `supportsInterface(0x86c5a9e1)` → `bool` (ERC-165 discovery).

Events emitted:
- `TransferAuthorizationUsed(address indexed token, address indexed from, address indexed to, uint256 value, bytes32 authorizationNonce)` — on successful settlement.
- `TransferAuthorizationCanceled(address indexed account, bytes32 authorizationNonce)` — on cancellation.

**Critical integration note:** the `signature` argument is always `keyHash (32 bytes) || ownerSignature`. Never wrap the digest with ERC-1271 or personal-sign — the account explicitly rejects wrapped digests.

Contract addresses (testnet and mainnet) are operator-provided after deployment. See `docs/delivery/CONTRACT_INTERFACE.md §3` for the address table.

---

## Repository Layout

```
src/
  TransferWithAuthorization.sol        # TWA mixin (new)
  interfaces/
    ITransferWithAuthorization.sol     # frozen ABI (new)
  SmartWallet.sol                      # core account (modified)
  FallbackHandler.sol                  # fallback handler (existing)
test/
  TransferWithAuthorization.t.sol      # unit + fuzz tests (new)
  TransferWithAuthorizationInvariant.t.sol  # invariant tests (new)
  Base.t.sol                           # shared test base (modified)
  integration/                         # integration test suite
script/
  deploy.s.sol                         # deployment script (modified)
  VerifyDeployment.s.sol               # verification script (new)
docs/
  process/                             # requirements, design, test, audit evidence
  delivery/                            # deployment runbook, interface handoff, ABI
  cn/                                  # Chinese documentation mirrors
```

---

## Foundry Dependencies

Foundry submodule dependencies are declared in `.gitmodules` and pinned in `foundry.lock`. The `lib/` directory contains submodule gitlinks (not file content) tracked by git.

To restore:
```bash
git submodule update --init --recursive
```

Do not commit `lib/` file content. The private `lib/smart-wallet-recovery` submodule requires internal GitLab access and is excluded from the scoped build. Use `forge build src script` or `--skip 'test/Recovery.t.sol'` for CI without internal access.

Build command:
```bash
forge build src script
# or full build (requires internal access to smart-wallet-recovery):
forge build
```

---

## Verification Summary

Source: [`docs/process/TEST_REPORT.md`](docs/process/TEST_REPORT.md), [`docs/process/INTEGRATION_TEST.md`](docs/process/INTEGRATION_TEST.md), [`docs/process/DEV_REVIEW.md`](docs/process/DEV_REVIEW.md), [`docs/process/AUDIT_REPORT.md`](docs/process/AUDIT_REPORT.md), [`docs/delivery/DEPLOY_DRY_RUN.md`](docs/delivery/DEPLOY_DRY_RUN.md)

| Gate | Result | Evidence |
|---|---|---|
| Unit tests | PASS | 407 tests, all pass (with `--skip 'test/Recovery.t.sol'`) |
| Fuzz tests | PASS | 14 fuzz targets, all pass |
| Invariant tests | PASS | 3 invariants (NONCE-ONCE, TOKEN-ACCOUNTING, RECEIVE-BY-PAYEE) |
| TWA coverage (`TransferWithAuthorization.sol`) | PASS | 100% lines / 100% branches |
| Integration tests | PASS | Happy path, replay, cancel, reentrancy, ERC-165, hook-isomorphism |
| Implementation review | PASS | No blocking implementation defect |
| Security audit | WARN/PASS | 0 Critical, 5 Medium advisories (non-blocking) |
| Fork dry-run | DEFERRED | No fork RPC configured in this run; operator must run before mainnet deployment |

---

## Deployment and Operations

Sources: [`docs/delivery/DEPLOY_RUNBOOK.md`](docs/delivery/DEPLOY_RUNBOOK.md), [`docs/delivery/EMERGENCY_PLAN.md`](docs/delivery/EMERGENCY_PLAN.md), [`docs/delivery/DEPLOY_CHECK.md`](docs/delivery/DEPLOY_CHECK.md), [`docs/delivery/DEPLOY_DRY_RUN.md`](docs/delivery/DEPLOY_DRY_RUN.md)

**All deployment, live explorer verification, and production key handling are manual operator actions.** This pipeline does not deploy to any live network, broadcast transactions, or access production keys.

Operator pre-deployment checklist:
1. Run the fork dry-run plan in `docs/delivery/DEPLOY_DRY_RUN.md` against a Cancun mainnet fork.
2. Complete all items in `docs/delivery/DEPLOY_CHECK.md`.
3. Follow `docs/delivery/DEPLOY_RUNBOOK.md` for the deployment sequence and post-deployment verification.
4. Keep `docs/delivery/EMERGENCY_PLAN.md` accessible during deployment.

Key deployment notes:
- Target chain: Ethereum mainnet, Cancun (EIP-1153 required). Do not deploy to a non-Cancun fork.
- Deployment uses `script/deploy.s.sol` (`DeployInit`) via `forge script`.
- Post-deployment verification uses `script/VerifyDeployment.s.sol`.
- Deployer key is operator-provided; never stored in this repository.

---

## Process Evidence

| Document | Path |
|---|---|
| PRD archive | [`docs/process/REQUIREMENTS.md`](docs/process/REQUIREMENTS.md) |
| Requirements analysis | [`docs/process/REQUIREMENTS_ANALYSIS.md`](docs/process/REQUIREMENTS_ANALYSIS.md) |
| Technical design | [`docs/process/DESIGN.md`](docs/process/DESIGN.md) |
| Interface specification | [`docs/process/INTERFACE_SPEC.md`](docs/process/INTERFACE_SPEC.md) |
| Security specification | [`docs/process/SECURITY_SPEC.md`](docs/process/SECURITY_SPEC.md) |
| Design review | [`docs/process/DESIGN_REVIEW.md`](docs/process/DESIGN_REVIEW.md) |
| Unit/fuzz/invariant test report | [`docs/process/TEST_REPORT.md`](docs/process/TEST_REPORT.md) |
| Integration test report | [`docs/process/INTEGRATION_TEST.md`](docs/process/INTEGRATION_TEST.md) |
| Implementation and test review | [`docs/process/DEV_REVIEW.md`](docs/process/DEV_REVIEW.md) |
| Audit report | [`docs/process/AUDIT_REPORT.md`](docs/process/AUDIT_REPORT.md) |
| Existing codebase baseline | [`docs/process/EXISTING_CODEBASE_BASELINE.md`](docs/process/EXISTING_CODEBASE_BASELINE.md) |
| Oli Run Config | [`docs/process/OLI_RUN_CONFIG.md`](docs/process/OLI_RUN_CONFIG.md) |
| Source manifest | [`docs/process/SOURCE_MANIFEST.md`](docs/process/SOURCE_MANIFEST.md) |
| Rework history | [`docs/process/REWORK_HISTORY.md`](docs/process/REWORK_HISTORY.md) |

---

## Known Limitations

1. **Private submodule**: `lib/smart-wallet-recovery` is a private internal submodule. Full `forge build` and tests including `test/Recovery.t.sol` require internal GitLab access. Use `forge build src script` or `--skip 'test/Recovery.t.sol'` for CI without internal access.
2. **Fork dry-run deferred**: no fork RPC was configured for this pipeline run. The operator must run the dry-run plan in `docs/delivery/DEPLOY_DRY_RUN.md` before any mainnet deployment.
3. **5 Medium audit findings**: non-blocking for delivery but should be reviewed before mainnet. See `docs/process/AUDIT_REPORT.md` for details.
4. **Contract addresses TBD**: `SmartWalletEntry` addresses for testnet and mainnet are operator-provided at deployment time. See `docs/delivery/CONTRACT_INTERFACE.md §3`.
5. **ERC-4337 validation-data packing non-canonical**: medium audit finding; operational limitation for ERC-4337 UserOps with expiring keys.
