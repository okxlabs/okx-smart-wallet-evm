# DEPLOY_DRY_RUN.md — 分叉模拟运行计划（部署前测试清单）

> 该计划可由操作员本地执行，用于在主网分叉上验证部署逻辑，**无需广播任何交易**，须在正式部署前完成。本计划由第 9 阶段生成，**由操作员在本地运行**。整个过程不使用真实部署者密钥，不向公共网络发送任何交易，也不进行任何实时区块链浏览器验证。

## 模拟运行状态：已推迟（DEFERRED）

- **阶段内执行：** 未执行。本阶段未配置分叉 RPC，`FORK_RPC_URL` 和 `MAINNET_RPC_URL` 均未设置，Oli 运行配置中也不包含分叉 RPC 字段，因此无可探测或执行的内容。该状态与 `PASS` 兼容：阶段状态不依赖模拟运行结果。
- **操作员操作：** 在正式部署前，针对目标链的分叉执行本计划，并将结果（PASS / FAILED）与 `DEPLOY_CHECK.md` 一并记录至部署日志。

本文档的状态值含义：`PASS`（已执行且成功）· `FAILED`（已执行但回滚/报错）· `SKIPPED`（RPC 已配置但不可达）· `DEFERRED`（未配置分叉 RPC——本次运行）。

---

## 1. 模拟运行验证内容

针对分叉环境对 `script/deploy.s.sol`（`DeployInit`）进行端到端模拟执行，验证以下内容：

- 部署**顺序**：`SmartWalletEntry`（实现合约）→ `SmartWalletFactory(implementation)`。
- 通过 **EIP-2470 单例工厂的 CREATE2** 路径（若分叉上不存在该工厂，则回退至普通 CREATE）可正常执行并返回非零代码。
- 确定性的 **CREATE2 预测地址与实际**部署地址一致（仅在工厂存在时生效）。
- **接线验证**：`SmartWalletFactory.IMPLEMENTATION()` 等于已部署的 `SmartWalletEntry` 地址。
- **依赖接线**：实现合约的 `entryPoint()` 等于标准 ERC-4337 v0.7 EntryPoint 地址。
- **无所有者安全性**：两个已部署合约均未被单例工厂所有，也不等于单例工厂地址（由构造逻辑保证——不存在 owner/admin 设置器）。
- **接口验证**：`SmartWalletEntry.supportsInterface(0x86c5a9e1)` 返回 `true`。
- （可选，建议进行冒烟测试）通过工厂创建账户、执行一次正常路径 ERC-20 结算，以及回放回滚测试（设计文档 §14 冒烟测试）。

模拟运行不会改变任何生产状态，也不会广播任何交易。

---

## 2. 分叉须匹配的目标链

| 字段 | 值 |
|------|----|
| 链 | 以太坊主网 |
| 链 ID | **1** |
| EVM | **Cancun**（EIP-1153 瞬态存储）——**必须**。非 Cancun 分叉无法触发 TWA 原生重入瞬态锁，请勿使用。 |

分叉所在链上必须存在 EIP-2470 单例工厂（`0xce0042B868300000d44A59004Da54A005ffdcf9f`）和 ERC-4337 v0.7 EntryPoint（`0x0000000071727De22E5E9d8BAf0edAc6f37da032`）（以太坊主网上均已存在）。标准主网分叉会自动继承这两者。

---

## 3. 操作员须提供的环境变量

在运行前于 Shell 中导出以下变量（切勿写入任何已提交的文件）：

| 变量 | 用途 | 模拟运行值 |
|------|------|------------|
| `FORK_RPC_URL` | 目标链分叉（或归档节点）的 RPC 端点。仅通过环境变量提供，切勿内联或提交。 | 您的分叉/归档节点端点 |
| `DEPLOYER_PRIVATE_KEY` | 由脚本通过 `vm.envUint` 读取。模拟运行时请使用**临时**密钥，无需资金或任何权限——仅用于推导模拟发送者，不会广播任何内容。 | 临时测试密钥（切勿使用真实部署者密钥） |
| `DEPLOY_FACTORY_SALT` | 由脚本通过 `vm.envBytes32` 读取。模拟运行时可使用任意 `bytes32`；建议使用生产环境预定的值，以同时验证预测地址。 | 一个 `bytes32` 盐值 |

解析后的 `FORK_RPC_URL` 可能包含密钥——请仅保存于环境变量中，切勿打印，切勿提交。若某命令将其输出，请手动脱敏处理。

---

## 4. 模拟运行命令（精确命令，使用操作员提供的 RPC，无广播）

从项目根目录（`okx-smart-wallet-dev/`）运行：

```bash
# 先离线构建，防止 forge 自动重置 lib/ 子模块（限定生产范围构建）。
FOUNDRY_OFFLINE=true forge build src script

# 分叉模拟运行——不加 --broadcast、不加 --verify、不加私钥参数。仅模拟。
forge script script/deploy.s.sol:DeployInit --rpc-url "$FORK_RPC_URL"
```

请勿在此命令中添加广播标志、验证标志或任何私钥标志。如需逐笔交易的模拟追踪，可添加 `-vvvv`（仅增加输出详情）。

---

## 5. 预期输出

脚本将打印以下内容（地址为分叉模拟值）：

- `Deployer: <address derived from the throwaway key>`
- `Deploy factory salt:` 后跟 `bytes32` 盐值。
- `Singleton factory present on chain: true`（主网分叉上）。
- 每个合约对应：`method: create2 (EIP-2470 singleton factory)`、`predicted address` 及 `deployed at:`——预测地址与部署地址必须相等。
- `SmartWallet implementation address verified on SmartWalletFactory!`
- 一个 `=== Deployment Summary ===` 块，包含 `SmartWallet Implementation address` 和 `SmartWalletFactory address`。
- `DeployInit script completed successfully`。

若分叉上不存在 EIP-2470 工厂，日志将改为显示 `method: create (fallback, reason=factory-unavailable)`，且地址不具确定性——在此类分叉上可接受，但目标链（主网）上存在该工厂。

---

## 6. 只读部署后检查（针对模拟/分叉地址执行）

可选择针对同一分叉运行只读验证脚本（无需广播，视图调用无需私钥）：

```bash
SMART_WALLET=<implementation-address> \
SMART_WALLET_FACTORY=<factory-address> \
EXPECTED_CHAIN_ID=1 \
forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url "$FORK_RPC_URL"
```

验证内容包括：两个地址均有代码；工厂 `IMPLEMENTATION()` == 实现合约地址；实现合约自引用匹配；`entryPoint()` == `0x0000000071727De22E5E9d8BAf0edAc6f37da032`；`supportsInterface(0x86c5a9e1)` == true；两个地址均不等于单例工厂地址；链 ID == 1。

建议额外进行以下冒烟测试（可选，在分叉上验证功能）：通过 `SmartWalletFactory.createAccount(...)` 创建账户，执行一次正常路径 ERC-20 `executeTransferWithAuthorization`，再尝试回放并确认其以 `AuthorizationAlreadyUsed` 回滚。确认 `forge inspect SmartWalletEntry storageLayout` 显示 TWA ERC-7201 命名空间与账户自定义存储根 `0x653ff6dc…` 不同。

---

## 7. 操作员通过/失败标准及停止条件

满足以下**所有条件**时判定为 **PASS**：
- 脚本执行完成并打印 `DeployInit script completed successfully`。
- 在工厂存在的分叉上，每个合约的 `predicted address == deployed at`，且该地址具有非零代码。
- `SmartWalletFactory.IMPLEMENTATION()` 等于已部署的 `SmartWalletEntry` 地址（脚本内断言未回滚）。
- `entryPoint()` == 标准 v0.7 EntryPoint，且 `supportsInterface(0x86c5a9e1)` == true。

出现以下**任一情况**时判定为 **FAILED / 停止**（解决前不得继续正式部署）：
- 脚本回滚，或脚本内 `Factory implementation mismatch` / EntryPoint / 接口断言触发。
- 某个 CREATE2 预测地址与实际部署地址不一致。
- `cast chain-id --rpc-url "$FORK_RPC_URL"` 未返回 `1`，或分叉未激活 Cancun。
- 任一部署地址代码为空，或与单例工厂地址冲突。

记录失败时，仅记录**错误类别**（例如：`script reverted`、`chain-id mismatch`、`address mismatch`、`transport error`）——切勿记录原始 `forge`/`cast` 输出，以免泄露 RPC URL 或密钥。

---

## 8. 安全约束（始终遵守）

- 切勿在模拟运行命令中添加 `--broadcast`、`--verify` 或任何私钥 CLI 参数。
- 切勿使用真实部署者密钥、助记词或生产环境密钥。仅使用临时密钥进行模拟。
- 切勿打印或提交已解析的 `FORK_RPC_URL`；在任何共享日志中将其脱敏为 `<fork RPC redacted>`。
- 本模拟运行不向公共网络发送任何交易，也不执行任何实时区块链浏览器验证。
