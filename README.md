# Unified Smart Wallet - Next-Generation Account Infrastructure

A modular and secure smart contract wallet implementation unifying EOA and smart contract accounts with support for multiple execution patterns and advanced security features.

## Overview

This implementation provides a flexible smart contract wallet that supports:

- EIP-4337 Account Abstraction standard
- EIP-7702 EOA-to-Smart Contract upgrade functionality
- Multiple execution methods (direct, relayer-based, UserOperation)
- Advanced validator system (ECDSA, Passkey, External validators)
- Modular architecture with managers and upgradeable proxy pattern
- Comprehensive permission system with admin controls

## Core Features

### 1. Factory Pattern Deployment

The wallet deployment uses a factory pattern:

1. **Smart Wallet Factory**:
   - Creates deterministic wallet addresses using CREATE2
   - Deploys proxy contracts pointing to implementation
   - Supports both direct factory calls and EIP-4337 EntryPoint initCode deployment
   - Supports batch wallet creation
   - Offers `createAccountWithCall` to deploy and execute initial transactions atomically

2. **Initialize Wallet**:
   - Calls the `initialize` function with initial owners
   - Sets up validator mappings and permissions
   - Configures admin settings and expiration rules

### 2. Execution Methods

#### Method 1: Direct Execution

- Direct execution from wallet owners
- Uses `execute(Call[] calls)` function
- Verifies caller is registered owner with valid permissions
- Supports batched transactions with hook validation
- Most gas-efficient for owner operations

#### Method 2: Relayer-Based Execution

1. **Signature-Based Authorization**:
   - Owner signs transaction data off-chain
   - Relayer submits via `executeWithRelayer`
   - Supports nonce management and expiry validation
   - Compatible with meta-transactions

2. **Validation Flow**:
   - Extract keyHash from validator data
   - Lookup registered validator for keyHash
   - Validate signature using appropriate validator
   - Execute calls if validation succeeds

#### Method 3: EIP-4337 UserOperation

- Full EIP-4337 Account Abstraction support
- Uses `executeUserOp` for EntryPoint integration
- Supports gas abstraction and paymaster integration
- Compatible with standard AA infrastructure

## Architecture
 
The implementation follows a modular manager-based design:

### Core Contracts
- `SmartWalletEntry`: Production implementation extending SmartWallet with custom ERC7201 storage layout
- `SmartWallet`: Base wallet contract inheriting all managers and core functionality
- `SmartWalletFactory`: Factory for deterministic wallet deployment using CREATE2
- `BaseAuthorization`: Access control foundation for self-executed functions

### Manager Modules
- `OwnerManager`: Owner registration, settings, and permissions
- `ValidationManager`: Signature validation with multiple validator types
- `ExecutionManager`: Low-level call execution and batched operations
- `NonceManager`: Nonce validation and replay protection
- `AllowanceManager`: Token allowance and spending controls
- `ERC4337Account`: EIP-4337 UserOperation support

### Supporting Components
- `FallbackHandler`: Token receiving and standard interface support
- `ERC712`: Structured data signing standard implementation
- `ERC7201`: Storage layout standard for upgradeable contracts

### Validators
- `ECDSAValidator`: Standard ECDSA signature validation
- `PasskeyValidator`: WebAuthn/Passkey validation support

### Libraries
- `BatchedCallLib`: Batched transaction execution
- `ChainlessLib`: Cross-chain signature validation
- `MerkleProofProcessor`: Merkle proof verification for multi-chain operations
- `MessageSignLib`: Message signing utilities
- `CallLib`: Low-level call helpers
- `DecodeLib`: Data decoding utilities

### Utility Tools
- `SmartWalletSimulator`: Gas estimation and simulation utility (located in scripts/utils/)

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

### Run Smoke Tests on local node

Execute the complete smoke test suite:

```bash
yarn smoke-test
```

This will run through all test scenarios including wallet deployment, initialization, direct execution, and relayer-based transactions.

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