# 智能合约审计报告

> **结论：** WARN
> **流水线阶段结论：** PASS
> **项目：** okx-smart-wallet-dev
> **代码库：** https://gitlab.okg.com/web3-wallet/smart-wallet-infra/okx-smart-wallet-dev.git
> **引用：** feature/aa-auth-4.0 (eeeba95ed2f0ece53133d981aaba943aa3e5ef53)
> **分析时间：** 2026-06-25T16:15:53Z
> **流水线：** oli-contract-audit
> **模式：** pipeline-stage
> **FAIL_ON：** critical
> **编译：** 默认 `forge build` 因继承的恢复套件测试导入失败；`forge build src script` 通过
> **静态分析工具：** slither, aderyn

---

## 结论

**WARN** — 未发现已验证的严重（Critical）问题，因此第 8 阶段机器门控在 `FAIL_ON=critical` 条件下将本次审计判定为 **PASS**。五个中等（Medium）级别问题作为非阻塞性建议保留，应在部署验证前进行评审。

来自发现器/静态检测阶段的高危（High）候选项经对抗性验证后被降级或拒绝。没有任何问题能够证明存在直接的未授权资金损失、签名重放、TWA 钩子绕过、存储冲突或原生结算重入。

## 执行摘要

本次审计审查了 OKX SmartWallet 账户的账户级带授权转账（Transfer With Authorization，TWA）变更，以及其所依赖的范围内现有代码。该功能新增了基于 EIP-712 签名的账户级 ERC-20/原生代币结算、nonce 终结性、收款方限制接收结算、取消、ERC-165 发现，以及后端 ABI/事件交接。

TWA 核心资金流和授权设计在审计中经受住了考验：签名使用直接的类型化数据摘要，随机 TWA nonce 与 ERC-4337/原生 nonce 相互隔离，结算在外部转账之前写入 TWA nonce，原生代币结算受瞬态重入锁保护，ERC-20 结算使用 SafeERC20，已验证的 keyHash 选择用于策略检查的钩子。

已确认的问题属于运营层面和账户生命周期层面的关切：ERC-4337 验证数据打包不符合规范、过期的所有者密钥在 UserOp 验证期间使用 `block.timestamp`、格式错误的内置验证器载荷可能导致回滚而非优雅失败、最后一个管理员的生命周期可能导致未来的自调用管理被永久锁死，以及未限定范围的默认 Foundry 构建仍因继承的私有恢复套件依赖而失败。

## 统计数据

| 严重程度 | 去重候选项 | 已确认 | 需要 PoC | 误报 |
|----------|-----------|--------|----------|------|
| CRITICAL | 1 | 0 | 0 | 0 |
| HIGH | 3 | 0 | 0 | 3 |
| MEDIUM | 6 | 5 | 0 | 2 |
| LOW | 1 | 0 | 0 | 1 |
| INFO | 0 | 0 | 0 | 0 |
| **合计** | **11** | **5** | **0** | **6** |

去重前原始候选项：14 个。进入验证阶段的去重候选项：11 个。已确认问题：5 个。已拒绝误报：6 个。

## 覆盖范围

**静态预检：** 编译=部分通过（`forge build` 失败；`forge build src script` 通过）· 分析工具=slither, aderyn

**子代理：** 11 个发现器 + 11 个验证器，以 `PARALLEL_CAP=4` 运行

| 模式包 | 原始候选项 | 已确认 | 跨包 | 状态 |
|--------|----------:|-------:|-----:|------|
| static | 4 | 1 | 0 | ok |
| protocol-account-abstraction | 5 | 3 | 2 | ok |
| universal-access-control | 1 | 1 | 1 | ok |
| universal-arithmetic | 2 | 1 | 1 | ok |
| universal-state-invariants | 2 | 1 | 2 | ok |
| capability-oracle-pricing | 0 | 0 | 0 | ok |
| capability-signatures | 0 | 0 | 0 | ok |
| capability-upgradeability | 0 | 0 | 0 | ok |
| protocol-economics | 0 | 0 | 0 | ok |
| universal-baseline | 0 | 0 | 0 | ok |
| universal-dos-griefing | 0 | 0 | 0 | ok |
| universal-interactions | 0 | 0 | 0 | ok |
| **验证后** | **11（去重）** | **5** | **3** | - |

## ID 映射

| 聚合 ID | 严重程度 | 来源 ID | 跨包 | 验证结果 | 标题 |
|---------|---------|---------|------|---------|------|
| M-01 | MEDIUM | AA-001, ARITH-001 | 是（2） | CONFIRMED | 签名失败的验证数据被移入错误的 ERC-4337 字段 |
| M-02 | MEDIUM | BASE-001 | 否 | CONFIRMED | 默认 Foundry 构建因继承的恢复套件导入而失败 |
| M-03 | MEDIUM | ACCESS-001, STATE-002 | 是（2） | CONFIRMED | 管理员生命周期可删除或降级最后一个活跃管理员 |
| M-04 | MEDIUM | AA-003 | 否 | CONFIRMED | 过期所有者在 ERC-4337 验证期间使用 `block.timestamp` |
| M-05 | MEDIUM | AA-005 | 否 | CONFIRMED | 内置验证器在验证期间可能回滚或执行无上限的证明计算 |

## 范围

**已分析合约：** `src/AllowanceManager.sol`、`src/BaseAuthorization.sol`、`src/ERC4337Account.sol`、`src/ERC712.sol`、`src/ERC7201.sol`、`src/ExecutionManager.sol`、`src/FallbackHandler.sol`、`src/NonceManager.sol`、`src/OwnerManager.sol`、`src/SmartWallet.sol`、`src/SmartWalletEntry.sol`、`src/SmartWalletFactory.sol`、`src/TransferWithAuthorization.sol`、`src/Types.sol`、`src/ValidationManager.sol`、`src/interfaces/` 下的接口，以及 `src/libraries/` 下的库。

**范围外：** 测试合约、部署脚本（构建可行性除外）、`lib/` 下的依赖项、`out/` 下生成的产物，以及 `.oli-work/context/technical/repo/` 下的参考上下文。Circle USDC EIP-3009 上下文仅用作开放时间窗口、收款方限制接收、nonce 终结性和取消语义的语义参考。

## 已确认问题

## [MEDIUM] M-01 - 签名失败的验证数据被移入错误的 ERC-4337 字段

- **聚合 ID：** M-01
- **来源 ID：** AA-001, ARITH-001
- **来源：** protocol-account-abstraction + universal-arithmetic
- **领域：** arithmetic
- **验证结果：** CONFIRMED — 验证器检查了捆绑的账户抽象 v0.7 语义，确认 `1 << 96` 被解码为虚假的非零聚合器/授权方，而非规范的签名失败标志。
- **跨包：** 是（2）
- **位置：**
  - `src/libraries/Static.sol:17`
  - `src/SmartWallet.sol:260`
  - `src/SmartWallet.sol:270`
  - `src/SmartWallet.sol:285`
  - `src/SmartWallet.sol:304`

### 描述
`Static.SIG_VALIDATION_FAILED` 被定义为 `1 << 96`，而 `validateUserOp` 在遇到短签名、未知/过期密钥哈希、不支持的无链 calldata 以及签名失败时返回此值。ERC-4337 验证数据使用低 160 位作为聚合器/签名失败字段；规范的签名失败值为 `1`，而非第 96 位。

已验证的路径可通过 EntryPoint 验证对格式错误或无效 UserOperation 触达。`onlyEntryPoint` 防止直接调用，但无法阻止 UserOperation 通过 EntryPoint 或捆绑器模拟路径到达账户。

### 影响
无效 UserOperation 可能被误分类为基于聚合器的验证，而非普通签名失败。这可能破坏 ERC-4337/捆绑器的兼容性并产生误导性的模拟结果，但由于受影响的 UserOperation 本身无效，未发现直接资金损失。

### 建议
使用规范的 ERC-4337 签名失败值：

```solidity
uint256 public constant SIG_VALIDATION_FAILED = 1;
```

保持 valid-until 打包在高位字段中，低 160 位授权方字段保留为 `0`、`1` 或真实聚合器地址。

## [MEDIUM] M-02 - 默认 Foundry 构建因继承的恢复套件导入而失败

- **聚合 ID：** M-02
- **来源 ID：** BASE-001
- **来源：** static
- **领域：** code-quality
- **验证结果：** CONFIRMED — 默认 `forge build` 因恢复套件导入失败，而 `forge build src script` 通过；由于生产源码/脚本编译成功，严重程度已从 Critical 降为 Medium。
- **跨包：** 否
- **位置：**
  - `test/Recovery.t.sol:5`
  - `test/Recovery.t.sol:6`
  - `test/Recovery.t.sol:7`
  - `test/Recovery.t.sol:8`
  - `test/Recovery.t.sol:9`

### 描述
确定性静态预检命令 `forge build` 失败，原因是 `test/Recovery.t.sol` 导入了当前依赖树中缺失的 `smart-wallet-recovery/...` 文件。限定范围的生产构建 `forge build src script` 通过，第 5/6/7 阶段的证据一致记录恢复套件为 TWA 变更范围之外的继承私有依赖限制。

### 影响
依赖未限定范围的默认 Foundry 构建的部署或 CI 流程可能在生成产物之前失败。这是一个运营交付风险，而非范围内的生产源码编译失败。

### 建议
在部署打包前恢复预期的 `smart-wallet-recovery` 依赖版本，或确保部署验证使用有文档说明的生产源码构建命令，同时保持恢复套件限制的可见性。

## [MEDIUM] M-03 - 管理员生命周期可删除或降级最后一个活跃管理员

- **聚合 ID：** M-03
- **来源 ID：** ACCESS-001, STATE-002
- **来源：** universal-access-control + universal-state-invariants
- **领域：** access-control
- **验证结果：** CONFIRMED — 验证器确认，活跃管理员可以自调用 `updateOwner` 或 `removeOwner`，从而使工厂部署的代理账户不存在任何实际注册的活跃管理员。
- **跨包：** 是（2）
- **位置：**
  - `src/OwnerManager.sol:69`
  - `src/OwnerManager.sol:92`
  - `src/SmartWallet.sol:149`

### 描述
`updateOwner` 和 `removeOwner` 受 `onlySelf` 保护，且 `_batchCall` 仅允许管理员密钥或内置自密钥进行自调用。然而，一旦活跃管理员通过有效的自调用进入这些函数，生命周期变更并不要求必须保留另一个活跃的已注册管理员。

`updateOwner` 可以降级或使最后一个管理员过期，`removeOwner` 可以将其删除。隐式的 `address(this)` 密钥被视为类管理员身份，但对于普通的工厂部署代理账户，它并非实际可恢复的签名者。

### 影响
错误操作或受损的管理员操作可能永久阻塞未来的仅限自调用管理功能，包括所有者恢复、授权额度批准、UUPS 升级以及空签名自取消流程。剩余的非管理员外部调用能力可能仍然存在，但特权账户管理可能被永久锁死。

### 建议
在删除、降级或使活跃管理员过期之前，要求必须保留另一个已注册的活跃管理员。仅统计已注册的、未过期的管理员密钥，除非部署明确设有可恢复的自密钥。

## [MEDIUM] M-04 - 过期所有者在 ERC-4337 验证期间使用 `block.timestamp`

- **聚合 ID：** M-04
- **来源 ID：** AA-003
- **来源：** protocol-account-abstraction
- **领域：** dos-griefing
- **验证结果：** CONFIRMED — 验证器确认，过期所有者在 `validateUserOp` 期间执行依赖 `TIMESTAMP` 的分支，而非通过验证数据返回所有者过期信息。
- **跨包：** 否
- **位置：**
  - `src/SmartWallet.sol:269`
  - `src/OwnerManager.sol:173`
  - `src/OwnerManager.sol:197`

### 描述
`validateUserOp` 调用 `getVerifiedValidator(pubKeyHash)`。对于设置了非零过期时间的所有者，`getVerifiedValidator` 会调用 `isSettingsExpired`，该函数在签名验证完成之前将过期时间与 `block.timestamp` 进行比较。

ERC-4337 验证应避免在验证代码中直接依赖时间戳/区块号，并通过返回的验证数据传达时间边界。当前的成功路径只返回签名提供的 `validUntil`，而非所有者设置的过期时间。

### 影响
由已配置过期时间的所有者签名的 UserOperation 可能被合规的捆绑器或 ERC-7562 风格的验证规则拒绝，即便它们在链上仍然有效。这是一个账户活性和集成兼容性问题。

### 建议
避免在 EntryPoint 验证路径中使用 `block.timestamp` 分支。将有效的所有者过期时间打包到返回的验证数据中，例如返回签名 `validUntil` 与所有者过期时间的最小值。

## [MEDIUM] M-05 - 内置验证器在验证期间可能回滚或执行无上限的证明计算

- **聚合 ID：** M-05
- **来源 ID：** AA-005
- **来源：** protocol-account-abstraction
- **领域：** dos-griefing
- **验证结果：** CONFIRMED — 验证器确认，格式错误的内置验证器载荷在 ABI 解码时可能回滚，而合法的大型证明数组会产生线性验证工作量且没有本地上限。
- **跨包：** 否
- **位置：**
  - `src/ValidationManager.sol:29`
  - `src/libraries/ECDSAValidatorLib.sol:31`
  - `src/libraries/PasskeyValidatorLib.sol:48`
  - `src/libraries/MerkleProofProcessor.sol:20`

### 描述
外部验证器合约被包裹在 `try/catch` 中，但内置的 ECDSA 和 passkey 验证器是直接调用的。UserOperation 签名控制 32 字节 keyHash 和 6 字节 validUntil 前缀之后作为验证器数据传入的字节。格式错误的 ECDSA 尾部数据可能在 `abi.decode(bytes32[])` 时回滚，格式错误的 passkey 载荷可能在解码 `WebAuthnAuth` 和证明时回滚。

解码成功时，证明数组在没有账户级最大值的情况下被线性处理。已注册的密钥哈希可被外部枚举，内置自密钥也映射到 ECDSA 验证器。

### 影响
攻击者可以提交使验证回滚或在失败前消耗大量验证 gas 的 UserOperation。影响属于运营层面的模拟/gas 滥用，受 `verificationGasLimit` 和捆绑器策略限制；未发现直接资金损失。

### 建议
使内置验证器的格式错误载荷以返回 `false` 的方式安全失败而非回滚，并对证明数组长度设置较小的文档化上限。针对格式错误的内置验证器载荷和超长证明数组添加测试。

## 需要 PoC

对抗性验证后，没有任何问题保留在 `NEEDS-POC` 状态。

## 误报

| ID | 标题 | 来源包 | 驳斥理由 |
|----|------|--------|---------|
| AA-004, STATE-001 | 无钩子的非管理员密钥保留对外部资产的无限制权限 | protocol-account-abstraction + universal-state-invariants | 行为可触达，但不构成绕过：已批准的文档明确将 `hook == address(0)` 定义为无钩子，并将无钩子的非管理员外部支出记录为与现有 execute 行为相同的已接受预置残留。 |
| STATIC-001 | 原生 TWA 结算将 ETH 发送给用户控制的收款方 | static | 经 CEI nonce 写入、全程瞬态 TWA 锁、受检低级调用、钩子包装和自调用限制驳斥。测试包含原生重入覆盖。 |
| STATIC-002 | 外部委托并回滚模拟器委托给任意目标 | static | 该函数在 delegatecall 后无条件回滚；EVM 回滚语义丢弃该帧中的存储写入、日志、转账、创建以及嵌套影响。 |
| STATIC-003 | 使用已部署工厂盐并附带 value 再次调用可能导致 ETH 滞留 | static | Solady 的辅助函数将非零 value 转发给已部署的实例或回滚；钱包代理具有可支付的 receive 路径。 |
| AA-002 | 无效 UserOp 可在验证失败前强制将 ETH 存入 EntryPoint | protocol-account-abstraction | EntryPoint 失败处理在验证数据失败后回滚整个交易，回滚存款信用；直接调用被 `onlyEntryPoint` 阻止。 |
| ARITH-002 | 未受检的 64 位 nonce 递增可绕回并重新打开旧 nonce | universal-arithmetic | 绕回需要 `2^64` 次同一密钥所有者授权的中继器成功执行；攻击者无法设置或独立推进私有 nonce 状态，因此不存在实际的安全影响。 |

## 建议

### 需要立即处理

未确认任何 Critical 级别问题，在 `FAIL_ON=critical` 条件下不生成 `rework_request.md`。

### 中等优先级

1. 将 `Static.SIG_VALIDATION_FAILED` 修正为规范的 ERC-4337 值 `1`，并添加验证数据打包回归测试。
2. 在 `updateOwner` 和 `removeOwner` 中添加最后活跃管理员的保留检查，或记录明确的可恢复自密钥部署模式。
3. 从 UserOp 验证路径中移除针对所有者过期的直接 `block.timestamp` 使用，并将有效过期时间打包到验证数据中。
4. 使内置验证器对格式错误载荷返回 `false` 而非回滚，并对 Merkle 证明长度设置上限。
5. 恢复私有恢复套件依赖，或使部署验证明确使用生产源码构建范围。

### 低优先级 / 最佳实践

1. 在部署交接中保留当前的 TWA 原生重入测试和委托并回滚模拟器文档。
2. 第 9 阶段应在部署验证前重新运行 `forge build src script`、大小检查、ABI 检查以及依赖项卫生检查。

## 各模式包报告索引

| 模式包 | 报告路径 | 原始候选项 |
|--------|---------|----------:|
| static | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/static.md` | 4 |
| capability-oracle-pricing | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/capability-oracle-pricing.md` | 0 |
| capability-signatures | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/capability-signatures.md` | 0 |
| capability-upgradeability | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/capability-upgradeability.md` | 0 |
| protocol-account-abstraction | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/protocol-account-abstraction.md` | 5 |
| protocol-economics | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/protocol-economics.md` | 0 |
| universal-access-control | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-access-control.md` | 1 |
| universal-arithmetic | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-arithmetic.md` | 2 |
| universal-baseline | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-baseline.md` | 0 |
| universal-dos-griefing | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-dos-griefing.md` | 0 |
| universal-interactions | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-interactions.md` | 0 |
| universal-state-invariants | `okx-smart-wallet-dev/.audit-workspace/.audit-tmp/universal-state-invariants.md` | 2 |

## 后端接口交接安全性

`docs/delivery/CONTRACT_INTERFACE.md` 经审查与实现相匹配。交接文档正确区分了终态 nonce 状态与结算：`transferAuthorizationState(nonce) == true` 以及 `AuthorizationAlreadyUsed` 可以代表已使用（Used）或已取消（Canceled），后端必须使用 `TransferAuthorizationUsed` 作为结算证明，使用 `TransferAuthorizationCanceled` 作为撤销证明。ABI 交接文件 `docs/delivery/abi/ITransferWithAuthorization.abi.json` 存在且非空。

## 链级检查清单

| 检查项 | 结果 |
|--------|------|
| EIP-712 域/类型哈希 | PASS — 直接使用 `hashTypedData(structHash)`，execute/receive/cancel 具有不同的类型哈希，账户/链绑定已保留。 |
| 重放保护 | PASS — TWA 随机 nonce 限定账户范围且具有终结性；已为后端事件对账记录 Used/Canceled 合并情况。 |
| 原生代币重入 | PASS — 瞬态锁跨越检查、nonce 写入、钩子调用、原生调用和事件触发全程覆盖。 |
| ERC-20 集成 | PASS — TWA 使用 SafeERC20，并在测试中处理无返回值/返回 false 的行为。 |
| 升级/存储 | PASS — UUPS 授权保持 `onlySelf`；TWA ERC-7201 命名空间与账户自定义存储根相互独立。 |
| ERC-4337 验证 | WARN — 已确认验证数据打包、所有者过期时间戳以及内置验证器格式错误/证明计算问题。 |
| 构建/依赖项 | WARN — 默认无范围限制的 `forge build` 因继承的恢复套件导入失败；生产 `src script` 构建通过。 |
