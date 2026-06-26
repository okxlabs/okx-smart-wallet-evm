# CONTRACT_INTERFACE.md — 后端合约接口交付文档（授权转账）

## 1. 接口交付状态

| 字段 | 值 |
|-------|-------|
| 状态 | `IMPLEMENTATION_MATCHED` |
| 目标链 | EVM — 以太坊主网（chainId 1），Cancun 版本（需要 EIP-1153） |
| 编译器 / 框架 | Solidity `0.8.29`，Foundry；`evm_version = cancun`，`optimizer = true`，`optimizer_runs = 100` |
| 源合约 | `src/interfaces/ITransferWithAuthorization.sol`（已冻结 ABI），`src/TransferWithAuthorization.sol`（混入合约），内联至可部署账户合约 `src/SmartWalletEntry.sol`（`SmartWalletEntry`） |
| ABI 文件 | `docs/delivery/abi/ITransferWithAuthorization.abi.json`（授权转账接口面）。完整账户 ABI 在构建时生成于 `out/SmartWalletEntry.sol/SmartWalletEntry.json`。 |
| 使用的构建命令 | `forge build` |
| 与接口规范的关系 | 严格实现 `docs/process/INTERFACE_SPEC.md` 中定义的后端集成覆盖层；函数/事件/错误签名与该规范及 `docs/process/DESIGN.md` 保持一致，未作任何变更。 |
| 提交哈希 | TBD（最终提交由交付阶段创建） |

账户 ABI 的变更**纯为增量扩展**：新增外部函数、两个新事件、五个新自定义错误，以及一个新的 ERC-165 接口 ID（`0x86c5a9e1`）。原有函数、事件、错误及存储布局均未更改或删除。

## 2. 后端集成概述

- **合约职责：** 智能钱包账户在签名时间窗口内，对每个随机授权随机数，恰好执行一次由所有者签名的资产转账（任意 ERC-20 代币或原生 ETH），转账来源为账户自身余额，并可选择通过签名密钥的支出策略钩子进行约束。此外，所有者可撤销未使用的授权，并提供只读的状态与域名发现接口。
- **后端可调用（需发送交易）的流程：**
  - `executeTransferWithAuthorization` — 无许可结算；任何中继器/协助方提交所有者签名的授权并支付 Gas。
  - `receiveWithAuthorization` — 仅限收款方（`msg.sender == to`）进行结算；适用于合约收款方需要在其自身流程中原子性完成收款的场景。
  - `cancelTransferAuthorization` — 撤销未使用的随机数；形式 A（带签名）可由任何人中继，形式 B（空签名）为账户在其自身执行路径中嵌套的自调用。
- **只读查询流程（eth_call）：** `transferAuthorizationState`、`TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`、`supportsInterface(0x86c5a9e1)`，以及公共类型哈希/常量获取器（`EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH`、`RECEIVE_WITH_AUTHORIZATION_TYPEHASH`、`CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH`、`INTERFACE_ID`、`NATIVE_ASSET`、`SIGNATURE_ENVELOPE_MIN_LENGTH`）。
- **事件/日志索引流程：** `TransferAuthorizationUsed`（结算）和 `TransferAuthorizationCanceled`（撤销）。
- **管理员/操作员专属流程：** `cancelTransferAuthorization` 形式 B 要求调用者为账户本身；无新增管理员角色——升级权限保持不变。
- **前端/用户钱包专属（后端不得直接调用）：** 生成 EIP-712 所有者签名。后端不持有所有者密钥；由用户钱包（ECDSA 或 Passkey）签名，后端仅负责组装信封并提交。

**最关键的事实：** 链上 `signature` 参数为**信封**格式，即 `keyHash (32 字节) || ownerSignature`。账户从 `signature[:32]` 中恢复 `keyHash`，路由至对应验证器，并对 `signature[32:]` 在**直接** EIP-712 摘要上进行验证。此前缀为 **32 字节**——**不是**现有中继器/UserOp 路径使用的 38 字节 `keyHash||validUntil` 前缀，且摘要**不得**被 ERC-1271 / personal-sign 二次封装。

## 3. 合约地址

| 环境 | 合约 | 地址 | 来源 |
|-------------|----------|---------|--------|
| 本地 / 分叉网络 | `SmartWalletEntry`（账户合约，实现 `ITransferWithAuthorization`） | TBD | 部署演练 |
| 测试网 | `SmartWalletEntry` | TBD | 运营方提供 |
| 主网 | `SmartWalletEntry` | TBD | 运营方提供 |

每个 TWA 授权均绑定至特定账户地址（即 EIP-712 域中的 `verifyingContract`）和链 ID。后端必须将实际账户地址同时用作调用目标和签名授权的 `from` 字段。

## 4. 函数参考

### `executeTransferWithAuthorization`

| 字段 | 内容 |
|-------|---------|
| 合约 | `SmartWalletEntry`（通过 `ITransferWithAuthorization`） |
| 函数 | `executeTransferWithAuthorization` |
| 签名 | `executeTransferWithAuthorization(address token,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce,bytes signature)` |
| 选择器 | `0x0e720282` |
| 可变性 / 访问类型 | nonpayable；无许可（任何调用者） |
| 必需调用者 / 签名者 | 调用者 = 任意中继器/协助方；签名者 = 账户的已注册所有者密钥 |
| 必需角色 | 调用者无需角色；签名必须来自已注册（且未过期）的账户密钥 |
| 参数 | `token`：ERC-20 代币地址，或用于原生 ETH 的 `NATIVE_ASSET`（`0xEeee…EEeE`）。`to`：收款地址，不得为零地址，也不得为原生资产哨兵地址。`value`：金额（wei / 代币最小单位）。`validAfter`/`validBefore`：开区间 Unix 时间戳边界（严格介于两者之间有效）。`authorizationNonce`：随机 `bytes32`，一次性使用。`signature`：`keyHash(32) || ownerSignature`。 |
| 返回值 | 无 |
| 发送的价值 | 无（不得发送 `msg.value`；原生 ETH 来源于账户余额） |
| 状态变更 | 标记 `authorizationNonce` 为已使用（在转账前），然后将 `value` 数量的 `token` 从账户转移至 `to` |
| 事件 / 日志 | `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` |
| 错误 / 回滚 | `AuthorizationAlreadyUsed`、`AuthorizationNotYetValid`、`AuthorizationExpired`、`InvalidRecipient`、`InvalidSignature`、`NonAdminSelfCall`、`ReentrantSettle`，钩子回滚，代币/原生 ETH 转账失败 |
| 后端处理 | 提交前通过 `eth_call` 模拟；以 `TransferAuthorizationUsed` 事件作为结算的权威证明；对终止状态的回滚不得重试；每个随机数至多结算一次 |
| 安全说明 | `to`/`value` 受签名约束——抢先交易无法改变结果；不得对摘要进行二次封装；32 字节前缀为强制要求 |

### `receiveWithAuthorization`

| 字段 | 内容 |
|-------|---------|
| 合约 | `SmartWalletEntry`（通过 `ITransferWithAuthorization`） |
| 函数 | `receiveWithAuthorization` |
| 签名 | `receiveWithAuthorization(address token,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce,bytes signature)` |
| 选择器 | `0x88b7ab63` |
| 可变性 / 访问类型 | nonpayable；受限（`msg.sender == to`） |
| 必需调用者 / 签名者 | 调用者必须为收款方 `to`（通常为收款合约）；签名者 = 已注册所有者密钥 |
| 必需角色 | 调用者必须等于 `to`，否则触发 `CallerNotPayee` |
| 参数 | 与 `executeTransferWithAuthorization` 相同，但使用**不同的**接收类型哈希进行签名 |
| 返回值 | 无 |
| 发送的价值 | 无 |
| 状态变更 | 与 `executeTransferWithAuthorization` 相同 |
| 事件 / 日志 | `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` |
| 错误 / 回滚 | `CallerNotPayee`，以及 `executeTransferWithAuthorization` 的所有条件；接收授权不能通过执行路径重放，反之亦然 |
| 后端处理 | 收款合约在其自身逻辑中调用此函数；后端将签名的接收授权提供给该合约 |
| 安全说明 | 独立的类型哈希将接收与执行隔离；为原子收款的收款方提供抗抢先交易保护 |

### `cancelTransferAuthorization`

| 字段 | 内容 |
|-------|---------|
| 合约 | `SmartWalletEntry`（通过 `ITransferWithAuthorization`） |
| 函数 | `cancelTransferAuthorization` |
| 签名 | `cancelTransferAuthorization(bytes32 authorizationNonce,bytes signature)` |
| 选择器 | `0xeca10231` |
| 可变性 / 访问类型 | nonpayable |
| 必需调用者 / 签名者 | 形式 A：调用者 = 任意中继器，由已注册账户密钥在取消类型哈希下签名。形式 B：空 `signature`，调用者 = 账户本身（`address(this)`），嵌套在账户的执行路径中。 |
| 必需角色 | 形式 A：已注册账户密钥签名。形式 B：账户自调用（否则触发 `NotFromSelf`）。 |
| 参数 | `authorizationNonce`：待撤销的随机数。`signature`：形式 A 为 `keyHash(32) || ownerSignature`，形式 B 为空（`0x`）。 |
| 返回值 | 无 |
| 发送的价值 | 无（不移动任何资金） |
| 状态变更 | 将 `authorizationNonce` 标记为终止态（视为已使用） |
| 事件 / 日志 | `TransferAuthorizationCanceled(authorizer=account, authorizationNonce)` |
| 错误 / 回滚 | `AuthorizationAlreadyUsed`（已使用或已取消）、`InvalidSignature`（形式 A）、`NotFromSelf`（形式 B 由非账户地址调用） |
| 后端处理 | 索引 `TransferAuthorizationCanceled`；已取消的随机数**不得**标记为已支付 |
| 安全说明 | 随机数为账户作用域，因此任何已注册密钥均可取消；最坏情况为恶意取消待处理支付（griefing），但不会造成资金损失 |

### `transferAuthorizationState`

| 字段 | 内容 |
|-------|---------|
| 合约 | `SmartWalletEntry`（通过 `ITransferWithAuthorization`） |
| 函数 | `transferAuthorizationState` |
| 签名 | `transferAuthorizationState(bytes32 authorizationNonce)` |
| 选择器 | `0xb69f0bd9` |
| 可变性 / 访问类型 | view |
| 必需调用者 / 签名者 | 无 |
| 参数 | `authorizationNonce`：待查询的随机数 |
| 返回值 | `bool used` — 若随机数处于终止态（已结算**或**已取消）则返回 true，若仍未使用则返回 false |
| 状态变更 | 无 |
| 后端处理 | 只读对账；`true` 表示终止态，但**本身并不意味着**"已结算"——参见第 6.1 节 |
| 安全说明 | 无法区分已结算与已取消——需通过事件加以区分 |

### `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`

| 字段 | 内容 |
|-------|---------|
| 合约 | `SmartWalletEntry`（通过 `ITransferWithAuthorization`） |
| 函数 | `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` |
| 签名 | `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` |
| 选择器 | `0x925a29fd` |
| 可变性 / 访问类型 | view |
| 必需调用者 / 签名者 | 无 |
| 返回值 | `bytes32` — 账户的 EIP-712 域分隔符 |
| 状态变更 | 无 |
| 后端处理 | 可直接读取，也可根据 `{name:"SmartWallet", version:"1.1.0", chainId, verifyingContract:account}` 在本地重建 |
| 安全说明 | 将授权绑定至该账户和链 |

### `supportsInterface`（已修改）

| 字段 | 内容 |
|-------|---------|
| 合约 | `SmartWalletEntry` |
| 函数 | `supportsInterface` |
| 签名 | `supportsInterface(bytes4 interfaceId)` |
| 选择器 | `0x01ffc9a7` |
| 可变性 / 访问类型 | view |
| 返回值 | `bool` — `supportsInterface(0x86c5a9e1) == true`；所有此前支持的接口 ID（ERC-165 `0x01ffc9a7`、ERC-1271 `0x1626ba7e`、ERC-721/1155 接收器）均保留 |
| 后端处理 | 集成前检测是否支持授权转账功能 |

### 公共常量获取器（只读）

`EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH()` → `0xe751bf1b…7b3c`；`RECEIVE_WITH_AUTHORIZATION_TYPEHASH()` → `0xd8a04c47…29fd`；`CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH()` → `0xf30be15a…9f8e`；`INTERFACE_ID()` → `0x86c5a9e1`；`NATIVE_ASSET()` → `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`；`SIGNATURE_ENVELOPE_MIN_LENGTH()` → `32`。后端可读取这些值以验证其链下类型化数据的构造是否正确。

## 5. 事件、日志与索引

| 事件 | Topic0 | 触发时机 | 可索引 / 可查询性 | 后端用途 |
|-------|--------|--------------|---------------------|---------------|
| `TransferAuthorizationUsed(address token, address from, address to, uint256 value, bytes32 authorizationNonce)` | `0xfce4059e…02ae` | 成功结算时（`executeTransferWithAuthorization` / `receiveWithAuthorization`） | `token`、`from`、`to` 已索引；`value`、`authorizationNonce` 在 **data** 中（不可按 topic 过滤） | **结算的权威证明。** 由于 `authorizationNonce` 在此处未被索引，需通过 `from`（=账户）/`to` 过滤并从事件数据中匹配随机数。 |
| `TransferAuthorizationCanceled(address authorizer, bytes32 authorizationNonce)` | `0x2e1fec16…8787` | 执行 `cancelTransferAuthorization` 时 | `authorizer`、`authorizationNonce` 均已索引（`authorizer` 始终为账户地址） | **撤销的权威证明。** 可按随机数进行 topic 过滤（通过索引 topic 进行一次性 `getLogs` 查询）。具有此事件的随机数**不得**标记为已支付。 |

## 6. 自定义错误与回滚处理

| 错误 / 回滚 | 选择器 | 含义 | 后端处理 |
|----------------|----------|---------|------------------|
| `AuthorizationAlreadyUsed(bytes32 authorizationNonce)` | `0x232555ae` | 随机数处于终止态——**已结算或已取消**（两者共用一个标志） | 不得重试；**不得**假定已结算——需通过事件对账（第 6.1 节） |
| `AuthorizationNotYetValid(uint256 validAfter)` | `0x7a4df079` | `block.timestamp <= validAfter` | 在 `validAfter` 后重试，或重新签名以修正时间窗口 |
| `AuthorizationExpired(uint256 validBefore)` | `0x3d91b05f` | `block.timestamp >= validBefore` | 不得重试；请求新的授权（新随机数 + 时间窗口） |
| `InvalidRecipient(address to)` | `0x17858bbe` | `to == address(0)` 或 `to == NATIVE_ASSET` | 不得重试；修正载荷（运营/数据错误） |
| `CallerNotPayee(address caller, address to)` | `0xa54718e8` | `receiveWithAuthorization` 未由 `to` 调用 | 不得重试；通过收款合约路由 |
| `InvalidSignature()` | `0x8baa579f` | 信封过短（`< 32`），keyHash 未注册/已过期，签名无效，或摘要被二次封装 | 不得原样重试；重新推导 keyHash，在**直接**摘要上重新签名，验证密钥已注册且有效 |
| `NonAdminSelfCall()` | `0x6d9677b1` | 结算目标为账户本身且使用非管理员密钥（原生 ETH `to == account`，或 ERC-20 `token == account`） | 不得重试；运营/数据错误——修正 `to`/`token` 或使用管理员密钥签名。`to` 为账户地址但 `token` 为外部 ERC-20 的正常支付**不受影响**。 |
| `ReentrantSettle()` | `0x66395e90` | 在当前结算进行中时发生重入结算 | 不得重试嵌套调用；表示收款方存在重入行为 |
| `NotFromSelf()` | `0xa575ba1c` | `cancelTransferAuthorization` 形式 B（空签名）由非账户地址调用 | 不得重试；通过账户自身的执行路径路由空签名取消操作 |
| 钩子回滚（来自已配置钩子的自定义错误） | （钩子定义） | 违反每密钥支出策略（超出限额 / 不在白名单） | 不得重试；向用户提示"策略限制"；运营方可在链下调整策略 |
| 转账失败（代币回滚 / 余额不足 / 原生 ETH 发送失败） | （代币/原生定义） | 结算无法完成 | 在余额/代币问题解决前不得重试；向用户提示 |

### 6.1 结算对账：区分已使用与已取消（具有约束力）

链上使用单个布尔值追踪每个随机数；`transferAuthorizationState(nonce) == true` 以及 `AuthorizationAlreadyUsed` 回滚对**成功结算**和**取消**均会触发。因此，链上状态**无法**区分已结算与已取消——只能通过两个不同的事件加以区分。后端在将任何支付记录为已支付前，**必须**遵循以下规则：

1. 仅当对应随机数存在匹配的 `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` 事件时，支付才被视为**已结算**。由于 `authorizationNonce` 在此事件中未被索引，需通过 `from`（=账户）/`to` 过滤并从事件**数据**中匹配随机数。
2. `TransferAuthorizationCanceled(authorizer=account, authorizationNonce)` 事件表示授权已被**撤销**，**不得**将其标记为已支付。此处随机数已被索引，因此可通过 topic 进行低成本的一次性 `getLogs` 查询。
3. `transferAuthorizationState(nonce) == true`（或 `AuthorizationAlreadyUsed` 回滚）**单独不足以**得出"已支付"的结论；它仅表示"终止态"。若对某个终止态随机数未找到任何事件（例如，处于区块重组中 / 索引延迟），则应将其状态视为**未知/待定**，而非已支付。

将已取消的随机数误判为已结算，会导致将已撤销的支付错误标记为已支付，从而使取消操作失去业务控制意义。

## 7. Java 集成示例（web3j，仅含占位符）

> 占位符：`<accountAddress>`、`<chainId>`、`<rpcUrl>`、`<relayerKey>`、`<tokenAddress>`、`<payeeAddress>`。请勿嵌入生产密钥、真实 RPC URL 或真实部署者/管理员地址。

**构建 EIP-712 类型化数据和所有者签名（由用户钱包签名；后端不持有所有者密钥）：**

```java
// Domain: name="SmartWallet", version="1.1.0", chainId=<chainId>, verifyingContract=<accountAddress>
// Primary type "ExecuteTransferWithAuthorization" (or "ReceiveWithAuthorization") fields, in order:
//   address token, address from, address to, uint256 value,
//   uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce
//   -> "from" MUST equal <accountAddress>
byte[] ownerSignature = walletSignsTypedData(typedDataJson); // 65-byte r||s||v for ECDSA owner keys
byte[] keyHash = Hash.sha3(addressBytes(ownerEoa));          // ECDSA: keccak256(abi.encodePacked(ownerAddress))
// On-chain envelope = keyHash(32) || ownerSignature   (32-byte prefix, NOT 38)
byte[] signatureEnvelope = concat(keyHash, ownerSignature);
```

**只读调用（eth_call）：**

```java
Function stateFn = new Function(
    "transferAuthorizationState",
    Arrays.asList(new Bytes32(authorizationNonce)),
    Arrays.asList(new TypeReference<Bool>() {}));
boolean terminal = decodeBool(web3j.ethCall(
    Transaction.createEthCallTransaction(caller, "<accountAddress>", FunctionEncoder.encode(stateFn)),
    DefaultBlockParameterName.LATEST).send());
// terminal == true means settled OR canceled -> confirm by event (see 6.1) before marking paid
```

**交易调用（由中继器提交；中继器密钥与所有者密钥无关）：**

```java
Function execFn = new Function(
    "executeTransferWithAuthorization",
    Arrays.asList(
        new Address("<tokenAddress>"),   // or NATIVE_ASSET 0xEeee...EEeE
        new Address("<payeeAddress>"),
        new Uint256(value),
        new Uint256(validAfter),
        new Uint256(validBefore),
        new Bytes32(authorizationNonce),
        new DynamicBytes(signatureEnvelope)),
    Collections.emptyList());
// Pre-submit simulation first (eth_call); success implies valid signature, sufficient balance,
// unused nonce, and passing hook policy. Then send with a relayer-managed nonce/gas.
String txHash = sendRawTransaction("<rpcUrl>", "<relayerKey>", "<accountAddress>",
    FunctionEncoder.encode(execFn));
```

**事件 / 日志解析：**

```java
// TransferAuthorizationUsed: topics[0]=keccak256("TransferAuthorizationUsed(address,address,address,uint256,bytes32)")
//   topics[1]=token, topics[2]=from(account), topics[3]=to; data = value(uint256) || authorizationNonce(bytes32)
// Filter by from(account)/to, then match authorizationNonce from data.
// TransferAuthorizationCanceled: topics[1]=authorizer(account), topics[2]=authorizationNonce (filterable by nonce).
```

## 8. 兼容性与版本管理

- **ABI 兼容性：** 纯增量扩展——新增函数/事件/错误及一个新的 ERC-165 接口 ID。所有现有账户接口（execute、中继器执行、UserOp 验证、EIP-1271、所有者管理、授权额度）保持其签名、事件和错误不变。
- **升级 / 代理影响：** 账户支持 UUPS 可升级；现有账户通过由账户本身授权的标准升级来获得此功能。未引入新的升级角色。新的授权随机数存储位于独立的命名空间中，不会移动或与现有存储重叠。
- **重新部署 / 升级 / 地址变更后后端必须重新检查的内容：** 确认 `supportsInterface(0x86c5a9e1) == true`，以及 `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` 与预期的 `{name, version, chainId, verifyingContract}` 匹配；重新固定同时用作调用目标和已签名 `from` 字段的账户地址。
- **过期 ABI 检测：** 后端应将 `supportsInterface(0x86c5a9e1)` 及三个类型哈希获取器的返回值与其编译时所用值进行核对；若不匹配，则表明 ABI 已过期或账户版本不同，在提交前必须刷新签名/编码逻辑。
