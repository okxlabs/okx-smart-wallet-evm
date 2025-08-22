# OKX Smart Wallet Scripts

This directory contains scripts migrated and adapted from the SmartAccount project to work with the OKX Smart Wallet architecture.

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

## Setup and Configuration

### Environment Variables

Before running the scripts, set up these environment variables in your `.env` file:

```bash
# Required contract addresses
SMART_WALLET_FACTORY=0x...          # SmartWalletFactory contract address
SMART_WALLET_IMPL=0x...             # SmartWallet implementation address
ECDSA_VALIDATOR=0x...               # ECDSAValidator contract address
PASSKEY_VALIDATOR=0x...             # PasskeyValidator contract address

# Optional
TEST_TOKEN=0x...                    # Test ERC20 token address
DEPLOYER_PRIVATE_KEY=0x...          # Your private key (for testing)
```

### Contract Deployment

Before using the scripts, ensure these contracts are deployed:

1. `SmartWallet` (implementation)
2. `SmartWalletFactory`
3. `ECDSAValidator`
4. `PasskeyValidator`
5. Test tokens (optional)

## Usage Examples

### Running the Send User Operation Script

```bash
# Set up environment variables first
export SMART_WALLET_FACTORY=0x...
export SMART_WALLET_IMPL=0x...
export ECDSA_VALIDATOR=0x...

# Run the script on a specific network
npx hardhat run scripts/sendUop.ts --network sepolia
```

### What the Script Does

The `sendUop.ts` script performs these operations:

1. **Setup Phase**
   - Loads contract instances
   - Creates initial owner configuration
   - Generates deterministic wallet address

2. **User Operation Creation**
   - Creates execution calls (ETH transfer example)
   - Generates initCode for wallet deployment (if needed)
   - Builds complete UserOperation structure

3. **Signature Generation**
   - Signs the UserOperation with ECDSA validator
   - Formats signature for OKX SmartWallet validation

4. **Output**
   - Displays complete UserOperation JSON
   - Shows gas estimates and transaction details

### Customizing Execution Calls

To modify what the User Operation executes, edit the calls array in `sendUop.ts`:

```typescript
const calls: Call[] = [
  // ETH transfer
  calldataUtils.generateTransferCalldata(
    recipientAddress,
    hre.ethers.parseEther("0.1")
  ),
  
  // ERC20 transfer
  calldataUtils.generateERC20TransferCalldata(
    tokenAddress,
    recipientAddress,
    ethers.parseUnits("100", 18)
  ),
  
  // ERC20 approval
  calldataUtils.generateERC20ApproveCalldata(
    tokenAddress,
    spenderAddress,
    ethers.MaxUint256
  )
];
```

## Utility Functions

### Contract Helpers (`utils/contracts.ts`)

```typescript
import { contracts } from "./utils/contracts";

// Get contract instances
const factory = await contracts.getSmartWalletFactory(signer);
const wallet = await contracts.getSmartWallet(address, signer);
const validator = await contracts.getECDSAValidator(signer);
```

### User Operation Utilities (`utils/userOp.ts`)

```typescript
import { userOpUtils } from "./utils/userOp";

// Create UserOperation
const userOp = userOpUtils.createUserOperation({
  sender: walletAddress,
  nonce: 0n,
  callData: executeCalldata,
  // ... other parameters
});

// Sign UserOperation
const signature = await userOpUtils.signUserOperationWithECDSA(
  userOp,
  signer,
  entryPointAddress,
  chainId
);
```

### Calldata Generation (`utils/calldata.ts`)

```typescript
import { calldataUtils } from "./utils/calldata";

// Generate initCode for wallet creation
const { sender, initCode } = await calldataUtils.generateInitCode(
  factoryAddress,
  implementationAddress,
  initialOwners,
  salt
);

// Create owner configurations
const ecdsaOwner = calldataUtils.createECDSAOwner(
  signerAddress,
  validatorAddress
);

const passkeyOwner = calldataUtils.createPasskeyOwner(
  pubKeyX,
  pubKeyY,
  validatorAddress
);
```

## Notes and Limitations

1. **Passkey Signing**: The Passkey signature generation in `userOp.ts` is currently a placeholder. For production use, implement proper Passkey/WebAuthn signing logic.

2. **Gas Estimation**: Gas limits are set to conservative defaults. You may want to implement dynamic gas estimation for production use.

3. **Error Handling**: The scripts include basic error handling. Consider adding more robust error handling for production applications.

4. **Network Configuration**: Ensure your `hardhat.config.ts` includes the networks you want to test on.

## Troubleshooting

### Common Issues

1. **"Contract not found" errors**
   - Ensure all environment variables are set
   - Verify contract addresses are correct for your network

2. **"Signature validation failed" errors**
   - Check that the correct validator is being used
   - Verify the keyHash generation matches the validator's expectations

3. **"Insufficient funds" errors**
   - Ensure the predicted wallet address has sufficient ETH for gas
   - For local testing, the script automatically funds accounts

### Getting Help

If you encounter issues:

1. Check that all contracts are deployed and addresses are correct
2. Verify your signer has sufficient funds
3. Review the console output for detailed error messages
4. Test on a local Hardhat network first before using testnets

## Migration Summary

This migration successfully adapts the SmartAccount `sendUop.ts` functionality to work with OKX Smart Wallet's architecture while maintaining the core User Operation flow. The modular utility structure makes it easy to extend and customize for different use cases.
