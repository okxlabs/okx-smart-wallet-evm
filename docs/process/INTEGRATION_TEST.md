# INTEGRATION_TEST.md — Account-Level Transfer With Authorization (TWA)

Stage 6.0 end-to-end integration testing for the account-level `TransferWithAuthorization` (TWA)
settlement surface inlined into the `SmartWallet` ERC-4337 / UUPS account. The system under test is a
real `SmartWalletEntry` account deployed and initialized through the real `SmartWalletFactory`; TWA is
compiled inline into that account's bytecode. No contract source, production script, or `foundry.toml`
was modified.

## Conclusion: PASS

All planned integration scenarios execute and pass. Assertions verify real end-to-end behavior across
multiple transactions, multiple actors/keys, two independently deployed accounts, ERC-20/native/fee-on-transfer
fund flows, the authorization-nonce lifecycle, the 4337-nonce vs TWA-nonce isolation, a UUPS upgrade, and the
Used-vs-Canceled event reconciliation contract. No forbidden source change occurred. No blocking implementation,
unit-test-gap, or integration-test-design issue was found, so no `rework_request.md` is emitted.

## Environment
- chain: EVM — Ethereum mainnet semantics, Cancun / EIP-1153 (transient storage), `solc 0.8.29`, `evm_version=cancun`, `optimizer_runs=100`.
- local environment: Foundry `forge 1.7.1` in-process EVM (no fork, no broadcast, no testnet/mainnet, no real keys).
- source path: `src/`
- test path: `test/` (integration tests under `test/integration/`)
- script path: `script/`
- integration test command: `forge test --match-path 'test/integration/' -vvv` (plus full-suite regression run with `--skip 'test/Recovery.t.sol'`).
- deployed addresses: none external — every contract under test (account implementation, factory, EntryPoint, validators) is deployed locally in `setUp()`; `NATIVE_ASSET` is the `0xEeee…EEeE` sentinel constant.
- upstream input snapshot (no-source-change baseline): `../inputs/A-05/okx-smart-wallet-dev`.
- recovery-suite limitation: the private `lib/smart-wallet-recovery` submodule cannot be cloned by this worker. Only `test/Recovery.t.sol` imports it; `src/` does not. All Forge commands use `--skip 'test/Recovery.t.sol'`, inherited as a non-blocking limitation from Stage 1.0/5.0. It is outside the TWA delta.
- Stage 1.0 `baseline_build_status=failed` was a stale Stage-1 snapshot (libs not yet fetched then). In this Stage 6 workspace all required libs are present and `forge build` / the existing 41 TWA unit tests pass.

## Stage 5 Readiness
`docs/process/TEST_REPORT.md` Conclusion is **PASS** (unit/fuzz/invariant for `src/TransferWithAuthorization.sol`: 100% line/branch; no Stage 4 defect). Stage 6 proceeds.

## Integration Test Plan

All integration tests live in `test/integration/TransferWithAuthorizationIntegration.t.sol`, reusing the real
deployment harness from `test/Base.t.sol` (`SmartWalletFactory.createAccount` → ERC-1967 clone → `initialize`).
Tests are derived from approved docs (DESIGN §4/§10/§11/§14/§16, SECURITY_SPEC §2/§5/§8, INTERFACE_SPEC §5/§6.1/§8),
the real implementation, and the Stage 5 tests — not from assumed protocol semantics. They deliberately target
cross-step / cross-role / cross-account / cross-module / cross-transaction behavior that Stage 5 function-level
unit/fuzz/invariant tests do not exercise.

Conventions (per `foundry-integration-rules.md` time-control guidance): a stable base time is set with
`vm.warp(10_000)`; authorization windows use absolute literals (e.g. `validAfter=9_000`, `validBefore=11_000`);
warp targets are absolute, never chained off a possibly-cached `block.timestamp`. Signatures are the real
`keyHash(32) ‖ ownerSignature` envelope over the direct `hashTypedData(structHash)` digest (INTERFACE_SPEC §8),
signed per-account so cross-account binding is exercised honestly.

### User Journey Matrix
| Journey | Actors | Steps | Expected Final State | Test |
|---------|--------|-------|----------------------|------|
| Owner authorizes → relayer settles ERC-20 → later replay rejected | owner (signer), relayer, recipient | fund account; relayer settles in tx1; advance block; relayer replays in tx2 | recipient credited once; nonce terminal; replay reverts `AuthorizationAlreadyUsed`; account debited exactly once | `test_journey_erc20SettleThenReplayInLaterTxReverts` |
| Owner revokes an outstanding authorization, then settlement is rejected | owner (admin, via account self-call), relayer | owner calls `execute([self cancel form B])`; later relayer tries to settle the canceled nonce | nonce terminal (canceled); `TransferAuthorizationCanceled` emitted; settle reverts `AuthorizationAlreadyUsed`; no funds moved | `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts` |
| Payee pulls an owed payment atomically inside its own contract flow | owner (signer), contract payee | sign receive auth to a contract payee; payee calls `receiveWithAuthorization` from its own logic | payee contract credited; nonce terminal; non-payee submit rejected | `test_multiActor_executePermissionless_receivePayeeGatedContractPayee` |
| Transient failure recovered by retrying the same signed authorization | owner (signer), admin, relayer | settle blocked by policy/balance in tx1; owner fixes condition in tx2; relayer re-submits the same signature in tx3 | first attempt leaves nonce unused and balances unchanged; final attempt settles once | `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature`, `test_recovery_insufficientBalanceThenFundThenRetrySameSignature` |

### Multi-Actor Scenario Matrix
| Scenario | Actors / Roles | Expected Interaction | Negative Actor Case | Test |
|----------|----------------|----------------------|---------------------|------|
| Several owner keys on one account each authorize a settle; per-key hook isolation | admin ECDSA key (no hook), non-admin ECDSA key (with hook) | each key's settle selects that key's own hook; an admin-key settle invokes no hook; a hooked-key settle invokes its hook exactly once with the exact `Call` | n/a (isolation positive) | `test_multiActor_perKeyHookIsolationAcrossOwners` |
| `execute` permissionless vs `receive` payee-gated | arbitrary relayer, contract payee | any relayer settles an execute auth; only the payee settles a receive auth | non-payee relayer submit of a receive auth reverts `CallerNotPayee`; unregistered-key auth reverts `InvalidSignature` | `test_multiActor_executePermissionless_receivePayeeGatedContractPayee` |
| Competing relayers front-run the same signed authorization | relayer A, relayer B (front-runner), recipient | first submitter settles to the signature-bound recipient; the loser's submit reverts | front-run is outcome-neutral: funds go to the signed `to`/`value`; loser reverts `AuthorizationAlreadyUsed` (R-2, INV-RECIPIENT-BOUND) | `test_multiActor_frontRunIsOutcomeNeutral` |

### Deployment / Initialization Matrix
| Component | Init Parameters | Role Setup | Expected Init State | Re-init Failure Test |
|-----------|-----------------|------------|---------------------|----------------------|
| `SmartWalletEntry` account via `SmartWalletFactory.createAccount` (fresh, multi-owner) | `InitialOwner[]` = two keys (ECDSA), `salt` | both initial owners registered as **admin** (`packSettings(true,0,0)`); `WalletInitialized` | TWA surface live immediately: `supportsInterface(0x86c5a9e1)==true`, `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` == account EIP-712 domain separator; a happy-path ERC-20 settle succeeds on the freshly-initialized account | `test_deploy_reinitializeReverts` (`initialize` again reverts `InvalidInitialization`) |
| `test_deploy_freshMultiOwnerAccountTwaLiveAndSettles` covers init wiring + first settle | | | | |

### Cross-Contract Interaction Matrix
| Interaction | Components | Expected Call | Failure Mode | Test |
|-------------|------------|---------------|--------------|------|
| Authorization replay across two independently deployed accounts | account A, account B (both register the same owner key) | a settle authorized for account A must not settle on account B | account B recomputes `from=address(this)=B` and uses B's domain separator (`verifyingContract=B`), so A's signature reverts `InvalidSignature`; B balances unchanged; the auth still settles on A | `test_crossAccount_authorizationDoesNotReplayAcrossAccounts` |
| Account ↔ ERC-20 via `SafeERC20` with a fee-on-transfer token | account, fee-on-transfer ERC-20, recipient | settle moves nominal `value` through `safeTransfer`; the token applies its fee | account debited `value`; recipient credited `value − fee`; event logs **nominal** `value`; nonce consumed (DESIGN §11, SECURITY_SPEC §4 "settle nominal value, no internal accounting assumption") | `test_fundFlow_feeOnTransferTokenSettlesNominalValue` |
| Account ↔ contract native recipient | account, contract recipient | native settle forwards value via checked `to.call{value}` | a recipient whose `receive()` reverts bubbles the revert; account balance + nonce unchanged | `test_failure_nativeRecipientRevertRollsBackFully` |
| Account ↔ per-key spending hook contract | account, hook contract | settle invokes the verified key's `preCheck`/`postCheck` | a blocking hook reverts and rolls back the consumed nonce | `test_multiActor_perKeyHookIsolationAcrossOwners`, `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature` |
| Account ↔ UUPS new implementation | account, V2 implementation | owner self-authorized `upgradeToAndCall` via `executeWithRelayer` | TWA authorization-nonce state (ERC-7201 namespace) persists across the upgrade; replay still reverts | `test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade` |

### Fund-Flow Scenario Matrix
| Flow | Assets | Start Balances | End Balances | Accounting Check | Test |
|------|--------|----------------|--------------|------------------|------|
| Multiple sequential ERC-20 settlements drain the account | Mock ERC-20 | account funded, recipients 0 | account = start − Σvalue; recipients = Σvalue | Σ recipient credits == Σ account debits == total outflow; conservation | `test_fundFlow_sequentialErc20SettlementsConserveAndDrain` |
| Mixed native + ERC-20 settlements interleaved | ETH + Mock ERC-20 | account funded in both | each ledger debited by its own Σvalue | native and token ledgers conserve independently in one account lifecycle | `test_fundFlow_mixedNativeAndErc20Conserve` |
| Fee-on-transfer settlement | fee-on-transfer ERC-20 | account funded | account −value; recipient +(value−fee) | nominal-value settlement; event logs `value`; no internal accounting beyond nonce flag | `test_fundFlow_feeOnTransferTokenSettlesNominalValue` |
| Self-recipient external-token payment (control) | Mock ERC-20 | account funded | net-zero (account is recipient) | a normal ERC-20 payment whose `to`==account but `token`==external is **not** a self-call; settles net-zero | covered within `test_multiActor_perKeyHookIsolationAcrossOwners` control assertion |

### State Continuity Matrix
| Scenario | Step Sequence | Intermediate State Checks | Final State Check | Test |
|----------|---------------|---------------------------|-------------------|------|
| TWA authorization-nonce space isolated from the 4337/native nonce | relayer `executeWithRelayer` (consumes 4337 nonce 0→1); then TWA settle | after relayer execute: `getNonce(0)==1`; after TWA settle: `getNonce(0)` unchanged | `getNonce(0)` advanced only by 4337 path; TWA nonce terminal only via TWA path; neither writes the other's space (INV-NONCE-ISOLATION) | `test_stateContinuity_twaNonceIsolatedFrom4337Nonce` |
| Independent authorization nonces progress independently | settle n1; cancel n2 (form A); leave n3 | n1 used, n2 canceled, n3 unused | n1/n2 terminal (replay reverts); n3 still settles later | `test_stateContinuity_independentNoncesProgressIndependently` |
| Authorization-nonce durability across a UUPS upgrade | settle n; upgrade implementation; query/replay n | n terminal before upgrade | n still terminal after upgrade; replay reverts; new impl marker live | `test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade` |

### Failure / Recovery Matrix
| Failure Scenario | Trigger | Expected Revert/Error | Recovery / Next State | Test |
|------------------|---------|-----------------------|-----------------------|------|
| Per-key hook blocks the spend | hooked non-admin key settle | hook custom error; nonce unused; no funds moved | owner removes the hook via `execute`; same signature re-submitted settles | `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature` |
| Insufficient account balance | `value` > account balance | transfer revert; nonce unused; balances unchanged | owner funds the account; same signature re-submitted settles | `test_recovery_insufficientBalanceThenFundThenRetrySameSignature` |
| Expired authorization | `block.timestamp >= validBefore` | `AuthorizationExpired` | not recoverable as-is; a fresh authorization (new nonce + window) settles | `test_failure_expiredAuthorizationReissueWorks` |
| Native recipient rejects ETH | contract recipient `receive()` reverts | bubbled recipient revert | nonce unused; account balance unchanged; can target a different recipient | `test_failure_nativeRecipientRevertRollsBackFully` |

### Solidity Best-Practice Workflow Matrix
| Workflow | Best-Practice Rule | Invalid End-to-End Scenario | Expected No-Partial-Effect Check | Test |
|----------|--------------------|-----------------------------|----------------------------------|------|
| Reject-before-effect on settle failure | CEI; no state/balance mutation before a rejected workflow completes | hook block, insufficient balance, native recipient revert, expired window | after revert: account balance, recipient balance, TWA nonce state, and 4337 nonce all unchanged | `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature`, `test_recovery_insufficientBalanceThenFundThenRetrySameSignature`, `test_failure_nativeRecipientRevertRollsBackFully`, `test_failure_expiredAuthorizationReissueWorks` |
| Terminal-once nonce across a full lifecycle | a nonce settles or cancels at most once | replay after settle; settle after cancel | second terminal transition reverts `AuthorizationAlreadyUsed`; balances move at most once | `test_journey_erc20SettleThenReplayInLaterTxReverts`, `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts`, `test_stateContinuity_independentNoncesProgressIndependently` |

### Context-Derived Scenario Coverage
| Context Source | Flow / Constraint | Scenario / Check | Status | Notes |
|----------------|-------------------|------------------|--------|-------|
| `context.technical` = Circle USDC repo (EIP-3009 origin: `transferWithAuthorization`/`receiveWithAuthorization`/`cancelAuthorization`) | open-interval validity window | expired-then-reissue + window boundary in journey/recovery tests | Covered | OKX TWA intentionally moves EIP-3009 semantics to account level (random nonce, envelope, payee-pull); divergence is by approved design, not a conflict |
| `context.technical` (Circle USDC) | payee-gated receive (anti-front-run) | contract-payee receive + non-payee reject + front-run neutrality | Covered | matches approved FR-2 / R-2 |
| `context.technical` (Circle USDC) | cancel makes a nonce terminal | owner cancel-then-settle-rejected; Used-vs-Canceled reconciliation | Covered | OKG design adds DR-001 event-only distinction |
| `context.business` | — | — | Not provided | no business context files present; recorded per context-loading policy |
| PRD-linked supplement `eip-account-level-transfer-with-authorization.md` | account-level TWA EIP draft (typehashes/envelope/ERC-165 id) | typehash/domain/interface wiring exercised by deployment + every settle | Covered (via approved docs) | PRD/INTERFACE_SPEC §8 are authoritative for envelope shape |

### Event and Observability Matrix
| Flow | Expected Events | Indexed Fields | Test |
|------|-----------------|----------------|------|
| Successful settle | `TransferAuthorizationUsed(token, from, to, value, authorizationNonce)` | `token`, `from`, `to` indexed; `value`, `authorizationNonce` in data (nonce **not** topic-filterable) | `test_journey_erc20SettleThenReplayInLaterTxReverts`, `test_observability_usedVsCanceledDistinguishableOnlyByEvent` |
| Cancellation | `TransferAuthorizationCanceled(authorizer, authorizationNonce)` | `authorizer` (==account), `authorizationNonce` both indexed (nonce **is** topic-filterable) | `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts`, `test_observability_usedVsCanceledDistinguishableOnlyByEvent` |
| Used vs Canceled reconciliation (INTERFACE_SPEC §6.1, DR-001) | both terminal nonces have `transferAuthorizationState==true`; only the distinct events disambiguate | proves backend must reconcile by event, not by on-chain state | `test_observability_usedVsCanceledDistinguishableOnlyByEvent` |

### Mock / Fixture Justification
| Mock / Fixture | Real Dependency | Behaviors Modeled | Behaviors Omitted | Safety Rationale | Failure Modes Covered |
|----------------|-----------------|-------------------|-------------------|------------------|-----------------------|
| `MockERC20` (from `test/Base.t.sol`) | standard ERC-20 | balances, mint, return-true `transfer` | fee/rebase | exact-value conservation is the property under test; SUT (account) is real | insufficient balance via standard revert |
| `IntegrationFeeOnTransferERC20` | fee-on-transfer ERC-20 (e.g. deflationary token) | deducts `value` from sender, credits `value−fee` to recipient, routes `fee` to a sink, returns true | rebasing, blacklists | models the real divergence between debited and received amount so the "settle nominal value" design note is verified, not assumed | recipient-credited-less accounting documented |
| `IntegrationContractPayee` | a contract payee that pulls an owed payment | calls `receiveWithAuthorization` from its own logic so `msg.sender == to` | unrelated business logic | exercises the real payee-gated path; does not replace the SUT | non-payee submit rejected |
| `IntegrationRecordingHook` | per-key spending-policy hook | records `preCheck`/`postCheck` count and the exact `Call` (target/value/data) and executor | production policy storage/limits | proves per-key hook selection + isolation through the real settle path; does not bypass the hook | n/a (positive) |
| `IntegrationBlockingHook` | blocking spending-policy hook | reverts in `preCheck` | policy internals | proves a hook revert rolls back the consumed nonce end-to-end and that removing it enables recovery | hook-driven revert + CEI rollback |
| `RevertingNativeRecipient` | a contract recipient that rejects ETH | `receive()` reverts | arbitrary griefing | proves a failed native leg rolls back fully (no partial effect) | native recipient rejection |
| `TwaWalletV2` (`is SmartWallet layout at 0x653ff6dc…`) | a real next UUPS implementation | identical storage layout + an `isUpgraded()` marker | new business logic | a faithful upgrade target so storage-durability is tested against a real `upgradeToAndCall`, not a stub | n/a (positive) |
| `Base` deployment harness (`SmartWalletFactory`, `EntryPoint`, `ECDSAValidator`, `PasskeyValidator`, EIP-2470) | production account/factory deployment & validator routing | real CREATE2 clone + `initialize` + real validator registration | production deploy scripts (Stage 9 owns those) | the account, factory, and validators are the real contracts; only external token/recipient/hook peripherals are mocked | re-init rejection, cross-account binding |

## Execution Evidence
- `forge test --match-path 'test/integration/*' --skip 'test/Recovery.t.sol' -vv` → **19 passed, 0 failed** (`.oli-work/forge-integration.log`).
- Full-suite regression `FOUNDRY_INVARIANT_RUNS=16 FOUNDRY_INVARIANT_DEPTH=16 forge test --skip 'test/Recovery.t.sol'` → **429 passed, 0 failed, 0 skipped** across 26 suites (`.oli-work/forge-full-suite.log`); the 19 new integration tests plus the 410 inherited unit/fuzz/invariant tests, no regression.
- `forge build` compiles cleanly against the restored libraries; `Compiler run successful!`.
- No-source-change gate `check_no_source_changes.py --forbid-prefix src --forbid-prefix script --forbid-file foundry.toml --baseline-dir ../../inputs/A-05/okx-smart-wallet-dev` → `status: ok`, `violations: []` (`.oli-work/no-source-change.json`). The only changed files under forbidden prefixes (`foundry.toml`, `src/*`) are `inherited_from_baseline` (byte-identical to the A-05 input snapshot); the only Stage-6 additions are `test/integration/TransferWithAuthorizationIntegration.t.sol` and `docs/process/INTEGRATION_TEST.md`.

### Foundry submodule / library environment note (build hygiene)
The repository's `.gitmodules` records newer library gitlink commits than the working-tree versions the source
compiles against (e.g. `lib/account-abstraction` gitlink → v0.8.0, but `src/ERC4337Account.sol` requires the
working-tree v0.7.0 API), and `lib/smart-wallet-recovery` is a private, un-cloneable submodule used only by the
already-skipped `test/Recovery.t.sol`. When `forge` recompiles it auto-runs `git submodule update --init`, which
otherwise resets every initialized library to the (incompatible) gitlink commit and breaks the build. This stage
restored the libraries to the A-05 working commits (offline `git checkout`) and set
`git config submodule.lib/<name>.update none` for every submodule (a `.git/config`-only change — untracked, not a
forbidden path, absent from `git status`), so the libraries stay pinned to the versions the source builds against.
No tracked file (including `.gitmodules`) was modified. This is an environment/build-hygiene observation, not a
contract behavior issue; it is surfaced for Stage 7.0/9.0 awareness (the gitlink/working-tree version drift should
be reconciled before production deployment).

## Scenario Results
| Scenario | Expected | Actual | Result |
|----------|----------|--------|--------|
| `test_deploy_freshMultiOwnerAccountTwaLiveAndSettles` | fresh multi-owner factory account: both owners admin, TWA id + domain separator live, ERC-20 settle works | as expected | PASS |
| `test_deploy_reinitializeReverts` | second `initialize` reverts `InvalidInitialization` | reverted as expected | PASS |
| `test_crossAccount_authorizationDoesNotReplayAcrossAccounts` | account A's authorization reverts `InvalidSignature` on account B (no funds), still settles on A | as expected | PASS |
| `test_journey_erc20SettleThenReplayInLaterTxReverts` | settle once (event + exact debit/credit), later replay reverts `AuthorizationAlreadyUsed`, no second credit | as expected | PASS |
| `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts` | owner cancels via real `execute` self-call (cancel event), later settle reverts, no funds moved | as expected | PASS |
| `test_stateContinuity_twaNonceIsolatedFrom4337Nonce` | relayer execution advances 4337 nonce 0→1; TWA settle leaves it at 1; spaces independent | as expected | PASS |
| `test_stateContinuity_independentNoncesProgressIndependently` | n1 used, n2 canceled, n3 still settles; both terminal nonces reject replay | as expected | PASS |
| `test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade` | nonce state survives a UUPS `upgradeToAndCall`; replay still reverts after upgrade | as expected | PASS |
| `test_multiActor_perKeyHookIsolationAcrossOwners` | admin-key settle invokes no hook; hooked-key settle invokes its hook once with the exact call; self-recipient external token is net-zero (control) | as expected | PASS |
| `test_multiActor_executePermissionless_receivePayeeGatedContractPayee` | arbitrary relayer settles execute; non-payee receive reverts `CallerNotPayee`; contract payee pulls successfully | as expected | PASS |
| `test_multiActor_frontRunIsOutcomeNeutral` | front-runner settles to the signed recipient; loser reverts `AuthorizationAlreadyUsed`; no double credit | as expected | PASS |
| `test_fundFlow_sequentialErc20SettlementsConserveAndDrain` | Σ recipient credits = Σ account debits = tracked outflow; account conserved | as expected | PASS |
| `test_fundFlow_mixedNativeAndErc20Conserve` | native and token ledgers each debited/credited exactly by their own value | as expected | PASS |
| `test_fundFlow_feeOnTransferTokenSettlesNominalValue` | account debited full `value`, recipient credited `value − fee`, event logs nominal `value`, nonce terminal | as expected | PASS |
| `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature` | hook blocks (nonce unused, no funds); owner removes hook; same signature then settles | as expected | PASS |
| `test_recovery_insufficientBalanceThenFundThenRetrySameSignature` | under-funded settle reverts (nonce unused); after funding, same signature settles | as expected | PASS |
| `test_failure_expiredAuthorizationReissueWorks` | expired authorization reverts `AuthorizationExpired`; fresh authorization with a new window settles | as expected | PASS |
| `test_failure_nativeRecipientRevertRollsBackFully` | native settle to a rejecting contract reverts; account balance + nonce unchanged | as expected | PASS |
| `test_observability_usedVsCanceledDistinguishableOnlyByEvent` | both nonces terminal in state; `Used` carries nonce in data (not topic), `Canceled` carries nonce as indexed topic | as expected | PASS |

## Failure Analysis
- None. All 19 integration scenarios and the 410 inherited unit/fuzz/invariant tests pass. No implementation defect, unit-test gap, or integration-test-design defect was exposed.

| Failed Case | Command | Expected | Actual | Root Cause Layer | Target Stage |
|-------------|---------|----------|--------|------------------|--------------|
| None | n/a | n/a | All integration scenarios and the full regression suite passed under the accepted recovery-suite skip | n/a | n/a |

## Design Risks Observed
- No blocking contract design risk surfaced end-to-end. Two informational observations for Stage 7.0:
  - **Fee-on-transfer / non-standard token accounting (by design, not a defect):** `executeTransferWithAuthorization` settles the nominal `value` via `SafeERC20.safeTransfer` and emits the nominal `value` in `TransferAuthorizationUsed`, while a fee-on-transfer token credits the recipient less than `value` (verified in `test_fundFlow_feeOnTransferTokenSettlesNominalValue`). This matches the approved design ("settle nominal value; no internal accounting assumption beyond the nonce flag"). Off-chain reconciliation that needs the actual received amount for such tokens must read the token's own `Transfer` event, not the TWA event's `value`.
  - **Library gitlink vs working-tree version drift (build hygiene, not contract behavior):** see the Foundry submodule note above. Recommend reconciling `.gitmodules` gitlinks with the versions the source compiles against before Stage 9.0 production deployment.

## Rework Integration Resolution
- Not applicable — this is an initial Stage 6 integration run (`../last/` absent; no Stage 6 `rework_request.md` injected). No prior integration tests to reuse.

## Integration Coverage Notes
- **Covered user journeys:** authorize→relay→settle→replay-rejected; owner-revoke→settle-rejected; contract-payee pull; transient-failure recovery by retrying the same signed authorization.
- **Covered actor/role interactions:** admin vs non-admin owner keys (per-key hook isolation); permissionless `execute` relayer vs payee-gated `receive`; front-running relayer (outcome-neutral); unregistered/non-payee negative actors.
- **Covered deployment/init paths:** fresh multi-owner factory deployment with both owners admin; live TWA interface id + domain separator on a freshly initialized account; re-initialization rejection.
- **Covered cross-contract interactions:** two independently deployed accounts (cross-account replay rejected by domain/`from` binding); account↔ERC-20 via `SafeERC20` including a fee-on-transfer token; account↔contract native recipient (success and revert); account↔per-key hook; account↔UUPS new implementation.
- **Covered fund flows:** multiple sequential ERC-20 settlements (conservation + drain); interleaved native + ERC-20 (independent ledger conservation); fee-on-transfer nominal-value settlement; external-token self-recipient net-zero control.
- **Covered state-continuity paths:** TWA authorization-nonce space isolated from the 4337/native nonce; independent nonces progress independently; authorization-nonce durability across a UUPS upgrade.
- **Covered failure/recovery paths:** hook block, insufficient balance, expired window, rejecting native recipient — each leaves no partial effect (account balance, recipient balance, nonce state, 4337 nonce unchanged) and, where applicable, is recoverable by fixing the condition and re-submitting the same signature or reissuing a fresh authorization.
- **Context-derived flows covered:** Circle USDC EIP-3009 lineage (open window, payee-gated receive, cancel terminality) is exercised; the OKX account-level divergences (random nonce, keyHash envelope, payee pull, event-only Used/Canceled distinction) are tested. No business context was provided.
- **Solidity best-practice workflow validation:** reject-before-effect (CEI / no partial effect) on every rejected workflow; terminal-once nonce across full lifecycles; outcome-neutral front-running.
- **Event/observability:** `TransferAuthorizationUsed` (token/from/to indexed; value+nonce in data) and `TransferAuthorizationCanceled` (authorizer+nonce indexed) verified; the binding reconciliation rule that Used vs Canceled is distinguishable only by event (not by on-chain `transferAuthorizationState`) is verified end-to-end.
- **Remaining non-blocking gaps:** the private `test/Recovery.t.sol` suite is skipped (un-cloneable submodule, outside the TWA delta); external-validator (non-built-in) TWA envelopes and passkey end-to-end are covered at the Stage 5 unit level rather than re-exercised here; the library gitlink/working-tree version drift is an environment item for Stage 7.0/9.0.
