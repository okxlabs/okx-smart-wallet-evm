# Unified Smart Wallet - Next-Generation Account Infrastructure

A modular and secure smart contract wallet implementation unifying EOA and smart contract accounts with support for multiple execution patterns and advanced security features.


## Overview

- **EIP-4337**: Full Account Abstraction via `EntryPoint.handleOps()`
- **EIP-7702**: EOA delegation to smart wallet implementation
- **Relayer mode**: `executeWithRelayer()` for gasless meta-transactions
- **Dual validators**: Built-in ECDSA and Passkey (WebAuthn/P256) validation
- **Modular managers**: Owners, nonces, allowances, execution, and validation as separate modules
- **UUPS upgradeable**: Authorized upgrade path via `UUPSUpgradeable`


## Architecture

### Core Contracts

| Contract | Description |
|----------|-------------|
| `SmartWalletEntry` | Production implementation; concrete contract with ERC-7201 custom storage layout |
| `SmartWallet` | Abstract base inheriting all manager modules and core execution logic |
| `SmartWalletFactory` | Deploys ERC-1967 proxy wallets at deterministic addresses via CREATE2 |
| `BaseAuthorization` | Access control base for self-executed (owner-only) functions |

### Manager Modules

| Module | Description |
|--------|-------------|
| `OwnerManager` | Owner registration, settings (admin flag, expiry, hook), and permission checks |
| `ValidationManager` | Signature dispatch to built-in or external validators |
| `ExecutionManager` | Low-level `Call` and `BatchedCall` execution |
| `NonceManager` | Nonce validation and replay protection |
| `AllowanceManager` | Persistent ETH and ERC-20 spending allowances |
| `ERC4337Account` | EIP-4337 `validateUserOp` and `executeUserOp` integration |

### Supporting Components

| Component | Description |
|-----------|-------------|
| `FallbackHandler` | ERC-1155/721 token receiving and ERC-165 interface support |
| `ERC712` | EIP-712 structured data signing |
| `ERC7201` | ERC-7201 storage namespace implementation |

### Built-in Validators

Validators are implemented as libraries and invoked via sentinel addresses defined in `Static.sol`:

| Sentinel Address | Validator | Library |
|-----------------|-----------|---------|
| `address(1)` | ECDSA | `ECDSAValidatorLib` |
| `address(2)` | Passkey (WebAuthn/P256) | `PasskeyValidatorLib` |

External validator contracts implementing `IValidator` are also supported for custom validation logic.

### Libraries

| Library | Description |
|---------|-------------|
| `ECDSAValidatorLib` | ECDSA signature recovery with optional Merkle proof |
| `PasskeyValidatorLib` | P256/WebAuthn signature verification with optional Merkle proof |
| `MerkleProofProcessor` | Merkle proof verification for cross-chain / multi-call signatures |
| `ChainlessLib` | Chain-agnostic (chainless) hash computation |
| `BatchedCallLib` | Encoding and hashing of `BatchedCall` structs |
| `CallLib` | Low-level `Call` struct helpers |
| `MessageSignLib` | Personal message signing utilities |
| `DecodeLib` | Calldata decoding helpers |
| `Static` | Shared sentinel addresses and constants |

## Usage

### Prepare environment

Requirements:
- Node.js (v18 or higher)
- npm or yarn package manager
- Foundry toolkit for Solidity development

Setup:
```bash
git submodule update --init --recursive
npm install  # or yarn install
```

### Testing

Run the test suite with Foundry:
```bash
forge test
```

For detailed test output:
```bash
forge test -vvvv
```
This will run through all test scenarios including wallet deployment, initialization, direct execution, and relayer-based transactions.


## Deployment

| Constract | address |
|---------|-------------|
| SmartWalletFactory | 0xDd3FEa01cD550C9EFfC893f346690b9A649f35EF |
| SmartWalletEntry | 0xe40ccB2D94975c51bff0C004eFDfd9B3a5796fA4 |


## Security Considerations

- Multi-layered validation system with external validator support
- Built-in support for ECDSA and Passkey (WebAuthn) validation
- Cross-chain replay protection with Merkle proof signatures
- Comprehensive nonce management prevents replay attacks
- Admin privilege controls with expiration mechanisms
- Hook-based validation for additional security checks
- Owner permission system with granular access controls
- Upgradeable implementation with authorized upgrade controls

## Documentation

This README provides a high-level overview and quick start guide. For detailed technical documentation, implementation specifics, and usage patterns, see the [Technical Documentation](./documents/README.md) folder.