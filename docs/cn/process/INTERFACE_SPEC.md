# INTERFACE_SPEC.md — 后端集成规范（TWA）

> 本文是对 `DESIGN.md` 的后端集成补充说明。引用 `DESIGN.md` 中的规范函数 id（`FN-*`）、事件及错误定义，**不**重复定义合约行为。目标读者：负责构造 EIP-712 载荷、收集所有者签名、选择/提交中继器并为 OKX SmartWallet TWA 功能索引事件的 Java 后端工程师。

## 1. 接口规范状态

| 字段 | 值 |
|------|-----|
| 状态 | `DESIGN_DRAFT` |
| 目标链 | EVM — 以太坊主网（chainId 1），Cancun |
| 来源文档 | `docs/process/DESIGN.md`、`docs/process/REQUIREMENTS.md`（PRD §2.1/FR-0..FR-5/§7/§8）、EIP 草案补充 |
| 预期最终交付物 | `docs/delivery/CONTRACT_INTERFACE.md`（Stage 4.0） |
| 预期机器可读产物 | Stage 4.0 生成的 `docs/delivery/abi/SmartWalletEntry.abi.json`（或 `ITransferWithAuthorization.abi.json`） |
| 变更类型 | 对现有账户 ABI 的增量添加（新增函数/事件/错误 + 一个 ERC-165 id）；现有接口保持不变 |

## 2. 后端集成概述

- **后端 / 中介方调用** `executeTransferWithAuthorization`（FN-001）——无许可地结算所有者签名的授权；由中继器支付 gas。
- **收款方合约调用** `receiveWithAuthorization`（FN-002）——仅 `to` 地址可结算（`msg.sender == to`）；用于合约收款方需在自身流程中原子性落账的场景。
- **用户/所有者钱包（链下）** 生成 EIP-712 签名（ECDSA 或 passkey）。后端不持有所有者私钥。
- **管理员 / 账户自调用** 在 `execute`/UserOp 中使用 B 形式（空签名）的 `cancelTransferAuthorization`；A 形式（有签名）可由任意中继器提交。
- **仅索引**（无交易调用）：`TransferAuthorizationUsed`、`TransferAuthorizationCanceled` 事件；只读 `transferAuthorizationState` / `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`。
- **链下状态 / 幂等性**：后端必须追踪已签发的 `authorizationNonce` 及其结算状态（已结算 / 已取消 / 待处理）；可在提交前通过 `eth_call` 模拟验证结算可行性，也可通过已发出的事件确认。随机 32 字节 nonce 使各授权相互独立、可按任意顺序结算（无需顺序追踪）。**链上 nonce 被"消耗"并不等同于已结算：** `transferAuthorizationState(nonce) == true`（以及 `AuthorizationAlreadyUsed` 回滚）由**成功结算**和 `cancel` **均会触发**（FR-3/FR-4 将两者归并到同一标志位）。只有在观察到匹配的 `TransferAuthorizationUsed` 事件后，才能将付款标记为已完成——详见 §6.1 结算对账。

**最关键的集成要点：** 链上 `signature` 参数是一个**包装体（envelope）** = `keyHash（32 字节）‖ ownerSignature`（`DESIGN.md` FN-101，`SIGNATURE_ENVELOPE_MIN_LENGTH = 32`）。合约提取 `keyHash = bytes32(signature[:32])`，通过 `getVerifiedValidator(keyHash)` 路由验证器，再将 `signature[32:]` 作为 `ownerSignature` 对 **直接** EIP-712 摘要 `hashTypedData(structHash)` 进行验证。这**不是**现有的 38 字节 execute 包装体（含 6 字节 `validUntil`），也**不是** EIP 草案中 20 字节验证器地址的示例。后端必须在签名后将 32 字节 `keyHash` 前置拼接，并且**绝对不能**对摘要进行 ERC-1271/MessageSignLib 包装。

## 3. 合约列表

| 合约 | 用途 | 后端相关性 | 说明 |
|------|------|-----------|------|
| `SmartWalletEntry`（账户，实现 `ITransferWithAuthorization`） | 账户级 TWA 结算 | 可调用 + 索引 | **已修改**（内联新增 TWA 接口） |
| `ITransferWithAuthorization` | 供中介方使用的固定 ABI | ABI 来源 | **新增** |
| 单密钥消费策略 Hook | 单密钥限额执行 | 索引/观察（链下配置） | 现有；影响结算是否成功 |

## 4. 后端可调用函数

> 规范行为见 `DESIGN.md`，此处仅说明后端集成细节。

### `executeTransferWithAuthorization` — FN-001 — 变更类型：新增
- 签名：`executeTransferWithAuthorization(address token, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce, bytes signature)`
- 调用方/角色：任意地址（中介方/中继器）。不可支付（non-payable）；原生资产从账户余额中划拨。
- 参数（链原生类型 / 含义）：`token` = ERC-20 地址，或原生资产使用 `NATIVE_ASSET`（`0xEeee…EEeE`）；`to` = 收款方（不得为零地址，否则报 `InvalidRecipient`）；`value` = 金额（wei / token 最小单位）；`validAfter`/`validBefore` = 开区间 Unix 时间范围；`authorizationNonce` = 随机 `bytes32`；`signature` = `keyHash(32) ‖ ownerSignature`。
- 返回值：无。
- 状态变更：标记 nonce 已使用（CEI 模式）后转账（`DESIGN.md` FN-102/FN-103）。
- 事件：`TransferAuthorizationUsed`。
- 错误：`AuthorizationAlreadyUsed`、`AuthorizationNotYetValid`、`AuthorizationExpired`、`InvalidRecipient`、`InvalidSignature`、Hook 回滚、转账失败（见 §6）。
- 前置条件：nonce 未使用、在有效时间窗口内、所有者签名有效、账户余额充足、符合单密钥 Hook 策略。
- 幂等性/重放：每个 nonce 最多结算一次；重新提交**已结算** nonce 将回滚 `AuthorizationAlreadyUsed`。抢先交易不改变最终结果（`to`/`value` 已绑定在签名中）——见 §6。**注意：** `AuthorizationAlreadyUsed` 也会在 nonce 已**取消**时触发，因此仅凭该回滚无法判断"已付款"——须通过事件对账（§6.1）。
- 链下准备（PREPARE）：构造 EIP-712 typed data（§7 格式字段），选择 `validAfter`/`validBefore`，生成随机 32 字节 nonce，收集所有者签名，按 §8 的单验证器布局组装 keyHash 包装体。
- 链下存储/索引（STORE/INDEX）：nonce → {token, to, value, 时间窗口, 账户, 状态}；对应 tx hash；`TransferAuthorizationUsed` 日志（结算的权威证明）。
- 安全/误用：提交前通过 `eth_call` 模拟；不得包装摘要；收到 `AuthorizationAlreadyUsed` 时不重试，且**不得假设已结算**：须通过 `TransferAuthorizationUsed` 事件确认后方可标记付款完成（§6.1）。

### `receiveWithAuthorization` — FN-002 — 变更类型：新增
- 与 FN-001 结构相同，**额外要求** `msg.sender == to`（否则报 `CallerNotPayee`）。签名使用**独立的** `RECEIVE` typehash——execute 类型的授权不能在此重放，反之亦然。
- 后端角色：收款方**合约**在其自身逻辑中调用此函数；后端向该合约提供已签名的接收授权。

### `cancelTransferAuthorization` — FN-003 — 变更类型：新增
- 签名：`cancelTransferAuthorization(bytes32 authorizationNonce, bytes signature)`。
- A 形式（签名非空）：任意中继器提交；由已注册的账户密钥使用 `CANCEL` typehash 签名（包装体 `keyHash(32) ‖ ownerSignature`）。
- B 形式（签名为空，长度为 0）：仅账户自身可调用（`msg.sender == address(this)`），即嵌套在 `execute`/UserOp 中。
- 错误：`AuthorizationAlreadyUsed`（已使用/已取消）、`NotFromSelf`（B 形式非自身调用）。
- 链下：决定何时取消待处理授权；索引 `TransferAuthorizationCanceled`。

### `transferAuthorizationState` — FN-004 — 变更类型：新增（view）
- `transferAuthorizationState(bytes32) returns (bool used)` — 若已使用**或**已取消则返回 true。用于只读对账（`eth_call`）。

### `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` — FN-005 — 变更类型：新增（view）
- 返回账户的 EIP-712 域分隔符。后端可读取以便使用，也可根据域字段自行重建（`name="SmartWallet"`、`version="1.1.0"`、`chainId`、`verifyingContract=account`）。

### `supportsInterface` — FN-006 — 变更类型：修改
- `supportsInterface(0x86c5a9e1) == true`；已有 id 保持不变。中介方用此检测账户是否支持 TWA。

## 5. 供后端索引的事件/日志

| 事件 | 由何方触发 | 触发时机 | 已索引/可查询字段 | 后端用途 |
|------|-----------|---------|-----------------|---------|
| `TransferAuthorizationUsed(address token, address from, address to, uint256 value, bytes32 authorizationNonce)` | FN-001 / FN-002 | 成功结算时 | `token`、`from`、`to` 已索引；`value`、`authorizationNonce` 在 **data** 中（不可按 topic 过滤） | **结算权威证明** — 只有在该 nonce 存在此事件时，方可将付款标记为已完成。**注意：** 无法通过 `getLogs` 按 `authorizationNonce` 过滤（该字段在此事件中未索引）——须按 `from`（账户）/`to` 过滤后从 data 中读取并匹配 nonce。 |
| `TransferAuthorizationCanceled(address authorizer, bytes32 authorizationNonce)` | FN-003 | 取消时 | `authorizer`、`authorizationNonce` 均已索引（`authorizer` 始终为账户 `address(this)`，而非执行取消的密钥） | **取消权威证明** — 存在此事件的 nonce 已被撤销，**不得**标记为已付款。可按 nonce（indexed）进行一次性 `getLogs` 查询。 |

## 6. 错误处理规范

| 错误/回滚 | 含义 | 后端处理方式 |
|----------|------|------------|
| `AuthorizationAlreadyUsed(bytes32)` | nonce 处于终态——**已使用或已取消**（合约将二者归并到同一标志位，FR-3/FR-4） | **不重试。** **不得**默认视为已结算。无论是已结算（被另一中继器抢先）还是已取消，均触发此回滚。须通过事件对账（§6.1）：匹配到 `TransferAuthorizationUsed` ⇒ 已结算（标记已付）；匹配到 `TransferAuthorizationCanceled` 或未找到 `Used` 事件 ⇒ 已取消/从未结算（**不得**标记已付；显示为已取消）。 |
| `AuthorizationNotYetValid(uint256 validAfter)` | `block.timestamp <= validAfter` | 等到 `validAfter` 后重试；或重新签名并修正时间窗口 |
| `AuthorizationExpired(uint256 validBefore)` | `block.timestamp >= validBefore` | 不重试；请求新授权（新 nonce + 时间窗口） |
| `InvalidRecipient(address to)` | `to == address(0)`（及/或原生资产哨兵值） | 不重试；修正载荷（运营/数据错误） |
| `CallerNotPayee(address caller, address to)` | `receiveWithAuthorization` 未由 `to` 调用 | 不重试；通过收款方合约路由 |
| `NonAdminSelfCall()`（复用基础 `ISmartWallet` 错误） | 结算目标为账户自身且使用**非管理员**密钥——原生 `to == account`，或 ERC-20 `token == account`（与 `execute`/`_batchCall` 保持一致；见 §8.4） | 不重试；运营/数据错误——修正 `to`/`token`，或使用管理员密钥签名。若 `to` 为账户但 `token` 为外部 ERC-20 的正常付款**不受影响**。 |
| `InvalidSignature()` | 包装体长度错误 / keyHash 未注册或已过期 / 签名无效 / 摘要被二次包装 | 不得原样重试；重新推导 keyHash，使用**直接**摘要重新签名，验证验证器已注册且处于活跃状态 |
| Hook 回滚（来自 Hook 的自定义错误） | 违反单密钥消费策略（超限 / 非白名单） | 不重试；向用户展示"策略限额"错误；运营方可在链下调整策略 |
| 转账失败（token 回滚 / 余额不足 / 原生资产发送失败） | 结算无法完成 | 在余额/token 问题解决前不重试；向用户展示 |

### 6.1 结算对账：区分**已使用**与**已取消**（约束性规则）

合约为每个 nonce 存储单个 `bool`；`transferAuthorizationState(nonce)` 对**成功结算**和**取消**均返回 `true`，`AuthorizationAlreadyUsed` 也会对两者均回滚（PRD FR-3 规则 4"已取消 nonce 视为已使用"；FR-4；`DESIGN.md` §8.1/§10）。因此链上状态**无法**区分已结算与已取消——只有两个不同的事件可以区分（PRD NFR-4）。后端在将任何付款记录为已完成前，**必须**遵循以下规则：

1. **仅当存在匹配的 `TransferAuthorizationUsed(token, from=account, to, value, authorizationNonce)` 事件时，付款才视为"已结算"。** 由于 `authorizationNonce` 在 `TransferAuthorizationUsed` 中**未索引**，须按 `from`（=账户）/`to` 过滤，再从事件 **data** 中读取并匹配 `authorizationNonce`。
2. **`TransferAuthorizationCanceled(authorizer=account, authorizationNonce)` 事件表示授权已被撤销**，**不得**标记为已付款。该事件中 nonce 已**索引**，可通过 topic 进行一次性 `getLogs` 查询——是最低成本的判断依据。
3. `transferAuthorizationState(nonce) == true`（或 `AuthorizationAlreadyUsed` 回滚）**单独不足以**得出"已付款"的结论；它仅表示"终态"。若对处于终态的 nonce 均未找到事件（例如处于区块重组/索引延迟中间状态），则将状态视为**未知/待确认**，而非已付款。

原因：将已取消的 nonce 误判为已结算，会导致一笔已撤销的付款被错误标记为已完成，破坏链下账务，并使 `cancel` 作为业务控制手段失效。

## 7. Java 集成说明（设计层级；仅含占位符）

- **EIP-712 签名**：使用 web3j 的 `StructuredDataEncoder`（或等效实现）按 §7 格式构造 typed data，包含 `types`/`domain`/`primaryType`；由**所有者**签名（通过所有者密钥进行 ECDSA，或通过钱包进行 passkey）。签名后**前置 32 字节 `keyHash`** 以生成链上 `signature` 包装体。**不得**进行任何 ERC-1271 / personal_sign / MessageSignLib 包装。各验证器的 `ownerSignature` 字节布局（ECDSA / 内置 passkey / 外部验证器）及 keyHash 推导方式详见 **§8（验证器专属签名包装体）**——注意 TWA 前缀为 **32 字节（仅 keyHash）**，**不是** `executeWithRelayer`/UserOp 使用的 38 字节 `keyHash‖validUntil` 前缀。
- **Typed data**（规范字段顺序与 `DESIGN.md §6` 中的 typehash 字符串一致）：
  - domain：`{ name: "SmartWallet", version: "1.1.0", chainId: <chainId>, verifyingContract: <accountAddress> }`
  - `ExecuteTransferWithAuthorization` / `ReceiveWithAuthorization` 字段：`token (address)`、`from (address)`、`to (address)`、`value (uint256)`、`validAfter (uint256)`、`validBefore (uint256)`、`authorizationNonce (bytes32)` — `from` **必须**等于账户地址。
  - `CancelTransferAuthorization` 字段：`authorizationNonce (bytes32)`。
- **提交**：使用交易管理器 / 原始调用提交 `executeTransferWithAuthorization`；提交 EOA（中继器）是任意的，与所有者密钥无关。
- **提交前模拟**：先通过 `eth_call` 模拟调用（参见 EIP"Settlement"）；成功则意味着签名有效、余额充足、nonce 未使用、Hook 策略通过。
- **读取**：通过只读 `eth_call` 调用 `transferAuthorizationState` 和 `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`；通过事件过滤器获取 `TransferAuthorizationUsed`/`Canceled`（注意 `authorizationNonce` 在 `Used` 事件中未索引）。
- **无密钥**：不得在代码、日志、URL、配置或聊天输出中嵌入生产私钥、真实 RPC URL、API 密钥或真实部署者/管理员地址；使用占位符（`<accountAddress>`、`<chainId>`、`<relayerKey>`）。

## 8. 验证器专属签名包装体（`keyHash ‖ ownerSignature`）

> 解决 OQ-1 / OQ-2 / OQ-3（PRD G-4）。信息来源：`src/ValidationManager.sol`、`src/libraries/ECDSAValidatorLib.sol`、`src/libraries/PasskeyValidatorLib.sol`、`src/OwnerManager.sol`、`lib/webauthn-sol/src/WebAuthn.sol`。规范验证路径：`DESIGN.md` FN-101 `_verifyTwaSignature`。

链上 `signature` 参数**始终**为 `keyHash（32 字节）‖ ownerSignature`。合约提取 `keyHash = bytes32(signature[:32])`，通过 `getVerifiedValidator(keyHash)`（`OwnerManager.sol:173`）路由验证器，并将 `ownerSignature = signature[32:]` **原样**传递给 `_validateSignature(validator, keyHash, hashTypedData(structHash), ownerSignature)`（`ValidationManager.sol:29`）。**没有** `validUntil` 字段：TWA 的有效性由签名中的 `validAfter`/`validBefore` 决定，因此前缀为 **32 字节（仅 keyHash）** —— **不是** `executeWithRelayer`/`validateUserOp`/`isValidSignature` 使用的 38 字节 `keyHash(32)‖validUntil(6)` 前缀（`SmartWallet.sol:188-199, 233-240`；`DecodeLib`）。

> ⚠ **最常见的后端错误：** 复用 38 字节的 execute/relayer 包装体。多出的 6 个 `validUntil` 字节使 `ownerSignature` 偏移 6 位，导致所有 TWA 签名均报 `InvalidSignature`。请使用 32 字节前缀。

`keyHash` 用于选择已注册的验证器：`address(1)` = 内置 ECDSA，`address(2)` = 内置 passkey，其他已注册合约地址 = 外部验证器（`Static.sol:7-8`）。内置 `address(this)` 密钥始终路由至 ECDSA。摘要为**直接** `hashTypedData(structHash)` —— 不进行 ERC-1271/`MessageSignLib` 包装（R-3，FR-1-AC-8）。

### 8.1 ECDSA — 内置验证器 `address(1)`
- **keyHash** = `keccak256(abi.encodePacked(ownerEOA))` — 对 20 字节所有者地址取 keccak（`ECDSAValidatorLib.sol:47`）。
- **ownerSignature** = 对直接摘要的 65 字节 `r(32) ‖ s(32) ‖ v(1)`（`ECDSAValidatorLib.sol:13,30,43`）。
- **完整包装体** = `keyHash(32) ‖ r,s,v(65)` = **97 字节**。
- 可选 Merkle 尾部 `… ‖ abi.encode(bytes32[] proofs)` 允许一个签名授权一批操作（`ECDSAValidatorLib.sol:31-40`）；单笔 TWA 结算**不使用** proofs（恰好 97 字节）。
- 可复用参考：`Base.t.sol::_signHash` → `abi.encodePacked(keyHash, abi.encodePacked(r,s,v))`。

### 8.2 Passkey — 内置验证器 `address(2)`
- **keyHash** = `keccak256(abi.encodePacked(pubKeyX, pubKeyY))` — 对两个 32 字节 P-256 坐标进行紧凑编码（packed）后取 keccak（`PasskeyValidatorLib.sol:60`）。⚠ 某个**外部** passkey 验证器测试使用 `keccak256(abi.encode([x,y]))`（不同的哈希）；内置验证器请使用 **`abi.encodePacked`** 形式。
- **ownerSignature** = `abi.encode(PasskeyValidatorLib.PasskeyPubKey{uint256 pubKeyX, uint256 pubKeyY})` **（64 字节）** ‖ `abi.encode(WebAuthn.WebAuthnAuth webAuthnAuth, bytes32[] proofs)`（`PasskeyValidatorLib.sol:39-51`）。
  - `WebAuthnAuth = { bytes authenticatorData; string clientDataJSON; uint256 challengeIndex; uint256 typeIndex; uint256 r; uint256 s }`（`webauthn-sol/WebAuthn.sol:22-37`）。
  - WebAuthn **challenge** 为 `abi.encode(rootHash)`，其中 `rootHash = MerkleProofProcessor.processWithMerkleProof(proofs, digest)`。当 `proofs` 为空时，`rootHash == digest`（即 TWA 的 `hashTypedData(structHash)`），因此 passkey 实际上对嵌入（base64url）在 `clientDataJSON` 中的 `abi.encode(digest)` 进行签名（`PasskeyValidatorLib.sol:54-72`）。链上公钥必须哈希到 `keyHash`。
- **完整包装体** = `keyHash(32) ‖ abi.encode(pubKeyX,pubKeyY)(64) ‖ abi.encode(WebAuthnAuth, bytes32[] proofs)`。
- 可复用参考：`HelperLib.getPasskeyMessageHash` / `HelperLib.getWebAuthnAuth`（`test/utils/Helper.s.sol:19-58`）+ `PasskeyValidator.t.sol::_createBuiltinPasskeySignature`（`:714-749`）。TWA 的**唯一**变化是去掉辅助函数在 `:737` 处前置的 `uint48(0) validUntil`（TWA 没有 validUntil）。Passkey 的 gas 不计入 ECDSA 的 <120k 目标（NFR-1）；其基准值在 Stage 5.0/6.0 中测量（OQ-4）。

### 8.3 外部验证器 — 其他已注册地址
- **keyHash** 和 **ownerSignature** 布局由该验证器自身的注册规范及 `validateSignature(keyHash, digest, validationData)` 合约定义；账户将 `ownerSignature = signature[32:]` 原样转发，并用 try/catch 包裹（失败关闭）（`ValidationManager.sol:56-66`）。后端须查阅具体外部验证器的规范；本设计仅固定外层 `keyHash(32) ‖ ownerSignature` 包装体。

### 8.4 自我目标结算边界情形（解决 OQ-6；DR-003）
当构建的 `Call.target == address(this)` 时——原生 `to == address(this)`，或 ERC-20 `token == address(this)`——若使用**非管理员**密钥，将回滚 `NonAdminSelfCall`，与 `execute`/`_batchCall` 保持一致（`SmartWallet.sol:152-164`；`DESIGN.md` FN-103 设计说明 3；`SECURITY_SPEC.md` INV-HOOK-ISOMORPHISM）。管理员 / 内置 `address(this)` 密钥可自我目标（原生自发是净零操作）。向账户自身进行的正常 ERC-20 付款（`token = <外部 ERC-20>`，`to = account`）**不属于**自调用（构建的 Call 目标是 `token`，而非账户），可正常结算。后端不应构造自我目标的结算载荷。

## 9. 开放集成问题

| 编号 | 问题 | 状态 / 解决方案 |
|------|------|---------------|
| OQ-1 | 后端如何为给定所有者/验证器（ECDSA vs passkey）推导 `keyHash`？ | **已解决** — §8.1/§8.2（ECDSA：`keccak256(abi.encodePacked(addr))`；内置 passkey：`keccak256(abi.encodePacked(pubKeyX,pubKeyY))`）。 |
| OQ-2 | `ownerSignature` 中 passkey 签名的精确编码（P-256 / WebAuthn 载荷）？ | **已解决** — §8.2（完整布局 + WebAuthnAuth 字段 + 可复用测试参考）。 |
| OQ-3 | 最终 `SIGNATURE_ENVELOPE_MIN_LENGTH` | **已解决** — 32（仅 keyHash 前缀；`DESIGN.md` FN-101）。 |
| OQ-6 | 原生资产结算与 `to == address(this)` 边界情形 | **已解决** — §8.4 / DR-003（非管理员自我目标回滚 `NonAdminSelfCall`；管理员自我目标 = 无操作）。 |
| OQ-4 | 包含 Hook 路径的 gas 估算；passkey 路径的 gas 基准（NFR-1 将 passkey 排除在 <120k 之外） | **开放（非阻塞）** — 在 Stage 5.0/6.0 中测量。 |
| OQ-5 | 后端是读取链上 `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` getter 还是在本地重建域 | **开放（非阻塞，取决于后端偏好）** — 两者均有效；getter（FN-005）提供便利，也可从 `{name:"SmartWallet", version:"1.1.0", chainId, verifyingContract:account}` 重建。 |

所有设计阻塞性集成问题均已解决；剩余事项（OQ-4/OQ-5）为非阻塞的操作/偏好项。根据 PRD + §8 + 上述假设，可以明确定义一个安全的后端集成边界。
