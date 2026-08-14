# REQUIREMENTS_ANALYSIS.md — PRD 覆盖度与就绪性索引

> 此为 Stage 2.0 的轻量级 PRD 覆盖度/就绪性索引。本文档**不是**重写版 PRD，也**不是** `DESIGN.md` 的推导来源。`DESIGN.md` 直接由 `docs/process/REQUIREMENTS.md`（PRD）、EIP 草案补充文档、现有代码、技术上下文及所选模式参考生成。原始 PRD id 保持不变，详细规则保留在 PRD 中。

功能：**账户级带授权转账（TWA）** — 在 OKX SmartWallet 账户上新增账户级 `ITransferWithAuthorization` 清算接口。

## 1. PRD 就绪性与来源清单

| 项目 | 内容 |
|------|-------|
| PRD 标题 / 版本 | PRD-账户级离线签名授权转账 (Account-Level Transfer With Authorization) v1.0-fix |
| PRD 来源路径 | `docs/process/REQUIREMENTS.md` |
| 合约专项 PRD | 是 — 包含 FR/AC/NFR、状态语义、产品不变量、数据对象、依赖项、风险、成功指标，以及 PRD 固定的 `_verifyTwaSignature` 规范 |
| 已读章节 | §1 概述，§2 背景/动机 + 接口 `ITransferWithAuthorization`，§3 范围，§4 FR-0..FR-5 + 目标追溯，§5 产品状态语义 + 不变量，§6 NFR-1..4，§7 技术要求 + `_verifyTwaSignature` 规范，§8 数据，§9 DEP-1..8，§10 指标，§11 风险 R-1..R-7/R-9，§12 PRD 到 TD 交接 |
| 目标链 / EVM | EVM — 以太坊主网（chainId 1），**Cancun**（EIP-1153 瞬态存储）。流程不变量 `chain=evm`。 |
| codebase_mode | `existing_code_change`（初次运行，首次采用；非重跑，无返工） |
| 权威补充文档 | EIP 草案"账户级带授权转账"（`.oli-work/prd-supplements/eip-account-level-transfer-with-authorization.md`，状态 `fetched`，约 31.6 KB）— 接口、3 个 typehash 常量值、`NATIVE_ASSET`、nonce 模型及 `INTERFACE_ID` 的规范来源。 |
| 技术上下文 | Circle USDC FiatToken 仓库（`.oli-work/context/technical/repo/`），标准 EIP-3009 参考（`contracts/v2/EIP3009.sol`）。索引/入口文件（`index.md`/`context.md`）未被纳入工作区快照；本次运行已重新确认仅 `repo/` 已物化。无业务上下文。 |
| 缺失章节 / 矛盾 | 无阻塞项。已注意：(a) EIP 参考实现使用 ERC-1271 + 20 字节验证器包装，但 PRD §7/§12 要求相反（直接类型化数据摘要 + 32 字节 `keyHash` 包装）— **PRD 优先**（FR-1-AC-8 要求 ERC-1271 包装的摘要必须失败）；(b) PRD §2.1 接口错误集与 EIP 参考实现错误集不同 — **PRD §2.1 优先**；(c) `InvalidRecipient(to)` 在任何 FR/AC 中均无触发规则 — 解析为安全派生守卫（见 §7）。 |

## 2. PRD ID 覆盖度索引

> id 原样保留，详细语义仍在所引用的 PRD 章节中。"直接设计覆盖目标"指向 `DESIGN.md`。

### 业务目标
| PRD ID | 类型 | 设计相关性 | 直接设计覆盖目标 | 备注 |
|--------|------|------------------|-------------------------------|-------|
| G-1 | 目标 | 合约 + ABI | FN-001, FN-002, FN-006 | 账户级清算标准接口 + ERC-165；ECDSA gas <120k |
| G-2 | 目标 | 合约 | FN-001/002 清算路径 | 任意 ERC-20 + 原生资产，无需修改代币合约 |
| G-3 | 目标 | 安全/不变量 | INV-NONCE-ONCE, INV-RECIPIENT-BOUND, FN-003 | 防重放 / 防抢跑 |
| G-4 | 目标 | 签名 | FN-101 `_verifyTwaSignature` + INTERFACE_SPEC §8 | 复用 ECDSA + passkey 验证器；后端/测试的验证器专属包装布局已指定（DR-002） |
| G-5 | 目标 | 安全/不变量 | INV-HOOK-ISOMORPHISM, FN-103 | TWA 清算复用签名密钥的 hook **以及 `_batchCall` 自调用守卫**，与 execute 同构（自目标一致性，DR-003） |

### 功能需求与验收标准
| PRD ID | 类型 | 设计相关性 | 直接设计覆盖目标 | 备注 |
|--------|------|------------------|-------------------------------|-------|
| FR-0 | 流程概述 | 合约 | DESIGN §4 时序图 | 使用流程（授权 / 促成方清算 / 接收 / 取消） |
| FR-1 (+规则 1-9) | 功能（P0） | 合约 | FN-001, FN-102, FN-103 | `executeTransferWithAuthorization`，无需许可 |
| FR-1-AC-1 | AC | 测试 | FN-001 | 正常路径 → 转账 + nonce 已用 + 事件 |
| FR-1-AC-2 | AC | 测试 | INV-NONCE-ONCE | 重复使用 nonce → `AuthorizationAlreadyUsed`，无资金移动 |
| FR-1-AC-3 | AC | 测试 | INV-TIME-WINDOW | 超出 `(validAfter, validBefore)` 窗口 → 回滚 |
| FR-1-AC-4 | AC | 测试 | FN-101 | 非拥有者/未注册签名者 → `InvalidSignature`，nonce 未消耗 |
| FR-1-AC-5 | AC | 测试 | FN-103 | 余额不足 → 整个交易回滚 |
| FR-1-AC-6 | AC | 测试 | INV-HOOK-ISOMORPHISM | 超限/非白名单（通过 hook） → hook 回滚，nonce 未消耗 |
| FR-1-AC-7 | AC | 测试 | INV-HOOK-ISOMORPHISM | 符合策略 → 成功，hook 记账与同参数 execute 一致 |
| FR-1-AC-8 | AC | 测试（反向） | FN-101 | ERC-1271 消息包装的摘要 → 必须失败回滚 |
| FR-1 边界 1 | 边界 | 测试 | FN-101 | `signature.length < SIGNATURE_ENVELOPE_MIN_LENGTH` → `InvalidSignature()` |
| FR-1 边界 2 | 边界 | 测试 | FN-101 | `getVerifiedValidator(keyHash)==address(0)` → `InvalidSignature()` |
| FR-2 (+规则 1-3) | 功能（P0） | 合约 | FN-002, FN-102, FN-103 | `receiveWithAuthorization`，`msg.sender == to`，独立 typehash |
| FR-2-AC-1 | AC | 测试 | FN-002 | 收款方在策略内调用 → 成功 + 事件 |
| FR-2-AC-2 | AC | 测试 | FN-002 | `msg.sender != to` → `CallerNotPayee` |
| FR-2-AC-3 | AC | 测试（反向） | INV-TYPESEP | 通过 receive 使用 execute 类型授权 → 验证失败（无跨类型重放） |
| FR-2-AC-4 | AC | 测试 | INV-HOOK-ISOMORPHISM | 超限/非白名单（通过 hook） → hook 回滚 |
| FR-3 (+规则 1-5) | 功能（P1） | 合约 | FN-003 | `cancelTransferAuthorization` 形式 A（签名）+ 形式 B（自调用，空签名） |
| FR-3-AC-1 | AC | 测试 | FN-003 | 形式 A 有效拥有者签名 → nonce 已用，`Canceled`，后续 execute/receive 回滚 |
| FR-3-AC-2 | AC | 测试 | FN-003 | 空签名 + `msg.sender != address(this)` → 回滚 |
| FR-3-AC-3 | AC | 测试 | INV-NONCE-ONCE | 已使用的 nonce → `AuthorizationAlreadyUsed` |
| FR-3-AC-4 | AC | 测试 | FN-003 | 空签名 + 自调用 → nonce 已用，`Canceled` |
| FR-4 | 功能（P2） | 合约 | FN-004, FN-005 | `transferAuthorizationState` + `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR`；nonce 管理规则 |
| FR-4-AC-1 | AC | 测试 | FN-004 | 已用/已取消的 nonce → 返回 true |
| FR-4-AC-2 | AC | 测试 | FN-004 | 从未使用的 nonce → 返回 false |
| FR-5 | 功能（P2） | 合约/ABI | FN-006 | ERC-165，`INTERFACE_ID = 0x86c5a9e1` 必须为 `public constant` |
| FR-5-AC-1 | AC | 测试 | FN-006 | `supportsInterface(0x86c5a9e1)` → true |
| FR-5-AC-2 | AC | 测试 | FN-006 | 未知 id → false |

### 状态、不变量、NFR
| PRD ID / 名称 | 类型 | 设计相关性 | 直接设计覆盖目标 | 备注 |
|---------------|------|------------------|-------------------------------|-------|
| 状态：未使用 / 已使用 / 已取消 | 状态机 | 合约 | DESIGN §10 | 已使用和已取消为终态，互斥 |
| 产品不变量 1（一次性；已用/已取消为终态） | 不变量 | 安全 | INV-NONCE-ONCE | |
| 产品不变量 2（nonce 空间与原生/4337 隔离） | 不变量 | 安全/存储 | INV-NONCE-ISOLATION | |
| 产品不变量 3（to 与 value 受签名约束） | 不变量 | 安全 | INV-RECIPIENT-BOUND | |
| 产品不变量 4（CEI：转账前先用 nonce） | 不变量 | 安全 | INV-CEI | |
| 产品不变量 5（受 hook 约束，与 execute 同构） | 不变量 | 安全 | INV-HOOK-ISOMORPHISM | |
| NFR-1 | 非功能 | gas/字节码 | DESIGN §2, §14, §16 | 运行时字节码 ≤ 24,576（EIP-170）；ECDSA ≤ 120,000 gas；passkey 单独基准 |
| NFR-2 | 非功能 | 安全 | INV-CEI, FN-106 锁 | 防重放/抢跑/原生重入（CEI + 瞬态锁） |
| NFR-3 | 非功能 | 权限 | DESIGN §3 访问控制, INV-HOOK-ISOMORPHISM | execute 无需许可；cancel 受限；TWA 不得绕过每密钥 hook |
| NFR-4 | 非功能 | 可观测性 | 事件 FN-001/002/003 | 所有状态变更均可通过事件观测 |

### 技术、数据、依赖项、风险、交接
| PRD ID / 项目 | 类型 | 设计相关性 | 直接设计覆盖目标 | 备注 |
|---------------|------|------------------|-------------------------------|-------|
| §7 `_verifyTwaSignature` 7 步规范 | 技术（PRD 固定） | 签名 | FN-101 | 包装格式 `keyHash(32)‖ownerSignature`；直接 `hashTypedData(structHash)`；无 ERC-1271 包装 |
| §7 typehash 可见性（public constant） | 技术（PRD 固定） | ABI | DESIGN §6 常量 | 3 个 typehash + `INTERFACE_ID` 必须为 `public constant` |
| §7 EIP-712 域（SmartWallet / 1.1.0） | 技术（PRD 固定） | 签名 | FN-104, FN-005 | 复用账户域；在 `Static.sol:22-23` 中验证 |
| §7 UUPS + ERC-7201 命名空间 | 技术 | 存储/升级 | DESIGN §8, §13 | 新 nonce 存储位于独立命名空间 |
| §7 EVM cancun + 瞬态重入锁 | 技术 | 安全/构建 | FN-106, 风险登记表 | 需要 `evm_version=cancun`（当前为 shanghai） |
| §7 单合约内联（EIP-170） | 技术 | 架构 | DESIGN §2, §5 | 新 mixin 内联编译；无 facade/library 链接 |
| §8.1 数据对象（转账授权 / 授权状态 / 代币配置 / 消费策略） | 数据 | 存储 | DESIGN §8 | `operationType` = typehash 选择器，非已签名的结构体字段 |
| §8.2 权限边界 | 数据 | 权威来源 | DESIGN §8, §11 | 链上与链下权限 |
| DEP-1..DEP-8 | 依赖项 | 信任模型 | DESIGN §12 | 全部"已确认"，同仓库链上原语 + 中继方 + cancun 链 |
| §10 指标（8 项） | 成功指标 | 测试/审计 | DESIGN §16 | gas、重放=0、收款人篡改=0、hook 绕过=0、代币覆盖度、字节码、ERC-1271 包装失败=100% |
| R-1..R-7, R-9（无 R-8） | 风险 | 安全 | SECURITY_SPEC §8 | 重入、抢跑、错误包装、存储冲突、知识、重叠、密钥绕过、gas/优化器 |
| §12 PRD 到 TD 交接 | 交接 | 全部 | DESIGN §1, §2 | PRD 固定项与 TD 决策项已记录 |

## 3. 合约范围分类

| PRD ID | 分类 | 合约职责 | 链下 / 后端职责 | 原因 |
|--------|----------------|-------------------------|------------------------------------|--------|
| FR-1, FR-2 | 链上 | 验证签名、检查 nonce/时间窗口、标记已用（CEI）、执行 hook、转账 | 构建 EIP-712 负载、收集签名、选择/提交中继方 | 不可逆清算 + 托管 |
| FR-3 | 链上 | 使未使用的 nonce 失效（签名或自调用） | 提交取消交易；决定何时取消 | 协议状态，不可逆 |
| FR-4 | 链上（状态）/ 混合（getter） | 跟踪 nonce 状态；暴露 getter | 索引事件；链下重建域分隔符 | 公开可验证性 |
| FR-5 | 链上 | ERC-165 `supportsInterface` | 促成方发现 | 公共接口检测 |
| `_verifyTwaSignature`（§7） | 链上 | 验证器路由 + 签名验证 | 生成拥有者签名（ECDSA/passkey） | 信任敏感授权 |
| 消费策略 / hook 限制（§8.1） | 混合 | hook 合约在链上强制执行；TWA 调用它 | 配置每密钥 hook 参数；为密钥配置 hook | 链上约束，链下配置 |
| NFR-4 可观测性 | 链上（发出）/ 链下（索引） | 发出事件 | 索引 `TransferAuthorizationUsed`/`Canceled` | 对账 |
| §3.2 范围外项目 | 超出范围 | 无 | — | 批量授权、链上 allowedTokens/限额、暂停/终止开关、paymaster、多链单签名、常设额度 — 见 §8 |

## 4. 现有上下文派生约束

> 此处为必要内容，因为 `codebase_mode=existing_code_change`。证据：`.oli-work/stage02-analysis/existing-code.md` + 直接读取（在 `DESIGN.md` 中引用）。

| # | 约束 | 来源（文件:行号） | 设计影响 |
|---|-----------|--------------------|---------------|
| C-1 | 账户是 UUPS 可升级的模块化智能账户（ERC-4337 + ERC-7702）；状态 mixin 由 `SmartWallet` 继承，部署为 `SmartWalletEntry`。 | `SmartWallet.sol:29-42`, `SmartWalletEntry.sol:9` | TWA 是新继承的 mixin，内联于单一账户字节码中 |
| C-2 | Hook 执行模式：`_batchCall(Call[],keyHash)` 解析 `getHook(_ownerSettings[keyHash])` 并运行 `preCheck(calls,msg.sender)` / `postCheck(ret,msg.sender)`。 | `SmartWallet.sol:146-172`, `OwnerManager.sol:225` | TWA 以经验证的 keyHash 为键，复制此 hook 调用语义 |
| C-3 | `Call{address target;uint256 value;bytes data}`。`_call` 是原始汇编调用，**不检查返回值**。 | `Types.sol:4`, `ExecutionManager.sol:11-40` | TWA 的 ERC-20 部分必须使用 SafeERC20（PRD §12"保留 SafeERC20 返回值校验"） |
| C-4 | 验证器路由：`getVerifiedValidator(bytes32)→address`（address(this)→ECDSA addr(1)，已过期→0）；`_validateSignature(addr,bytes32,bytes32,bytes)→bool`（ECDSA/passkey/外部，失败关闭）。 | `OwnerManager.sol:173`, `ValidationManager.sol:29` | `_verifyTwaSignature` 原样复用两者 |
| C-5 | EIP-712 由 solady 支持；`hashTypedData(structHash)` = `keccak256(0x1901‖domSep‖structHash)`；域 `name="SmartWallet"`，`version="1.1.0"`。 | `ERC712.sol:13`, `Static.sol:22-23` | 摘要推导与 EIP 草案完全匹配；复用 `hashTypedData` |
| C-6 | `Static.NATIVE_ETH = 0xEeee…EEeE`（ERC-7528）已存在。 | `Static.sol:19-20` | 作为原生资产哨兵复用；不得重新声明冲突值 |
| C-7 | ERC-7201 命名空间模式 `keccak256(abi.encode(uint256(keccak256(ns))-1)) & ~0xff`；现有命名空间 `SmartWallet.ERC7201.CustomStorage` 根 `0x653ff6dc…`。整个账户使用原生 `layout at` 指令。 | `ERC7201.sol`, `Static.sol:24-27`, `SmartWalletEntry.sol:9` | 新 TWA nonce 命名空间必须独立 + 使用汇编存储访问器 |
| C-8 | `onlySelf` = `msg.sender == address(this)`；`_authorizeUpgrade` 为 `onlySelf`。 | `BaseAuthorization.sol:12`, `SmartWallet.sol:366` | 取消形式 B 复用 `onlySelf`；升级权限不变 |
| C-9 | 原生执行 nonce `mapping(uint192=>uint64)`（NonceManager）。 | `NonceManager.sol:12` | TWA `mapping(bytes32=>bool)` 是独立空间（不变量 2） |
| C-10 | 现有 execute/UserOp 签名包装为 38 字节（`keyHash(32)+validUntil(6)+sig`）；`isValidSignature` 通过 `MessageSignLib.hash` 包装摘要。 | `SmartWallet.sol:110,124,331,345`, `DecodeLib` | TWA 使用独立的 32 字节包装（`keyHash(32)+sig`），且不得使用 MessageSignLib 包装（R-3） |
| C-11 | 构建配置：`solc 0.8.29`，**`evm_version=shanghai`**，`optimizer_runs=2000`。 | `foundry.toml:5-9` | shanghai 无法编译 EIP-1153 瞬态锁 → 必须切换至 cancun（风险登记表） |
| C-12 | ERC-165 `supportsInterface` 为 `virtual` `||` if-chain。 | `FallbackHandler.sol:32-44` | 通过 override + `super` 扩展以添加 `0x86c5a9e1` |
| C-13（上下文） | Circle EIP-3009 使用按 `(address,nonce)` 的映射、严格**开区间** `(validAfter, validBefore)` 窗口，`receiveWithAuthorization` 要求 `to==msg.sender`，以及 `cancelAuthorization`。 | 上下文 `contracts/v2/EIP3009.sol` | 确认 TWA 的开区间窗口、接收调用者检查及取消语义；OKX 使用扁平的 `bytes32` 映射并增加 `token` 字段 |

技术上下文与 PRD 之间无冲突；上下文与 PRD 所规定的 EIP-3009 派生语义相互印证。EIP 草案与 PRD 之间的分歧以 PRD 为准（见 §1 和 §7）。

## 5. 变更范围与保留行为

| 方面 | 详情 |
|--------|--------|
| 请求的变更 | 在 SmartWallet 账户上添加 `ITransferWithAuthorization` 清算接口（FR-1..FR-5），复用现有验证器路由 + hook + EIP-712 域。 |
| 变更类型 | TWA 逻辑为**B 类型**（全新模块）— 指定到完整的新代码深度。以下为 **A 类型**（修改现有）：`supportsInterface`（添加一个 id）、`foundry.toml`（`evm_version` shanghai→cancun）以及 `SmartWallet` 继承列表（添加 mixin）。 |
| 直接受影响 | 新增：`src/interfaces/ITransferWithAuthorization.sol`、`src/TransferWithAuthorization.sol`（mixin）。修改：`src/SmartWallet.sol`（继承 mixin）、`src/FallbackHandler.sol` 或 mixin override（ERC-165）、`foundry.toml`（evm_version）。 |
| 间接受影响 | 字节码大小（EIP-170 预算）→ `optimizer_runs` 重新调优；存储布局（新 ERC-7201 命名空间，不得冲突）；gas 基准。 |
| 必须保持不变 | 现有 execute / executeWithRelayer / executeUserOp / validateUserOp 行为；38 字节 execute 签名包装；现有 owner/validator/hook/nonce 语义；现有 ERC-7201 `CustomStorage` 布局；现有 ERC-165 id；UUPS 升级权限（`onlySelf`）；EIP-712 域。 |
| 无更广泛影响的证据 | TWA 仅新增外部函数 + 一个独立存储命名空间 + 一个 ERC-165 id；它调用现有内部原语而不修改它们。瞬态重入锁和 `evm_version=cancun` 是增量变更（cancun 是 shanghai 的超集）。全局影响分析见 `DESIGN.md §2.5`。 |

## 6. 设计覆盖目标

| PRD ID | 预期设计覆盖 | 规范设计所有者 | 测试 / 审查目标 | 状态 |
|--------|--------------------------|------------------------|----------------------|--------|
| FR-1 | 函数 + nonce + 时间窗口 + 签名 + hook + 转账 + 事件 | FN-001 / FN-102 / FN-103 | 单元 + 模糊 + 不变量 + 集成 | 已覆盖 |
| FR-2 | 函数 + `to==msg.sender` + 独立 typehash | FN-002 | 单元 + 反向（跨类型） | 已覆盖 |
| FR-3 | 函数 + 形式 A/B + nonce 失效 | FN-003 | 单元 | 已覆盖 |
| FR-4 | 视图 getter + nonce 跟踪 | FN-004 / FN-005 | 单元 | 已覆盖 |
| FR-5 | ERC-165 检测 | FN-006 | 单元 | 已覆盖 |
| `_verifyTwaSignature` | 按 7 步规范进行内部验证 | FN-101 | 单元 + 反向（R-3） | 已覆盖 |
| 不变量 1-5 | 强制执行点 | INV-NONCE-ONCE / -ISOLATION / -RECIPIENT-BOUND / -CEI / -HOOK-ISOMORPHISM | 不变量测试 | 已覆盖 |
| NFR-1 | 字节码 + gas 预算 | DESIGN §2/§14 | `forge build --sizes`，gas 报告 | 已覆盖（在 Stage 4.0 中验证） |
| NFR-2/3/4 | 重入锁、权限矩阵、事件 | FN-106 / DESIGN §3 / 事件 | 不变量 + 访问控制 + 事件测试 | 已覆盖 |
| 安全派生 | `InvalidRecipient(to)` 零地址守卫，无 hook 密钥残留 | SD-1..（SECURITY_SPEC §2/§8） | 单元 + 审计 | 已覆盖 |

## 7. 假设、未决问题与阻塞项

| 项目 ID | 类型 | 来源 | 影响 | 决策 / 所需输入 |
|---------|------|--------|--------|-------------------------|
| A-1 | 假设 | PRD §7 / 现有代码 | `SIGNATURE_ENVELOPE_MIN_LENGTH = 32`（包装 = `keyHash(32)‖ownerSignature`；TWA 有效性来自已签名的 `validAfter`/`validBefore`，因此与现有 38 字节 execute 包装不同，无 6 字节 `validUntil` 前缀）。 | 采用 32；记录；Stage 4.0 确认 |
| A-2 | 假设 | EIP 草案 + PRD §8.1 | `operationType`（§8.1 字段）通过**选择 typehash**（Execute vs Receive）实现，而非已签名的结构体字段；三种已签名字段集在其他方面完全相同。 | 采用；在 DESIGN §9 中记录 |
| A-3 | 假设（安全派生） | 安全分析师 / PRD §2.1 | `InvalidRecipient(to)` — PRD 声明了该错误但未给出触发规则。采用：当 `to == address(0)` 时回滚（防止通过 `to.call{value}` 静默销毁原生 ETH）。同时建议拒绝 `to == NATIVE_ASSET` 哨兵。 | 采用 `to==address(0)`（及哨兵）守卫；记录为安全派生（SD-1/SD-2） |
| A-4 | 假设 | PRD §7 / R-9 | `optimizer_runs` 是动态调节值；Stage 4.0 通过二分法搜索，在添加 TWA + public constant typehash getter 后满足 EIP-170 要求。 | Stage 4.0 拥有具体值 |
| A-5 | 假设 | PRD §7 / R-4 | 新 ERC-7201 命名空间字符串（例如 `SmartWallet.ERC7201.TransferAuthorization`）；具体槽位在 Stage 4.0 中计算并经存储布局验证确认无冲突。 | Stage 4.0 计算 + 验证 |
| A-6 | 假设 | PRD FR-3 / EIP | 取消形式 A 由**任意已注册账户密钥**通过 `_verifyTwaSignature` 授权（nonce 是账户范围的，非密钥范围），与 EIP 的"owner(s)"及账户授权模型一致。 | 采用；残余 griefing 风险已记录（SECURITY_SPEC） |
| OQ-1 | **已解决**（Stage 3.0 返工 DR-002） | 后端 / 接口 | 后端如何为每个 owner/validator 派生 `keyHash` 并在 `ownerSignature` 内编码 passkey 签名。 | **已在 `INTERFACE_SPEC.md` §8（验证器专属签名包装）中解决** — ECDSA `keccak256(abi.encodePacked(addr))` + 65 字节签名；内置 passkey `keccak256(abi.encodePacked(pubKeyX,pubKeyY))` + `abi.encode(PasskeyPubKey)‖abi.encode(WebAuthnAuth,bytes32[])`；外部验证器自定义。关闭 G-4 后端交接。 |
| OQ-2 | 未决问题 | PRD NFR-1 | passkey 路径 gas 基准（PRD 将 passkey 排除在 <120k ECDSA 目标之外）。 | Stage 5.0/6.0 单独测量 |

无阻塞项。PRD 在内部已足够定义安全的合约行为；所有未决项均为 TD 级别（Stage 4.0）或后端交接事项，而非缺失的产品决策。

## 8. 链下与范围外边界

| PRD 项目（§3.2 / §8.2） | 未在链上实现的原因（本次变更） |
|------------------------|-------------------------------|
| 批量授权（单次多笔转账） | PRD：每次 ERC 单笔转账，以降低复杂度/审计面 |
| 链上 `allowedTokens` 白名单 / 每账户限额 | PRD：账户层不限制代币；限制委托给 hook + 链下 |
| 链上紧急暂停 / 终止开关 | PRD：依赖取消 + 链下风险控制 |
| Paymaster / gas 赞助 | PRD：中继方直接支付 gas |
| 多链单签名批处理 | PRD：由现有 Merkle 路径覆盖 |
| 常设额度（代扣） | PRD：由现有 Allowance 路径覆盖 |
| 签名负载构建、中继方选择、接收 UI 元数据、事件索引历史、策略参数配置 | PRD §8.2 链下权限 |

## 9. Stage 3.0 返工更新（DR-001 / DR-002 / DR-003）

> 来自 Stage 3.0 设计审查的就绪性/可追溯性变化。上述 PRD id 覆盖度不变（无新增/删除 PRD id）；这些是文档一致性和后端交接解决方案。完整的返工解决方案见 `output.md`。

| DR | 受影响的 PRD id | 解决方案 | 规范落地位置 | 覆盖度/就绪性影响 |
|----|------------------|------------|-------------------|---------------------------|
| DR-001 | FR-3, FR-4, NFR-4 | 清算对账必须通过事件区分已使用与已取消；`AuthorizationAlreadyUsed`/`state==true` 不等于"已清算"。 | INTERFACE_SPEC §6/§6.1；DESIGN §10；SECURITY_SPEC §5/§9(14) | 修正了 FR-3 取消语义上的后端集成正确性缺口；提升了 Stage 4.0 交接的就绪性。 |
| DR-002 | G-4, FR-1, FR-2（§7 包装） | 验证器专属签名包装（ECDSA/passkey/外部）已完整规范；OQ-1 已解决。 | INTERFACE_SPEC §8；DESIGN FN-101/§16 | G-4 后端/测试路径现可构建，无需逆向工程；就绪性提升。 |
| DR-003 | G-5, FR-1, FR-2, R-7, NFR-3, 不变量 5 | 自调用守卫在 TWA 清算中复制（FN-103 步骤 3）；INV-HOOK-ISOMORPHISM 现在在自目标路径上成立。 | DESIGN FN-103/§15.5/§16；SECURITY_SPEC §2/§3/§9(13)；INTERFACE_SPEC §8.4 | 消除了同构性声明中的内部一致性缺陷；无 PRD 覆盖度变化。 |
