# Smart Wallet Scripts

Scripts for deploying, simulating, and interacting with the Smart Wallet contracts.

## Directory Structure

```
script/
├── deploy/              # Deployment scripts
├── estimategas/         # Gas simulation contracts
└── sendTransaction/     # Transaction scripts
    ├── eip4337/         # EIP-4337 UserOperation mode
    ├── eip7702/         # EIP-7702 EOA delegation
    ├── relayerMode/     # Relayer (executeWithRelayer) mode
    └── utils/           # Shared utilities
```

## Local Testing

```shell
# Start local blockchain node with EIP-7702 support
anvil --hardfork prague

# (Optional) Deploy EIP-2470 Singleton Factory if not yet on chain
forge script script/deploy/DeploySingletonFactory.s.sol --rpc-url http://localhost:8545 --broadcast

# Set environment variables (see .env.example)
cp .env.example .env

# Deploy SmartWallet + SmartWalletFactory
forge script script/deploy/DeployInit.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy simulator contracts (for gas estimation)
forge script script/deploy/DeploySimulator.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Deploy Scripts (`deploy/`)

| File | Description |
|------|-------------|
| `DeployInit.s.sol` | Deploys `SmartWalletEntry` and `SmartWalletFactory` via Factory |
| `DeployInitHelper.s.sol` | Library helper used by `DeployInit` for deterministic deployment logic |
| `DeploySimulator.s.sol` | Deploys `SimulateECDSAValidator`, `SimulatePasskeyValidator`, and `SmartWalletSimulator` |
| `DeploySingletonFactory.s.sol` | Deploys the EIP-2470 Singleton Factory (only needed if not yet on chain) |
| `EIP2470.s.sol` | Library encapsulating EIP-2470 factory deployment via Nick's method |
| `IDeployFactory.s.sol` | Interface for the Factory `deploy()` function |

All deployments use the EIP-2470 Singleton Factory at `0xce0042B868300000d44A59004Da54A005ffdcf9f` for deterministic, cross-chain consistent addresses.

## Gas Estimation (`estimategas/`)

| File | Description |
|------|-------------|
| `SmartWalletSimulator.sol` | Inherits `SmartWallet`; simulates `executeWithRelayer` and reverts with gas metrics (`executionGas`, `intrinsicGas`, `totalGas`) |
| `ISmartWalletSimulator.sol` | Interface defining `simulateExecuteWithRelayer()` and `SimulateExecution` error |
| `SimulateECDSAValidator.sol` | Standalone ECDSA validator contract used by the simulator (mirrors on-chain validator logic) |
| `SimulatePasskeyValidator.sol` | Standalone Passkey/P256 validator contract used by the simulator |
| `CalculateCallDataGas.sol` | Library for computing intrinsic calldata gas (16 gas/non-zero byte, 4 gas/zero byte) |

## Send Transaction Scripts (`sendTransaction/`)

### EIP-4337 Mode (`eip4337/`)

Send transactions via `EntryPoint.handleOps()` as ERC-4337 UserOperations.

| File | Description |
|------|-------------|
| `SendUopWithECDSA.s.sol` | Forge script: build and submit a `PackedUserOperation` signed with ECDSA |
| `SendUopWithECDSA.ts` | Hardhat script: equivalent TypeScript version |
| `SendUopWithPasskey.s.sol` | Forge script: build and submit a `PackedUserOperation` signed with Passkey (P256) |
| `SendUopWithPasskey.ts` | Hardhat script: equivalent TypeScript version |

### Relayer Mode (`relayerMode/`)

Send transactions via `SmartWallet.executeWithRelayer()`, bypassing EntryPoint.

| File | Description |
|------|-------------|
| `SendWithECDSA.s.sol` | Forge script: call `executeWithRelayer` with ECDSA-signed `BatchedCall` |
| `SendWithECDSA.ts` | Hardhat script: equivalent TypeScript version |
| `SendWithPasskey.s.sol` | Forge script: call `executeWithRelayer` with Passkey-signed `BatchedCall` |
| `SendWithPasskey.ts` | Hardhat script: equivalent TypeScript version |

### EIP-7702 Mode (`eip7702/`)

| File | Description |
|------|-------------|
| `setCode.ts` | Sets EIP-7702 authorization on an EOA to delegate to the SmartWallet implementation |

### Utilities (`utils/`)

| File | Description |
|------|-------------|
| `Helper.sol` | Solidity library with shared helpers for Passkey signing, UserOp hashing, and Merkle proof construction |
| `EventTopics.s.sol` | Forge script that prints event topic selectors for all SmartWallet contract events |
| `userOp.ts` | TypeScript utilities for building and packing ERC-4337 `UserOperation` structs |
| `calldata.ts` | TypeScript utilities for encoding `Call` and `BatchedCall` calldata |
| `contracts.ts` | Contract instance factory helpers; reads addresses from environment variables |
| `passkeySign.ts` | P256/Passkey signing utility using `ec-pem` and Node.js `crypto` |

## Environment Variables

```shell
DEPLOYER_PRIVATE_KEY=     # Private key of the deployer/relayer
DEPLOY_FACTORY_SALT=      # bytes32 salt for deterministic deployment
SMART_WALLET_FACTORY=     # Deployed SmartWalletFactory address
SMART_WALLET=             # Deployed SmartWalletEntry implementation address
ENTRY_POINT=              # ERC-4337 EntryPoint address (default: v0.7)
PASSKEY_PRIVATE_KEY=               # Hex private key for Passkey signing (testing only)
```
