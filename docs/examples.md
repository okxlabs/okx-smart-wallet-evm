# Integration Examples

These examples show how to construct valid requests for the contracts in this repository. They use **EntryPoint v0.7**, the built-in ECDSA validator (`address(1)`), and the current wallet signing domain. For complete method definitions and signature formats, see the [contract reference](./contracts.md); for execution flows, see [Architecture](./architecture.md).

## Contents

- [Running the Solidity Examples](#running-the-solidity-examples)
- [Create and Fund an Account](#create-and-fund-an-account)
- [Deploy and Execute in One Transaction](#deploy-and-execute-in-one-transaction)
- [Execute a Batch Directly](#execute-a-batch-directly)
- [Submit a Signed Batch Through a Relayer](#submit-a-signed-batch-through-a-relayer)
- [Submit an ERC-4337 UserOperation](#submit-an-erc-4337-useroperation)
- [Add, Update, and Remove an Owner](#add-update-and-remove-an-owner)
- [Approve and Spend Wallet Allowances](#approve-and-spend-wallet-allowances)
- [Transfer with an Owner Authorization](#transfer-with-an-owner-authorization)
- [Validate an ERC-1271 Signature](#validate-an-erc-1271-signature)
- [Add an Owner with a Chainless Request](#add-an-owner-with-a-chainless-request)
- [Execute with a Passkey](#execute-with-a-passkey)
- [Use a Delegated EOA](#use-a-delegated-eoa)
- [Simulate and Estimate Gas](#simulate-and-estimate-gas)

## Running the Solidity Examples

The Solidity examples are local Foundry tests. Create `test/DocumentationExamples.t.sol` from the fixture below and insert the subsequent Solidity function blocks at the marked location inside `DocumentationExamplesTest`. Each `test_` function runs with a fresh `setUp`, so examples do not depend on execution order.

```bash
forge test --match-contract DocumentationExamplesTest -vv
```

`vm.sign`, `vm.prank`, `vm.deal`, and `vm.etch` are test helpers. In an application, the owner signs through its signing provider, the submitting account sends a transaction, and assets come from real account balances. All transaction amounts below use wei; the example ERC-20 has 18 decimals.

### Shared Fixture

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {IAllowanceManager} from "src/interfaces/IAllowanceManager.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {MessageSignLib} from "src/libraries/MessageSignLib.sol";
import {Static} from "src/libraries/Static.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "test/utils/Helper.s.sol";

contract ExampleToken is ERC20 {
    constructor(address holder) ERC20("Example Token", "EXM") {
        _mint(holder, 1_000 ether);
    }
}

contract DocumentationExamplesTest is Test {
    SmartWalletEntry internal implementation;
    SmartWalletFactory internal factory;
    SmartWalletEntry internal wallet;
    ExampleToken internal token;
    address internal owner;
    uint256 internal ownerPk;
    bytes32 internal ownerKeyHash;
    address internal relayer;
    address internal recipient;

    function setUp() public {
        vm.warp(1_000_000);
        vm.deal(address(this), 10 ether);
        (owner, ownerPk) = makeAddrAndKey("owner");
        ownerKeyHash = keccak256(abi.encodePacked(owner));
        relayer = makeAddr("relayer");
        recipient = makeAddr("recipient");

        implementation = new SmartWalletEntry();
        factory = new SmartWalletFactory(address(implementation));
        wallet = SmartWalletEntry(payable(
            factory.createAccount{value: 2 ether}(_initialOwners(), 1)
        ));
        token = new ExampleToken(address(wallet));
    }

    function _initialOwners() internal view returns (InitialOwner[] memory owners) {
        owners = new InitialOwner[](1);
        owners[0] = InitialOwner(ownerKeyHash, address(1));
    }

    function _singleCall(address target, uint256 value, bytes memory data)
        internal pure returns (Call[] memory calls)
    {
        calls = new Call[](1);
        calls[0] = Call(target, value, data);
    }

    function _ecdsaSignature(bytes32 digest) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _adminCall(bytes memory data) internal {
        Call[] memory calls = _singleCall(address(wallet), 0, data);
        vm.prank(owner);
        wallet.execute(calls);
    }

    // Insert the remaining Solidity function blocks here.
}
```

The ECDSA owner key hashes the **20-byte signer address**, not a serialized public key. The factory initializes this owner as an admin. `_adminCall` constructs a wallet self-call and submits it through the admin's `execute` path.

## Create and Fund an Account

Use a stable salt and the same ordered owner list for prediction and deployment. The factory accepts ETH to fund the account; calling it again returns the existing account without reinitializing owners.

```solidity
function test_CreateAccount() public {
    InitialOwner[] memory owners = _initialOwners();
    uint256 salt = 2;
    address predicted = factory.getAddress(owners, salt);

    address account = factory.createAccount{value: 1 ether}(owners, salt);

    assertEq(account, predicted);
    assertEq(account.balance, 1 ether);
    assertEq(factory.createAccount(owners, salt), account);
    assertEq(SmartWalletEntry(payable(account)).ownerCount(), 1);
}
```

## Deploy and Execute in One Transaction

`createAccountWithCall` uses the relayer authorization path. Before deployment, compute the domain with the **predicted account address** as `verifyingContract`; the account cannot yet answer `hashTypedData` calls. Use the factory's implementation address in the signed batch.

```solidity
function test_CreateAccountWithCall() public {
    InitialOwner[] memory owners = _initialOwners();
    uint256 salt = 3;
    address predicted = factory.getAddress(owners, salt);
    BatchedCall memory batch = BatchedCall(
        _singleCall(recipient, 0.1 ether, ""), 0
    );
    uint48 validUntil = uint48(block.timestamp + 1 hours);
    bytes32 structHash = BatchedCallLib.hash(
        batch, validUntil, factory.IMPLEMENTATION()
    );
    bytes32 domainSeparator = keccak256(abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(Static.ERC712_NAMESPACE)),
        keccak256(bytes(Static.ERC712_VERSION)),
        block.chainid,
        predicted
    ));
    bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    bytes memory envelope = abi.encodePacked(
        ownerKeyHash, validUntil, _ecdsaSignature(digest)
    );

    address account = factory.createAccountWithCall{value: 1 ether}(
        owners, salt, batch, envelope
    );

    assertEq(account, predicted);
    assertEq(recipient.balance, 0.1 ether);
    assertEq(account.balance, 0.9 ether);
    assertEq(SmartWalletEntry(payable(account)).hashTypedData(structHash), digest);
    assertEq(SmartWalletEntry(payable(account)).getNonce(0), 1);
}
```

Nonce zero is appropriate for this new account. For an existing account, read its current relayer sequence. Use the concrete `SmartWalletFactory` ABI: `ISmartWalletFactory` does not declare `createAccountWithCall`.

## Execute a Batch Directly

The sender must be an active address-based owner. `execute` is nonpayable: `Call.value` comes from the account's existing balance. Each call targets a real address; zero is not a self-call shorthand.

```solidity
function test_DirectBatch() public {
    Call[] memory calls = new Call[](2);
    calls[0] = Call(recipient, 0.1 ether, "");
    calls[1] = Call(
        address(token), 0,
        abi.encodeCall(IERC20.transfer, (recipient, 10 ether))
    );

    vm.prank(owner);
    wallet.execute(calls);

    assertEq(recipient.balance, 0.1 ether);
    assertEq(token.balanceOf(recipient), 10 ether);
}
```

Calls execute in order, with owner hooks around the batch. A reverted call or hook rolls back the batch. Arbitrary batch calls use low-level EVM success: if a token returns `false` instead of reverting, that return value is not decoded by `execute`. The allowance and transfer-authorization paths use `SafeERC20` for their ERC-20 transfers.

## Submit a Signed Batch Through a Relayer

Read the wallet's relayer sequence, pack it with the 192-bit key, hash the batch using the wallet's EIP-712 domain, and concatenate the signature envelope with `abi.encodePacked`.

```solidity
function test_RelayerBatch() public {
    uint192 key = 7;
    uint64 sequence = wallet.getNonce(key);
    uint256 nonce = (uint256(key) << 64) | uint256(sequence);
    BatchedCall memory batch = BatchedCall(
        _singleCall(recipient, 0.1 ether, ""), nonce
    );
    uint48 validUntil = uint48(block.timestamp + 1 hours);
    bytes32 digest = wallet.hashTypedData(
        BatchedCallLib.hash(batch, validUntil, wallet.IMPLEMENTATION())
    );
    bytes memory envelope = abi.encodePacked(
        ownerKeyHash, validUntil, _ecdsaSignature(digest)
    );

    vm.prank(relayer);
    wallet.executeWithRelayer(batch, envelope);

    assertEq(recipient.balance, 0.1 ether);
    assertEq(wallet.getNonce(key), sequence + 1);
}
```

The ECDSA envelope is 103 bytes: 32-byte key hash, six-byte `uint48 validUntil`, and 65-byte signature. Do not use `abi.encode` for this outer envelope or add a personal-sign prefix to the relayer digest. The submitting relayer pays transaction gas; the batch spends account assets.

## Submit an ERC-4337 UserOperation

Use the v0.7 EntryPoint nonce, not `wallet.getNonce`. `callData` must contain the `executeUserOp` selector followed by `abi.encode(calls)`. This example uses an already deployed account and deposits ETH into EntryPoint to cover its gas.

```solidity
function test_UserOperation() public {
    // Test-only installation at the address enforced by the wallet.
    EntryPoint localEntryPoint = new EntryPoint();
    address entryPointAddress = wallet.entryPoint();
    vm.etch(entryPointAddress, address(localEntryPoint).code);
    IEntryPoint entryPoint = IEntryPoint(entryPointAddress);
    entryPoint.depositTo{value: 0.1 ether}(address(wallet));

    Call[] memory calls = _singleCall(recipient, 0.1 ether, "");
    uint192 key = 0;
    PackedUserOperation memory userOp;
    userOp.sender = address(wallet);
    userOp.nonce = entryPoint.getNonce(address(wallet), key);
    userOp.initCode = "";
    userOp.callData = abi.encodePacked(
        IERC4337Account.executeUserOp.selector, abi.encode(calls)
    );
    // High 128 bits: verification gas; low 128 bits: call gas.
    userOp.accountGasLimits = bytes32(
        (uint256(1_000_000) << 128) | uint256(300_000)
    );
    userOp.preVerificationGas = 50_000;
    // High 128 bits: max priority fee; low 128 bits: max fee.
    userOp.gasFees = bytes32(
        (uint256(1 gwei) << 128) | uint256(2 gwei)
    );
    userOp.paymasterAndData = "";

    uint48 validUntil = uint48(block.timestamp + 1 hours);
    bytes32 digest = MessageHashUtils.toEthSignedMessageHash(
        keccak256(abi.encode(
            entryPoint.getUserOpHash(userOp), validUntil, wallet.IMPLEMENTATION()
        ))
    );
    userOp.signature = abi.encodePacked(
        ownerKeyHash, validUntil, _ecdsaSignature(digest)
    );

    PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    ops[0] = userOp;
    vm.prank(relayer);
    entryPoint.handleOps(ops, payable(relayer));

    assertEq(recipient.balance, 0.1 ether);
    assertEq(entryPoint.getNonce(address(wallet), key), userOp.nonce + 1);
    assertEq(wallet.getNonce(key), 0); // Separate relayer nonce state.
}
```

The gas values are local examples, not production estimates. On a live chain, use the existing EntryPoint and a compatible bundler to estimate and submit the operation. Finalize gas, fee, paymaster, and call fields before producing the final signature; changing signed fields requires signing again. Unlike relayer batches, this UserOperation digest includes the Ethereum signed-message prefix exactly once.

For a not-yet-deployed proxy, `initCode` is the packed 20-byte factory address followed by the ABI-encoded `createAccount(initialOwners, salt)` call. Its `sender` must match the predicted address. Compute the signature using the factory's implementation address, and arrange prefunding or paymaster sponsorship before submission.

## Add, Update, and Remove an Owner

Owner management requires an admin-authorized **wallet self-call**. Pack settings locally and query them with `getOwnerConfig`; there are no public `packSettings` or `getOwnerSettings` methods.

```solidity
function test_ManageOwners() public {
    address sessionOwner = makeAddr("session-owner");
    bytes32 keyHash = keccak256(abi.encodePacked(sessionOwner));
    uint40 expiration = uint40(block.timestamp + 1 days);
    // No admin flag and no hook; expiration occupies bits 160–199.
    uint256 settings = uint256(expiration) << 160;
    _adminCall(abi.encodeCall(IOwnerManager.addOwner, (keyHash, address(1), settings)));

    (address validator, uint256 currentSettings) = wallet.getOwnerConfig(keyHash);
    assertEq(validator, address(1));
    assertEq(wallet.getExpiration(currentSettings), expiration);
    assertFalse(wallet.isAdmin(currentSettings));

    // Replace the entire settings word, preserving expiry and hook.
    uint256 updatedSettings = (uint256(1) << 200)
        | (uint256(wallet.getExpiration(currentSettings)) << 160)
        | uint256(uint160(wallet.getHook(currentSettings)));
    _adminCall(abi.encodeCall(
        IOwnerManager.updateOwner, (keyHash, validator, updatedSettings)
    ));
    (, currentSettings) = wallet.getOwnerConfig(keyHash);
    assertTrue(wallet.isAdmin(currentSettings));

    _adminCall(abi.encodeCall(IOwnerManager.removeOwner, (keyHash)));
    assertFalse(wallet.hasOwner(keyHash));
}
```

A non-admin owner can still execute external calls. Expiration alone does not impose a spending limit; configure a suitable hook for that policy. Removing an owner does not revoke persistent allowances that were already granted to spenders.

## Approve and Spend Wallet Allowances

These allowances are stored by the wallet and are separate from an ERC-20 token's `approve`/`allowance` state. The admin grants an allowance by self-call; the spender then calls the wallet directly.

```solidity
function test_WalletAllowance() public {
    address spender = makeAddr("spender");
    IAllowanceManager.ApprovalInfo[] memory approvals =
        new IAllowanceManager.ApprovalInfo[](1);
    approvals[0] = IAllowanceManager.ApprovalInfo({
        token: address(token), spender: spender, amount: 10 ether
    });
    _adminCall(abi.encodeCall(IAllowanceManager.batchApproveToken, (approvals)));

    vm.prank(spender);
    wallet.transferFromToken(address(token), recipient, 3 ether);
    assertEq(token.balanceOf(recipient), 3 ether);
    assertEq(wallet.getTokenAllowance(address(token), spender), 7 ether);

    approvals[0].amount = 0;
    _adminCall(abi.encodeCall(IAllowanceManager.batchApproveToken, (approvals)));
    assertEq(wallet.getTokenAllowance(address(token), spender), 0);
}
```

For native ETH, approve `Static.NATIVE_ETH` and spend through `transferFromNative(recipient, amount)`. A finite allowance decreases when spent; `type(uint256).max` remains unchanged. Spending uses the allowance without checking owner membership or invoking owner hooks.

## Transfer with an Owner Authorization

A transfer authorization uses a separate `bytes32` nonce scoped to the signing owner. The following helper signs with the fixture's initial owner and binds both that key hash and the current implementation. Its envelope has a 32-byte prefix, with no six-byte `validUntil` field.

```solidity
function _authorizationSignature(bytes32 structHash) internal view returns (bytes memory) {
    bytes32 digest = wallet.hashTypedData(keccak256(abi.encode(
        structHash, ownerKeyHash, wallet.IMPLEMENTATION()
    )));
    return abi.encodePacked(ownerKeyHash, _ecdsaSignature(digest));
}

function test_TransferAuthorization() public {
    uint256 validAfter = block.timestamp - 1;
    uint256 validBefore = block.timestamp + 1 hours;
    bytes32 nonce = keccak256("example-transfer-1");
    bytes32 typeHash = keccak256(
        "ExecuteTransferWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
    );
    bytes32 structHash = keccak256(abi.encode(
        typeHash, address(token), address(wallet), recipient, uint256(10 ether),
        validAfter, validBefore, nonce
    ));
    bytes memory signature = _authorizationSignature(structHash);

    vm.prank(relayer);
    wallet.executeTransferWithAuthorization(
        address(token), recipient, 10 ether, validAfter, validBefore, nonce, signature
    );

    assertEq(token.balanceOf(recipient), 10 ether);
    assertTrue(wallet.transferAuthorizationState(ownerKeyHash, nonce));
}
```

Use a fresh nonce for each authorization in the same owner namespace; the fixed label is only a deterministic test fixture. Settlement requires `validAfter < block.timestamp < validBefore`; zero `validBefore` does not mean unlimited validity. Use `Static.NATIVE_ETH` for native transfers. Configured hooks must support [IHookTransferAuthorization](../src/interfaces/IHookTransferAuthorization.sol).

For payee-only submission, use `receiveWithAuthorization`, sign the distinct `ReceiveWithAuthorization(...)` type from the [reference](./contracts.md#signing-an-authorization), and submit from `to`. An execute signature cannot be reused for the receive method.

### Cancel an Unused Authorization

Cancellation binds the target owner in its own struct. A valid owner can cancel its own nonce; an active admin can cancel another owner's nonce. An empty signature is supported only through an authorized wallet self-call.

```solidity
function test_CancelAuthorization() public {
    bytes32 nonce = keccak256("example-canceled-transfer");
    bytes32 typeHash = keccak256(
        "CancelTransferAuthorization(bytes32 targetKeyHash,bytes32 authorizationNonce)"
    );
    bytes32 structHash = keccak256(abi.encode(typeHash, ownerKeyHash, nonce));
    bytes memory signature = _authorizationSignature(structHash);

    vm.prank(relayer);
    wallet.cancelTransferAuthorization(ownerKeyHash, nonce, signature);

    assertTrue(wallet.transferAuthorizationState(ownerKeyHash, nonce));
}
```

`transferAuthorizationState` returns true for both settled and canceled nonces. This state is independent of relayer and EntryPoint sequences and survives removing and re-adding the owner.

## Validate an ERC-1271 Signature

A registered owner's ERC-1271 signature uses the `SmartWalletMessage` wrapper and the 38-byte envelope prefix. The verifier supplies the original application hash to `isValidSignature`.

```solidity
function test_ERC1271Signature() public view {
    bytes32 applicationHash = keccak256("example application message");
    uint48 validUntil = uint48(block.timestamp + 1 hours);
    bytes32 digest = wallet.hashTypedData(MessageSignLib.hash(
        applicationHash, validUntil, wallet.IMPLEMENTATION()
    ));
    bytes memory signature = abi.encodePacked(
        ownerKeyHash, validUntil, _ecdsaSignature(digest)
    );

    assertEq(wallet.isValidSignature(applicationHash, signature), bytes4(0x1626ba7e));
}
```

A configured hook must also approve validator-based ERC-1271 signatures. Delegated EOAs have a separate raw 65-byte signature path that requires the recovered signer to equal the account address; see the [ERC-1271 reference](./contracts.md#erc-1271-validation).

## Add an Owner with a Chainless Request

Chainless requests require an admin and allow only self-calls to `addOwner` or `upgradeToAndCall`. The relayer sequence still comes from the wallet, while `getChainlessQueueState` supplies the next usable queue ID.

```solidity
function test_ChainlessAddOwner() public {
    uint16 operationType = 0; // Convention for owner additions.
    uint16 queueId = wallet.getChainlessQueueState(operationType);
    require(queueId < type(uint16).max, "Queue exhausted");
    uint192 key = uint192(
        (uint256(196) << 32) | (uint256(operationType) << 16) | uint256(queueId)
    );
    uint256 nonce = (uint256(key) << 64) | uint256(wallet.getNonce(key));
    bytes32 newKeyHash = keccak256(abi.encodePacked(makeAddr("chainless-owner")));
    BatchedCall memory batch = BatchedCall(_singleCall(
        address(wallet), 0,
        abi.encodeCall(IOwnerManager.addOwner, (newKeyHash, address(1), uint256(0)))
    ), nonce);
    uint48 validUntil = uint48(block.timestamp + 1 hours);
    bytes32 digest = wallet.hashTypedDataSansChainId(
        BatchedCallLib.hash(batch, validUntil, wallet.IMPLEMENTATION())
    );
    bytes memory envelope = abi.encodePacked(
        ownerKeyHash, validUntil, _ecdsaSignature(digest)
    );

    vm.prank(relayer);
    wallet.executeWithRelayer(batch, envelope);

    assertTrue(wallet.hasOwner(newKeyHash));
    assertEq(wallet.getChainlessQueueState(operationType), queueId + 1);
}
```

The complete nonce satisfies `nonce >> 96 == 196`. Setting the ordinary nonce key to `196` is not sufficient. The domain omits the chain ID but still binds the account and implementation; matching addresses and acceptable nonce/queue state are needed on each target chain. Accepting queue `N` invalidates queue IDs up to and including `N` for that operation type. See [queue semantics](./contracts.md#nonces-and-chainless-queues).

## Execute with a Passkey

This example creates a local P-256 test key and a WebAuthn assertion using the repository's [test helper](../test/utils/Helper.s.sol). An application instead obtains an assertion from the user's authenticator for the requested challenge. The assertion's JSON indices and signature values must come from that assertion.

```solidity
function test_PasskeyRelayerBatch() public {
    uint256 passkeyPk = 1; // Local test credential.
    (uint256 x, uint256 y) = vm.publicKeyP256(passkeyPk);
    bytes32 keyHash = keccak256(abi.encodePacked(x, y));
    _adminCall(abi.encodeCall(IOwnerManager.addOwner, (keyHash, address(2), uint256(0))));

    BatchedCall memory batch = BatchedCall(
        _singleCall(recipient, 0.1 ether, ""), uint256(wallet.getNonce(0))
    );
    uint48 validUntil = uint48(block.timestamp + 1 hours);
    bytes32 digest = wallet.hashTypedData(
        BatchedCallLib.hash(batch, validUntil, wallet.IMPLEMENTATION())
    );
    (, , bytes32 assertionHash) = HelperLib.getPasskeyMessageHash(digest);
    (bytes32 r, bytes32 s) = vm.signP256(passkeyPk, assertionHash);
    WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(digest, uint256(r), uint256(s));
    bytes32[] memory proofs = new bytes32[](0);
    bytes memory validatorSignature = bytes.concat(abi.encode(x, y), abi.encode(auth, proofs));
    bytes memory envelope = abi.encodePacked(keyHash, validUntil, validatorSignature);

    vm.prank(relayer);
    wallet.executeWithRelayer(batch, envelope);

    assertEq(recipient.balance, 0.1 ether);
}
```

With no Merkle proof, the challenge bytes are `abi.encode(digest)`. Always include the proof array, even when empty: the built-in validator decodes `(WebAuthnAuth, bytes32[])`. The same validator payload can be used with other signature-bearing entry points after signing their respective digests and applying their required envelope prefixes.

## Use a Delegated EOA

A delegated EOA starts with an implicit ECDSA root owner. It does not call factory-only `initialize`. This test models delegation locally, then executes a transfer from the EOA's own address and balance.

```solidity
function test_DelegatedEOA() public {
    vm.signAndAttachDelegation(address(implementation), ownerPk);
    SmartWalletEntry delegatedWallet = SmartWalletEntry(payable(owner));
    vm.deal(owner, 1 ether);
    assertEq(delegatedWallet.ownerCount(), 0); // Root key is not enumerated.
    (address validator, uint256 settings) = delegatedWallet.getOwnerConfig(ownerKeyHash);
    assertEq(validator, address(1));
    assertTrue(delegatedWallet.isAdmin(settings));

    Call[] memory calls = _singleCall(recipient, 0.1 ether, "");
    vm.prank(owner);
    delegatedWallet.execute(calls);

    assertEq(recipient.balance, 0.1 ether);
}
```

This cheatcode example does not submit a delegation transaction to a network. Actual delegation requires an EIP-7702 authorization transaction; it is separate from the v0.7 UserOperation flow. See [delegated account lifecycle](./architecture.md#delegated-eoas).

## Simulate and Estimate Gas

Simulate the actual relayer entry point with a valid signed request. The repository does not provide a `SmartWalletSimulator` contract, and `delegateAndRevert` does not return predefined gas metrics.

The following ethers v6 helper uses the account address, relayer address, and signed batch prepared by the application. `batchedCall` is an object with `calls` and `nonce`; each call has `target`, `value`, and hex `data`. Use `bigint` for integer fields and a hex string for `validatorData`.

```javascript
import { Interface, JsonRpcProvider } from "ethers";

async function estimateRelayerGas({
  rpcUrl,
  walletAddress,
  relayerAddress,
  batchedCall,
  validatorData,
}) {
  const provider = new JsonRpcProvider(rpcUrl);
  const abi = new Interface([
    "function executeWithRelayer(tuple(tuple(address target,uint256 value,bytes data)[] calls,uint256 nonce) batchedCall,bytes validatorData)",
  ]);
  const data = abi.encodeFunctionData("executeWithRelayer", [
    batchedCall,
    validatorData,
  ]);
  const transaction = {
    from: relayerAddress,
    to: walletAddress,
    data,
  };

  await provider.call(transaction);
  return provider.estimateGas(transaction);
}
```

Both RPC methods simulate without submitting a transaction or consuming the nonce. The account must have enough assets, and the signature, expiry, nonce, and hook policy must be valid at the simulated state. A later state change can invalidate the request. For UserOperations, use the bundler's ERC-4337 estimation flow; estimating the relayer method does not estimate EntryPoint validation or paymaster costs.

## Common Integration Mistakes

| Mistake                                                                  | Correct construction                                            |
| ------------------------------------------------------------------------ | --------------------------------------------------------------- |
| Hashing an ECDSA public-key blob as the owner key                        | Hash the packed 20-byte signer address                          |
| Using `abi.encode` for the outer signature envelope                      | Use packed concatenation with the exact prefix widths           |
| Using the wallet's nonce for a UserOperation                             | Query EntryPoint for the account's packed nonce                 |
| Encoding `execute(calls)` in a UserOperation                             | Encode `executeUserOp.selector` followed by `abi.encode(calls)` |
| Calling owner management directly from an external admin                 | Route it through an authorized wallet self-call                 |
| Treating `address(0)` as the wallet target                               | Use the actual account address                                  |
| Reusing a relayer signature for UserOperations or transfer authorization | Build the digest and envelope for the selected entry point      |
| Encoding only a Passkey assertion without its proof array                | Encode the assertion together with `bytes32[] proofs`           |

For additional executable scenarios, see [factory tests](../test/SmartWalletFactory.t.sol), [execution tests](../test/Execution.t.sol), [UserOperation tests](../test/UserOpSelector.t.sol), [transfer-authorization tests](../test/TransferWithAuthorization.t.sol), and [Passkey tests](../test/PasskeyValidator.t.sol).
