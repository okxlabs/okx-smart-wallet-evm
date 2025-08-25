# OKX Smart Wallet Scripts

This directory contains scripts migrated and adapted from the SmartAccount project to work with the OKX Smart Wallet architecture.

## Local Testing

```shell
# Start local blockchain node with 7702 support
anvil --hardfork prague
# Deploy the DeployFactory contract
./scripts/smoke_test/deploy-factory.sh
# Check your .env file
# Deploy AA contracts
forge script scripts/DeployInit.sol --rpc-url http://localhost:8545 --broadcast
```

## Files Overview

### Core Scripts

- **`sendUop.ts`** - Main script for creating and sending User Operations (migrated from SmartAccount)
- **`utils/contracts.ts`** - Contract instance helper functions
- **`utils/userOp.ts`** - User Operation utilities and signature generation
- **`utils/calldata.ts`** - Calldata generation utilities for various operations

### Existing Scripts (Original OKX)

- **`smoke_test/1-setCodeAndInitialize.ts`** - EIP-7702 account setup script
- **`generatePasskeySignature.ts`** - P256 signature generation for Passkey validation
- **`validateP256Point.ts`** - P256 public key validation
- **`checkP256Values.ts`** - P256 signature verification

## Architecture Differences

The scripts have been adapted to work with OKX Smart Wallet's architecture, which differs from the original SmartAccount project:

### SmartAccount vs OKX Smart Wallet

| Aspect | SmartAccount | OKX Smart Wallet |
|--------|--------------|------------------|
| Main Contract | `PayableAccount` | `SmartWallet` |
| Factory Contract | `AccountFactory` | `SmartWalletFactory` |
| Architecture | ERC-7579 Modular | Composite Pattern |
| Validators | `WebAuthnAndECDSAValidator` | `ECDSAValidator` + `PasskeyValidator` |
| Initialization | Complex multi-param | Simple `InitialOwner[]` |

### Key Changes Made

1. **Contract Interface Changes**
   - `PayableAccount` → `SmartWallet`
   - `AccountFactory` → `SmartWalletFactory`
   - Simplified initialization parameters

2. **Validator Changes**
   - Split combined validator into separate ECDSA and Passkey validators
   - Updated signature format requirements

3. **Dependency Updates**
   - Removed SmartAccount-specific helper contracts
   - Updated import statements to match OKX project structure
   - Fixed ethers.js import patterns