# 本地区块链测试指南

本指南将详细介绍如何在本地测试 OKX Smart Wallet 的 sendUop 脚本。

## 🏁 快速开始

### 1. 启动本地 Hardhat 网络

在 **第一个终端** 启动本地区块链：

```bash
cd okx-smart-wallet
npx hardhat node
```

这将启动一个本地区块链网络，默认监听在 `http://127.0.0.1:8545`，Chain ID 为 `31337`。

### 2. 部署合约

在 **第二个终端** 部署必要的合约：

```bash
# 部署核心合约
npx hardhat run scripts/DeployInit.sol --network localhost

# 或者使用 foundry 部署
forge script scripts/DeployInit.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 3. 设置环境变量

创建 `.env` 文件或直接设置环境变量：

```bash
# 使用 Hardhat 提供的测试私钥
export DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 设置合约地址（部署后获得）
export SMART_WALLET_FACTORY=0x...
export SMART_WALLET_IMPL=0x...
export ECDSA_VALIDATOR=0x...
export PASSKEY_VALIDATOR=0x...
```

### 4. 运行测试脚本

```bash
npx hardhat run scripts/sendUop.ts --network localhost
```

## 📋 详细步骤

### Step 1: 准备环境

确保你有正确的依赖：

```bash
npm install
# 或
yarn install
```

### Step 2: 配置 Hardhat 网络

确认 `hardhat.config.ts` 中包含本地网络配置：

```typescript
networks: {
  hardhat: {
    chainId: 31337
  },
  localhost: {
    url: "http://127.0.0.1:8545",
    chainId: 31337
  }
}
```

### Step 3: 部署脚本示例

创建一个简单的部署脚本 `scripts/deploy-local.ts`：

```typescript
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying contracts for local testing...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  // 1. Deploy SmartWallet implementation
  const SmartWallet = await ethers.getContractFactory("SmartWallet");
  const smartWallet = await SmartWallet.deploy();
  await smartWallet.waitForDeployment();
  console.log("✅ SmartWallet deployed to:", await smartWallet.getAddress());
  
  // 2. Deploy SmartWalletFactory
  const SmartWalletFactory = await ethers.getContractFactory("SmartWalletFactory");
  const factory = await SmartWalletFactory.deploy();
  await factory.waitForDeployment();
  await factory.initialize();
  console.log("✅ SmartWalletFactory deployed to:", await factory.getAddress());
  
  // 3. Deploy ECDSAValidator
  const ECDSAValidator = await ethers.getContractFactory("ECDSAValidator");
  const ecdsaValidator = await ECDSAValidator.deploy();
  await ecdsaValidator.waitForDeployment();
  console.log("✅ ECDSAValidator deployed to:", await ecdsaValidator.getAddress());
  
  // 4. Deploy PasskeyValidator
  const PasskeyValidator = await ethers.getContractFactory("PasskeyValidator");
  const passkeyValidator = await PasskeyValidator.deploy();
  await passkeyValidator.waitForDeployment();
  console.log("✅ PasskeyValidator deployed to:", await passkeyValidator.getAddress());
  
  // 5. Deploy test ERC20 token
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const testToken = await MockERC20.deploy("Test Token", "TEST");
  await testToken.waitForDeployment();
  console.log("✅ Test Token deployed to:", await testToken.getAddress());
  
  // Print environment variables to set
  console.log("\n📋 Set these environment variables:");
  console.log(`export SMART_WALLET_FACTORY=${await factory.getAddress()}`);
  console.log(`export SMART_WALLET_IMPL=${await smartWallet.getAddress()}`);
  console.log(`export ECDSA_VALIDATOR=${await ecdsaValidator.getAddress()}`);
  console.log(`export PASSKEY_VALIDATOR=${await passkeyValidator.getAddress()}`);
  console.log(`export TEST_TOKEN=${await testToken.getAddress()}`);
  console.log(`export DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

### Step 4: 运行部署脚本

```bash
npx hardhat run scripts/deploy-local.ts --network localhost
```

### Step 5: 测试 sendUop 脚本

现在可以运行主要的测试脚本：

```bash
npx hardhat run scripts/sendUop.ts --network localhost
```

## 🔧 本地测试特性

### 自动资金注入

脚本会自动检测本地网络（Chain ID 31337）并：

1. **给 deployer 账户注入 ETH**：
```typescript
if (chainId === 31337n) {
  await network.provider.send("hardhat_setBalance", [
    deployer.address,
    "0x1000000000000000000000000" // 巨量 ETH
  ]);
}
```

2. **给预测的钱包地址注入 ETH**：
```typescript
if (chainId === 31337n && !accountExists) {
  const tx = await deployer.sendTransaction({
    to: sender,
    value: hre.ethers.parseEther("1.0"),
  });
  await tx.wait();
}
```

### 本地网络优势

- **快速交易确认**：无需等待区块时间
- **无限 ETH**：可以自由注入资金
- **重置网络**：重启节点即可重置状态
- **详细日志**：可以看到所有交易和合约调用

## 🧪 测试场景

### 1. 基础 UserOp 测试

```bash
# 测试基本的 ETH 转账 UserOperation
npx hardhat run scripts/sendUop.ts --network localhost
```

### 2. 自定义执行测试

修改 `sendUop.ts` 中的 calls 数组来测试不同操作：

```typescript
const calls: Call[] = [
  // 多个 ETH 转账
  calldataUtils.generateTransferCalldata(
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", // 第二个测试账户
    hre.ethers.parseEther("0.1")
  ),
  calldataUtils.generateTransferCalldata(
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", // 第三个测试账户
    hre.ethers.parseEther("0.05")
  ),
  
  // ERC20 代币操作
  calldataUtils.generateERC20TransferCalldata(
    testTokenAddress,
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    hre.ethers.parseUnits("100", 18)
  )
];
```

### 3. 测试不同验证器

```typescript
// 测试 ECDSA 验证器
const ecdsaOwner = calldataUtils.createECDSAOwner(
  deployer.address,
  ecdsaValidatorAddress
);

// 测试 Passkey 验证器
const passkeyOwner = calldataUtils.createPasskeyOwner(
  pubKeyX,
  pubKeyY,
  passkeyValidatorAddress
);
```

## 🛠 调试和监控

### 1. 查看网络状态

```bash
# 查看账户余额
npx hardhat run scripts/check-balance.ts --network localhost

# 查看合约代码
npx hardhat run scripts/check-contract.ts --network localhost
```

### 2. 创建调试脚本

`scripts/debug-wallet.ts`:

```typescript
import { contracts } from "./utils/contracts";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  // 检查合约是否正确部署
  try {
    const factory = await contracts.getSmartWalletFactory(deployer);
    const validator = await contracts.getECDSAValidator(deployer);
    
    console.log("✅ Factory address:", await factory.getAddress());
    console.log("✅ Validator address:", await validator.getAddress());
    console.log("✅ Deployer balance:", await deployer.provider.getBalance(deployer.address));
    
  } catch (error) {
    console.error("❌ Contract loading failed:", error.message);
  }
}

main().catch(console.error);
```

## 🐛 常见问题解决

### 问题 1: "Cannot find module" 错误
```bash
# 重新安装依赖
rm -rf node_modules package-lock.json
npm install
```

### 问题 2: 合约地址未设置
```bash
# 确保环境变量正确设置
echo $SMART_WALLET_FACTORY
echo $ECDSA_VALIDATOR

# 或在脚本中硬编码测试地址
```

### 问题 3: Gas 估算失败
```bash
# 增加 gas limit
const userOp = userOpUtils.createUserOperation({
  // ...
  verificationGasLimit: 3000000, // 增加到 3M
  callGasLimit: 1000000,         // 增加到 1M
});
```

### 问题 4: 网络连接问题
```bash
# 确认 Hardhat 节点正在运行
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545
```

## 📊 测试结果示例

成功的测试运行应该显示类似输出：

```
🚀 OKX Smart Wallet - Send User Operation
=========================================
Deployer address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Network: localhost
Chain ID: 31337
💰 Funded deployer account for local testing

📄 Loading contract instances...
✅ Contracts loaded successfully
- EntryPoint: 0x0000000071727De22E5E9d8BAf0edAc6f37da032
- Factory: 0x5FbDB2315678afecb367f032d93F642f64180aa3
- SmartWallet Implementation: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
- ECDSA Validator: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

⚙️ Setting up wallet configuration...
Initial owner keyHash: 0x...
Initial owner validator: 0x...

🔍 Generating initCode and predicting sender...
Predicted sender address: 0x...
InitCode length: 196
Account exists: ❌ No
💰 Funded predicted account with 1 ETH

📝 Creating execution calls...
Number of calls: 1
Call 1: { target: '0x...', value: '0.001 ETH', dataLength: 0 }

🔨 Creating User Operation...
UserOp created:
- Sender: 0x...
- Nonce: 0x0
- InitCode: 196 bytes
- CallData length: 132

✍️ Signing User Operation...
Signature generated, length: 96

✅ User Operation prepared successfully!
```

这样你就可以在完全本地的环境中测试所有功能了！🎯
