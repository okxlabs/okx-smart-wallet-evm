# Smart Wallet - EIP-4337 Account Abstraction Wallet

A modular and secure smart contract wallet implementation supporting EIP-4337 account abstraction with advanced security features and multiple validator types.

## Overview

This implementation provides a flexible smart contract wallet that supports:

- EIP-4337 Account Abstraction standard
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
   - Supports batch wallet creation

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

- `SmartWallet`: Main wallet contract inheriting all managers
- `OwnerManager`: Manages owner registration, settings, and permissions
- `NonceManager`: Handles nonce validation and management
- `ValidationManager`: Signature validation with multiple validator types
- `ExecutionManager`: Low-level call execution functionality
- `AllowanceManager`: Token allowance and spending controls
- `FallbackHandler`: Token receiving and standard interface support

## Usage

### Prepare environment

```bash
git submodule update --init --recursive
```

### Deploy

Deploy on XLayer Mainnet:
```bash
RPC_URL=https://rpc.xlayer.tech
forge script scripts/deploy/DeployInit.sol --rpc-url $RPC_URL --legacy --broadcast
```

Deploy and initialize 7702 wallet on local
```bash
# Start local blockchain node with 7702 support
anvil --hardfork prague
./initialise.sh
```

### 1. Deploy & Initialize Wallet

Deploy a new smart wallet using the factory:

```bash
npx hardhat run scripts/smoke_test/1-setCodeAndInitialize.ts --network <NETWORK>
```

This script:

- Creates a new wallet instance via SmartWalletFactory
- Initializes with initial owners and validators
- Sets up permissions and admin settings

### 2. Execute Direct Transactions

Send transactions directly from the wallet:

```bash
forge script scripts/smoke_test/2-sendTxs.sol --rpc-url <RPC_URL> --broadcast
```

This demonstrates:

- Self-executed transactions
- Batch call functionality
- Direct interaction with external contracts

### 3. Execute via Relayer

Send transactions through a relayer:

```bash
forge script scripts/smoke_test/3-sendTxsAsRelayer.sol --rpc-url <RPC_URL> --broadcast
```

This demonstrates:

- Off-chain signature generation with proper keyHash format
- Relayer-based transaction execution via `executeWithRelayer`
- Signature validation using registered validators
- Nonce management and replay protection
- Support for chain-agnostic signatures

## Security Considerations

- Multi-layered validation system with external validator support
- Comprehensive nonce management prevents replay attacks
- Admin privilege controls with expiration mechanisms
- Hook-based validation for additional security checks
- Owner permission system with granular access controls
- Built-in support for ECDSA and Passkey (WebAuthn) validation
- Upgradeable implementation with authorized upgrade controls
