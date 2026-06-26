## Overall Decision: APPROVED

## Review Summary
- target chain: EVM, Ethereum mainnet semantics, Cancun / EIP-1153, Solidity 0.8.29 / Foundry
- reviewed source paths: `src/interfaces/ITransferWithAuthorization.sol`, `src/TransferWithAuthorization.sol`, `src/SmartWallet.sol`, `src/FallbackHandler.sol`, relevant existing modules `OwnerManager`, `ValidationManager`, `ERC712`, `ExecutionManager`, `BaseAuthorization`, `NonceManager`
- reviewed unit/fuzz/invariant test paths: `test/TransferWithAuthorization.t.sol`, `test/TransferWithAuthorizationInvariant.t.sol`, relevant existing wallet tests in the scoped suite
- reviewed integration test paths: `test/integration/TransferWithAuthorizationIntegration.t.sol`
- context status and context sources reviewed: technical context present and reviewed (`.oli-work/context/technical/index.md`, Circle `contracts/v2/EIP3009.sol`); PRD supplement reviewed (`.oli-work/prd-supplements/eip-account-level-transfer-with-authorization.md`); no business context provided
- verification commands: raw `forge build` / raw `forge test -vvv` / raw `forge coverage --report summary` fail only on inherited private `test/Recovery.t.sol` dependency; `forge build src script`, `forge test --skip 'test/Recovery.t.sol' -vvv`, scoped coverage, ABI checker, size, storage-layout, git status, and secret scan were run
- highest severity: MEDIUM (non-blocking bytecode margin and inherited private recovery-suite environment limitation)
- re-review: no

## Independent Implementation Baseline
- intended on-chain responsibilities: add the frozen account-level `ITransferWithAuthorization` surface to the SmartWallet account; verify direct EIP-712 owner authorizations; settle exactly one ERC-20 or native transfer from the account; consume/cancel random nonces; expose state/domain/ERC-165 observability; preserve existing execute/UserOp/relayer/UUPS behavior.
- intended off-chain responsibilities: construct typed data, collect ECDSA/passkey/external-validator signatures, submit relayer/payee transactions, configure hooks, index `Used`/`Canceled` events, and distinguish settled from canceled terminal nonces by events rather than the boolean getter alone.
- critical contracts/modules: `TransferWithAuthorization`, `ITransferWithAuthorization`, `SmartWallet`, `FallbackHandler`, `OwnerManager`, `ValidationManager`, `ERC712`, `ExecutionManager`, `IHook`, `BaseAuthorization`, `NonceManager`.
- critical external interfaces: `executeTransferWithAuthorization`, `receiveWithAuthorization`, `cancelTransferAuthorization`, `transferAuthorizationState`, `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`, `TransferAuthorizationUsed`, `TransferAuthorizationCanceled`, custom TWA errors plus reused `InvalidSignature`, `NonAdminSelfCall`, `NotFromSelf`, and `ReentrantSettle`.
- critical user flows: permissionless relayer settlement, payee-pulled receive settlement, owner-signed cancel, account-self cancel via execute, post-upgrade nonce durability, replay rejection, event reconciliation.
- critical fund/asset flows: account-funded ERC-20 transfer via `SafeERC20.safeTransfer`; account-funded native transfer via checked low-level call; no escrow, fee, refund, or whitelist; revert rolls back nonce and balances.
- critical permissions, roles, and signers: any caller may submit valid execute authorizations; only `to` may call receive; cancel form A requires any registered account key signature; cancel form B requires `msg.sender == address(this)`; hook and self-call policy is selected from the verified `keyHash`, not the relayer.
- expected state machine: `Unused -> Used` on successful execute/receive; `Unused -> Canceled` on successful cancel; `Used` and `Canceled` are terminal and both encode as `true` in `authorizationStates`.
- required events, errors, and observability: emit `TransferAuthorizationUsed` after successful settlement and `TransferAuthorizationCanceled` after cancellation; return collapsed terminal state through `transferAuthorizationState`; backend must reconcile terminal nonces with events.
- non-negotiable security invariants: one-time nonce terminality, nonce namespace isolation from 4337/native nonce, recipient/value/time/type/domain binding, CEI with rollback on revert, direct typed-data digest with no ERC-1271 wrapper, hook isomorphism including self-call parity, open time window, native reentrancy lock, no native burn, value conservation.
- required unit/fuzz/invariant test targets: constants/getters, all function success/failure paths, signature envelope and wrong signer/wrapped digest/cross-type tests, open-window edges, replay/cancel terminality, hook blocking and call-shape, self-target matrix with external-token self-recipient control, native reentrancy, fuzzed value/recipient binding, invariant nonce/accounting/nonce-isolation handler.
- required integration scenarios: real factory account deployment/init, cross-account replay rejection, settle/replay journey, owner self-call cancel, nonce isolation, independent nonces, UUPS durability, per-key hook isolation, permissionless execute/payee-gated receive, front-run neutrality, ERC-20/native/fee-on-transfer fund flows, failure/recovery, native recipient rollback, Used-vs-Canceled event disambiguation.
- context-derived constraints: Circle EIP-3009 confirms open `(validAfter, validBefore)` window, payee-gated receive, random nonce terminality, and cancel semantics; PRD/EIP supplement fixes typehashes, native sentinel, and interface id while PRD overrides token-level ERC-3009 where the account-level design intentionally differs.
- ambiguous points: none blocking. Implementation-only `ReentrantSettle` is documented in `CONTRACT_INTERFACE.md`; the ABI handoff file is intentionally the frozen interface ABI, while full account ABI is available from build artifacts.

## Context Alignment Check
| Context Source | Constraint / Signal | Implementation/Test Treatment | Result | Notes |
|----------------|---------------------|-------------------------------|--------|-------|
| `.oli-work/context/technical/index.md` | Context repo is Circle USDC at commit `59db8d...`, source of EIP-3009 transfer/receive/cancel semantics. | Review checked Circle `contracts/v2/EIP3009.sol`; implementation adopts open window and payee receive while adding account-level token/native support. | PASS | No conflict with approved docs. |
| Circle `contracts/v2/EIP3009.sol` | Nonce terminality, `now > validAfter`, `now < validBefore`, `to == msg.sender` receive, cancel authorization. | Code uses `block.timestamp <= validAfter` and `>= validBefore` reverts; receive requires `msg.sender == to`; cancel sets terminal bool. | PASS | Tests include equality edges, payee rejection, replay, and cancel. |
| PRD supplement `eip-account-level-transfer-with-authorization.md` | Frozen interface/typehash/native sentinel/interface id and account-level TWA behavior. | Constants, events, functions, native sentinel, and interface id match design and tests. | PASS | PRD remains authoritative where OKX account envelope differs from ERC-3009. |
| Business context | No files under `.oli-work/context/business`. | Review used approved requirements/design/security docs as source of business rules. | PASS | Recorded as no business context provided. |
| Existing-code baseline | `codebase_mode=existing_code_change`; existing build baseline had dependency failures from unavailable private/nested deps. | Delta preserves layout and existing modules; raw commands still fail only on private recovery test dependency, scoped TWA evidence passes. | PASS | Not treated as a Stage 4 blocker because production build and in-scope tests pass. |

## Implementation Alignment Check
| Area | Expected Behavior | Implementation Behavior | Result | Issue |
|------|-------------------|-------------------------|--------|-------|
| Frozen interface | Add exact TWA functions/events/errors without changing signatures. | `ITransferWithAuthorization.sol` defines the frozen surface; `SmartWallet.supportsInterface` adds `INTERFACE_ID`. | PASS | none |
| Signature envelope | `keyHash(32) || ownerSignature`; direct `hashTypedData(structHash)`; no execute-style 38-byte `validUntil` prefix and no `MessageSignLib` wrapper. | `_verifyTwaSignature` slices 32-byte keyHash, calls `getVerifiedValidator`, computes direct `hashTypedData`, then `_validateSignature` over suffix. | PASS | none |
| Nonce and window | Account-scoped random `bytes32` nonce, open interval, terminal used/canceled bool. | `_authorizeAndSettle` checks terminal bool, `<= validAfter`, `>= validBefore`, then marks true before settlement; cancel also marks true. | PASS | none |
| Settlement fund flow | Native via checked call, ERC-20 via SafeERC20, no escrow or fee, revert rolls back nonce. | `_settleWithHook` uses SafeERC20 for ERC-20 and checked low-level call with revert bubbling for native; CEI write reverts atomically on downstream revert. | PASS | none |
| Hook and self-call parity | Use verified keyHash to select hook and self-call admin allowance; do not let relayer determine policy. | `_settleWithHook` loads `_ownerSettings[keyHash]`, calls hook with byte-identical `Call`, applies self-call guard using verified key settings. | PASS | none |
| Receive flow | Only payee may call, with distinct receive typehash. | `receiveWithAuthorization` rejects non-payee before shared settlement with receive typehash. | PASS | none |
| Cancel flow | Signed form A or empty-signature self-call form B; no fund movement or hook. | `cancelTransferAuthorization` verifies signature when non-empty; empty signature requires `msg.sender == address(this)`; emits `Canceled`. | PASS | none |
| Upgrade/storage compatibility | No new initializer or upgrade role; new TWA nonce namespace separate from existing layout. | `TransferWithAuthorization` owns ERC-7201 slot `0xd0d1...2900`; `SmartWalletEntry` layout root remains `0x653f...cb00`; `_authorizeUpgrade onlySelf` unchanged. | PASS | none |
| Existing behavior preservation | Existing execute/UserOp/relayer/owner/validator behavior must remain intact. | Scoped full suite excluding unrelated recovery test passes 429/429; integration UUPS durability passes. | PASS | none |

## Backend Interface Handoff Check
| Area | Expected Interface Evidence | Actual Interface Evidence | Result | Issue |
|------|-----------------------------|---------------------------|--------|-------|
| Handoff status | `docs/delivery/CONTRACT_INTERFACE.md` non-empty with `IMPLEMENTATION_MATCHED`. | Document status is `IMPLEMENTATION_MATCHED` and describes target chain, source contracts, ABI file, build relationship, and additive ABI change. | PASS | none |
| ABI file | ABI under `docs/delivery/abi/` for backend-callable TWA surface. | `docs/delivery/abi/ITransferWithAuthorization.abi.json` contains 5 functions, 2 events, and frozen interface errors. ABI checker status `ok`. | PASS | none |
| Function/event/error docs | Names, signatures, selectors, caller rules, events, and retry/idempotency guidance match implementation. | Handoff documents execute/receive/cancel/getters, terminal-state semantics, `Used` vs `Canceled`, custom errors, and placeholder-only Java/web3j examples. | PASS | none |
| Event reconciliation | Backend must not treat `state == true` or `AuthorizationAlreadyUsed` as paid without `Used` event. | Handoff section 6.1 makes `Used` event required settlement proof and `Canceled` event not paid. Integration test verifies event-only disambiguation. | PASS | none |
| Secret hygiene | Handoff examples must use placeholders and no production secrets. | Secret scan found no production secrets; docs use placeholders. Matches from scan were constants and deterministic test fixture keys only. | PASS | none |

## Test Alignment Check
| Area | Expected Test Evidence | Actual Test Evidence | Result | Issue |
|------|------------------------|----------------------|--------|-------|
| Unit coverage of functions | Success, boundary, revert, events, state, access, signature, token/native paths. | `test/TransferWithAuthorization.t.sol` covers constants/getters, ERC-20/native/no-return token, passkey, replay, wrong signer, wrapped digest failure, short/38-byte envelopes, open-window edges, receive, cancel, hooks, self-target matrix, native reentrancy, and fuzzed binding. | PASS | none |
| Invariant tests | Nonce terminality, accounting conservation, native/4337 nonce isolation with realistic handler actions. | `TransferWithAuthorizationInvariant.t.sol` handler exercises execute/receive/cancel/replay over tracked nonces and asserts the required invariants. | PASS | none |
| Integration tests | Real system under test, realistic deployment/init, multi-actor workflows, fund flows, state continuity, failure/recovery, events. | `TransferWithAuthorizationIntegration.t.sol` deploys real factory/account and covers 19 end-to-end scenarios including UUPS durability and event disambiguation. | PASS | none |
| Coverage | Affected new/modified production surface must meet 100/100 or have concrete existing-code exemption. | Scoped coverage: `src/TransferWithAuthorization.sol` 100.0% line / 100.0% branch. Whole production gate: 98.8839% line / 98.8506% branch due legacy non-TWA files; accepted under existing-code delta policy and recorded in `TEST_REPORT.md`. | PASS | none |
| Report credibility | Stage 5/6 reports must match runnable local evidence. | Re-ran scoped test and coverage. Results support Stage 5/6 claims. Raw unscoped commands fail for the documented private recovery dependency only. | PASS | none |

## Mock and Harness Credibility
| Dependency / Harness | Purpose | Realistic Semantics Preserved | Result | Notes |
|----------------------|---------|------------------------------|--------|-------|
| `MockERC20` | Standard ERC-20 exact-value unit/integration flows. | Balances, minting, transfer return behavior, and insufficient-balance failure preserved. | PASS | Suitable for exact-value conservation. |
| false-return / no-return token fixtures | Exercise SafeERC20 edge cases. | False return reverts, no-return success path modeled. | PASS | Covers non-standard token return semantics. |
| passkey test helper | Validate 32-byte TWA envelope on built-in passkey validator. | Uses actual account validator path and rejects legacy 38-byte execute prefix. | PASS | Unit-level passkey coverage is sufficient for envelope correctness. |
| recording/blocking hooks | Prove key-selected hook call shape and rollback on hook failure. | Records `Call` target/value/data/executor and can revert in preCheck. | PASS | Demonstrates hook isomorphism without replacing SUT. |
| invariant handler | Adversarial state-machine driver for TWA API. | Generates valid signatures, repeated settle/cancel/replay attempts, and tracks token accounting. | PASS | Does not fake TWA behavior. |
| integration Base/factory harness | Real account deployment and initialization. | Uses real `SmartWalletFactory`, `SmartWalletEntry`, validators, EntryPoint, and UUPS upgrade path. | PASS | Only external peripherals are mocked. |
| fee-on-transfer integration token | Validate nominal-value design behavior. | Debits full `value`, credits `value - fee`, and records fee sink. | PASS | Confirms backend must use token events for actual received amount if needed. |
| rejecting native recipient | Failure/recovery for native callback. | Reverts ETH receipt and proves nonce/balance rollback. | PASS | Covers native external-call failure. |

## Evidence Verification
| Command / Check | Result | Notes |
|-----------------|--------|-------|
| Required input existence/non-empty check | PASS | All required process/delivery docs, ABI file, source, unit/fuzz/invariant tests, integration test, `TEST_REPORT.md`, and `INTEGRATION_TEST.md` exist. |
| Context load | PASS | Technical context and PRD supplement reviewed; no business context. |
| `forge build` | FAIL, accepted environment limitation | Fails resolving `smart-wallet-recovery/...` imports only from `test/Recovery.t.sol`, inherited private dependency issue outside TWA delta. |
| `forge build src script` | PASS | Production source and scripts compile successfully. |
| `forge build src script --sizes` | PASS with MEDIUM note | `SmartWalletEntry` runtime size 24,510 bytes, 66 bytes below EIP-170 hard limit. Requires no Stage 7 rework but should be rechecked before deployment. |
| `forge test -vvv` | FAIL, accepted environment limitation | Same `test/Recovery.t.sol` private recovery dependency import failure. |
| `forge test --skip 'test/Recovery.t.sol' -vvv` | PASS | 429 tests passed, 0 failed, 0 skipped across 26 suites. |
| `forge coverage --report summary` | FAIL, accepted environment limitation | Same private recovery dependency import failure. |
| `forge coverage --skip 'test/Recovery.t.sol' --report summary` | PASS | 429 tests passed; generated `.oli-work/forge-coverage-summary.txt`. |
| TWA coverage gate | PASS | `coverage_gate.py --include-path-regex '^src/transferwithauthorization\.sol$'`: 100.0% line and branch, status `ok`. |
| Whole production coverage gate | FAIL, accepted existing-code limitation | `--exclude-path-regex '(^|/)(script|test|lib)/'`: 98.8839% line / 98.8506% branch. Legacy non-TWA gaps are documented in `TEST_REPORT.md`; affected TWA contract is 100/100. |
| ABI/interface checker | PASS | `check_contract_interface.py --fail-on-missing`: status `ok`, one ABI checked. |
| `forge inspect SmartWalletEntry storageLayout` | PASS with tooling limitation | Existing layout root fields listed; TWA assembly ERC-7201 mapping is not shown by compiler layout, but its explicit slot differs from the existing layout root. |
| Secret/delivery hygiene scan | PASS | Matches were fixed constants, storage slots, `.gitignore` patterns, and deterministic test fixture keys; no production key, RPC credential, bearer token, or API secret found. |
| `git status --short` from repo root | PASS with notes | Expected implementation/test/docs changes and submodule drift are visible; no contradictory generated ABI/report issue found. |

## Shared Wrong-Assumption Review
| Area | Expected Behavior | Implementation Assumption | Test Assumption | Result | Root Cause |
|------|-------------------|---------------------------|-----------------|--------|------------|
| Signature envelope | 32-byte `keyHash` prefix, no execute-style 38-byte `validUntil`, direct typed-data digest. | Code enforces 32-byte min and direct digest. | Tests prove passkey 32-byte success, 38-byte prefix failure, wrapped digest failure, wrong signer failure. | PASS | n/a |
| Hook key binding | Verified signing keyHash selects hook and self-call guard; relayer is not policy authority. | Code derives settings from returned keyHash. | Unit/integration recording hook checks call shape and per-key hook isolation. | PASS | n/a |
| Used vs Canceled | Boolean terminal state cannot prove payment; events disambiguate. | Code stores one bool and emits distinct events. | Integration verifies both terminal states and event-only disambiguation. | PASS | n/a |
| Self-call scope | Non-admin must be blocked only when built `Call.target == account`; external-token transfer to account as recipient remains allowed. | Code checks `calls[0].target == address(this)` after building native/erc20 call target. | Tests cover non-admin native self-target, non-admin token==account, admin native self-send, and external-token to account control. | PASS | n/a |
| Coverage scoping | Existing-code delta may scope 100/100 gate to affected production file, not legacy untouched files. | Implementation does not rely on untested legacy deltas. | Stage 5 coverage gate and Stage 7 rerun prove 100/100 on `TransferWithAuthorization.sol`; whole-production legacy gaps are disclosed. | PASS | n/a |

## Design Invariant Scope Fidelity
| Invariant (DESIGN.md) | Stated Scope | Code Enforcement | Over-restricted Paths | Result | Notes |
|-----------------------|--------------|------------------|-----------------------|--------|-------|
| INV-NONCE-ONCE | Each authorization nonce can become Used or Canceled at most once; both terminal. | `authorizationStates[nonce]` checked before settle/cancel and set true on success. | none | PASS | Invariant tests cover repeated settle/cancel/replay. |
| INV-NONCE-ISOLATION | TWA nonce namespace isolated from native/4337 `NonceManager`. | Separate ERC-7201 slot and no calls to `validateAndUpdateNonce`. | none | PASS | Integration verifies 4337 nonce unchanged by TWA. |
| INV-RECIPIENT-BOUND | Signed digest binds token/from/to/value/window/nonce. | Struct hash includes token, `address(this)`, to, value, validAfter, validBefore, nonce. | none | PASS | Fuzz mutates recipient/value and fails signatures. |
| INV-CEI | Nonce write precedes transfer, but reverts roll back write. | `_authorizeAndSettle` sets flag before `_settleWithHook`; transfer/hook failure reverts whole call. | none | PASS | Tests prove hook/token/native failures leave nonce unused. |
| INV-HOOK-ISOMORPHISM | TWA invokes verified-key hook with byte-identical single `Call` and same self-call rule as `_batchCall`; two documented non-divergences: relayer executor and SafeERC20 ERC-20 execution. | `_settleWithHook` builds native/erc20 `Call`, selects hook/settings by keyHash, passes `msg.sender` executor, applies self-call guard from verified key settings, and uses SafeERC20 for actual ERC-20 transfer. | none | PASS | External-token `to == account` remains allowed because `Call.target` is token, not account. |
| INV-TIME-WINDOW | Open interval only: valid strictly after `validAfter` and strictly before `validBefore`. | Reverts on `block.timestamp <= validAfter` and `>= validBefore`. | none | PASS | Unit tests cover equality edges. |
| INV-TYPESEP | Execute, receive, and cancel signatures are not cross-replayable. | Distinct public typehash constants used for each struct hash. | none | PASS | Cross-type replay tests pass. |
| INV-NO-NATIVE-BURN | Settlement recipient cannot be zero or native sentinel. | `_requireValidRecipient` rejects `address(0)` and `NATIVE_ASSET`. | none | PASS | Does not reject legitimate account recipient for external token. |
| INV-VALUE-CONSERVATION | Successful standard-token/native settlement moves exactly value; failure reverts balances; fee-on-transfer is nominal-value by design. | SafeERC20/native call plus transaction atomicity; no internal balance accounting beyond nonce. | none | PASS | Unit/fuzz/integration cover exact paths and fee-on-transfer nominal semantics. |

## Dimension Results
| Dimension | Result | Notes |
|-----------|--------|-------|
| Requirements/design understanding | PASS | Baseline reconstructed from approved docs and context; no blocking ambiguity. |
| Implementation alignment | PASS | Source implements frozen interface, signature, nonce, hook, self-call, fund-flow, and storage requirements. |
| Security-spec implementation | PASS | Direct digest, nonce terminality, hook parity, receive gate, CEI, native reentrancy lock, and event observability are implemented. |
| Backend interface handoff | PASS | Handoff is `IMPLEMENTATION_MATCHED`; ABI checker passes; event reconciliation and placeholders are documented. |
| Code quality and maintainability | PASS | Delta is focused and follows existing account patterns; no unrelated source rewrite identified in TWA scope. |
| Solidity best-practice compliance | PASS | SafeERC20, explicit custom errors, CEI, transient guard, ERC-7201 namespace, and existing access-control patterns used. |
| Unit/fuzz/invariant test quality | PASS | Tests prove behavior rather than mirroring code and include negative, fuzz, passkey, and invariant coverage. |
| Integration test quality | PASS | Real account/factory/UUPS deployment path with honest external fixtures and multi-step workflows. |
| Mock/harness credibility | PASS | Mocks preserve relevant balances, failures, hook semantics, and do not replace the SUT. |
| Evidence credibility | PASS | Local reruns support Stage 5/6 claims under documented recovery-suite limitation. |
| Shared wrong-assumption risk | PASS | No implementation/test pair was found to share a wrong assumption against approved docs/context. |
| Design invariant scope fidelity | PASS | Scope-qualified invariants, especially self-call parity and external-token self-recipient control, are enforced exactly. |

## Blocking Issues
- none.

## Non-blocking Notes
- [MEDIUM] `SmartWalletEntry` runtime bytecode is 24,510 bytes, only 66 bytes below the EIP-170 hard limit. This does not block audit because it is deployable and source is stable, but Stage 9 must re-run size checks before deployment and avoid source growth without a size mitigation.
- [MEDIUM] Raw `forge build`, raw `forge test -vvv`, and raw `forge coverage --report summary` fail on inherited private `test/Recovery.t.sol` imports from `lib/smart-wallet-recovery`. This suite is outside the TWA delta and has been consistently disclosed; production build and scoped 429-test suite pass.
- [LOW] Whole production-source coverage is 98.8839% line / 98.8506% branch because of legacy non-TWA files. The affected `src/TransferWithAuthorization.sol` contract is 100.0% line / 100.0% branch and the existing-code exemption is concrete in `TEST_REPORT.md`.
- [LOW] Git status shows submodule gitlink drift and tracked implementation/test/docs changes expected from the flow. Reconcile dependency gitlinks before deployment packaging.

## Previous Rework Response Review
- item: DR-001 Used vs Canceled reconciliation
- target stage response: Stage 2/3 documents require backend event reconciliation; Stage 4 handoff documents it; Stage 6 integration tests verify it.
- reviewer assessment: PASS.

- item: DR-002 validator-specific signature envelope
- target stage response: Design/interface specify 32-byte `keyHash || ownerSignature`; implementation and tests enforce 32-byte TWA envelope and reject execute-style 38-byte prefix.
- reviewer assessment: PASS.

- item: DR-003 self-target hook isomorphism
- target stage response: Design/security specify self-call guard keyed by verified keyHash; implementation mirrors `_batchCall`; tests cover self-target matrix and legitimate external-token self-recipient control.
- reviewer assessment: PASS.

- item: user-driven rerun
- target stage response: `REWORK_HISTORY.md` says no user-driven rework.
- reviewer assessment: N/A.
