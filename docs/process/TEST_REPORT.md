# Unit, Fuzz, and Invariant Test Results

## Conclusion: PASS

Stage 5 rework added and ran independent unit, fuzz, and invariant coverage for the approved account-level `TransferWithAuthorization` implementation. The scoped TWA and existing affected-suite campaigns pass, no Stage 4 implementation defect was found, and no forbidden production source/script/foundry changes were introduced by this stage.

Non-blocking environment limitation: the private `lib/smart-wallet-recovery` submodule cannot be cloned by this worker, so every Forge command was run with `--skip 'test/Recovery.t.sol'`. That legacy recovery suite is outside the TWA delta and is not treated as a Stage 5 blocker for this run.

## Environment

- target chain: EVM, Ethereum mainnet semantics, Cancun / EIP-1153.
- codebase mode: `existing_code_change`, Stage 5 rework attempt 2.
- source path: `src/`
- test path: `test/`
- script path: `script/`
- upstream input snapshot: `../inputs/A-04/okx-smart-wallet-dev`
- context status: no live `.oli-work/context` files were present in this Stage 5 workspace; approved process docs preserve the Circle USDC EIP-3009 technical context and PRD-linked TWA EIP supplement. No business context was provided.
- recovery-suite limitation: accepted non-blocking environment limitation; all Forge commands used `--skip 'test/Recovery.t.sol'`.
- commands run:
  - `forge test --skip 'test/Recovery.t.sol' -vvv --no-match-test 'invariant'` -> passed, 407 tests, `.oli-work/forge-scoped-unit-no-invariant.log`
  - `forge test --skip 'test/Recovery.t.sol' --match-test 'testFuzz' -vvv` -> passed, 14 fuzz tests, `.oli-work/forge-scoped-fuzz.log`
  - `FOUNDRY_INVARIANT_RUNS=16 FOUNDRY_INVARIANT_DEPTH=16 forge test --skip 'test/Recovery.t.sol' --match-test 'invariant' -vvv` -> passed, 3 invariants, `.oli-work/forge-scoped-invariant.log`
  - `forge test --skip 'test/Recovery.t.sol' --match-test 'test_passkey' -vvv` -> passed, 2 TWA passkey tests, `.oli-work/forge-passkey-twa.log`
  - `forge coverage --skip 'test/Recovery.t.sol' --report summary` -> passed, 410 tests, `.oli-work/forge-coverage-scoped-summary.txt`
  - `coverage_gate.py --include-path-regex '^src/transferwithauthorization\.sol$'` -> passed, 100% lines / 100% branches, `.oli-work/coverage-gate-transfer-with-authorization.json`
  - `coverage_gate.py --exclude-path-regex '(^|/)(script|test|lib)/'` -> expected existing-code whole-production fail, 98.8839% lines / 98.8506% branches, `.oli-work/coverage-gate-production.json`
  - `check_no_source_changes.py --forbid-prefix src --forbid-prefix script --forbid-file foundry.toml --baseline-dir ../../inputs/A-04/okx-smart-wallet-dev` -> passed, `.oli-work/no-source-change.json`
  - `forge fmt --check test/Base.t.sol test/TransferWithAuthorization.t.sol test/TransferWithAuthorizationInvariant.t.sol` -> passed

## Test Plan

### Requirement-to-Test Matrix

| Requirement | Expected Behavior | Test File / Test Name | Status |
|-------------|-------------------|------------------------|--------|
| FR-1 / FR-1-AC-1 | `executeTransferWithAuthorization` settles signed ERC-20/native transfer, emits `TransferAuthorizationUsed`, and marks nonce terminal. | `TransferWithAuthorization.t.sol::test_executeErc20_happy`, `test_executeNative_happy`, `test_noReturnToken_settlesViaSafeERC20`, `testFuzz_executeErc20MovesExactValue` | PASS |
| FR-1-AC-2 / INV-NONCE-ONCE | Reusing a used or canceled nonce reverts and cannot move funds again. | `test_replay_reverts`, `test_cancelFormB_selfThenSettleReverts`, `invariant_nonceSettlesAtMostOncePerTrackedNonce` | PASS |
| FR-1-AC-3 / INV-TIME-WINDOW | Settlement is valid only in the open interval `(validAfter, validBefore)`. | `test_notYetValid_reverts`, `test_expired_reverts` | PASS |
| FR-1-AC-4 / FR-1 boundary 1/2 | Wrong signer, short envelope, wrapped digest, mutated fields, unregistered key, or malformed legacy envelope fails and leaves nonce unused. | `test_wrongSigner_reverts`, `test_unregisteredKey_revertsAndNonceUnused`, `test_wrappedDigestSignature_revertsAndNonceUnused`, `test_shortEnvelope_reverts`, `test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused`, fuzz mutation tests | PASS |
| FR-1-AC-5 / INV-VALUE-CONSERVATION | Insufficient account balance or token failure reverts atomically with nonce unused and balances unchanged. | `test_falseReturnToken_revertsAndNonceUnused`, `test_insufficientErc20Balance_revertsAndNonceUnused`, `test_insufficientNativeBalance_revertsAndNonceUnused`, `invariant_tokenAccountingConservedAcrossSuccessfulSettles` | PASS |
| FR-1-AC-6 / FR-1-AC-7 / G-5 | Key-selected hook is invoked with execute-equivalent call shape; hook reverts roll back nonce. | `test_hookInvoked_blocksSettle_and_nonceUnconsumed`, `test_recordingHookReceivesExactErc20CallAndExecutor`, `test_recordingHookReceivesExactNativeCallAndExecutor` | PASS |
| FR-1-AC-8 / R-3 | ERC-1271/MessageSignLib-wrapped digest signatures fail; direct typed-data signatures pass. | `test_wrappedDigestSignature_revertsAndNonceUnused`, happy paths | PASS |
| G-4 / DR-002 | TWA uses `keyHash(32) || ownerSignature`; passkey keyHash is `keccak256(abi.encodePacked(pubKeyX,pubKeyY))`; no `validUntil` prefix. | `test_passkeyEnvelope32BytePrefix_settlesErc20`, `test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused` | PASS |
| FR-2 / FR-2-AC-1..4 | `receiveWithAuthorization` is payee-gated, uses a distinct typehash, and inherits settlement safety. | `test_receive_happy_byPayee`, `test_receive_callerNotPayee_reverts`, `test_crossTypeReplay_reverts`, invariant `receiveByPayee` action | PASS |
| FR-3 / FR-3-AC-1..4 | Signed cancel and self-call cancel consume unused nonces, emit cancel event, and later settlement reverts. | `test_cancelFormA_signed`, `test_cancelFormB_selfThenSettleReverts`, `test_cancelFormA_invalidSignature_revertsAndNonceUnused`, `test_cancelAlreadyUsedNonce_reverts`, invariant `cancel` action | PASS |
| FR-4 | `transferAuthorizationState` returns false for unused and true for used or canceled; domain getter matches typed-data hash. | `test_transferAuthorizationState_unusedFalse`, happy/cancel tests, `test_domainSeparatorGetterMatchesDigest` | PASS |
| FR-5 | `supportsInterface(0x86c5a9e1)` returns true and existing ERC-165/ERC-1271 ids are preserved. | `test_supportsInterface` | PASS |
| NFR-2 / R-1 | Native and token settlement reentrancy cannot double-spend or consume nested nonce. | `test_nativeReentrancyCannotConsumeNestedNonce`, invariant replay actions | PASS |
| NFR-3 / DR-003 | Non-admin keys cannot self-target through TWA; admin/self semantics match execute. | `test_nonAdminNativeSelfTarget_revertsAndNonceUnused`, `test_nonAdminTokenSelfTarget_revertsAndNonceUnused`, `test_adminNativeSelfTarget_succeedsNetZero`, `test_externalTokenToWalletRecipient_succeedsForNonAdmin` | PASS |
| NFR-4 / DR-001 | Used vs canceled are event-distinguished; boolean state is terminal-only. | used/canceled event assertions and backend-handoff rule review | PASS |

### Function-to-Test Matrix

| Function | Happy Path | Boundary | Revert/Error | Events | State Changes | Status |
|----------|------------|----------|--------------|--------|---------------|--------|
| `executeTransferWithAuthorization` | ERC-20, native, no-return token, passkey, fuzzed amount/recipient/window | zero value, full funded balance, open-window equality, 32-byte passkey prefix | replay, wrong signer, unregistered key, wrapped digest, short envelope, legacy 38-byte passkey envelope, invalid recipient, insufficient balance, false-return token, nonpayable `msg.value`, reentrancy, hook revert, self-target guard | `TransferAuthorizationUsed` | nonce false -> true; exact asset movement; rollback on revert | PASS |
| `receiveWithAuthorization` | payee caller ERC-20 settlement | receive typehash | caller != payee, execute-signed payload, shared settlement failures | `TransferAuthorizationUsed` | same as execute | PASS |
| `cancelTransferAuthorization` | signed form A and self-call empty-signature form B | already terminal nonce | bad signature, empty signature from non-self | `TransferAuthorizationCanceled` | nonce false -> true; no asset movement | PASS |
| `transferAuthorizationState` | false before use, true after use/cancel | arbitrary unused nonce | n/a | n/a | view only | PASS |
| `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` | matches `hashTypedData` composition | n/a | n/a | n/a | view only | PASS |
| `supportsInterface` | TWA id and existing ids | unknown id | n/a | n/a | view only | PASS |
| Public constants | exact typehashes, `INTERFACE_ID`, `NATIVE_ASSET`, `SIGNATURE_ENVELOPE_MIN_LENGTH` | n/a | n/a | n/a | view only | PASS |

### Security Invariant-to-Test Matrix

| Invariant | Test Type | Handler / Test Name | Status |
|-----------|-----------|---------------------|--------|
| INV-NONCE-ONCE | invariant + unit | `TransferWithAuthorizationHandler`; `invariant_nonceSettlesAtMostOncePerTrackedNonce` | PASS |
| INV-NONCE-ISOLATION | invariant | `invariant_twaDoesNotAdvanceNativeNonceSpace`; normal execute nonce unchanged by TWA | PASS |
| INV-RECIPIENT-BOUND | fuzz/unit | mutated `to` and `value` invalidate signatures | PASS |
| INV-CEI | unit/invariant | hook/token/native reverts leave nonce unused; reentrant nested settle blocked | PASS |
| INV-HOOK-ISOMORPHISM | unit | recording hook captures exact `Call` target/value/data/executor; self-call guard matrix | PASS |
| INV-TIME-WINDOW | unit | equality edges revert, valid open interval actions pass | PASS |
| INV-TYPESEP | unit | execute/receive/cancel cross-type signatures fail | PASS |
| INV-NO-NATIVE-BURN | unit | zero and native-sentinel recipients revert before settlement | PASS |
| INV-VALUE-CONSERVATION | unit/fuzz/invariant | exact MockERC20/native balance deltas and invariant token accounting | PASS |

### Permission / Revert Matrix

| Function | Authorized Caller | Unauthorized Caller | Expected Error / Revert | Test |
|----------|-------------------|---------------------|-------------------------|------|
| `executeTransferWithAuthorization` | any relayer with valid owner signature | bad signer/key or mutated signed fields | `InvalidSignature` | wrong signer, unregistered key, wrapped digest, mutation fuzz |
| `executeTransferWithAuthorization` passkey path | any relayer with valid passkey envelope | legacy execute-style 38-byte prefix | revert with nonce/funds unchanged | `test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused` |
| `receiveWithAuthorization` | `msg.sender == to` with valid signature | any caller where `msg.sender != to` | `CallerNotPayee(caller,to)` | `test_receive_callerNotPayee_reverts` |
| `cancelTransferAuthorization` form A | any relayer with registered-key cancel signature | relayer with wrong signature | `InvalidSignature` | `test_cancelFormA_invalidSignature_revertsAndNonceUnused` |
| `cancelTransferAuthorization` form B | `msg.sender == address(account)` with empty signature | non-self caller with empty signature | `NotFromSelf` | `test_cancelFormB_nonSelf_reverts` |
| TWA self-target settle | admin key or built-in self key for `target == account` | non-admin key self-targeting native `to` or ERC-20 `token` | `NonAdminSelfCall` | self-target matrix tests |

### State-Machine Matrix

| State | Valid Transition | Invalid Transition | Test |
|-------|------------------|--------------------|------|
| Unused | -> Used by successful execute/receive | n/a | happy paths and invariant handler |
| Unused | -> Canceled by signed/self cancel | n/a | cancel tests and invariant handler |
| Used | no further transition | execute/receive/cancel same nonce | replay and cancel-after-use tests |
| Canceled | no further transition | execute/receive/cancel same nonce | cancel-then-settle and invariant terminal-count check |

### Fund-Flow Matrix

| Flow | Asset | Expected Accounting | Negative Case | Test |
|------|-------|---------------------|---------------|------|
| Execute ERC-20 | Mock ERC-20 | account decreases by `value`, recipient increases by `value`, nonce consumed | false-return token, insufficient balance, mutated value | happy, fuzz, rollback tests |
| Execute native | ETH via `NATIVE_ASSET` | account decreases by `value`, recipient increases by `value`, nonce consumed | insufficient balance, recipient reentry | native happy and reentry tests |
| Execute passkey ERC-20 | Mock ERC-20 | same as ECDSA, using built-in passkey validator | legacy 38-byte prefix fails | passkey envelope tests |
| Receive ERC-20 | Mock ERC-20 | same as execute, only payee caller | non-payee caller, execute-type signature | receive tests |
| Cancel | no asset | no balance movement; nonce terminal; cancel event | invalid signer or terminal nonce | cancel tests |
| Hook path | ERC-20/native call shape | hook sees one call and can block/allow; revert rolls back nonce and transfer | blocking hook, self-target non-admin | hook tests |

### Fuzz Domain Matrix

| Target | Inputs | Valid Domain | `vm.assume` Rules | Boundary Values |
|--------|--------|--------------|-------------------|-----------------|
| ERC-20 execute success | `to`, `value`, `nonce`, relayer | non-zero/non-sentinel recipient; value bounded to account balance; fresh nonce | filters invalid recipient and account self-target for this positive case | `0`, dust, full funded balance |
| Signature binding: value | signed amount, mutated amount, nonce | both amounts bounded; mutation must change signed field | assumes `mutatedValue != value` | nearby values through fuzzing |
| Signature binding: recipient | signed recipient, mutated recipient, nonce | both recipients non-zero and not native sentinel | assumes changed recipient | arbitrary actor addresses |
| Invariant handler actions | nonce seed, amount seed, recipient seed, relayer seed | tracked 8 nonces; valid open windows; bounded amount <= current wallet balance | uses `bound`; no discard of valid failures | replay on same nonce, mixed settle/cancel order |

### Invariant Handler And Actor Model

- handler: `TransferWithAuthorizationHandler` in `test/TransferWithAuthorizationInvariant.t.sol`.
- actors: two relayers, three payees, the initialized Alice smart wallet, and the registered Alice ECDSA key.
- actions: `execute`, `receiveByPayee`, `cancel`, `replayExecute`.
- tracked state: 8 nonce values, per-nonce settle/cancel success counts, wallet token balance, recipient token balance sum, total token outflow, native account nonce.
- target constraints: `targetContract(address(handler))` and explicit `targetSelector` restrict fuzzed calls to handler actions.

### Mock / Fixture Matrix

| Mock / Fixture | Real Dependency | Behaviors Modeled | Behaviors Omitted | Safety Rationale |
|----------------|-----------------|-------------------|-------------------|------------------|
| `MockERC20` | standard ERC-20 | balances, minting, normal `transfer` return | fee/rebase semantics | sufficient for exact-value settlement and account balance deltas |
| `FalseReturnERC20` | non-standard token | returns `false` from `transfer` without updating balances | metadata and allowance | directly targets SafeERC20 false-return failure behavior |
| `NoReturnERC20` | USDT-style token | state-changing `transfer` with no return data | approvals/allowances not needed | proves SafeERC20 accepts successful no-return transfers |
| `RecordingHook` | key-selected spending hook | `preCheck`/`postCheck`, exact call array, executor, return data hash | production policy storage/rate limits | verifies TWA invokes hooks with faithful execute-equivalent call shape |
| `RevertingHook` | blocking spending hook | `preCheck` revert | policy internals | proves hook failure rolls back nonce and transfer |
| `ReentrantNativeReceiver` | malicious native recipient | nested TWA call attempt and result recording | arbitrary callback griefing beyond reentry | directly targets reentrancy lock and nonce rollback |
| passkey fixtures from `Base` + `HelperLib` | built-in P-256 passkey validator | keyHash derivation, WebAuthn challenge/signature encoding, validator ownerSignature without `validUntil` | external passkey validator-specific envelope | proves the approved built-in passkey TWA envelope and catches legacy 38-byte execute-prefix mistakes |
| invariant handler | adversarial relayers/payees | valid signatures, repeated settle/cancel/replay sequences, token accounting | passkey/external validator stateful campaigns | invariant campaign targets TWA state/fund-flow properties while unit tests cover passkey encoding |

### Existing-Code Delta Coverage

- Existing valid tests were preserved. Stage 5 added focused TWA coverage in `test/TransferWithAuthorization.t.sol` and `test/TransferWithAuthorizationInvariant.t.sol`.
- Rework attempt 2 added two passkey-specific TWA assertions: correct 32-byte passkey envelope succeeds; legacy 38-byte execute-style prefix rejects and leaves nonce unused.
- Legacy execute, UserOp, allowance, owner-manager, factory, and recovery behavior were not re-templated. `test/Recovery.t.sol` is excluded because its private dependency is unavailable and it is outside the TWA delta.
- `test/Base.t.sol` remains a test helper change only (`vm.envOr("DEPLOY_FACTORY_SALT", bytes32(0))`) and is not production source.
- Affected TWA production contract coverage reached 100% lines and 100% branches. Whole production-source coverage remains below 100% due legacy file-level gaps outside the new TWA contract.

## Results

| Test Area | Expected | Actual | Result |
|-----------|----------|--------|--------|
| Unit/non-invariant suite | Scoped suite excluding unrelated private recovery dependency passes | 407 tests passed, 0 failed | PASS |
| Dedicated fuzz suite | Fuzz domains pass | 14 fuzz tests passed, including 3 TWA fuzz tests | PASS |
| Dedicated invariant suite | Handler campaign preserves nonce/accounting invariants | 3 TWA invariants passed at 16 runs / 256 calls each | PASS |
| Passkey TWA regression | Built-in passkey 32-byte envelope succeeds; legacy 38-byte prefix rejects | 2 tests passed | PASS |
| Coverage run | Produce affected-code coverage evidence | `forge coverage --skip 'test/Recovery.t.sol' --report summary` passed; 410 tests passed | PASS |
| Focused TWA coverage gate | 100% line/branch on affected new production contract | `src/TransferWithAuthorization.sol`: 100% line / 100% branch | PASS |
| Whole production coverage gate | Existing-code baseline may scope gate to affected files/functions | 98.8839% line / 98.8506% branch; gaps are legacy production files outside the TWA contract | ACCEPTED EXISTING-CODE LIMITATION |
| No-source-change gate | no Stage 5 diffs under `src/`, `script/`, or `foundry.toml` vs Stage 4 snapshot | status `ok`; forbidden production changes inherited from A-04 only | PASS |

## Coverage

- coverage command: `forge coverage --skip 'test/Recovery.t.sol' --report summary`; passed and produced `.oli-work/forge-coverage-scoped-summary.txt`.
- affected new contract coverage: `src/TransferWithAuthorization.sol` has 100.00% lines (70/70), 100.00% statements (82/82), 100.00% branches (21/21), and 100.00% functions (11/11).
- focused affected-contract gate: passed with 100.00% line and 100.00% branch coverage, `.oli-work/coverage-gate-transfer-with-authorization.json`.
- whole production-source gate with `script/`, `test/`, and `lib/` excluded: 98.8839% line and 98.8506% branch coverage, `.oli-work/coverage-gate-production.json`.
- exemptions: accepted existing-code delta scoping only. Legacy coverage gaps in `AllowanceManager`, `OwnerManager`, and `SmartWallet` predate / sit outside the new `TransferWithAuthorization` production contract; modified TWA-facing behavior (`supportsInterface`, hook/self-call paths, validator/domain routing through TWA) is directly tested.
- exemption safety rationale: the Stage 5 coverage gate is focused on the new/affected TWA surface per existing-code test rules; no TWA production line or branch is exempted.

## Fuzz Campaigns

| Target | Input Domain | Assumptions | Runs | Result |
|--------|--------------|-------------|------|--------|
| `testFuzz_executeErc20MovesExactValue` | recipient address, `uint96` amount, nonce seed, relayer address | recipient non-zero, not native sentinel, not account; value bounded to wallet token balance | 256 | PASS |
| `testFuzz_mutatedValueInvalidatesSignature` | signed and mutated amounts, nonce seed | mutated value differs from signed value | 256 | PASS |
| `testFuzz_mutatedRecipientInvalidatesSignature` | signed and mutated recipients, nonce seed | recipients non-zero, not native sentinel, and different | 256 | PASS |
| Existing non-TWA fuzz tests | decode and allowance domains | existing test assumptions | 256 each | PASS |

## Invariant Campaigns

| Invariant | Handler | Actors | Runs / Depth | Result |
|-----------|---------|--------|--------------|--------|
| `invariant_nonceSettlesAtMostOncePerTrackedNonce` | `TransferWithAuthorizationHandler` | two relayers, three recipients, Alice wallet/key | 16 runs / 16 depth in dedicated command; 256 runs / 500 depth during coverage | PASS |
| `invariant_tokenAccountingConservedAcrossSuccessfulSettles` | `TransferWithAuthorizationHandler` | same | 16 runs / 16 depth in dedicated command; 256 runs / 500 depth during coverage | PASS |
| `invariant_twaDoesNotAdvanceNativeNonceSpace` | `TransferWithAuthorizationHandler` | same | 16 runs / 16 depth in dedicated command; 256 runs / 500 depth during coverage | PASS |

## Mock / Fixture Justification

| Mock / Fixture | Real Dependency | Behaviors Modeled | Behaviors Omitted | Safety Rationale | Failure Modes Covered |
|----------------|-----------------|-------------------|-------------------|------------------|-----------------------|
| `MockERC20` | ERC-20 token | balance accounting, mint, return-true `transfer` | fee-on-transfer/rebase behavior | exact transfer conservation is the behavior under test | insufficient balance through standard transfer revert |
| `FalseReturnERC20` | non-standard ERC-20 | false return without state change | metadata/allowance | exercises SafeERC20 false-return handling without weakening SUT | rollback and nonce unused on token failure |
| `NoReturnERC20` | no-return ERC-20 | state-changing transfer with no return data | approvals/allowances | models USDT-style success path | successful no-return token settlement |
| `RecordingHook` | account hook | exact call shape, executor, pre/post counts, return data | hook policy limits | validates hook isomorphism rather than bypassing it | hook call-shape mismatch would fail assertions |
| `RevertingHook` | account hook | preCheck revert | policy-specific storage | proves hook revert rolls back settlement | hook-driven revert and nonce rollback |
| `ReentrantNativeReceiver` | malicious native recipient | nested settlement attempt during receive | unrelated gas griefing | directly targets the TWA native transfer reentrancy hazard | nested call blocked, nested nonce unused |
| passkey fixtures | built-in passkey validator and WebAuthn helper | real P-256 signing, WebAuthn auth object, passkey keyHash, TWA ownerSignature layout | production UI/browser ceremony | helper mirrors existing project passkey tests and changes only the TWA-specific absence of `validUntil` | incorrect 38-byte execute-style prefix rejected |
| `TransferWithAuthorizationHandler` | adversarial callers over account TWA API | generated valid signatures, repeated settle/cancel/replay attempts, token accounting | passkey stateful handler path | unit tests cover passkey cryptography; invariant handler covers state-machine/fund-flow properties | double-settle, terminal-state, accounting, native nonce isolation |

## Context Coverage

| Context Source | Constraint / Signal | Test Coverage | Status | Notes |
|----------------|---------------------|---------------|--------|-------|
| Live Stage 5 `.oli-work/context` | no business or technical context files present in current workspace | n/a | Not provided | Recorded per context-loading policy |
| Approved docs carrying Circle EIP-3009 context | open interval, payee-gated receive, cancel/state terminality | time boundary tests, receive caller tests, cancel terminal tests, nonce invariant | Covered | PRD/design override token-level differences by moving semantics to account-level wallet |
| PRD-linked TWA EIP supplement via approved docs | interface/typehash/nonce/ERC-165 constants | constant/interface/domain tests | Covered | PRD wins on 32-byte keyHash envelope and direct digest |
| Existing SmartWallet tests | local Base helper, ECDSA/passkey keyHash, hook/self-call patterns | Stage 5 reuses `Base`, existing validators, and hook fixtures; adds TWA-focused fixtures only | Covered | Preserves existing-code style and avoids re-templating |
| Stage 1 baseline | private recovery dependency unavailable | all Forge commands scoped with accepted skip | Accepted limitation | Recovery is outside TWA delta |

## Failure Analysis

| Failed Case | Command | Expected | Actual | Root Cause Layer | Target Stage |
|-------------|---------|----------|--------|------------------|--------------|
| None | n/a | n/a | Unit, fuzz, invariant, focused coverage, and no-source-change gates passed under the accepted recovery skip | n/a | n/a |

## Rework Test Resolution

| Item | Test Added / Updated | Result |
|------|----------------------|--------|
| Attempt 1 produced only skeleton output | Rebuilt substantive Stage 5 deliverables: TWA unit tests, invariant tests, coverage logs, report, output summary | PASS |
| Comprehensive unit tests | `test/TransferWithAuthorization.t.sol` now covers public constants, getters, ERC-20/native/no-return paths, receive, cancel, signatures, hooks, self-target guards, reentrancy, and passkey envelope encoding | PASS |
| Fuzz tests | Added/ran TWA fuzz tests for exact ERC-20 accounting and recipient/value signature binding | PASS |
| Invariant tests | Added/ran `test/TransferWithAuthorizationInvariant.t.sol` handler for nonce terminality, token accounting, and native nonce isolation | PASS |
| Passkey keyHash / ownerSignature encoding priority | Added `test_passkeyEnvelope32BytePrefix_settlesErc20` and `test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused` | PASS |
| Recovery dependency limitation | Treated as non-blocking per user instruction; all Forge commands used `--skip 'test/Recovery.t.sol'` and reported the scope | PASS |

No Stage 4 rework request was emitted.
