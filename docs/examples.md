# Examples and Use Cases

This document provides practical code examples and common use cases for the Smart Wallet system.

## Code Examples

### 1. Account Creation

#### Account Creation Pattern
```solidity
// 1. Predict wallet address
address predictedAddress = factory.getAddress(initialOwners, salt);

// 2. Fund the predicted address if needed
// ... fund logic ...

// 3. Create wallet
address wallet = factory.createAccount(initialOwners, salt);

// 4. Verify address matches prediction
require(wallet == predictedAddress, "Address mismatch");
```

#### Basic Account Creation
```solidity
// 1. Prepare initial owners
InitialOwner[] memory initialOwners = new InitialOwner[](1);
initialOwners[0] = InitialOwner({
    keyHash: keccak256(abi.encodePacked(publicKey)),
    validator: ecdsaValidator
});

// 2. Generate salt for deterministic address
uint256 salt = uint256(keccak256(abi.encodePacked("my-wallet", block.timestamp)));

// 3. Create account
address wallet = factory.createAccount(initialOwners, salt);
```

#### Account Creation with Initial Call
```solidity
// 1. Prepare initial call (e.g., approve tokens)
Call[] memory initialCalls = new Call[](1);
initialCalls[0] = Call({
    target: tokenAddress,
    value: 0,
    data: abi.encodeWithSelector(
        IERC20.approve.selector,
        spenderAddress,
        amount
    )
});

// 2. Create BatchedCall
BatchedCall memory batchedCall = BatchedCall({
    calls: initialCalls,
    nonce: 0
});

// 3. Create account with initial execution
address wallet = factory.createAccountWithCall(
    initialOwners,
    salt,
    batchedCall,
    validatorData
);
```


### 2. Direct Execution

#### Single Call Execution
```solidity
// Execute single call
Call memory call = Call({
    target: contractAddress,
    value: 0,
    data: abi.encodeWithSelector(
        IContract.functionName.selector,
        param1,
        param2
    )
});

Call[] memory calls = new Call[](1);
calls[0] = call;

smartWallet.execute(calls);
```

#### Batch Call Execution
```solidity
// Execute multiple calls in single transaction
Call[] memory calls = new Call[](3);

// Approve token 1
calls[0] = Call({
    target: token1,
    value: 0,
    data: abi.encodeWithSelector(IERC20.approve.selector, router, amount1)
});

// Approve token 2
calls[1] = Call({
    target: token2,
    value: 0,
    data: abi.encodeWithSelector(IERC20.approve.selector, router, amount2)
});

// Execute swap
calls[2] = Call({
    target: router,
    value: 0,
    data: abi.encodeWithSelector(IRouter.swap.selector, swapData)
});

smartWallet.execute(calls);
```

#### Execution Pattern (Best Practice)
```solidity
// 1. Prepare calls
Call[] memory calls = new Call[](2);
calls[0] = Call(target1, 0, data1);
calls[1] = Call(target2, value2, data2);

// 2. Execute directly (owner only)
smartWallet.execute(calls);

// 3. Or execute through relayer
BatchedCall memory batchedCall = BatchedCall(calls, nonce);
bytes memory validatorData = abi.encode(keyHash, validUntil, signature);
smartWallet.executeWithRelayer(batchedCall, validatorData);
```

### 3. Relayer Execution

#### Basic Relayer Execution
```solidity
// 1. Prepare calls
Call[] memory calls = new Call[](1);
calls[0] = Call({
    target: targetContract,
    value: 0,
    data: functionData
});

// 2. Create BatchedCall
BatchedCall memory batchedCall = BatchedCall({
    calls: calls,
    nonce: getNonce(0)
});

// 3. Prepare validator data
bytes32 keyHash = keccak256(abi.encodePacked(publicKey));
uint48 validUntil = uint48(block.timestamp + 1 hours);
bytes memory signature = signMessage(messageHash, privateKey);

bytes memory validatorData = abi.encode(keyHash, validUntil, signature);

// 4. Execute through relayer
smartWallet.executeWithRelayer(batchedCall, validatorData);
```

#### Relayer Execution with Multiple Calls
```solidity
// 1. Prepare complex operation
Call[] memory calls = new Call[](4);

// Approve tokens
calls[0] = Call(token1, 0, approveData1);
calls[1] = Call(token2, 0, approveData2);

// Execute operations
calls[2] = Call(router, 0, swapData);
calls[3] = Call(contract, 0, callbackData);

// 2. Create batch call
BatchedCall memory batchedCall = BatchedCall({
    calls: calls,
    nonce: getNonce(0)
});

// 3. Execute through relayer
smartWallet.executeWithRelayer(batchedCall, validatorData);
```

### 4. ERC-4337 Execution

#### UserOperation Execution
```solidity
// 1. Prepare UserOperation
PackedUserOperation memory userOp = PackedUserOperation({
    sender: walletAddress,
    nonce: getNonce(0),
    initCode: "",
    callData: abi.encodeWithSelector(
        ISmartWallet.execute.selector,
        calls
    ),
    accountGasLimits: packGasLimits(100000, 1000000),
    preVerificationGas: 50000,
    gasFees: packGasFees(maxFeePerGas, maxPriorityFeePerGas),
    paymasterAndData: "",
    signature: userSignature
});

// 2. Execute through EntryPoint
entryPoint.handleOps([userOp], beneficiary);
```

### 5. Owner Management

#### Owner Management Pattern (Best Practice)
```solidity
// 1. Pack settings
uint256 settings = ownerManager.packSettings(true, 0, address(0));

// 2. Add owner
ownerManager.addOwner(keyHash, validator, settings);

// 3. Update owner
uint256 newSettings = ownerManager.packSettings(false, expiration, hook);
ownerManager.updateOwner(keyHash, newValidator, newSettings);

// 4. Remove owner
ownerManager.removeOwner(keyHash);
```

#### Adding New Owner
```solidity
// 1. Pack owner settings
uint256 settings = ownerManager.packSettings(
    false,           // isAdmin
    block.timestamp + 24 hours,  // expiration
    address(0)       // hook
);

// 2. Add owner
bytes32 keyHash = keccak256(abi.encodePacked(newPublicKey));
ownerManager.addOwner(keyHash, validatorAddress, settings);
```

#### Updating Owner Settings
```solidity
// 1. Get current settings
uint256 currentSettings = ownerManager.getOwnerSettings(keyHash);

// 2. Update specific fields
bool isAdmin = ownerManager.isAdmin(currentSettings);
uint40 expiration = ownerManager.getExpiration(currentSettings);
address hook = ownerManager.getHook(currentSettings);

// 3. Pack new settings
uint256 newSettings = ownerManager.packSettings(
    true,            // make admin
    expiration,      // keep same expiration
    newHookAddress   // update hook
);

// 4. Update owner
ownerManager.updateOwner(keyHash, newValidator, newSettings);
```

#### Removing Owner
```solidity
// Remove owner by keyHash
ownerManager.removeOwner(keyHash);
```

### 6. Gas Estimation

#### Simulating Execution
```solidity
// 1. Prepare calls for simulation
Call[] memory calls = new Call[](2);
calls[0] = Call(token1, 0, approveData);
calls[1] = Call(router, 0, swapData);

BatchedCall memory batchedCall = BatchedCall({
    calls: calls,
    nonce: 0
});

// 2. Prepare fake validator data for simulation
bytes memory fakeValidatorData = abi.encode(
    keyHash,
    block.timestamp + 1 hours,
    fakeSignature
);

// 3. Simulate to get gas estimate
try smartWallet.delegateAndRevert(
    address(simulator),
    abi.encodeWithSelector(
        ISmartWalletSimulator.simulateExecuteWithRelayer.selector,
        batchedCall,
        validator,
        fakeValidatorData
    )
) {
    // This should always revert with gas info
} catch (bytes memory revertData) {
    // Check if it's a SimulateExecution error
    if (bytes4(revertData[:4]) == Errors.SimulateExecution.selector) {
        // Decode the gas metrics from the error
        (uint256 executionGas, uint256 intrinsicGas, uint256 totalGas) = abi.decode(
            revertData[4:],
            (uint256, uint256, uint256)
        );
        
        // Use totalGas for gas estimation
        uint256 gasEstimate = totalGas;
        console.log("Execution gas:", executionGas);
        console.log("Intrinsic gas:", intrinsicGas);
        console.log("Total gas estimate:", totalGas);
    } else {
        // Handle other errors
        revert("Simulation failed with unexpected error");
    }
}
```

