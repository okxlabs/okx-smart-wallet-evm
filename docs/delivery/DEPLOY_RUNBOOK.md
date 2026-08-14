# DEPLOY_RUNBOOK.md — okx-smart-wallet-dev (Account-Level Transfer-With-Authorization / TWA)

> Operator deployment checklist for the TWA delta on the OKX SmartWallet account. Execute the steps **in order**; do not skip a step. If any **STOP** condition is hit, halt immediately, archive the listed evidence, and consult `docs/delivery/EMERGENCY_PLAN.md` before continuing.

## Deployment Status: READY

Upstream audit Pipeline-stage Conclusion = **PASS** (`docs/process/AUDIT_REPORT.md`: verdict WARN, 0 confirmed Critical/High, 5 non-blocking Medium advisories under `FAIL_ON=critical`). Implementation/test review = **APPROVED** (`docs/process/DEV_REVIEW.md`). Scoped production build verified PASS this stage. All required deployment parameters, dependency addresses, chain ID, and owner/admin destinations are known and recorded below.

This runbook does **not** itself broadcast any transaction: every active (uncommented) command is dry-run-safe. Broadcasting is a deliberate operator action (Step 9), shown only as a commented template.

---

## 1. Project Information

| Field | Value |
|-------|-------|
| Repository | `https://gitlab.okg.com/web3-wallet/smart-wallet-infra/okx-smart-wallet-dev.git` |
| Base branch | `dev` |
| Working branch | `feature/aa-auth-4.0` |
| Commit SHA | `<COMMIT_SHA>` (operator records the exact deployed commit) |
| Target chain | EVM — **Ethereum mainnet** |
| Chain ID | **1** |
| EVM version | **Cancun** (EIP-1153 transient storage) — **REQUIRED** |
| Environment | Production (first launch) |
| Release identifier | `<RELEASE_ID>` (operator assigns; record with the salt) |
| Solidity / toolchain | solc `0.8.29`, Foundry; `evm_version=cancun`, `optimizer=true`, `optimizer_runs=100` (`foundry.toml`) |
| Deploy script | `script/deploy.s.sol` (contract `DeployInit`) |
| Context status | technical = Circle USDC (EIP-3009 semantic reference only — does not govern this deployment); business = none. No deployment-convention conflict. |

---

## 2. Operator Safety Rules

1. **NEVER** put a real private key on a command line. The deploy script reads the key from the `DEPLOYER_PRIVATE_KEY` environment variable. For the dry-run, use a **throwaway** key with no funds and no privileges.
2. **NEVER** write a literal RPC URL into any file under `docs/`. Use the `$RPC_URL` / `$FORK_RPC_URL` environment variable or a `<rpc-endpoint>` placeholder; provide the real endpoint only in your shell at execution time.
3. **Every active (uncommented) command in this runbook is dry-run-safe** — none carry the broadcast flag, the verify flag, or a private-key flag. The live broadcast command exists only as a commented template in Step 9; you uncomment it in your own shell after every gate below has passed.
4. **HARD PRECONDITION — do NOT deploy to a non-Cancun chain.** The TWA native-reentrancy lock uses EIP-1153 transient storage, which a non-Cancun chain does not support (DESIGN §12 DEP-6, §14). Confirm `chainId == 1` and Cancun activation before broadcasting. X Layer (chainId 196 / testnet 1952) is the documented compatible alternative; mainnet is the first launch target.
5. The implementation and factory are **ownerless and immutable** — there is no proxy admin, no global pause, and no upgrade admin to set at deploy time. Do not assign an owner/admin during deployment; per-account owners are set later at account creation, which is not an operator deploy step.
6. Do not let `forge` auto-run `git submodule update` — it can reset drifted-but-working `lib/` gitlinks and break the build. Build **offline** (`FOUNDRY_OFFLINE=true`) and reconcile `lib/` gitlinks before packaging.
7. Treat `script/deploy.s.sol` and the `foundry.toml` build settings as frozen for this release. Any source change invalidates the size margin and the post-deploy facts below and requires re-running the full checklist.
8. Record every produced address, the salt, and the commit SHA in your deployment log; archive the evidence named at each step.

---

## 3. Pre-Deployment Checklist

Complete **every** item before proceeding to Section 4. Each item: action / command-or-confirmation / expected output / STOP condition / evidence.

### 3.1 — Clean checkout at the audited commit
- **Action:** checkout the working branch; confirm a clean tree at the intended commit.
- **Command:**
  ```bash
  git rev-parse HEAD
  git status --porcelain
  ```
- **Expected:** `git rev-parse HEAD` prints the commit you record as `<COMMIT_SHA>`; `git status --porcelain` prints nothing.
- **STOP if:** the tree is dirty or HEAD ≠ the intended commit.
- **Evidence:** the commit SHA and clean status output.

### 3.2 — Confirm chain identity and Cancun activation
- **Action:** confirm the target RPC is Ethereum mainnet (chainId 1) and Cancun-active. Read-only; uses your shell `$RPC_URL`.
- **Command:**
  ```bash
  # $RPC_URL must be exported in your shell; never written into this file.
  cast chain-id --rpc-url "$RPC_URL"
  ```
- **Expected:** `1`.
- **STOP if:** the value is not `1`, or the chain is not Cancun-active (Safety Rule 4 / DEP-6).
- **Evidence:** the chain-id output and a note confirming Cancun activation.

### 3.3 — Reconcile `lib/` submodule gitlink drift (audit LOW)
- **Action:** confirm `lib/` submodule gitlinks match the locked dependency state; do not run a network submodule update against drifted-but-working libs.
- **Command:**
  ```bash
  git submodule status
  ```
- **Expected:** revisions match the locked state (`foundry.lock`); no drift that would change compiled bytecode.
- **STOP if:** gitlinks drift in a way that would alter the compiled libraries (solady / OZ / account-abstraction / webauthn-sol); reconcile to the locked revisions first; do not let forge auto-reset them.
- **Evidence:** `git submodule status` output.

### 3.4 — Reconcile the `package.json` deploy-script path (pre-existing repo inconsistency)
- **Action:** note that the `package.json` `deploy` npm script points to a **non-existent** `script/deploy/DeployInit.s.sol`. The real deploy script is `script/deploy.s.sol` (per `README.md` §Deploy). Run `forge` directly per this runbook, or reconcile the npm path before relying on `yarn deploy`.
- **Confirmation (manual):** operator confirms they will invoke `forge script script/deploy.s.sol` directly, not the broken `yarn deploy` alias.
- **STOP if:** any pipeline step depends on the `yarn deploy` alias resolving — fix the npm `deploy`/`deploy:broadcast` paths first.
- **Evidence:** a deployment-log note of which invocation path was used and whether the npm script was reconciled.

### 3.5 — Production build + EIP-170 size check (audit M-02; EIP-170 margin)
- **Action:** run the **scoped production build with sizes**. Use `forge build src script` — NOT bare `forge build`, which fails on `test/Recovery.t.sol` importing the uninitialized private `lib/smart-wallet-recovery` dependency (audit M-02). Build offline.
- **Command:**
  ```bash
  FOUNDRY_OFFLINE=true forge build src script --sizes
  ```
- **Expected:** exit `0`; `SmartWalletEntry` runtime **≤ 24,576 bytes** (EIP-170). Stage 9 recorded `SmartWalletEntry = 24,510 B` (margin **66 B**) and `SmartWalletFactory = 2,218 B`.
- **STOP if:** the build fails, OR `SmartWalletEntry` runtime exceeds 24,576 bytes, OR its size grew beyond 24,510 B without an approved size mitigation. The margin is only 66 bytes.
- **Evidence:** full `--sizes` output and exit code; compare against the 24,510 B / 66 B baseline.

### 3.6 — Confirm archived deterministic secret & static checks (Stage 9)
- **Action:** review the archived secret-scan and static-deployment-check results this stage ran. You do not re-run the stage's bundled safety scripts (they ship with the deployment skill pack and are not part of the repository).
- **Confirmation:** open `docs/delivery/DEPLOY_CHECK.md` and confirm the secret scan and static checks are recorded as passing for this commit.
- **STOP if:** `DEPLOY_CHECK.md` records any failed secret/static check, or is absent for this commit.
- **Evidence:** reference to `docs/delivery/DEPLOY_CHECK.md`.

### 3.7 — Confirm required deploy environment variables (no values printed)
- **Action:** confirm the two env vars the deploy script reads are exported, **without printing values**. The script reads `DEPLOYER_PRIVATE_KEY` (`vm.envUint`) and `DEPLOY_FACTORY_SALT` (`vm.envBytes32`).
- **Command:**
  ```bash
  # Presence check only — does NOT print the secret value.
  test -n "$DEPLOYER_PRIVATE_KEY" && echo "DEPLOYER_PRIVATE_KEY: set" || echo "DEPLOYER_PRIVATE_KEY: MISSING"
  test -n "$DEPLOY_FACTORY_SALT"  && echo "DEPLOY_FACTORY_SALT: set"  || echo "DEPLOY_FACTORY_SALT: MISSING"
  ```
- **Expected:** both print `set`. For the dry-run, `DEPLOYER_PRIVATE_KEY` is a throwaway key; `DEPLOY_FACTORY_SALT` is a documented, reproducible `bytes32` salt (e.g. `keccak256("okx-smart-wallet:twa:v1.1.0")`), chosen and recorded by the operator.
- **STOP if:** either is `MISSING`, or you cannot confirm a throwaway key for the dry-run.
- **Evidence:** the `set`/`MISSING` lines (no secret values) and the recorded salt + release id.

### 3.8 — Run the operator fork dry-run (pre-deployment step)
- **Action:** execute the operator-runnable fork dry-run from `docs/delivery/DEPLOY_DRY_RUN.md` (deferred in-stage because no fork RPC was configured). That plan owns the exact command, fork setup, and assertions.
- **Confirmation:** run the dry-run exactly as specified in `docs/delivery/DEPLOY_DRY_RUN.md` (uses a `$FORK_RPC_URL` placeholder and a throwaway key; no broadcast).
- **Expected:** both contracts deploy on the fork, `SmartWalletFactory.IMPLEMENTATION()` matches the deployed `SmartWalletEntry`, and the smoke path (create account → ERC-20 settle → replay-revert) behaves as documented.
- **STOP if:** the dry-run fails any assertion, or you cannot obtain a fork RPC endpoint.
- **Evidence:** the dry-run console log and the addresses/assertions it produced.

---

## 4. Deployment Data

| Parameter | Value | Source |
|-----------|-------|--------|
| Deploy method | **CREATE2 via EIP-2470 Singleton Factory** (plain-CREATE fallback only where the factory is absent) | `script/deploy.s.sol`, `script/IDeployFactory.s.sol` |
| EIP-2470 Singleton Factory | `0xce0042B868300000d44A59004Da54A005ffdcf9f` (same address all chains) | `script/deploy.s.sol` (`DEPLOY_FACTORY`) |
| Factory present on mainnet? | **YES** (CREATE2 used; no fallback expected) | Deployment Facts |
| Salt | `DEPLOY_FACTORY_SALT` (`bytes32`, operator-supplied env; same salt for both deploys; documented & reproducible) | `script/deploy.s.sol` |
| ERC-4337 EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` (hardcoded; must exist on chain; not a constructor arg) | `src/ERC4337Account.sol:18` |
| `NATIVE_ASSET` sentinel | `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` (constant, not an address dependency) | `src/libraries/Static.sol` / DESIGN §6 |
| Predicted CREATE2 address | `keccak256(0xff ++ 0xce0042…ffdcf9f ++ salt ++ keccak256(initCode))[12:]` (EIP-2470 uses the salt directly, no msg.sender mixing) | Deployment Facts |
| TWA `INTERFACE_ID` | `0x86c5a9e1` (ERC-165) | `src/TransferWithAuthorization.sol:35` |
| `SmartWalletEntry` runtime size | 24,510 B (margin 66 B under EIP-170 24,576) | Stage 9 `--sizes` |
| `SmartWalletFactory` runtime size | 2,218 B | Stage 9 `--sizes` |

### Owner / Admin / Role / Emergency destinations

| Destination | Value at deploy time |
|-------------|----------------------|
| Implementation owner/admin | **NONE** — `SmartWalletEntry` is ownerless/immutable; constructor sets `IMPLEMENTATION = address(this)` and `_disableInitializers()` (no msg.sender privilege; never initialized) |
| Factory owner/admin | **NONE** — `SmartWalletFactory` sets immutable `IMPLEMENTATION` from its constructor **parameter**, not `msg.sender`; ownerless |
| Proxy admin | **NONE** — UUPS; upgrade authority `_authorizeUpgrade` is `onlySelf` (per account) |
| Global pause / upgrade admin | **NONE** (no global pause or kill-switch; DESIGN §13) |
| Per-account owners | set later at account creation via `initialize(InitialOwner[])` (caller-supplied, `onlyFactory`) — NOT an operator deploy step |
| Invariant (asserted by absence) | no owner/admin/role is ever the singleton factory address |

---

## 5. Context-Derived Deployment Constraints

- **Technical context (Circle USDC / EIP-3009):** semantic reference only (open window, payee-gated receive, nonce terminality, cancel). Different system (FiatToken); its deploy scripts do not govern this repository. No conflict.
- **Business context:** none provided.
- **Net effect:** no deployment constraint beyond what DESIGN already encodes (Cancun requirement, payee-gating semantics).

---

## 6. Audit Advisory Handling (operations-relevant findings)

All findings are non-blocking (0 Critical/High; 5 Medium).

| ID | Severity | Operational handling at deploy time |
|----|----------|-------------------------------------|
| **M-02** — default `forge build` fails on inherited recovery-suite imports | MEDIUM | Build with `forge build src script` (Step 3.5), never bare `forge build`; optionally restore the private `smart-wallet-recovery` dependency before packaging. Production src+script compiles cleanly. |
| **EIP-170 margin** | MEDIUM | `SmartWalletEntry` runtime is 24,510 B — only 66 B under the limit. Re-run `--sizes` before deploy (Step 3.5) and forbid source growth without a size mitigation. |
| **Submodule gitlink drift** | LOW | Reconcile `lib/` gitlinks before packaging (Step 3.3); build offline; do not let forge auto-reset them. |
| **M-03** — last-admin lifecycle can brick self-call administration | MEDIUM | Per-account, post-deploy lifecycle caution — not a deploy step. Carry into monitoring; see `docs/delivery/EMERGENCY_PLAN.md`. |
| **M-04 / M-05** — owner-expiry uses `block.timestamp` in validation; built-in validators can revert / do unbounded proof work | MEDIUM | Bundler-compatibility / gas-griefing residual risk — monitoring item, no fund loss. See `docs/delivery/EMERGENCY_PLAN.md`. |
| **M-01** — non-canonical `SIG_VALIDATION_FAILED` packing | MEDIUM | Bundler-compatibility advisory; no fund loss; tracked, non-blocking. |

Carry M-01/M-03/M-04/M-05 into `docs/delivery/EMERGENCY_PLAN.md` as monitoring/residual-risk; M-02 / size / submodule are handled by the pre-deploy checklist above.

---

## 7. Deployment Order

Deterministic CREATE2 through the EIP-2470 Singleton Factory. `script/deploy.s.sol` (`DeployInit`) performs both steps in one `run()`.

| # | Contract | Constructor args | Deploy mechanism | Notes |
|---|----------|------------------|------------------|-------|
| 1 | **SmartWalletEntry** (UUPS account implementation; TWA inlined) | **none** | `IDeployFactory.deploy(type(SmartWalletEntry).creationCode, salt)` | Ownerless; `_disableInitializers()` in constructor. CREATE2-eligible (no msg.sender privilege). |
| 2 | **SmartWalletFactory** | `address _implementation` = the **SmartWalletEntry address from step 1** | `IDeployFactory.deploy(abi.encodePacked(type(SmartWalletFactory).creationCode, abi.encode(impl)), salt)` | Immutable `IMPLEMENTATION` set from the parameter; ownerless. CREATE2-eligible. |

Same salt for both; resulting addresses differ because the init code differs. For cross-chain identical addresses: identical init code (same compiler settings) + same salt + factory present. The CREATE fallback (reason `factory-unavailable`) applies only where EIP-2470 is absent — not expected on mainnet.

---

## 8. Real Deployment Command Templates (no secret values)

> The **active** command (Step 8) is the dry-run-safe simulation. The **live** template (Step 9) is intentionally commented — every line starts with `#`. Uncomment it only after every gate in Section 3 has passed. Never inline a private key or a literal RPC URL.

### Step 8 — Final simulation (dry-run-safe; ACTIVE)
- **Action:** simulate the deployment against the target RPC **without broadcasting**, re-confirming the script runs end-to-end (including its `IMPLEMENTATION()` assertion).
- **Command:**
  ```bash
  # $RPC_URL and the deploy env vars are exported in your shell (never written here).
  # Active command is simulation only (no broadcast/verify/key flags).
  FOUNDRY_OFFLINE=true forge script script/deploy.s.sol:DeployInit --rpc-url "$RPC_URL"
  ```
- **Expected:** simulation completes; logs print the Deployer address, the salt, the simulated `SmartWallet Implementation address`, the `SmartWalletFactory address`, `SmartWallet implementation address verified on SmartWalletFactory!`, and `DeployInit script completed successfully`.
- **STOP if:** the simulation reverts, the `IMPLEMENTATION()` assertion fails, or a predicted address is unexpected.
- **Evidence:** the full simulation log including both simulated addresses.

### Step 9 — Live broadcast (COMMENTED template — uncomment deliberately to deploy)
- **Action:** after all gates pass, broadcast. Uncomment exactly one template below in your own shell (do not edit this committed file to uncomment). The key is read from the `DEPLOYER_PRIVATE_KEY` env var by the script; do not pass it on the command line.

  ```bash
  # ===== UNCOMMENT TO BROADCAST (production deploy) =====
  # Preconditions: chainId 1 (Cancun), Section 3 fully passed, throwaway key replaced
  # with the real funded deployer key in $DEPLOYER_PRIVATE_KEY, salt + release id recorded.
  #
  # FOUNDRY_OFFLINE=true forge script script/deploy.s.sol:DeployInit \
  #   --rpc-url "$RPC_URL" \
  #   --broadcast
  #
  # ===== OPTIONAL: broadcast + explorer source verification =====
  # Provide the explorer API key via your shell env (e.g. $ETHERSCAN_API_KEY); do not inline it.
  #
  # FOUNDRY_OFFLINE=true forge script script/deploy.s.sol:DeployInit \
  #   --rpc-url "$RPC_URL" \
  #   --broadcast \
  #   --verify
  ```

- **Expected:** the script broadcasts both CREATE2 deployments via the EIP-2470 factory, prints the final implementation and factory addresses, and the `IMPLEMENTATION()` assertion holds. Transactions confirm on-chain.
- **STOP if:** a transaction reverts/fails to confirm, the `IMPLEMENTATION()` assertion fails, or a deployed address does not match the Step 8 / dry-run address.
- **Evidence:** the broadcast log, the `broadcast/` run artifacts, both on-chain addresses, the transaction hashes, the salt, `<COMMIT_SHA>` / `<RELEASE_ID>`.

---

## 9. Post-Deployment Verification Checklist

Run all checks against the **broadcast** addresses (all read-only). Replace `<SmartWalletEntry>` / `<SmartWalletFactory>` with the deployed addresses; `$RPC_URL` comes from your shell. You may instead run `script/VerifyDeployment.s.sol` (see `docs/delivery/DEPLOY_DRY_RUN.md` §6) to perform all of these at once.

### 9.1 — Factory points at the implementation
```bash
cast call <SmartWalletFactory> "IMPLEMENTATION()(address)" --rpc-url "$RPC_URL"
```
- **Expected:** equals the deployed `<SmartWalletEntry>` address. **STOP if** not. **Evidence:** command output.

### 9.2 — Both addresses have non-zero code
```bash
cast code <SmartWalletEntry>   --rpc-url "$RPC_URL"
cast code <SmartWalletFactory> --rpc-url "$RPC_URL"
```
- **Expected:** non-empty bytecode (not `0x`) for both; each equals its predicted CREATE2 address. **STOP if** either returns `0x` or differs from its predicted address. **Evidence:** both outputs + predicted-vs-actual comparison.

### 9.3 — TWA ERC-165 interface advertised
```bash
cast call <SmartWalletEntry> "supportsInterface(bytes4)(bool)" 0x86c5a9e1 --rpc-url "$RPC_URL"
```
- **Expected:** `true`. **STOP if** `false`. **Evidence:** command output.

### 9.4 — EntryPoint is the canonical v0.7 address
```bash
cast call <SmartWalletEntry> "entryPoint()(address)" --rpc-url "$RPC_URL"
```
- **Expected:** `0x0000000071727De22E5E9d8BAf0edAc6f37da032`. **STOP if** any other address. **Evidence:** command output.

### 9.5 — Storage layout: TWA namespace does not collide
```bash
forge inspect SmartWalletEntry storageLayout
```
- **Expected:** the TWA ERC-7201 namespace is distinct from the account custom-storage root `0x653ff6dc…`; no overlap (R-4). **STOP if** overlap. **Evidence:** the storage-layout output / archived diff.

### 9.6 — Bytecode size under EIP-170 (re-confirm)
```bash
FOUNDRY_OFFLINE=true forge build src script --sizes
```
- **Expected:** `SmartWalletEntry` runtime ≤ 24,576 B (24,510 B baseline, margin 66 B). **STOP if** over the limit. **Evidence:** `--sizes` output.

### 9.7 — Fork smoke (per dry-run plan)
- **Confirmation:** confirm the happy-path smoke from `docs/delivery/DEPLOY_DRY_RUN.md` (create an account via the factory, happy-path ERC-20 settle, replay-revert) was exercised on a fork. On mainnet this is validated via the fork dry-run (Step 3.8), not by moving production funds. **STOP if** any smoke assertion fails. **Evidence:** reference to the dry-run smoke log.

---

## 10. Emergency and Stop Conditions

**Halt deployment immediately** (do not broadcast; if already broadcasting, stop and assess) if **any** of the following occurs:

- The target chain is not Cancun-active or `chainId != 1` (Safety Rule 4 / DEP-6 — hard precondition).
- The production build fails, or `SmartWalletEntry` exceeds the EIP-170 24,576 B limit / grew beyond the 24,510 B baseline without an approved mitigation.
- `docs/delivery/DEPLOY_CHECK.md` records a failed secret/static check, or a secret value is detected in any artifact.
- The fork dry-run (`docs/delivery/DEPLOY_DRY_RUN.md`) fails any assertion.
- A required env var (`DEPLOYER_PRIVATE_KEY`, `DEPLOY_FACTORY_SALT`) is missing, or a non-throwaway key was used for the dry-run.
- The Step 8 simulation reverts or the `IMPLEMENTATION()` assertion fails.
- A broadcast transaction reverts/fails to confirm, or a deployed address diverges from the simulated/predicted CREATE2 address.
- Any post-deployment verification (Section 9) fails.

**Capability note:** these contracts have **no on-chain pause, kill-switch, or recovery mechanism** (DESIGN §13). There is no operator lever to halt a deployed account. Documented mitigations are per-account `cancel` of unused authorizations plus off-chain risk control. Do not assume an on-chain emergency stop exists.

**Residual risks to monitor post-deploy** (audit, non-blocking): M-03 (last-admin lifecycle can brick per-account self-administration), M-04 / M-05 (bundler-compatibility / validation gas-griefing), M-01 (non-canonical signature-failure packing). Carry these into the monitoring plan.

---

## 11. Emergency Plan Reference

For incident response, residual-risk monitoring (M-01 / M-03 / M-04 / M-05), the "no on-chain pause/recovery" capability statement, and the `cancel` + off-chain risk-control mitigation procedure, see **`docs/delivery/EMERGENCY_PLAN.md`**.

---

## 12. Manual Approval / Confirmation Records

Record each item before broadcasting. (Sign-offs filled in by the operator/approver at execution time.)

| Item | Recorded value | Confirmed by | Date |
|------|----------------|--------------|------|
| Audit Pipeline-stage Conclusion = PASS | PASS (WARN; 0 Critical/High) | | |
| DEV_REVIEW = APPROVED | APPROVED | | |
| Deployed commit `<COMMIT_SHA>` | | | |
| Release identifier `<RELEASE_ID>` | | | |
| `DEPLOY_FACTORY_SALT` (recorded, reproducible) | | | |
| chainId = 1, Cancun-active confirmed (Step 3.2) | | | |
| Production build + size (Step 3.5): 24,510 B / margin 66 B | | | |
| Secret & static checks PASS (`DEPLOY_CHECK.md`, Step 3.6) | | | |
| Fork dry-run PASS (`DEPLOY_DRY_RUN.md`, Step 3.8) | | | |
| `lib/` submodule drift reconciled (Step 3.3) | | | |
| `package.json` deploy-path reconciliation acknowledged (Step 3.4) | | | |
| Step 8 simulation PASS | | | |
| Authorization to broadcast (Step 9) | | | |
| Deployed `SmartWalletEntry` address | | | |
| Deployed `SmartWalletFactory` address | | | |
| Post-deploy verification (Section 9) all PASS | | | |

---

*End of DEPLOY_RUNBOOK.md. This runbook contains no secret values, no literal RPC URLs, and no private keys. The only broadcast/verify/private-key flag occurrences are on commented (`#`-prefixed) template lines in Step 9.*
