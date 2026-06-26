# DEPLOY_DRY_RUN.md — Fork Dry-Run Plan (Pre-Deployment Test Checklist)

> Operator-runnable plan to validate the deployment logic on a mainnet fork **without broadcasting**, before any real deployment. Stage 9 produces this plan; the **operator runs it locally**. It uses NO real deployer secret, sends NO transaction to a public network, and performs NO live explorer verification.

## Dry-Run Status: DEFERRED

- **In-stage execution:** not performed. No fork RPC was configured for this stage — `FORK_RPC_URL` and `MAINNET_RPC_URL` are unset and the Oli Run Config carries no fork-RPC field — so there was nothing to probe or run. This is `PASS`-compatible: the stage status does not depend on the dry-run.
- **Operator action:** run this plan against a fork of the target chain before deploying. Record the outcome (PASS / FAILED) in your deployment log alongside `DEPLOY_CHECK.md`.

Status values for this document: `PASS` (ran and succeeded) · `FAILED` (ran and reverted/errored) · `SKIPPED` (RPC configured but unreachable) · `DEFERRED` (no fork RPC configured — this run).

---

## 1. What this dry-run validates

A simulated end-to-end execution of `script/deploy.s.sol` (`DeployInit`) against a fork, confirming:

- Deployment **order**: `SmartWalletEntry` (implementation) → `SmartWalletFactory(implementation)`.
- **CREATE2 via the EIP-2470 Singleton Factory** path (or, on a fork without the factory, the plain-CREATE fallback) executes and returns non-zero code.
- The deterministic **predicted CREATE2 address equals the actual** deployed address (when the factory is present).
- **Wiring**: `SmartWalletFactory.IMPLEMENTATION()` equals the deployed `SmartWalletEntry` address.
- **Dependency wiring**: the implementation's `entryPoint()` equals the canonical ERC-4337 v0.7 EntryPoint.
- **Ownerless safety**: neither deployed contract is owned by, or equal to, the singleton factory (asserted by construction — no owner/admin setter exists).
- **Interface**: `SmartWalletEntry.supportsInterface(0x86c5a9e1)` is `true`.
- (Optional, recommended smoke) creating an account via the factory, a happy-path ERC-20 settle, and a replay-revert (DESIGN §14 smoke).

The dry-run does NOT change any production state and does NOT broadcast.

---

## 2. Target chain the fork must match

| Field | Value |
|-------|-------|
| Chain | Ethereum mainnet |
| Chain ID | **1** |
| EVM | **Cancun** (EIP-1153 transient storage) — REQUIRED. A non-Cancun fork cannot exercise the TWA native-reentrancy transient lock; do not use one. |

The fork must be of a chain where both the EIP-2470 Singleton Factory (`0xce0042B868300000d44A59004Da54A005ffdcf9f`) and the ERC-4337 v0.7 EntryPoint (`0x0000000071727De22E5E9d8BAf0edAc6f37da032`) exist (they do on Ethereum mainnet). A standard mainnet fork inherits both.

---

## 3. Environment the operator supplies

Export these in your shell before running (never write them into a committed file):

| Variable | Purpose | Dry-run value |
|----------|---------|---------------|
| `FORK_RPC_URL` | RPC endpoint of a fork (or archive node) of the target chain. Supplied only via your environment; never inlined or committed. | your fork/archive endpoint |
| `DEPLOYER_PRIVATE_KEY` | Read by the script via `vm.envUint`. For a dry-run use a **throwaway** key with no funds and no privileges — it only derives a simulated sender; nothing is broadcast. | a throwaway test key (do NOT use a real deployer key) |
| `DEPLOY_FACTORY_SALT` | Read by the script via `vm.envBytes32`. Any `bytes32` for the dry-run; use the value you intend for production to also validate the predicted addresses. | a `bytes32` salt |

The resolved `FORK_RPC_URL` may embed a secret key — keep it only in the environment variable, never print it, and never commit it. If a command echoes it, redact it.

---

## 4. The dry-run command (exact, operator-provided RPC, no broadcast)

Run from the project root (`okx-smart-wallet-dev/`):

```bash
# Build offline first so forge does not auto-reset lib/ submodules (scoped production build).
FOUNDRY_OFFLINE=true forge build src script

# Fork dry-run — NO --broadcast, NO --verify, NO private-key flag. Simulation only.
forge script script/deploy.s.sol:DeployInit --rpc-url "$FORK_RPC_URL"
```

Do NOT add the broadcast flag, the verify flag, or any private-key flag to this command. If you want a transaction-by-transaction simulation trace, add `-vvvv` (verbosity only).

---

## 5. Expected outputs

The script prints (addresses are fork-simulated):

- `Deployer: <address derived from the throwaway key>`
- `Deploy factory salt:` followed by the `bytes32` salt.
- `Singleton factory present on chain: true` (on a mainnet fork).
- For each contract: `method: create2 (EIP-2470 singleton factory)`, the `predicted address`, and `deployed at:` — predicted and deployed must be equal.
- `SmartWallet implementation address verified on SmartWalletFactory!`
- A `=== Deployment Summary ===` block with the `SmartWallet Implementation address` and `SmartWalletFactory address`.
- `DeployInit script completed successfully`.

If the fork lacks the EIP-2470 factory, the log instead shows `method: create (fallback, reason=factory-unavailable)` and the addresses are not deterministic — acceptable on such a fork, but the target chain (mainnet) has the factory.

---

## 6. Read-only post-deploy checks (run against the simulated/forked addresses)

Optionally run the read-only verification script against the same fork (no broadcast, no key needed for view calls):

```bash
SMART_WALLET=<implementation-address> \
SMART_WALLET_FACTORY=<factory-address> \
EXPECTED_CHAIN_ID=1 \
forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url "$FORK_RPC_URL"
```

It asserts: both addresses have code; factory `IMPLEMENTATION()` == implementation; implementation self-reference matches; `entryPoint()` == `0x0000000071727De22E5E9d8BAf0edAc6f37da032`; `supportsInterface(0x86c5a9e1)` == true; neither address equals the singleton factory; chain id == 1.

Recommended additional smoke (optional, exercises the feature on the fork): create an account via `SmartWalletFactory.createAccount(...)`, perform a happy-path ERC-20 `executeTransferWithAuthorization`, then attempt a replay and confirm it reverts `AuthorizationAlreadyUsed`. Confirm `forge inspect SmartWalletEntry storageLayout` shows the TWA ERC-7201 namespace distinct from the account custom-storage root `0x653ff6dc…`.

---

## 7. Operator pass/fail criteria and stop conditions

**PASS** when all of the following hold:
- The script completes and prints `DeployInit script completed successfully`.
- For each contract on a factory-present fork, `predicted address == deployed at` and the address has non-zero code.
- `SmartWalletFactory.IMPLEMENTATION()` equals the deployed `SmartWalletEntry` address (the in-script assertion did not revert).
- `entryPoint()` == the canonical v0.7 EntryPoint and `supportsInterface(0x86c5a9e1)` == true.

**FAILED / STOP** if any of the following occur (do not proceed to real deployment until resolved):
- The script reverts, or the in-script `Factory implementation mismatch` / EntryPoint / interface assertion fires.
- A predicted CREATE2 address does not equal the actual deployed address.
- `cast chain-id --rpc-url "$FORK_RPC_URL"` does not return `1`, or the fork is not Cancun-active.
- Either deployed address has empty code, or collides with the singleton factory address.

When recording a failure, record only the **error category** (e.g. `script reverted`, `chain-id mismatch`, `address mismatch`, `transport error`) — never raw `forge`/`cast` output that may echo the RPC URL or key.

---

## 8. Safety constraints (always)

- Never add `--broadcast`, `--verify`, or any private-key CLI flag to the dry-run.
- Never use a real deployer key, mnemonic, or production secret. Use a throwaway key for simulation only.
- Never print or commit the resolved `FORK_RPC_URL`; redact it (`<fork RPC redacted>`) in any shared log.
- This dry-run never sends a transaction to a public network and never performs live explorer verification.
