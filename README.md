# Wallet Core - EIP-7702 Smart Contract Wallet

A modular and secure implementation of EIP-7702 smart contract wallet with multiple execution types and advanced security features.

## Overview

This implementation provides a flexible smart contract wallet that supports:

- EIP-7702 Type 4 initialization
- Three distinct execution types
- Advanced security features including replay protection and batched transactions
- Modular architecture with separate storage and execution logic

## Core Features

### 1. Set Code & Initialize

The wallet setup involves two main steps:

1. **Set Code**:

   - Submits an EIP-7702 Type 4 transaction
   - Assigns smart contract code to an EOA (Externally Owned Address)
   - Transforms the EOA into a smart contract wallet

2. **Initialize Contract**:
   - Calls the `initialize` function in Wallet Core
   - Sets up proper configuration and state
   - Creates and links Core Storage for nonce management

### 2. Execution Types

#### Type 1: Execute From Self

- Direct execution from the wallet itself
- Uses `executeFromSelf` function
- Verifies transaction through self-check
- Supports batched transactions via `_batchCall`
- Most gas-efficient execution type

#### Type 2: Execute From Relayer

1. **Validator Setup**:
   - User adds validator to wallet core
   - Validator signs transaction off-chain with nonce
2. **Execution Flow**:
   - User provides off-chain signature
   - Relayer submits transaction via `executeWithValidation`
   - Core Storage manages nonce for replay protection
   - ECDSA validation ensures signature authenticity

#### Type 3: Execute From Executor

1. **Session-Based Execution**:

   - No pre-encoded calls needed
   - Uses hook-based validation (`preHook` and `postHook`)
   - Single signature authorizes entire session

2. **Session Parameters**:
   - `session_id`
   - `validAfter`
   - `validUntil`
   - `executor`
   - `validator`
   - `preCheck`
   - `postCheck`
   - `signature`

## Architecture

The implementation follows a modular design:

- `WalletCore`: Main contract handling execution logic
- `Core Storage`: Manages nonces and validation states
- `ExecutionLogic`: Handles different execution types
- `ValidationLogic`: Manages signature and session validation
- `ExecutorLogic`: Implements session-based execution with hooks
- `FallbackHandler`: Provides token receiving capabilities

## Deployed Contracts

### Ethereum Mainnet

| Contract    | Address                                      |
| ----------- | -------------------------------------------- |
| WalletCore  | `0x80296FF8D1ED46f8e3C7992664D13B833504c2Bb` |
| CoreStorage | `0x7DAF91DFe55FcAb363416A6E3bceb3Da34ff1d30` |

### Sepolia Testnet

| Contract    | Address                                      |
| ----------- | -------------------------------------------- |
| WalletCore  | `0x80296FF8D1ED46f8e3C7992664D13B833504c2Bb` |
| CoreStorage | `0x7DAF91DFe55FcAb363416A6E3bceb3Da34ff1d30` |

## Usage

### 1. Set Code & Initialize Wallet

Deploy and initialize your ERC-7702 wallet:

```bash
npx hardhat run scripts/smoke_test/1-setCodeAndInitialize.ts --network <NETWORK>
```

This script:

- Sets up the EOA as a smart contract wallet
- Initializes core storage and configuration

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

This shows:

- Relayer-based transaction execution
- Signature validation
- Nonce management
- Gas-efficient transaction batching

## Security Considerations

- All execution types include proper validation
- Nonce management prevents replay attacks
- Session-based execution can be revoked
- Hook-based validation provides additional security layers
