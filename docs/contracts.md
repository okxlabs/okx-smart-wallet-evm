# Smart Contract Reference

This reference covers the interfaces implemented by the current repository. Use it to construct calls, encode signatures, and interpret results. For account lifecycle and execution flows, see [Architecture](./architecture.md); for build and deployment commands, see the [project README](../README.md#usage).

[SmartWalletEntry](../src/SmartWalletEntry.sol) is the concrete wallet implementation. [SmartWallet](../src/SmartWallet.sol) composes the inherited managers; applications call their methods at the **account address** (a factory-created proxy or a delegated EOA). [SmartWalletFactory](../src/SmartWalletFactory.sol) is a separate deployment contract. The current ERC-4337 integration uses **EntryPoint v0.7** at `0x0000000071727De22E5E9d8BAf0edAc6f37da032`.

Individual files in [src/interfaces](../src/interfaces/) describe parts of the API. Generate the complete ABIs, including inherited methods, from the concrete contracts:

```bash
forge inspect src/SmartWalletEntry.sol:SmartWalletEntry abi --json
forge inspect src/SmartWalletFactory.sol:SmartWalletFactory abi --json
```

## Contents

- [Shared Types](#shared-types)
- [Factory and Initialization](#factory-and-initialization)
- [Batch Execution](#batch-execution)
- [Owners and Permissions](#owners-and-permissions)
- [Nonces and Chainless Queues](#nonces-and-chainless-queues)
- [Signatures and Hashing](#signatures-and-hashing)
- [Transfer Authorizations](#transfer-authorizations)
- [Persistent Allowances](#persistent-allowances)
- [External Validators and Hooks](#external-validators-and-hooks)
- [Upgrades, Introspection, and Simulation](#upgrades-introspection-and-simulation)
- [Events and Errors](#events-and-errors)

## Shared Types

The following tuples are defined in [Types.sol](../src/Types.sol):

```solidity
struct Call {
    address target;
    uint256 value;
    bytes data;
}

struct BatchedCall {
    Call[] calls;
    uint256 nonce;
}

struct InitialOwner {
    bytes32 keyHash;
    address validator;
}
```

`Call.value` is denominated in wei and paid from the account balance. `target` is used literally: use the account address for a self-call; `address(0)` is not a self-call alias. `BatchedCall` contains no expiry field; relayer expiry is carried in the signature envelope.

[IAllowanceManager](../src/interfaces/IAllowanceManager.sol) defines:

```solidity
struct ApprovalInfo {
    address token;
    address spender;
    uint256 amount;
}
```

Amounts use wei for native ETH and token base units for ERC-20 tokens. Both allowances and transfer authorizations identify native ETH with `Static.NATIVE_ETH`, whose value is `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`.

For UserOperations, use the dependency's [PackedUserOperation](../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol) v0.7 tuple. `accountGasLimits` packs the verification gas limit into the high 128 bits and the call gas limit into the low 128 bits; `gasFees` packs the priority fee into the high 128 bits and the maximum fee into the low 128 bits.

## Factory and Initialization

Sources: [SmartWalletFactory](../src/SmartWalletFactory.sol), [SmartWallet.initialize](../src/SmartWallet.sol), [BaseAuthorization](../src/BaseAuthorization.sol).

Deploy `SmartWalletEntry` first, then pass its address to the factory constructor, `constructor(address implementation)`. The factory deploys account proxies using that implementation.

| Factory method                                                                                                    | Mutability / result | Behavior                                                                                        |
| ----------------------------------------------------------------------------------------------------------------- | ------------------- | ----------------------------------------------------------------------------------------------- |
| `IMPLEMENTATION()`                                                                                                | `view → address`    | Implementation configured when the factory was deployed                                         |
| `getAddress(InitialOwner[] initialOwners, uint256 salt)`                                                          | `view → address`    | Predicts the deterministic account address without deploying it                                 |
| `createAccount(InitialOwner[] initialOwners, uint256 salt)`                                                       | `payable → address` | Creates and initializes the proxy, or returns the existing account; forwards ETH to the account |
| `createAccountWithCall(InitialOwner[] initialOwners, uint256 salt, BatchedCall batchedCall, bytes validatorData)` | `payable → address` | Creates or retrieves the account, then calls its `executeWithRelayer`                           |

The effective CREATE2 salt is `keccak256(abi.encode(initialOwners, salt))`. Owner ordering affects the address. Repeating a deployment does not reinitialize the account. `createAccountWithCall` requires a valid relayer signature and nonce even when the account is newly created; a failed execution reverts the entire factory call.

`createAccountWithCall` is implemented by the concrete factory but is not declared in `ISmartWalletFactory`. Use the concrete ABI when calling it.

The wallet's `initialize(InitialOwner[] initialOwners)` is nonpayable, callable once, and restricted to the factory embedded in the proxy's immutable arguments. The list must be nonempty, and every initial owner receives admin settings with no expiry or hook (`uint256(1) << 200`). Duplicate keys, the implicit root key, and invalid validator addresses are rejected.

A delegated EOA uses its implicit root authority to add owners through an authorized execution path. It does not use factory initialization. See [account models](./architecture.md#account-models-and-lifecycle).

## Batch Execution

Sources: [SmartWallet](../src/SmartWallet.sol), [ERC4337Account](../src/ERC4337Account.sol), [ExecutionManager](../src/ExecutionManager.sol).

| Wallet method                                                                                 | Caller / authorization                                             | Result                                                         |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------- |
| `execute(Call[] calls)`                                                                       | Active owner selected by `keccak256(abi.encodePacked(msg.sender))` | Executes the batch; no return value                            |
| `executeWithRelayer(BatchedCall batchedCall, bytes validatorData)`                            | Any caller with a valid owner signature, expiry, and relayer nonce | Executes the batch; no return value                            |
| `validateUserOp(PackedUserOperation userOp, bytes32 userOpHash, uint256 missingAccountFunds)` | EntryPoint only                                                    | Returns ERC-4337 `uint256 validationData`                      |
| `executeUserOp(PackedUserOperation userOp, bytes32 userOpHash)`                               | EntryPoint only, following validation                              | Executes calls decoded from `userOp.callData`; no return value |
| `entryPoint()`                                                                                | Public, `pure`                                                     | Returns the fixed v0.7 EntryPoint address                      |

All four execution/validation methods are **nonpayable**. Fund the account before execution, or through the payable factory deployment path. Calls inside a batch can transfer ETH from the account balance.

Direct execution checks the sender's owner configuration and expiration; it does not call the owner's signature validator. Passkey signatures therefore use a signature-bearing entry point such as `executeWithRelayer` or a UserOperation.

Batch execution invokes the owner's pre-hook, performs calls in order, and invokes the post-hook. A call to the account itself requires admin settings. Successful return data is discarded. A failing call or hook reverts the batch; a failed low-level batch call forwards at most 256 bytes of revert data.

### ERC-4337 Call Encoding

Both regular and chainless UserOperations require this `callData` layout:

```solidity
// IERC4337Account is defined in src/interfaces/IERC4337Account.sol.
// calls is a Call[] array.
userOp.callData = abi.encodePacked(
    IERC4337Account.executeUserOp.selector,
    abi.encode(calls)
);
```

This is a four-byte selector followed by the ABI encoding of `Call[]`. It is **not** the full ABI encoding of `executeUserOp(userOp, userOpHash)`: EntryPoint supplies those arguments when invoking the account.

`validateUserOp` attempts to pay `missingAccountFunds`, validates the execution selector and signature, and returns `1` for recognized signature-validation failures. On success it encodes the earlier of the owner's expiry and the signature's `validUntil` into bits 160–207 of `validationData`; zero expiry is treated as unlimited. Malformed ABI data can still revert.

`executeUserOp` rechecks that the selected owner still exists and has not expired, then uses its current settings. It does not verify the signature again. If execution fails after successful EntryPoint validation, validation-phase nonce and queue changes can remain consumed. See [nonce handling](#nonces-and-chainless-queues).

## Owners and Permissions

Source: [OwnerManager](../src/OwnerManager.sol); interface: [IOwnerManager](../src/interfaces/IOwnerManager.sol).

### Owner Management

| Method                                                                    | Access / result                                | Behavior                                                                                     |
| ------------------------------------------------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `addOwner(bytes32 keyHash, address validator, uint256 settings)`          | Wallet self-call; no return value              | Registers a new key                                                                          |
| `updateOwner(bytes32 keyHash, address newValidator, uint256 newSettings)` | Wallet self-call; no return value              | Replaces an existing key's validator and settings                                            |
| `removeOwner(bytes32 keyHash)`                                            | Wallet self-call; no return value              | Removes a registered key                                                                     |
| `getOwnerConfig(bytes32 keyHash)`                                         | `view → (address validator, uint256 settings)` | Returns raw configuration, including expired settings; missing keys return `(address(0), 0)` |
| `hasOwner(bytes32 keyHash)`                                               | `view → bool`                                  | Tests membership in the stored owner registry                                                |
| `ownerCount()`                                                            | `view → uint256`                               | Counts stored owners                                                                         |
| `ownerAt(uint256 index)`                                                  | `view → bytes32`                               | Returns a stored key; an out-of-range index reverts                                          |
| `getOwnerKeys()`                                                          | `view → bytes32[]`                             | Returns all stored keys                                                                      |

Enumeration includes expired keys and excludes the implicit root key. Ordering can change after removal, so use `keyHash` as the stable identifier.

For the implicit root key, `keccak256(abi.encodePacked(accountAddress))`, `getOwnerConfig` always returns `(address(1), uint256(1) << 200)`. This enables a delegated EOA to authenticate with its own private key. The root is not stored and cannot be added, updated, or removed through the registry.

### Packed Settings

| Bits    | Field               | Meaning                                                |
| ------- | ------------------- | ------------------------------------------------------ |
| 0–159   | Hook address        | Zero disables the owner's hook                         |
| 160–199 | `uint40` expiration | Unix timestamp; zero means no expiry                   |
| 200–207 | Admin flag          | Grants admin permission only when this byte equals `1` |
| 208–255 | Reserved            | Leave zero when constructing settings                  |

Construct settings in the client; the contract does not expose a `packSettings` method:

```solidity
// admin: bool; expiration: uint40; hook: address.
uint256 settings =
    (uint256(admin ? 1 : 0) << 200) |
    (uint256(expiration) << 160) |
    uint256(uint160(hook));
```

| Settings helper                       | Mutability / result                                                                     |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| `getHook(uint256 settings)`           | `pure → address`                                                                        |
| `getExpiration(uint256 settings)`     | `pure → uint40`                                                                         |
| `isAdmin(uint256 settings)`           | `pure → bool`                                                                           |
| `isSettingsExpired(uint256 settings)` | `view → bool`; true when expiration is nonzero and strictly less than `block.timestamp` |

Non-admin owners can execute external calls subject to their hooks. Admin status permits wallet self-calls. For example, an active admin using direct execution can register another owner with this Solidity fragment:

```solidity
// wallet: ISmartWallet; keyHash, validator, and settings describe the new owner.
Call[] memory calls = new Call[](1);
calls[0] = Call({
    target: address(wallet),
    value: 0,
    data: abi.encodeCall(IOwnerManager.addOwner, (keyHash, validator, settings))
});
wallet.execute(calls);
```

Calling `addOwner` directly from an external admin address fails `onlySelf`. A delegated EOA can also originate a transaction directly to its own address, satisfying the self-call requirement.

## Nonces and Chainless Queues

Sources: [NonceManager](../src/NonceManager.sol), [ChainlessLib](../src/libraries/ChainlessLib.sol).

| Request type           | State / query                                                         | Encoding                                                                                    |
| ---------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Relayer batch          | Wallet `getNonce(uint192 key) → uint64` (`view`)                      | High 192 bits: key; low 64 bits: sequence                                                   |
| UserOperation          | EntryPoint's `getNonce(account, key)`                                 | EntryPoint returns the packed key and sequence; wallet `getNonce` does not query this state |
| Transfer authorization | Wallet `transferAuthorizationState(ownerKeyHash, authorizationNonce)` | Independent `bytes32` nonce per owner; no sequence                                          |

Relayer sequences start at zero and increment after successful execution. A reverting relayer call rolls back nonce consumption. Different keys have independent sequences. Pack a regular relayer nonce as `(uint256(key) << 64) | uint256(sequence)`.

Chainless mode is selected when `nonce >> 96 == 196`:

```text
[255..96: prefix 196][95..80: operation type][79..64: queue id][63..0: sequence]
```

```solidity
uint256 nonce =
    (uint256(196) << 96) |
    (uint256(operationType) << 80) |
    (uint256(queueId) << 64) |
    uint256(sequence);
```

Here `operationType` and `queueId` are `uint16`, and `sequence` is `uint64`. `getChainlessQueueState(uint16 operationType) → uint16` is a view method returning the smallest queue ID that may be used next, initially zero.

Chainless requests require an admin owner. Every included call must target the account and use either `addOwner` or `upgradeToAndCall`. The convention `operationType = 0` for owner additions and `1` for upgrades is not enforced on-chain.

Accepting queue `N` advances its operation type's floor to `N + 1`, invalidating every queue ID up to and including `N`. IDs below the floor and ID `65535` are rejected; accepting `65534` exhausts that operation type's queues. Relayer requests and UserOperations share this wallet queue floor, while their sequence counters remain separate. Each chain maintains its own state.

## Signatures and Hashing

Sources: [ERC712](../src/ERC712.sol), [ValidationManager](../src/ValidationManager.sol), [BatchedCallLib](../src/libraries/BatchedCallLib.sol), [MessageSignLib](../src/libraries/MessageSignLib.sol).

### Domain and Envelopes

The standard domain uses `name = "SmartWallet"`, `version = "2.0.0"`, the current `chainId`, and the account address as `verifyingContract`.

| Helper                                                    | Result                                                                                                                                                                                                    |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hashTypedData(bytes32 structHash)`                       | `view → bytes32`; EIP-712 digest using the standard domain                                                                                                                                                |
| `hashTypedDataSansChainId(bytes32 structHash)`            | `view → bytes32`; digest using a domain that omits the `chainId` field, rather than setting it to zero                                                                                                    |
| `eip712Domain()`                                          | `view → (bytes1 fields, string name, string version, uint256 chainId, address verifyingContract, bytes32 salt, uint256[] extensions)`; standard domain with `fields = 0x0f`, zero salt, and no extensions |
| `getUserOpHashWithoutChainId(PackedUserOperation userOp)` | `view → bytes32`; `keccak256(abi.encode(userOp.hash(), entryPoint()))` using the v0.7 `UserOperationLib` hash                                                                                             |

Signature envelopes use packed concatenation (`+` in the table below). `validatorSignature` is the validator-specific payload described later.

| Entry point                                   | Signature bytes                                                                                             |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `executeWithRelayer`                          | `keyHash (32)` + `validUntil (6)` + `validatorSignature`                                                    |
| `validateUserOp`, through `userOp.signature`  | `keyHash (32)` + `validUntil (6)` + `validatorSignature`                                                    |
| Validator-based `isValidSignature`            | `keyHash (32)` + `validUntil (6)` + `validatorSignature`; total length must exceed 38 and must not equal 65 |
| Signed transfer authorization or cancellation | `keyHash (32)` + `validatorSignature`; no six-byte expiry prefix                                            |

Use `abi.encodePacked(keyHash, uint48(validUntil), validatorSignature)` for the first format. `validUntil = 0` means no signature expiry for batches, UserOperations, and ERC-1271. Transfer authorizations use their own explicit time window.

### Relayer Digest

The relayer's signed type is:

```text
BatchedCall(Call[] calls,uint256 nonce,uint48 validUntil,address walletImpl)Call(address target,uint256 value,bytes data)
```

Each `Call` hashes its `data` bytes; the array hashes the concatenation of its element hashes. [CallLib](../src/libraries/CallLib.sol) implements this encoding. `walletImpl` is the current wallet's `IMPLEMENTATION()` value.

```solidity
// wallet: SmartWallet; validUntil: uint48.
bytes32 structHash = BatchedCallLib.hash(batchedCall, validUntil, wallet.IMPLEMENTATION());
bytes32 digest = wallet.hashTypedData(structHash);
```

For a chainless nonce, use `hashTypedDataSansChainId(structHash)` instead. The account address and implementation remain bound. ECDSA signs this digest directly; adding an Ethereum signed-message prefix would produce a different digest.

### UserOperation Digest

For a regular UserOperation, begin with EntryPoint v0.7's `getUserOpHash(userOp)`. For chainless mode, use the wallet's `getUserOpHashWithoutChainId(userOp)`. The wallet then expects:

```solidity
bytes32 digest = MessageHashUtils.toEthSignedMessageHash(
    keccak256(abi.encode(userOpHash, validUntil, wallet.IMPLEMENTATION()))
);
```

This signed-message prefix is part of the UserOperation path. It is not the relayer EIP-712 digest. Sign once over the resulting digest, or use a signing API that applies the prefix once to the inner 32-byte hash.

### ERC-1271 Validation

`isValidSignature(bytes32 hash, bytes signature)` is a view method returning `0x1626ba7e` for acceptance and `0xffffffff` for rejection.

- **Exactly 65 bytes:** recovers an ECDSA signer directly from the supplied `hash` and requires it to equal the account address. This delegated-EOA compatibility path adds no domain, expiry, implementation binding, or hook check.
- **Validator envelope:** validates the active owner and expiry, verifies a signature over `hashTypedData(MessageSignLib.hash(hash, validUntil, IMPLEMENTATION))`, then requires the configured hook to approve. The signed type is `SmartWalletMessage(bytes32 hash,uint48 validUntil,address walletImpl)`.

Malformed validator payloads can revert during decoding; callers should handle both an invalid return value and a reverted call.

### Built-In Validator Payloads

Addresses `1` and `2` are internal routing identifiers, not deployed validator contracts. Any other validator address must contain code when registered and implement [IValidator](../src/interfaces/IValidator.sol).

| Validator             | Owner key hash                                                    | `validatorSignature` encoding                                                  |
| --------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| ECDSA, `address(1)`   | `keccak256(abi.encodePacked(signerAddress))`                      | 65-byte ECDSA signature, optionally followed by `abi.encode(bytes32[] proofs)` |
| Passkey, `address(2)` | `keccak256(abi.encodePacked(uint256(pubKeyX), uint256(pubKeyY)))` | `abi.encode(pubKeyX, pubKeyY)` followed by `abi.encode(webAuthnAuth, proofs)`  |
| External validator    | Defined by that validator                                         | Defined by that validator                                                      |

[ECDSAValidatorLib](../src/libraries/ECDSAValidatorLib.sol) accepts the standard 65-byte `r || s || v` signature with `v` equal to 27 or 28. If trailing bytes are present, they must ABI-decode as a proof array.

[PasskeyValidatorLib](../src/libraries/PasskeyValidatorLib.sol) always decodes both the WebAuthn structure and a `bytes32[]` proof array. Supply an empty array when no proof is needed; `abi.encode(webAuthnAuth)` alone is insufficient. The [WebAuthnAuth](../lib/webauthn-sol/src/WebAuthn.sol) tuple is:

```solidity
struct WebAuthnAuth {
    bytes authenticatorData;
    string clientDataJSON;
    uint256 challengeIndex;
    uint256 typeIndex;
    uint256 r;
    uint256 s;
}
```

The JSON indices depend on the actual client data. The challenge is `abi.encode(MerkleProof.processProof(proofs, digest))`, and the implementation calls `WebAuthn.verify` with `requireUV: false`.

For both built-in validators, proofs transform the operation digest into a Merkle root before signature verification. An empty proof preserves the original digest. This proves membership in a signed set of digests; it does not implement a multi-owner signature threshold.

## Transfer Authorizations

Source: [TransferWithAuthorization](../src/TransferWithAuthorization.sol); interface: [ITransferWithAuthorization](../src/interfaces/ITransferWithAuthorization.sol).

These account methods transfer native ETH or ERC-20 tokens from the account balance using an owner signature. Both settlement methods are nonpayable and return no value:

```solidity
function executeTransferWithAuthorization(
    address token,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 authorizationNonce,
    bytes calldata signature
) external;

function receiveWithAuthorization(
    address token,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 authorizationNonce,
    bytes calldata signature
) external;
```

Anyone may submit `executeTransferWithAuthorization`. `receiveWithAuthorization` requires `msg.sender == to`. They use distinct signed types, so a signature for one cannot authorize the other.

Settlement requires an active signing owner and the strict time window `validAfter < block.timestamp < validBefore`. A zero `validBefore` does **not** mean unlimited validity. The native-asset path sends empty calldata; the ERC-20 path uses `SafeERC20.safeTransfer`.

### Signing an Authorization

Use the exact type string for the selected method:

```text
ExecuteTransferWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)
ReceiveWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)
CancelTransferAuthorization(bytes32 targetKeyHash,bytes32 authorizationNonce)
```

For settlement, hash the selected type string into `typeHash`, then construct:

```solidity
bytes32 structHash = keccak256(abi.encode(
    typeHash, token, address(wallet), to, value,
    validAfter, validBefore, authorizationNonce
));
bytes32 boundHash = keccak256(abi.encode(
    structHash, signerKeyHash, wallet.IMPLEMENTATION()
));
bytes32 digest = wallet.hashTypedData(boundHash);
// Sign digest with the selected validator to obtain validatorSignature.
bytes memory signature = abi.encodePacked(signerKeyHash, validatorSignature);
```

`from` is always the account address. The implementation and signing key are bound **outside** the transfer struct hash. Signing only the listed transfer fields through a standard typed-data encoder is insufficient: the final digest must include the extra binding shown above. Do not add a personal-sign prefix or the ERC-1271 `SmartWalletMessage` wrapper.

### State and Cancellation

| Method                                                                                            | Access / result             | Behavior                                                                               |
| ------------------------------------------------------------------------------------------------- | --------------------------- | -------------------------------------------------------------------------------------- |
| `transferAuthorizationState(bytes32 ownerKeyHash, bytes32 authorizationNonce)`                    | `view → bool`               | True after either settlement or cancellation                                           |
| `cancelTransferAuthorization(bytes32 targetKeyHash, bytes32 authorizationNonce, bytes signature)` | Nonpayable; no return value | Cancels an unused nonce for the target owner                                           |
| `SIGNATURE_ENVELOPE_MIN_LENGTH()`                                                                 | `view → uint256`            | Returns `32`, the key-hash prefix length; this alone is not a valid built-in signature |

A signed cancellation uses `keccak256(abi.encode(cancelTypeHash, targetKeyHash, authorizationNonce))` as `structHash`, then applies the same signer/implementation binding and signature envelope as settlement. The signer must be the target owner or a currently active admin. An empty signature instead requires a wallet self-call.

Nonce state is scoped to `(ownerKeyHash, authorizationNonce)`, shared by execute, receive, and cancel, and independent of relayer and EntryPoint nonces. Used and canceled states are both terminal; removing and re-adding an owner does not reset them.

Settlement marks the nonce used before invoking the hook and transferring assets. A revert rolls this state back. The two settlement methods use a transient-storage reentrancy guard; this guard does not cover every wallet entry point. Configured hooks must support the dedicated transfer-authorization interface described [below](#external-validators-and-hooks).

## Persistent Allowances

Source: [AllowanceManager](../src/AllowanceManager.sol); interface: [IAllowanceManager](../src/interfaces/IAllowanceManager.sol).

| Method                                                                | Access / result                  | Behavior                                                                           |
| --------------------------------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------------------- |
| `batchApproveToken(ApprovalInfo[] approvals)`                         | Wallet self-call; returns `bool` | Sets each token/spender allowance to the supplied amount; zero spender is rejected |
| `transferFromNative(address recipient, uint256 amount)`               | Approved spender; returns `bool` | Spends the caller's native ETH allowance                                           |
| `transferFromToken(address token, address recipient, uint256 amount)` | Approved spender; returns `bool` | Spends the caller's ERC-20 allowance                                               |
| `getTokenAllowance(address token, address spender)`                   | `view → uint256`                 | Returns the stored allowance                                                       |

All write methods are nonpayable. These are **wallet-managed allowances**, separate from allowances created by calling an ERC-20 token's `approve` method. Transfers draw from the account's assets.

Finite allowances decrease by the transferred amount; `type(uint256).max` remains unchanged. Both transfer methods return `true` immediately for zero amounts, without checks or events. A positive transfer through `transferFromToken` rejects the native ETH sentinel.

Spending does not recheck owner membership or execute owner hooks. An existing allowance remains usable after an owner is removed. Set the allowance to zero through an authorized `batchApproveToken` self-call to revoke it.

## External Validators and Hooks

[ValidationManager](../src/ValidationManager.sol) provides internal dispatch logic; the wallet itself does not expose `validateSignature`. External validators implement:

```solidity
function validateSignature(
    bytes32 keyHash,
    bytes32 messageHash,
    bytes calldata validatorData
) external view returns (bool);
```

The wallet catches a reverting external validator and treats it as signature failure. Validator-specific payload encoding and key identity are defined by the validator.

Hooks are selected from the signing owner's settings. [HookLib](../src/libraries/HookLib.sol) dispatches three distinct paths:

| Path                     | Hook callbacks                                                                                                                                                                                                   | Compatibility / failure behavior                                                                                         |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Batch execution          | `IHook.preCheck(Call[] calls, address executor) → bytes`, then `postCheck(bytes preCheckRet, address executor)`                                                                                                  | A configured hook is called directly; a revert aborts the batch                                                          |
| Validator-based ERC-1271 | `IHook.isValidSignatureCheck(address caller, bytes32 hash, bytes signature) → bool`                                                                                                                              | Hook must advertise `IHook` through ERC-165 and approve via a view call                                                  |
| Transfer settlement      | `IHookTransferAuthorization.preTransferWithAuthorization(bytes32 keyHash, address token, address to, uint256 value, address caller) → bytes`, then `postTransferWithAuthorization(bytes preRet, address caller)` | Hook must advertise `IHookTransferAuthorization` through ERC-165; incompatibility or callback failure reverts settlement |

Full interfaces: [IHook](../src/interfaces/IHook.sol), [IHookTransferAuthorization](../src/interfaces/IHookTransferAuthorization.sol). Pre/post callbacks are declared payable, but the wallet forwards no ETH to them. The pre-check's return bytes are passed to its corresponding post-check.

The hook's `msg.sender` is the account. The explicit `executor` or `caller` argument is the caller of the wallet entry point: an owner, relayer, EntryPoint, or signature verifier. In particular, a transfer relayer is not the authorizing owner; use the supplied `keyHash` for that identity. A zero hook address skips callbacks. Transfer cancellation does not invoke settlement hooks.

## Upgrades, Introspection, and Simulation

| Wallet method                                             | Mutability / result              | Usage                                                                                                                                     |
| --------------------------------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `IMPLEMENTATION()`                                        | `view → address`                 | Immutable address of the implementation whose code is currently running                                                                   |
| `upgradeToAndCall(address newImplementation, bytes data)` | Payable; no return value         | UUPS upgrade with self-call authorization and a compatible proxy context; optionally delegatecalls the new implementation with `data`     |
| `proxiableUUID()`                                         | `view → bytes32`                 | Returns the ERC-1967 implementation slot when called directly on the implementation; reverts in delegated context                         |
| `getImmutableFactory()`                                   | `view → address`                 | Reads the factory embedded in the factory-created proxy format; not a general-purpose getter for delegated EOAs or direct implementations |
| `namespace()`                                             | `pure → string`                  | Returns `SmartWallet.ERC7201.CustomStorage`                                                                                               |
| `CUSTOM_STORAGE_ROOT()`                                   | `view → bytes32`                 | Returns `0x653ff6dcbda533c3c7d8ffb646da3e510d0de40f237170c4da3f874472aecb00`                                                              |
| `supportsInterface(bytes4 interfaceId)`                   | `view → bool`                    | Reports the interface IDs listed below                                                                                                    |
| `delegateAndRevert(address target, bytes data)`           | Nonpayable; no successful return | Permissionless simulation helper; delegatecalls the target, then reverts with `DelegateAndRevert(bool success, bytes ret)`                |

A factory's `IMPLEMENTATION()` stays fixed even if an individual proxy upgrades. The account's getter reflects the implementation currently executing. EIP-7702 delegation changes use a new EOA authorization; updating an ERC-1967 slot does not change the EOA's delegation target. See [implementation changes](./architecture.md#storage-and-implementation-changes).

`SmartWalletEntry` applies Solidity's custom storage layout at the root shown above. The [ERC7201](../src/ERC7201.sol) getters expose its namespace and root; they do not enumerate all separately namespaced storage used by inherited modules.

For simulation, use `eth_call` and decode the deliberate `DelegateAndRevert` error. The outer revert rolls back changes even if the inner delegatecall succeeds. The repository does not include a separate `SmartWalletSimulator` implementation.

### Asset Reception and Interface Detection

[FallbackHandler](../src/FallbackHandler.sol) accepts plain ETH through `receive()`. Its payable fallback returns the appropriate selector for ERC-721 and ERC-1155 receiver callbacks and reverts for unknown selectors.

| Interface         | `supportsInterface` ID |
| ----------------- | ---------------------- |
| ERC-165           | `0x01ffc9a7`           |
| ERC-1271          | `0x1626ba7e`           |
| ERC-721 receiver  | `0x150b7a02`           |
| ERC-1155 receiver | `0x4e2312e0`           |

The ERC-1155 single and batch callback selectors are `0xf23a6e61` and `0xbc197c81`. Receiver callbacks are handled by fallback rather than explicit methods in the wallet ABI. The current `supportsInterface` implementation reports only the four IDs above, including no transfer-authorization interface ID.

## Events and Errors

### Events

The table uses full parameter types and marks indexed fields. Account events are emitted at the account address; `AccountCreated` is emitted by the factory.

| Event                                                                                                                                                         | When emitted                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `AccountCreated(address indexed account, address indexed implementation, InitialOwner[] initialOwners, uint256 salt)`                                         | A new account is deployed and initialized; not emitted when returning an existing account            |
| `WalletInitialized()`                                                                                                                                         | Initial owner setup completes                                                                        |
| `OwnerAdded(bytes32 keyHash, address validator, uint256 settings)`                                                                                            | A key is registered                                                                                  |
| `OwnerUpdated(bytes32 keyHash, address newValidator, uint256 settings)`                                                                                       | A key's configuration is replaced                                                                    |
| `OwnerRemoved(bytes32 keyHash, address validator)`                                                                                                            | A registered key is removed                                                                          |
| `ExecuteSuccessEvent(bytes32 indexed intentHash, address caller)`                                                                                             | Direct `execute` completes; `intentHash` is `CallLib.hash(calls)`                                    |
| `RelayerExecuteSuccessEvent(bytes32 indexed intentHash, address sender, uint256 nonce)`                                                                       | Relayer execution completes; `intentHash` is the signed digest and `sender` is the submitting caller |
| `NonceConsumed(uint192 key, uint64 nonce)`                                                                                                                    | A relayer sequence is consumed                                                                       |
| `ChainlessQueueInvalidated(uint16 indexed operationType, uint16 indexed queueId)`                                                                             | The queue floor advances past the accepted queue ID                                                  |
| `TransferAuthorizationUsed(address indexed token, address indexed from, address indexed to, uint256 value, bytes32 authorizationNonce, bytes32 ownerKeyHash)` | A signed transfer settles                                                                            |
| `TransferAuthorizationCanceled(bytes32 indexed ownerKeyHash, bytes32 indexed authorizationNonce)`                                                             | A transfer nonce is canceled                                                                         |
| `ApproveToken(address indexed owner, address indexed token, address indexed spender, uint256 amount)`                                                         | A wallet allowance is set                                                                            |
| `TransferFromNative(address indexed owner, address indexed spender, address indexed recipient, uint256 amount)`                                               | A positive native transfer uses an allowance                                                         |
| `TransferFromToken(address indexed owner, address indexed spender, address indexed token, address recipient, uint256 amount)`                                 | A positive ERC-20 transfer uses an allowance                                                         |
| `NativeAllowanceUpdated(address indexed spender, uint256 newAllowance)`                                                                                       | A finite native allowance is spent                                                                   |
| `TokenAllowanceUpdated(address indexed token, address indexed spender, uint256 newAllowance)`                                                                 | A finite ERC-20 allowance is spent                                                                   |

Inherited lifecycle events include `Initialized(uint64 version)` and `Upgraded(address indexed implementation)`. `executeUserOp` does not emit either wallet batch-success event; track the EntryPoint's `UserOperationEvent` and application-specific target events for that path. Reverted calls do not retain their logs.

### Common Errors

| Error                                                                   | Meaning                                                                |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `NotFromSelf()`                                                         | An operation restricted to wallet self-calls was called externally     |
| `NotEntryPoint()`                                                       | An ERC-4337 entry point was called by another address                  |
| `UnauthorizedInitialization()` / `InvalidInitialization()`              | Initialization caller or lifecycle is invalid                          |
| `InitialOwnersLengthIsZero()`                                           | New-account initialization has no owners                               |
| `InvalidCaller(address)` / `InvalidKeyHash(bytes32)`                    | Caller/key is not permitted in that context, is missing, or is expired |
| `NonAdminSelfCall()`                                                    | A non-admin batch attempted a wallet self-call                         |
| `ValidatorAlreadyExists()` / `ValidatorNotFound()`                      | Owner registration state does not match the operation                  |
| `InvalidValidatorImpl(address)`                                         | A non-built-in validator has no code                                   |
| `InvalidNonce(uint256)`                                                 | Relayer sequence does not match                                        |
| `InvalidNonceKey(uint256)`                                              | Relayer chainless permissions, calls, or queue state are invalid       |
| `ExpiryPassed(uint48)`                                                  | Relayer signature expiry has passed                                    |
| `InvalidValidatorDataLength(uint256 actual, uint256 required)`          | Relayer signature envelope is too short                                |
| `InvalidSignature()`                                                    | Signature authorization failed                                         |
| `AuthorizationAlreadyUsed(bytes32)`                                     | Transfer nonce was already settled or canceled                         |
| `AuthorizationNotYetValid(uint256)` / `AuthorizationExpired(uint256)`   | Transfer time window is not open                                       |
| `CallerNotPayee(address caller, address to)`                            | Receive authorization was submitted by someone other than the payee    |
| `UnauthorizedCancellation(bytes32 signerKeyHash, bytes32 ownerKeyHash)` | A non-admin signer tried to cancel another key's nonce                 |
| `HookNotTransferAuthorizationCompatible(bytes32 keyHash, address hook)` | Configured hook does not advertise the required transfer interface     |
| `NativeAllowanceExceeded()` / `TokenAllowanceExceeded()`                | Caller has insufficient wallet allowance                               |
| `InvalidSpender()` / `InvalidTokenForTransfer()`                        | Zero spender, or native sentinel used for a positive ERC-20 transfer   |
| `TransferNativeFailed()` / `SafeERC20FailedOperation(address token)`    | Asset transfer failed                                                  |
| `UnauthorizedCallContext()` / `UpgradeFailed()`                         | UUPS call context or replacement implementation is invalid             |
| `ReentrancyGuardReentrantCall()`                                        | Guarded transfer settlement was re-entered                             |

Use the generated ABI for the complete error set and parameter names. Calls can also bubble errors from targets, tokens, hooks, or ABI decoding. ERC-4337 validation failures may be returned as validation data, and ERC-1271 failures may be returned as the invalid magic value, rather than reverting with `InvalidSignature`.
