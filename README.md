# OKX Smart Wallet - Next Generation Account Infrastructure

A modular and secure smart contract wallet implementation unifying EOA and smart contract accounts with support for multiple execution patterns and advanced security features.

## Overview

- **EIP-4337 v0.7**: Account Abstraction via `EntryPoint.handleOps()`
- **EIP-7702**: EOA delegation to smart wallet implementation
- **Relayer mode**: `executeWithRelayer()` for gasless meta-transactions
- **Built-in validators**: ECDSA and Passkey (WebAuthn/P256), with support for external validators
- **Authorized transfers**: EIP-712 native ETH and ERC-20 settlement via `TransferWithAuthorization`
- **Modular managers**: Owners, nonces, allowances, execution, and validation as separate modules
- **UUPS upgradeable**: Authorized upgrade path via `UUPSUpgradeable`

## Architecture

### Core Contracts

| Contract             | Description                                                                      |
| -------------------- | -------------------------------------------------------------------------------- |
| `SmartWalletEntry`   | Production implementation; concrete contract with ERC-7201 custom storage layout |
| `SmartWallet`        | Abstract base inheriting all manager modules and core execution logic            |
| `SmartWalletFactory` | Deploys ERC-1967 proxy wallets at deterministic addresses via CREATE2            |
| `BaseAuthorization`  | `onlySelf` authorization and factory-bound initialization guards                 |

### Manager Modules

| Module              | Description                                                                     |
| ------------------- | ------------------------------------------------------------------------------- |
| `OwnerManager`      | Owner registration, settings (admin flag, expiry, hook), and permission checks  |
| `ValidationManager` | Signature dispatch to built-in or external validators                           |
| `ExecutionManager`  | Low-level execution of a single `Call` and bounded revert-data forwarding       |
| `NonceManager`      | Relayer nonce validation and per-operation-type chainless queue floors          |
| `AllowanceManager`  | Persistent native ETH and ERC-20 spending allowances                            |
| `ERC4337Account`    | EntryPoint access control, prefunding, and chainless UserOperation hash helpers |

### Supporting Components

| Component                   | Description                                                          |
| --------------------------- | -------------------------------------------------------------------- |
| `TransferWithAuthorization` | Signature-authorized native ETH and ERC-20 settlement and revocation |
| `FallbackHandler`           | ERC-721/ERC-1155 token receiving and ERC-165 interface support       |
| `ERC712`                    | EIP-712 domain and typed-data hashing                                |
| `ERC7201`                   | ERC-7201 namespace and storage-root metadata                         |

### Built-in Validators

Validators are implemented as libraries and invoked via sentinel addresses defined in `Static.sol`:

| Sentinel Address | Validator               | Library               |
| ---------------- | ----------------------- | --------------------- |
| `address(1)`     | ECDSA                   | `ECDSAValidatorLib`   |
| `address(2)`     | Passkey (WebAuthn/P256) | `PasskeyValidatorLib` |

External validator contracts implementing `IValidator` are also supported for custom validation logic.

### Chainless Transactions

Chainless transactions omit the chain ID from the signed hash, allowing the same signed operation to be submitted on multiple chains. They are supported by both ERC-4337 `UserOperation` execution and `executeWithRelayer()`.

Cross-chain submission requires compatible wallet addresses, implementations, owner configuration, nonce sequences, and queue state on every target chain.

The packed nonce uses the following layout:

```text
[chainless prefix: 160 bits][operation type: 16 bits][queue ID: 16 bits][sequence: 64 bits]
```

It can be constructed as:

```solidity
uint256 nonce =
    (Static.CHAINLESS_NONCE_KEY << 96) |
    (uint256(operationType) << 80) |
    (uint256(queueId) << 64) |
    sequence;
```

- `operationType` selects an independent queue namespace. The recommended convention is `0` for `addOwner` and `1` for `upgradeToAndCall`; this mapping is not enforced on-chain.
- `queueId` controls invalidation within one operation type. The initial queue floor is `0`. Once queue `N` is accepted, every queue ID less than or equal to `N` becomes invalid for that operation type, while other operation types remain unaffected.
- `sequence` is the standard 64-bit nonce sequence managed by the EntryPoint in ERC-4337 mode or by the wallet nonce manager in relayer mode.
- Chainless calls must be admin-authorized self-calls, and currently only `addOwner` and `upgradeToAndCall` selectors are allowed.

Use `getChainlessQueueState(operationType)` to read the current queue floor before constructing a transaction. A floor below `65535` is the next minimum usable queue ID. Queue ID `65535` is reserved and rejected, so the maximum usable queue ID is `65534`; a floor of `65535` means that operation type is exhausted.

### TransferWithAuthorization

`TransferWithAuthorization` allows a registered owner to sign an implementation-bound transfer authorization off-chain and lets a relayer or payee submit it on-chain. The signed data binds the signing owner key, token, wallet, recipient, amount, validity window, a random single-use `authorizationNonce`, and the current wallet implementation. Use `Static.NATIVE_ETH` for native ETH or the token contract address for an ERC-20 transfer.

The execute/receive signature envelope is:

```text
[keyHash: 32 bytes][owner validator signature]
```

| Function                           | Usage                                                                                                      |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `executeTransferWithAuthorization` | Permissionless settlement; any relayer may submit the signed authorization.                                |
| `receiveWithAuthorization`         | Payee-submitted settlement; `msg.sender` must equal the signed recipient.                                  |
| `cancelTransferAuthorization`      | Takes `(targetKeyHash, authorizationNonce, signature)`; the target owner or a valid admin may sign.        |
| `transferAuthorizationState`       | Takes `(ownerKeyHash, authorizationNonce)` and returns whether that owner's nonce was settled or canceled. |

An authorization is valid only when `block.timestamp > validAfter` and `block.timestamp < validBefore`. Nonces are tracked by `authorizationStates[ownerKeyHash][authorizationNonce]`: different owners may independently use the same nonce, but execute, receive and cancel share one terminal state for a given owner/nonce pair. Removing and re-adding the same owner key does not reset its nonce state. This intentionally differs from ERC-8335's account-wide, single-use nonce semantics; this interface is not a drop-in ERC-8335 implementation. The account's EIP-712 domain binds authorizations to the wallet and current chain.

All three signed paths bind the implementation outside the existing authorization type hashes:

```solidity
bytes32 boundHash =
    keccak256(abi.encode(structHash, signerKeyHash, wallet.IMPLEMENTATION()));
bytes32 digest = wallet.hashTypedData(boundHash);
```

Sign the resulting `digest` using the owner's validator-specific signing scheme. Calling `signTypedData` on the original authorization fields alone does not produce this digest; do not add a `personal_sign` prefix or ERC-1271 message wrapper. Clients using the implementation-only `abi.encode(structHash, IMPLEMENTATION)` formula must add `signerKeyHash` and re-sign. The execute/receive envelopes are unchanged. Cancellation takes an explicit target key, and the state getter and both authorization events include the owner key.

The signing `keyHash` is present in both the envelope and the digest. It selects validator routing, nonce lookup, and the signing owner's settings while preventing a relayer from rerouting an unchanged validator signature to another owner's nonce namespace or spending-policy hook.

Cancellation uses `cancelTransferAuthorization(bytes32 targetKeyHash, bytes32 authorizationNonce, bytes signature)`:

```text
Signed:    [signerKeyHash: 32 bytes][validator signature]
Self-call: empty signature (0 bytes)
```

For signed cancellation, use the EIP-712 type `CancelTransferAuthorization(bytes32 targetKeyHash,bytes32 authorizationNonce)` and compute `structHash = keccak256(abi.encode(CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH, targetKeyHash, authorizationNonce))` before applying the implementation-binding digest formula above. Signing `targetKeyHash` prevents a relay from switching the owner being canceled. A non-admin may cancel only its own nonce; an unexpired admin may cancel a nonce for any owner (including a removed owner). An empty signature requires `msg.sender == address(this)` and must pass the wallet's admin-authorized self-call execution path.

Changing to a different implementation invalidates pending signatures bound to the previous implementation; used and canceled owner-scoped nonces remain terminal across upgrades that preserve the current storage layout.

If the signing owner has a spending-policy hook, the hook must advertise `IHookTransferAuthorization` through ERC-165. Settlement fails closed when the configured hook is incompatible or rejects the transfer.

### Libraries

| Library               | Description                                                                     |
| --------------------- | ------------------------------------------------------------------------------- |
| `ECDSAValidatorLib`   | ECDSA signature recovery with optional Merkle proofs                            |
| `PasskeyValidatorLib` | P256/WebAuthn signature verification with optional Merkle proofs                |
| `HookLib`             | ERC-165 checks and hook dispatch for execution, TWA, and ERC-1271               |
| `ChainlessLib`        | Chainless nonce parsing, selector allowlisting, and self-call validation        |
| `BatchedCallLib`      | EIP-712 struct hashing for `BatchedCall`                                        |
| `CallLib`             | EIP-712-style hashing for individual calls and call arrays                      |
| `MessageSignLib`      | EIP-712 struct hashing for ERC-1271 wallet messages                             |
| `DecodeLib`           | Decoding of call arrays and signature envelope components                       |
| `Static`              | Shared validator sentinels, nonce prefix, return values, and protocol constants |

## Deployments & Audits

> Ethereum / X Layer / Base / Optimism / Arbitrum / BSC / Polygon

The addresses below are the documented deterministic deployments. Verify the deployed runtime bytecode on the target network before production use.

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| `SmartWalletFactory` | `0xDd3FEa01cD550C9EFfC893f346690b9A649f35EF` |
| `SmartWalletEntry`   | `0xe40ccB2D94975c51bff0C004eFDfd9B3a5796fA4` |

- [Audits](./docs/audits/)

## Usage

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) — Solidity development toolkit
- Node.js v18+ and `yarn`

### Setup

```bash
git submodule update --init --recursive
yarn install
```

### Build

```bash
yarn build
# or: forge build src script
```

### Test

```bash
# Run full test suite
forge test

# Verbose output
forge test -vvvv

# Coverage report
yarn coverage
```

### Deploy

```bash
# Set DEPLOYER_PRIVATE_KEY and a 32-byte DEPLOY_FACTORY_SALT first.

# Dry-run and verify the deployment flow.
forge script script/deploy.s.sol:DeployInit --rpc-url <RPC_URL>

# Broadcast the deployment.
forge script script/deploy.s.sol:DeployInit --rpc-url <RPC_URL> --broadcast
```

## Security Considerations

- Signatures are routed by `keyHash`, decoupling owner identifiers from validator implementations.
- Standard relayer, ERC-4337, and TWA hashes are chain-bound; chainless operations deliberately omit the chain ID and are restricted to admin-authorized, allowlisted self-calls with independent queue invalidation.
- ERC-4337 sequences, relayer nonces, chainless queue floors, and TWA authorization nonces provide replay protection for their respective execution paths.
- Owner settings support administrator privileges, expiration, and spending-policy hooks.
- TWA and ERC-1271 hook paths fail closed when a configured hook is incompatible or rejects an operation.
- ERC-7201 namespacing isolates wallet and TWA storage across upgrades.
- UUPS upgrades require a wallet self-call, which is permitted only through an authorized admin execution path.

## Documentation

This README provides a high-level overview and quick start guide. For detailed technical documentation, implementation specifics, and usage patterns, see the [Technical Documentation](./docs/README.md) folder.
