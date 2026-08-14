# Smart Contract Audit Report

> **Verdict:** WARN
> **Pipeline-stage Conclusion:** PASS
> **Project:** okx-smart-wallet-dev
> **Repository:** https://gitlab.okg.com/web3-wallet/smart-wallet-infra/okx-smart-wallet-dev.git
> **Ref:** feature/aa-auth-4.0 (eeeba95ed2f0ece53133d981aaba943aa3e5ef53)
> **Analyzed:** 2026-06-25T16:15:53Z
> **Pipeline:** oli-contract-audit
> **Mode:** pipeline-stage
> **FAIL_ON:** critical
> **Compile:** default `forge build` failed on inherited recovery-suite test imports; `forge build src script` passed
> **Static analyzers:** slither, aderyn

---

## Verdict

**WARN** — no verified Critical findings were found, so the Stage 8 machine gate projects this audit to **PASS** under `FAIL_ON=critical`. Five Medium findings remain as non-blocking advisories and should be reviewed before deployment validation.

High-severity candidates from the finder/static passes were adversarially verified and either reduced or rejected. No finding demonstrates direct unauthorized fund loss, signature replay, TWA hook bypass, storage collision, or native-settlement reentrancy.

## Executive Summary

This audit reviewed the account-level Transfer With Authorization (TWA) delta for the OKX SmartWallet account and the in-scope existing code it depends on. The feature adds EIP-712 signed account-level ERC-20/native settlement, nonce terminality, payee-gated receive settlement, cancellation, ERC-165 discovery, and backend ABI/event handoff.

The core TWA fund-flow and authorization design held up under audit: signatures use the direct typed-data digest, random TWA nonces are isolated from the ERC-4337/native nonce, settlement writes the TWA nonce before external transfer, native settlement is protected by a transient reentrancy lock, ERC-20 settlement uses SafeERC20, and the verified keyHash selects the hook used for policy checks.

The confirmed issues are operational and account-lifecycle concerns: ERC-4337 validation-data packing is non-canonical, expiring owner keys use `block.timestamp` during UserOp validation, malformed built-in validator payloads can revert rather than cleanly fail, last-admin lifecycle can brick future self-call administration, and the unscoped default Foundry build still fails on an inherited private recovery-suite dependency.

## Statistics

| Severity | Deduped Candidates | Confirmed | Needs PoC | False Positive |
|----------|-------------------|-----------|-----------|----------------|
| CRITICAL | 1 | 0 | 0 | 0 |
| HIGH | 3 | 0 | 0 | 3 |
| MEDIUM | 6 | 5 | 0 | 2 |
| LOW | 1 | 0 | 0 | 1 |
| INFO | 0 | 0 | 0 | 0 |
| **Total** | **11** | **5** | **0** | **6** |

Raw candidates before deduplication: 14. Deduplicated candidates entering verification: 11. Confirmed findings: 5. Rejected false positives: 6.

## Coverage

**Static pre-pass:** compile=partial (`forge build` fail; `forge build src script` pass) · analyzers=slither, aderyn

**Subagents:** 11 finders + 11 verifiers, run with `PARALLEL_CAP=4`

| Pattern Pack | Raw Candidates | Confirmed | Multi-pack | Status |
|---|---:|---:|---:|---|
| static | 4 | 1 | 0 | ok |
| protocol-account-abstraction | 5 | 3 | 2 | ok |
| universal-access-control | 1 | 1 | 1 | ok |
| universal-arithmetic | 2 | 1 | 1 | ok |
| universal-state-invariants | 2 | 1 | 2 | ok |
| capability-oracle-pricing | 0 | 0 | 0 | ok |
| capability-signatures | 0 | 0 | 0 | ok |
| capability-upgradeability | 0 | 0 | 0 | ok |
| protocol-economics | 0 | 0 | 0 | ok |
| universal-baseline | 0 | 0 | 0 | ok |
| universal-dos-griefing | 0 | 0 | 0 | ok |
| universal-interactions | 0 | 0 | 0 | ok |
| **After Verification** | **11 deduped** | **5** | **3** | - |

## ID Mapping

| Aggregate ID | Severity | Source IDs | Multi-pack | Verified | Title |
|---|---|---|---|---|---|
| M-01 | MEDIUM | AA-001, ARITH-001 | yes (2) | CONFIRMED | Signature-failure validation data is shifted into the wrong ERC-4337 field |
| M-02 | MEDIUM | BASE-001 | no | CONFIRMED | Default Foundry build fails on inherited recovery-suite imports |
| M-03 | MEDIUM | ACCESS-001, STATE-002 | yes (2) | CONFIRMED | Admin lifecycle can remove or downgrade the last active admin |
| M-04 | MEDIUM | AA-003 | no | CONFIRMED | Expiring owners use `block.timestamp` inside ERC-4337 validation |
| M-05 | MEDIUM | AA-005 | no | CONFIRMED | Built-in validators can revert or perform unbounded proof work during validation |

## Scope

**Contracts analyzed:** `src/AllowanceManager.sol`, `src/BaseAuthorization.sol`, `src/ERC4337Account.sol`, `src/ERC712.sol`, `src/ERC7201.sol`, `src/ExecutionManager.sol`, `src/FallbackHandler.sol`, `src/NonceManager.sol`, `src/OwnerManager.sol`, `src/SmartWallet.sol`, `src/SmartWalletEntry.sol`, `src/SmartWalletFactory.sol`, `src/TransferWithAuthorization.sol`, `src/Types.sol`, `src/ValidationManager.sol`, interfaces under `src/interfaces/`, and libraries under `src/libraries/`.

**Out of scope:** test contracts, deployment scripts except for build viability, dependencies under `lib/`, generated artifacts under `out/`, and reference context under `.oli-work/context/technical/repo/`. The Circle USDC EIP-3009 context was used only as semantic reference for open time windows, receive payee gating, nonce terminality, and cancel semantics.

## Confirmed Issues

## [MEDIUM] M-01 - Signature-failure validation data is shifted into the wrong ERC-4337 field

- **Aggregate ID:** M-01
- **Source IDs:** AA-001, ARITH-001
- **Source:** protocol-account-abstraction + universal-arithmetic
- **Domain:** arithmetic
- **Verified:** CONFIRMED - the verifier checked the bundled account-abstraction v0.7 semantics and confirmed that `1 << 96` decodes as a bogus non-zero aggregator/authorizer rather than canonical signature failure.
- **Multi-pack:** yes (2)
- **Locations:**
  - `src/libraries/Static.sol:17`
  - `src/SmartWallet.sol:260`
  - `src/SmartWallet.sol:270`
  - `src/SmartWallet.sol:285`
  - `src/SmartWallet.sol:304`

### Description
`Static.SIG_VALIDATION_FAILED` is defined as `1 << 96`, and `validateUserOp` returns this value for short signatures, unknown/expired key hashes, unsupported chainless calldata, and failed signatures. ERC-4337 validation data uses the low 160 bits as the aggregator/signature-failure field; canonical signature failure is `1`, not bit 96.

The verified path is reachable through EntryPoint validation for malformed or invalid UserOperations. `onlyEntryPoint` prevents direct calls but does not prevent a user operation from reaching the account through the EntryPoint or bundler simulation path.

### Impact
Invalid UserOperations can be misclassified as aggregator-based validation rather than ordinary signature failure. This can break ERC-4337/bundler compatibility and produce misleading simulation results, but no direct fund loss was shown because the affected UserOperation is invalid.

### Recommendation
Use the canonical ERC-4337 signature-failure value:

```solidity
uint256 public constant SIG_VALIDATION_FAILED = 1;
```

Keep valid-until packing in the upper fields and leave the low 160-bit authorizer field as `0`, `1`, or a real aggregator address.

## [MEDIUM] M-02 - Default Foundry build fails on inherited recovery-suite imports

- **Aggregate ID:** M-02
- **Source IDs:** BASE-001
- **Source:** static
- **Domain:** code-quality
- **Verified:** CONFIRMED - default `forge build` fails on the recovery-suite imports, while `forge build src script` passes; severity was reduced from Critical to Medium because production source/script compilation succeeds.
- **Multi-pack:** no
- **Locations:**
  - `test/Recovery.t.sol:5`
  - `test/Recovery.t.sol:6`
  - `test/Recovery.t.sol:7`
  - `test/Recovery.t.sol:8`
  - `test/Recovery.t.sol:9`

### Description
The deterministic static pre-pass command `forge build` failed because `test/Recovery.t.sol` imports `smart-wallet-recovery/...` files that are absent from the current dependency tree. The scoped production build `forge build src script` passed, and Stage 5/6/7 evidence consistently records the recovery suite as an inherited private dependency limitation outside the TWA delta.

### Impact
Deployment or CI procedures that rely on an unscoped default Foundry build can fail before producing artifacts. This is an operational delivery risk, not an in-scope production source compile failure.

### Recommendation
Restore the expected `smart-wallet-recovery` dependency revision before deployment packaging, or ensure deployment validation uses a documented production-source build command while keeping the recovery-suite limitation visible.

## [MEDIUM] M-03 - Admin lifecycle can remove or downgrade the last active admin

- **Aggregate ID:** M-03
- **Source IDs:** ACCESS-001, STATE-002
- **Source:** universal-access-control + universal-state-invariants
- **Domain:** access-control
- **Verified:** CONFIRMED - the verifier confirmed an active admin can self-call `updateOwner` or `removeOwner` and leave no practical registered active admin for factory-deployed proxy accounts.
- **Multi-pack:** yes (2)
- **Locations:**
  - `src/OwnerManager.sol:69`
  - `src/OwnerManager.sol:92`
  - `src/SmartWallet.sol:149`

### Description
`updateOwner` and `removeOwner` are protected by `onlySelf`, and `_batchCall` only permits self-calls for an admin key or the built-in self key. However, once an active admin reaches these functions through a valid self-call, the lifecycle mutation does not require another active registered admin to remain.

`updateOwner` can downgrade or expire the last admin, and `removeOwner` can delete it. The implicit `address(this)` key is treated as admin-like, but for ordinary factory-deployed proxy accounts it is not a practical recoverable signer.

### Impact
A mistaken or compromised admin operation can permanently block future self-call-only administration, including owner recovery, allowance approvals, UUPS upgrades, and empty-signature self-cancel flows. Remaining non-admin external-call capabilities may still exist, but privileged account administration can be bricked.

### Recommendation
Before removing, downgrading, or expiring an active admin, require another active registered admin to remain. Count only registered, non-expired admin keys unless the deployment explicitly has a recoverable self key.

## [MEDIUM] M-04 - Expiring owners use `block.timestamp` inside ERC-4337 validation

- **Aggregate ID:** M-04
- **Source IDs:** AA-003
- **Source:** protocol-account-abstraction
- **Domain:** dos-griefing
- **Verified:** CONFIRMED - the verifier confirmed that expiring owners execute a `TIMESTAMP`-dependent branch during `validateUserOp` rather than returning the owner expiration through validation data.
- **Multi-pack:** no
- **Locations:**
  - `src/SmartWallet.sol:269`
  - `src/OwnerManager.sol:173`
  - `src/OwnerManager.sol:197`

### Description
`validateUserOp` calls `getVerifiedValidator(pubKeyHash)`. For owners with non-zero expiration settings, `getVerifiedValidator` calls `isSettingsExpired`, which compares the expiration with `block.timestamp` before signature validation completes.

ERC-4337 validation should avoid direct timestamp/block-number dependencies in validation code and communicate time bounds through returned validation data. The current success path only returns the signature-supplied `validUntil`, not the owner setting expiration.

### Impact
UserOperations signed by configured expiring owners can be rejected by compliant bundlers or ERC-7562-style validation rules even while they would be valid on-chain. This is an account-liveness and integration-compatibility issue.

### Recommendation
Avoid `block.timestamp` branching inside the EntryPoint validation path. Pack the effective owner expiration into returned validation data, for example by returning the minimum of signature `validUntil` and owner expiration.

## [MEDIUM] M-05 - Built-in validators can revert or perform unbounded proof work during validation

- **Aggregate ID:** M-05
- **Source IDs:** AA-005
- **Source:** protocol-account-abstraction
- **Domain:** dos-griefing
- **Verified:** CONFIRMED - the verifier confirmed malformed built-in validator payloads can revert in ABI decoding, and valid large proof arrays create linear validation work without a local cap.
- **Multi-pack:** no
- **Locations:**
  - `src/ValidationManager.sol:29`
  - `src/libraries/ECDSAValidatorLib.sol:31`
  - `src/libraries/PasskeyValidatorLib.sol:48`
  - `src/libraries/MerkleProofProcessor.sol:20`

### Description
External validator contracts are wrapped in `try/catch`, but built-in ECDSA and passkey validators are called directly. A UserOperation signature controls the bytes passed as validator data after the 32-byte keyHash and 6-byte validUntil prefix. Malformed ECDSA tails can revert in `abi.decode(bytes32[])`, and malformed passkey payloads can revert while decoding `WebAuthnAuth` and proofs.

When decoding succeeds, proof arrays are processed linearly without an account-level maximum. Registered key hashes are externally enumerable, and the built-in self key also maps to the ECDSA validator.

### Impact
Attackers can submit UserOperations that make validation revert or consume excessive verification gas before failing. The impact is operational simulation/gas griefing bounded by `verificationGasLimit` and bundler policy; no direct fund loss was shown.

### Recommendation
Make built-in validator decoding fail closed without reverting, and cap proof array length to a small documented maximum. Add tests for malformed built-in validator payloads and overlong proof arrays.

## Needs PoC

No findings remained in `NEEDS-POC` after adversarial verification.

## False Positives

| ID | Title | Source Pack(s) | Refutation Reason |
|----|-------|----------------|-------------------|
| AA-004, STATE-001 | Hookless non-admin keys retain unbounded external asset authority | protocol-account-abstraction + universal-state-invariants | Reachable behavior, but not a bypass: approved docs explicitly define `hook == address(0)` as no hook and record hookless non-admin external spending as an accepted provisioning residual identical to existing execute behavior. |
| STATIC-001 | Native TWA settlement sends ETH to a user-controlled recipient | static | Refuted by CEI nonce write, full-span transient TWA lock, checked low-level call, hook wrapping, and self-call restrictions. Tests include native reentrancy coverage. |
| STATIC-002 | External delegate-and-revert simulator delegates to an arbitrary target | static | The function unconditionally reverts after delegatecall; EVM revert semantics discard storage writes, logs, transfers, creates, and nested effects from the frame. |
| STATIC-003 | Re-calling an already deployed factory salt with value may strand ETH | static | Solady's helper forwards non-zero value to the already-deployed instance or reverts; the wallet proxy has a payable receive path. |
| AA-002 | Invalid UserOps can force ETH into EntryPoint deposit before validation fails | protocol-account-abstraction | EntryPoint failure handling reverts the full transaction after failed validation data, rolling back deposit credit; direct calls are blocked by `onlyEntryPoint`. |
| ARITH-002 | Unchecked 64-bit nonce increment can wrap and reopen old nonces | universal-arithmetic | The wrap requires `2^64` successful same-key owner-authorized relayer executions; an attacker cannot set or independently advance the private nonce state, so no realistic security impact remains. |

## Recommendations

### Immediate Action Required

No Critical findings were confirmed, and no `rework_request.md` is emitted under `FAIL_ON=critical`.

### Medium Priority

1. Fix `Static.SIG_VALIDATION_FAILED` to the canonical ERC-4337 value `1` and add a validation-data packing regression test.
2. Add last-active-admin preservation checks to `updateOwner` and `removeOwner`, or document an explicit recoverable self-key deployment mode.
3. Remove direct `block.timestamp` use from the UserOp validation path for owner expiration and pack the effective expiration into validation data.
4. Make built-in validator malformed payloads return `false` instead of reverting, and cap Merkle proof length.
5. Restore the private recovery-suite dependency or make deployment validation explicitly use the production-source build scope.

### Low Priority / Best Practices

1. Keep the current TWA native reentrancy test and delegate-and-revert simulator documentation in the deployment handoff.
2. Stage 9 should re-run `forge build src script`, size checks, ABI checks, and a dependency hygiene check before deployment validation.

## Per-pack Report Index

| Pattern Pack | Report Path | Raw Candidates |
|---|---|---:|
| static | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/static.md` | 4 |
| capability-oracle-pricing | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/capability-oracle-pricing.md` | 0 |
| capability-signatures | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/capability-signatures.md` | 0 |
| capability-upgradeability | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/capability-upgradeability.md` | 0 |
| protocol-account-abstraction | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/protocol-account-abstraction.md` | 5 |
| protocol-economics | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/protocol-economics.md` | 0 |
| universal-access-control | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-access-control.md` | 1 |
| universal-arithmetic | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-arithmetic.md` | 2 |
| universal-baseline | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-baseline.md` | 0 |
| universal-dos-griefing | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-dos-griefing.md` | 0 |
| universal-interactions | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-interactions.md` | 0 |
| universal-state-invariants | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-state-invariants.md` | 2 |

## Backend Interface Handoff Safety

`docs/delivery/CONTRACT_INTERFACE.md` was reviewed as implementation-matched. The handoff correctly distinguishes terminal nonce state from settlement: `transferAuthorizationState(nonce) == true` and `AuthorizationAlreadyUsed` can mean either Used or Canceled, and the backend must use `TransferAuthorizationUsed` as settlement proof and `TransferAuthorizationCanceled` as revocation proof. The ABI handoff file `docs/delivery/abi/ITransferWithAuthorization.abi.json` is present and non-empty.

## Chain-specific Checklist

| Area | Result |
|---|---|
| EIP-712 domain/typehashes | PASS - direct `hashTypedData(structHash)`, distinct execute/receive/cancel typehashes, account/chain binding preserved. |
| Replay protection | PASS - TWA random nonce is account-scoped and terminal; Used/Canceled collapse is documented for backend event reconciliation. |
| Native reentrancy | PASS - transient lock spans checks, nonce write, hook calls, native call, and event emission. |
| ERC-20 integration | PASS - TWA uses SafeERC20 and handles no-return/false-return behavior in tests. |
| Upgrade/storage | PASS - UUPS authorization remains `onlySelf`; TWA ERC-7201 namespace is distinct from the account custom-storage root. |
| ERC-4337 validation | WARN - confirmed validation-data packing, owner-expiration timestamp, and built-in validator malformed/proof-work findings. |
| Build/dependencies | WARN - default unscoped `forge build` fails on inherited recovery-suite imports; production `src script` build passes. |

