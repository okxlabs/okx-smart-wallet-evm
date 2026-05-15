# Smart Contracts

## Overview

The Smart Wallet system consists of several core smart contracts that work together to provide a Account Abstraction solution. This document provides detailed information about each contract's structure, functionality, relationships, and integration patterns.

## Contract Architecture

### Core Contracts

1. **[SmartWallet](#1-smartwallet)**: Main wallet implementation (abstract base contract)
2. **[SmartWalletFactory](#2-smartwalletfactory)**: Account creation and deployment
3. **[SmartWalletEntry](#3-smartwalletentry)**: Production implementation with ERC7201 storage
4. **[OwnerManager](#4-ownermanager)**: Multi-owner management system with admin permissions
5. **[NonceManager](#5-noncemanger)**: Nonce validation and management
6. **[ValidationManager](#6-validationmanager)**: Authentication and signature validation
7. **[AllowanceManager](#7-allowancemanager)**: Token allowance management
8. **[FallbackHandler](#8-fallbackhandler)**: Token receiving and standard interface support

### Utility Tools

1. **[SmartWalletSimulator](#smartwalletsimulator)**: Gas estimation utility (located in scripts/utils/)

## Contract Details

### 1. SmartWallet

The main smart contract wallet that implements the core functionality.

#### Interface
```solidity
interface ISmartWallet is IERC165 {
    /// @notice Initialize wallet with initial owners
    /// @param initialOwners Array of initial owners with their validators
    function initialize(InitialOwner[] calldata initialOwners) external;

    /// @notice Execute multiple contract calls in a single transaction
    /// @param calls Array of Call structs containing destination address, value, and calldata
    function execute(Call[] calldata calls) external;

    /// @notice Execute calls through a relayer with signature validation
    /// @param batchedCall BatchedCall struct containing calls and nonce
    /// @param validatorData Encoded validation data (keyHash + validUntil + signature + merkle proofs)
    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external;

    /// @notice EIP-1271 signature validation
    /// @param hash The hash of the data to be validated
    /// @param signature The signature to be validated
    /// @return The magic value if signature is valid
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);

    /// @notice Get the implementation address
    /// @return The implementation contract address
    function IMPLEMENTATION() external view returns (address);

    /// @notice Delegate execution to external contracts (e.g., simulator)
    /// @param target The target contract address
    /// @param data The calldata to send to the target
    function delegateAndRevert(address target, bytes calldata data) external;
}
```

#### Key Functions

**Initialization:**
- `initialize(initialOwners[])`: Initialize wallet with initial owners and their validators

**Execution Modes:**
- `execute(calls[])`: Direct execution (owner only), supports EIP-7702 delegation
- `executeWithRelayer(batchedCall, validatorData)`: Relayer execution with signature validation
- `executeUserOp(userOp, userOpHash)`: ERC-4337 compatible execution (EntryPoint only)

**Utilities:**
- `isValidSignature(hash, signature)`: EIP-1271 signature validation
- `delegateAndRevert(target, data)`: Delegate execution to external contracts but reverts (e.g., simulator)
- `IMPLEMENTATION()`: Get the implementation contract address

#### Execution Modes

The SmartWallet implements three execution modes:

##### 1. Direct Execution
- **Function**: `execute(Call[] calldata calls)`
- **Access**: Owner only
- **Use case**: Direct contract calls, supports EIP-7702 delegation
- **Gas**: User pays directly

##### 2. Relayer Execution  
- **Function**: `executeWithRelayer(BatchedCall calldata batchedCall, bytes calldata validatorData)`
- **Access**: Anyone (with valid signature)
- **Use case**: Gasless transactions via relayer
- **Gas**: Relayer pays, user provides signature
- **Validator Data**: See [Validator Data Variations](#validator-data-variations) section

##### 3. ERC-4337 Execution
- **Function**: `executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)`
- **Access**: EntryPoint only
- **Use case**: ERC-4337 standard compliance
- **Gas**: Handled by EntryPoint infrastructure


## Data Structures
```solidity
struct Call {
    address target;    // Contract to call (address(0) = self)
    uint256 value;     // ETH amount to send
    bytes data;        // Calldata
}

struct BatchedCall {
    Call[] calls;      // Array of calls
    uint256 nonce;     // Nonce for ordering
}

// For 4337 compatability
struct PackedUserOperation {
    address sender;                // Account address
    uint256 nonce;                 // Nonce value
    bytes initCode;                // Contract initialization code
    bytes callData;                // Execution calldata
    bytes32 accountGasLimits;      // Gas limits for account
    uint256 preVerificationGas;    // Pre-verification gas
    bytes32 gasFees;               // Gas fee information
    bytes paymasterAndData;        // Paymaster data
    bytes signature;                // User operation signature
}
```
### 2. SmartWalletFactory

Responsible for creating and deploying new smart wallet instances.

#### Interface
```solidity
interface ISmartWalletFactory {
    /// @notice Create smart account with owners and validators
    /// @param initialOwners Array of initial owners with their validators
    /// @param salt Salt for deterministic address generation
    /// @return account The deployed smart wallet address
    function createAccount(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external payable returns (address account);

    /// @notice Create smart account and execute initial calls
    /// @param initialOwners Array of initial owners with their validators
    /// @param salt Salt for deterministic address generation
    /// @param batchedCall BatchedCall struct containing calls and nonce
    /// @param validatorData Encoded validation data for the initial calls
    /// @return account The deployed smart wallet address
    function createAccountWithCall(
        InitialOwner[] calldata initialOwners,
        uint256 salt,
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external payable returns (address account);

    /// @notice Predict deterministic address for given parameters
    /// @param initialOwners Array of initial owners with their validators
    /// @param salt Salt for deterministic address generation
    /// @return The predicted smart wallet address
    function getAddress(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address);
}
```

#### Key Functions

**Account Creation:**
- `createAccount(initialOwners[], salt)`: Deploy new wallet with initial owners
- `createAccountWithCall(initialOwners[], salt, batchedCall, validatorData)`: Deploy and execute initial calls

**Address Prediction:**
- `getAddress(initialOwners[], salt)`: Predict deterministic wallet address before deployment

#### InitialOwner Structure
```solidity
struct InitialOwner {
    bytes32 keyHash;      // Public key hash
    address validator;     // Validator contract address
}
```

### 3. SmartWalletEntry

The production implementation of SmartWallet with custom ERC7201 storage layout.

#### Overview
- **Purpose**: Production-ready wallet implementation
- **Inheritance**: Extends SmartWallet abstract contract  
- **Storage**: Uses ERC7201 standard for upgradeable storage layout
- **Deployment**: This is the actual implementation deployed by SmartWalletFactory

#### Key Features
- Inherits all functionality from SmartWallet base contract
- Implements custom storage layout following ERC7201 standard
- Provides upgrade safety through storage slot separation
- Production-optimized with gas efficiency considerations
- Main entry point for all wallet operations in production

#### Implementation Note
```solidity
// SmartWalletEntry extends SmartWallet with production storage layout
contract SmartWalletEntry is SmartWallet {
    // Uses ERC7201 storage pattern for upgradeability
    // All functionality inherited from SmartWallet abstract contract
}
```

### 4. OwnerManager

Manages multiple owners with flexible permission settings.

#### Interface
```solidity
interface IOwnerManager {
    // Public mappings (auto-generated getters)
    /// @notice Get the validator address for a given keyHash
    /// @param keyHash The public key hash to query
    /// @return The validator address for this owner
    function ownerValidators(bytes32 keyHash) external view returns (address);
    
    /// @notice Get the packed settings for a given keyHash
    /// @param keyHash The public key hash to query
    /// @return The packed settings value
    function ownerSettings(bytes32 keyHash) external view returns (uint256);

    /// @notice Add an owner to the wallet
    /// @param keyHash The public key hash to associate with this validator
    /// @param validator The address of the validator contract to be registered
    /// @param settings Packed settings value (use packSettings to create)
    function addOwner(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) external;

    /// @notice Update an owner's validator and settings
    /// @param keyHash The public key hash to associate with this validator
    /// @param newValidator The address of the new validator contract
    /// @param newSettings Packed settings value (use packSettings to create)
    function updateOwner(
        bytes32 keyHash,
        address newValidator,
        uint256 newSettings
    ) external;

    /// @notice Remove an owner from the wallet
    /// @param keyHash The public key hash to remove
    function removeOwner(bytes32 keyHash) external;

    /// @notice Check if an owner exists
    /// @param keyHash The public key hash to check
    /// @return True if the owner exists
    function hasOwner(bytes32 keyHash) external view returns (bool);

    /// @notice Get the total number of owners
    /// @return The number of owners
    function ownerCount() external view returns (uint256);

    /// @notice Get owner keyHash at specific index
    /// @param index The index of the owner to retrieve
    /// @return The keyHash at the specified index
    function ownerAt(uint256 index) external view returns (bytes32);

    /// @notice Get all owner keyHashes
    /// @return Array of all owner keyHashes
    function getOwnerKeys() external view returns (bytes32[] memory);

    /// @notice Get comprehensive owner settings
    /// @param keyHash The public key hash to query
    /// @return validator The validator address
    /// @return hook The hook address (address(0) if no hook)
    /// @return expiration Unix timestamp when validator expires (0 = never expires)
    /// @return adminStatus Whether this validator has admin privileges
    /// @return expired Whether the validator is currently expired
    function getOwnerSettings(
        bytes32 keyHash
    ) external view returns (
        address validator,
        address hook,
        uint40 expiration,
        bool adminStatus,
        bool expired
    );

    /// @notice Get the verified validator for a given keyHash
    /// @param keyHash The public key hash to look up
    /// @return The validator address to use for validation
    function getVerifiedValidator(bytes32 keyHash) external view returns (address);

    /// @notice Pack settings into a single uint256 value
    /// @param adminFlag Whether the owner has admin privileges
    /// @param expiration Unix timestamp when validator expires (0 = never expires)
    /// @param hook Hook address (address(0) = no hook)
    /// @return Packed settings value
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook
    ) external pure returns (uint256);

    /// @notice Extract hook address from packed settings
    /// @param settings Packed settings value
    /// @return hook Hook address (address(0) = no hook)
    function getHook(uint256 settings) external pure returns (address);

    /// @notice Extract expiration timestamp from packed settings
    /// @param settings Packed settings value
    /// @return expiration Unix timestamp (0 = never expires)
    function getExpiration(uint256 settings) external pure returns (uint40);

    /// @notice Extract admin flag from packed settings
    /// @param settings Packed settings value
    /// @return isAdmin True if signer has admin privileges
    function isAdmin(uint256 settings) external pure returns (bool);

    /// @notice Check if settings are currently expired
    /// @param settings Packed settings value
    /// @return True if the settings are expired
    function isSettingsExpired(uint256 settings) external view returns (bool);
}
```

#### Key Functions

**Owner Management:**
- `addOwner(keyHash, validator, settings)`: Register new owner with validator and settings
- `updateOwner(keyHash, newValidator, newSettings)`: Update existing owner's validator and settings  
- `removeOwner(keyHash)`: Remove owner from wallet
- `hasOwner(keyHash)`: Check if keyHash exists
- `ownerCount()`: Get total number of owners
- `ownerAt(index)`: Get owner keyHash at specific index
- `getOwnerKeys()`: Get all owner keyHashes as array

**Owner Information:**
- `ownerValidators(keyHash)`: Get validator address for keyHash (public mapping)
- `ownerSettings(keyHash)`: Get packed settings for keyHash (public mapping)
- `getOwnerSettings(keyHash)`: Get complete owner info (validator, hook, expiration, adminStatus, expired)
- `getVerifiedValidator(keyHash)`: Get verified validator address for validation

**Settings Utilities:**
- `packSettings(adminFlag, expiration, hook)`: Pack settings into uint256
- `getHook(settings)`: Extract hook address from packed settings
- `getExpiration(settings)`: Extract expiration timestamp from packed settings
- `isAdmin(settings)`: Extract admin flag from packed settings
- `isSettingsExpired(settings)`: Check if settings are currently expired

#### Settings Structure
```solidity
// Settings bit layout (uint256):
// Bits [255-208]: not used (6 bytes)
// Bits [207-200]: isAdmin flag (1 byte)
// Bits [199-160]: expiration timestamp (5 bytes, uint40)
// Bits [159-0]:   hook address (20 bytes, address)
```

#### Storage Structure
```solidity
// Core storage variables
EnumerableSetLib.Bytes32Set internal _ownerKeys;
mapping(bytes32 => address) public ownerValidators;
mapping(bytes32 => uint256) public ownerSettings;
```

#### Admin Permissions

The Smart Wallet implements a hierarchical permission system where certain operations require admin privileges.

**Admin Capabilities:**

**Admin owners can:**
- Call `addOwner()` - Add new owners to the wallet
- Call `updateOwner()` - Update existing owner settings and validators
- Call `removeOwner()` - Remove owners from the wallet
- Execute self-calls - Call the wallet's own functions directly
- Modify owner settings and permissions

**Non-Admin Restrictions:**

**Non-admin owners cannot:**
- Execute any self-calls to the wallet contract
- Modify owner settings or permissions
- Add, update, or remove other owners
- Access admin-only functions

**Initial Owner Admin Status:**

**Default admin permissions:**
- All `initialOwners` automatically receive admin privileges during wallet initialization
- Admin settings are packed as: `packSettings(true, 0, address(0))`
  - `adminFlag = true` - Grants admin privileges
  - `expiration = 0` - Never expires
  - `hook = address(0)` - No hook address

**Admin Permission Structure:**

```solidity
// Admin settings structure
uint256 adminSettings = packSettings(
    true,           // adminFlag: true = admin, false = regular owner
    0,              // expiration: 0 = never expires, timestamp = expires at time
    address(0)      // hook: address(0) = no hook, address = hook contract
);

// Check admin status
bool isAdmin = isAdmin(ownerSettings[keyHash]);
```

**Permission Enforcement:**

The system enforces admin permissions through:
- **`onlyOwner` modifier**: Checks if caller is a registered owner
- **Admin flag validation**: Verifies admin status for privileged operations
- **Self-call restrictions**: Non-admin owners cannot execute self-calls
- **Settings validation**: Admin operations require admin privileges

### 5. NonceManager

Handles nonce validation and management for transaction ordering.

#### Interface
```solidity
interface INonceManager {
    /// @notice Returns the current nonce value for a specific key
    /// @param key The nonce key to query
    /// @return The current nonce value for this key
    function getNonce(uint192 key) external view returns (uint64);
}
```

#### Internal Implementation
The NonceManager also contains an internal function `validateAndUpdateNonce` that is used internally by the wallet to validate and update nonces during transaction execution. This function:
- Validates that the provided nonce matches the stored value
- Always increments the nonce (reverts are handled by the calling function if validation fails)
- Emits a `NonceConsumed` event
- Returns true if validation passed, false otherwise

#### Key Functions

**Public Interface:**
- `getNonce(key)`: Get current nonce value for specific key

**Internal Functions:**
- `validateAndUpdateNonce(packedNonce)`: Internal function to validate and update nonce (not exposed in interface)

#### Nonce Structure
```solidity
// 2-dimensional nonce: uint256 nonce = uint192 key + uint64 value
mapping(uint192 key => uint64 seq) public _nonces;
```

#### Special Nonce Keys
- **Chainless operations**: `nonce key = 196` - Enables cross-chain signature reuse for specific methods
- **Concurrent execution**: Different nonce keys allow parallel transaction processing without conflicts
- **Key usage**: Only allows two methods `addOwner` and `upgradeToAndCall`

#### Chainless Nonce Validation
The chainless nonce key (`196`) allows cross-chain signature reuse for specific operations. When used:
- **Allowed functions**: Only `addOwner()` and `upgradeToAndCall()` are permitted
- **Security**: All calls must be self-calls, chain ID excluded from signature validation
- **Use case**: Add same owner or deploy same upgrade across multiple chains with one signature
- **Validation**: `ChainlessLib.validateChainlessNonceCallData()` ensures only whitelisted operations

### 6. ValidationManager

Interface for different authentication methods.

#### Interface
```solidity
interface IValidator {
    /// @notice Validate a signature for a given message hash
    /// @param keyHash The hash of the public key/address to validate against
    /// @param messageHash The hash of the message being validated
    /// @param validatorData The signature and validation data (format depends on validator type)
    /// @return True if the signature is valid, false otherwise
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) external view returns (bool);
}
```

#### Key Functions

**Signature Validation:**
- `validateSignature(keyHash, messageHash, validatorData)`: Validate signature for given message hash (interface method)

#### Validator Types

##### Built-in Validators
1. **ECDSA and Recovery Signer Validator** (`address(1)`): Traditional ECDSA signature validation
   - Built-in validator at address `0x0000000000000000000000000000000000000001`
   
2. **Passkey Validator** (`address(2)`): WebAuthn/P256 authentication
   - Built-in validator at address `0x0000000000000000000000000000000000000002`
   - Supports passkey and WebAuthn signatures

3. **Passkey / ECDSA  + Merkel Tree Validator**

##### External Validators
3. **Custom Validators**: Pluggable validation contracts
   - Any contract implementing the IValidator interface
   - Allows for custom authentication methods

#### Validator data structure

```solidity
bytes validatorData = pubkeyHash (32 bytes) + validUntil (6 bytes) + signature + merkle proofs (optional)
```

#### Validator Data Variations

**1. ECDSA without Merkle Proof:**
```solidity
| Field     | Size     | Description        |
|-----------|----------|--------------------|
| keyHash   | 32 bytes | Owner key hash     |
| until     | 6 bytes  | Valid until        |
| signature | 65 bytes | ECDSA signature    |
```

**2. ECDSA with Merkle Proof:**
```solidity
| Field         | Size       | Description                    |
|---------------|------------|--------------------------------|
| keyHash       | 32 bytes   | Owner key hash                 |
| until         | 6 bytes    | Valid until timestamp          |
| signature     | 65 bytes   | ECDSA signature                |
| merkle proofs | variable   | abi.encode(proofs)             |
```

**3. Passkey without Merkle Proof:**
```solidity
| Field         | Size       | Description                    |
|---------------|------------|--------------------------------|
| keyHash       | 32 bytes   | Owner key hash                 |
| until         | 6 bytes    | Valid until timestamp          |
| PassKey[X,Y]  | 64 bytes   | Passkey public key coordinates |
| webAuth       | variable   | abi.encode(webAuth)            |
```

**4. Passkey with Merkle Proof:**
```solidity
| Field                   | Size       | Description                    |
|-------------------------|------------|--------------------------------|
| keyHash                 | 32 bytes   | Owner key hash                 |
| until                   | 6 bytes    | Valid until timestamp          |
| PassKey[X,Y]            | 64 bytes   | Passkey public key coordinates |
| webAuth + merkle proofs | variable   | abi.encode(webAuth,proofs)     |
```


#### Signature validation types
```solidity
// Passkey validation (WebAuthn)
/// @notice Passkey authentication data structure
struct WebAuthnAuth {
    /// @dev The WebAuthn authenticator data.
    ///      See https://www.w3.org/TR/webauthn-2/#dom-authenticatorassertionresponse-authenticatordata.
    bytes authenticatorData;
    /// @dev The WebAuthn client data JSON.
    ///      See https://www.w3.org/TR/webauthn-2/#dom-authenticatorresponse-clientdatajson.
    string clientDataJSON;
    /// @dev The index at which "challenge":"..." occurs in `clientDataJSON`.
    /// 23
    uint256 challengeIndex; /// 23
    /// @dev The index at which "type":"..." occurs in `clientDataJSON`.
    /// 1
    uint256 typeIndex;      /// 1
    /// @dev The r value of secp256r1 signature
    uint256 r;
    /// @dev The s value of secp256r1 signature
    uint256 s;
}

// Merkle Proof
bytes32[] memory proofs
```

### 7. AllowanceManager

Manages token allowances and spending limits.

#### Interface
```solidity
interface IAllowanceManager {
    /// @notice Batch approve multiple spenders for multiple tokens (native ETH and ERC20)
    /// @param approvals Array of ApprovalInfo structs
    /// @return success True if all approvals succeeded
    function batchApproveToken(
        ApprovalInfo[] calldata approvals
    ) external returns (bool success);

    /// @notice Transfer native ETH from this contract using persistent allowance
    /// @param recipient The address to receive ETH
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromNative(
        address recipient,
        uint256 amount
    ) external returns (bool success);

    /// @notice Transfer tokens from this contract using persistent allowance
    /// @param token The ERC20 token address
    /// @param recipient The address to receive tokens
    /// @param amount The amount to transfer
    /// @return success True if transfer succeeded
    function transferFromToken(
        address token,
        address recipient,
        uint256 amount
    ) external returns (bool success);

    /// @notice Get the current persistent native ETH allowance
    /// @param spender The spender address
    /// @return allowance The current allowance
    function nativeAllowance(
        address spender
    ) external view returns (uint256 allowance);

    /// @notice Get the current persistent token allowance
    /// @param token The ERC20 token address
    /// @param spender The spender address
    /// @return allowance The current allowance
    function tokenAllowance(
        address token,
        address spender
    ) external view returns (uint256 allowance);
}
```

#### Key Functions

**Token Approvals:**
- `batchApproveToken(approvals[])`: Batch approve multiple spenders for multiple tokens (native ETH and ERC20)

**Token Transfers:**
- `transferFromNative(recipient, amount)`: Transfer native ETH using persistent allowance
- `transferFromToken(token, recipient, amount)`: Transfer ERC20 tokens using persistent allowance

**Allowance Queries:**
- `nativeAllowance(spender)`: Get current persistent native ETH allowance
- `tokenAllowance(token, spender)`: Get current persistent token allowance

### 8. FallbackHandler

Handles token receiving functionality and standard interface support.

#### Overview
The FallbackHandler is an abstract contract that enables the wallet to receive various types of tokens and implements standard interface detection.

#### Key Features
- **ETH Receiving**: Implements `receive()` function to accept native ETH transfers
- **ERC721 Support**: Handles `onERC721Received` callbacks for NFT transfers
- **ERC1155 Support**: Handles both single and batch ERC1155 token transfers
- **Interface Detection**: Implements ERC165 `supportsInterface` for standard compliance

#### Supported Interfaces
- `IERC721Receiver` (0x150b7a02)
- `IERC1155Receiver` (0x4e2312e0)
- `IERC1271` (0x1626ba7e)
- `IERC165` (0x01ffc9a7)

## Contract Relationships

```
SmartWalletFactory
  ↓ creates (via proxy)
SmartWalletEntry
  ↓ extends
SmartWallet (abstract)
  ↓ inherits
├── OwnerManager (manages owners and permissions)
├── NonceManager (handles transaction ordering)  
├── ValidationManager (authenticates operations)
├── AllowanceManager (manages token allowances)
├── ERC4337Account (EIP-4337 support)
├── FallbackHandler (token receiving)
└── Other managers...
```

## Utility Tools

### SmartWalletSimulator

**Location**: `scripts/utils/SmartWalletSimulator.s.sol` (not a core contract)

**Purpose**: A utility contract for gas estimation and simulation that reverts with detailed gas metrics without executing transactions.

**Note**: This is not a core contract but a development/testing utility. The interface is defined in `src/interfaces/ISmartWalletSimulator.sol`.

#### Interface
```solidity
interface ISmartWalletSimulator {
    /// @notice Simulate a sponsored transaction, measuring gas costs for validation and execution
    /// @dev Always reverts with `Errors.SimulateExecution` containing execution gas, intrinsic gas, and total gas metrics
    /// @param batchedCall BatchedCall struct containing calls, nonce, and expiry
    /// @param validator Validator address intended to be used for validation during execution
    /// @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        address validator,
        bytes calldata validatorData
    ) external;
}
```

**Gas Simulation:**
- `simulateExecuteWithRelayer(batchedCall, validator, validatorData)`: Simulate sponsored transaction and measure gas costs (always reverts with `Errors.SimulateExecution(executionGas, intrinsicGas, totalGas)`)

## Recovery System

The recovery system is implemented through external contracts:

1. **RecoverySigner**: Handles account recovery through multiple mechanisms
2. **RecoverySignerFactory**: Creates and manages recovery signers
3. **Recovery Verifiers**: Validate recovery credentials (Passkey, ZKEmail, SocialID)

### Recovery Integration
```solidity
// Recovery signer can be added as owner
bytes32 recoveryKeyHash = keccak256(abi.encodePacked(recoverySigner));
uint256 recoverySettings = packSettings(true, 0, address(0));

addOwner(recoveryKeyHash, eoaValidator, recoverySettings);
```

## ERC-4337 Compatibility

### EntryPoint Integration
```solidity
function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) external onlyEntryPoint returns (uint256 validationData)

function executeUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash
) external onlyEntryPoint
```

### UserOperation Processing
- **Signature Validation**: Extract and validate keyHash from signature
- **Call Decoding**: Parse calls from userOp.callData
- **Batch Execution**: Execute multiple calls in sequence
- **Event Emission**: Emit execution success events

## Events

The Smart Wallet system emits various events to track important state changes and operations.

### OwnerManager Events

```solidity
/// @notice Emitted when an owner is added
/// @param keyHash The public key hash of the new owner
/// @param validator The validator address for the owner
event OwnerAdded(bytes32 keyHash, address validator);

/// @notice Emitted when an owner is updated
/// @param keyHash The public key hash of the owner
/// @param newValidator The new validator address
event OwnerUpdated(bytes32 keyHash, address newValidator);

/// @notice Emitted when an owner is removed
/// @param keyHash The public key hash of the removed owner
/// @param validator The validator address that was removed
event OwnerRemoved(bytes32 keyHash, address validator);
```

### NonceManager Events

```solidity
/// @notice Emitted when a nonce is consumed/validated
/// @param key The nonce key
/// @param nonce The nonce value that was consumed
event NonceConsumed(uint192 key, uint64 nonce);
```

### SmartWalletFactory Events

```solidity
/// @notice Emitted when a new smart wallet account is created
/// @param account The address of the created wallet
/// @param implementation The implementation address
/// @param initialOwners Array of initial owners
/// @param salt The salt used for deterministic address generation
event AccountCreated(
    address indexed account,
    address indexed implementation,
    InitialOwner[] initialOwners,
    uint256 salt
);
```

### ExecutionManager Events

```solidity
/// @notice Emitted when execution is successful
/// @param intentHash The hash of the intent that was executed
/// @param sender The address that initiated the execution
/// @param nonce The nonce used for execution
event ExecuteSuccessEvent(
    bytes32 indexed intentHash,
    address sender,
    uint256 nonce
);
```

### AllowanceManager Events

```solidity
/// @notice Emitted when token allowance is approved (both native ETH and ERC20 tokens)
/// @param owner The owner of the tokens
/// @param token The token address (use Static.NATIVE_ETH for native ETH)
/// @param spender The spender address
/// @param amount The approved amount
event ApproveToken(
    address indexed owner,
    address indexed token,
    address indexed spender,
    uint256 amount
);

/// @notice Emitted when native ETH is transferred using allowance
/// @param owner The owner of the ETH
/// @param spender The spender address
/// @param recipient The recipient address
/// @param amount The amount transferred
event TransferFromNative(
    address indexed owner,
    address indexed spender,
    address indexed recipient,
    uint256 amount
);

/// @notice Emitted when ERC20 tokens are transferred using allowance
/// @param owner The owner of the tokens
/// @param spender The spender address
/// @param token The token contract address
/// @param recipient The recipient address
/// @param amount The amount transferred
event TransferFromToken(
    address indexed owner,
    address indexed spender,
    address indexed token,
    address recipient,
    uint256 amount
);

/// @notice Emitted when a native ETH allowance is updated
/// @param spender The spender address
/// @param newAllowance The new allowance amount
event NativeAllowanceUpdated(address indexed spender, uint256 newAllowance);

/// @notice Emitted when a token allowance is updated
/// @param token The token contract address
/// @param spender The spender address
/// @param newAllowance The new allowance amount
event TokenAllowanceUpdated(
    address indexed token,
    address indexed spender,
    uint256 newAllowance
);
```
