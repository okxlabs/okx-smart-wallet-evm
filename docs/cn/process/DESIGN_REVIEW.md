## 总体决定：已批准

## 审查摘要
- 目标链：EVM，以太坊主网 `chainId=1`，需要 Cancun / EIP-1153。
- 审查文件：`docs/process/REQUIREMENTS.md`、`REQUIREMENTS_ANALYSIS.md`、`DESIGN.md`、`INTERFACE_SPEC.md`、`SECURITY_SPEC.md`、`EXISTING_CODEBASE_BASELINE.md`、`SOURCE_MANIFEST.md`、`REWORK_HISTORY.md`、`.oli-work/prd-supplements/eip-account-level-transfer-with-authorization.md`，以及 `src/` 下的选定源文件和 `.oli-work/stage02-analysis/` 下的选定 Stage 2 分析文件。
- 上下文状态及上下文来源审查：来自 Circle USDC 仓库索引和 PRD 补充文档的技术上下文已存在；未发现业务上下文。与 PRD 或设计包之间无上下文冲突。
- 确定性包检查：通过。`.oli-work/stage03-design-package-check.json` 的 `status=ok`，`blocking_count=0`，需求分析、设计、接口规范和安全规范均无缺失分组。
- Stage 2.0 流程遥测状态：刷新后的工作空间/输入包中不存在 Stage 2 最终 `output.md`；rework-lite 分析文件存在。遥测仅用于诊断目的，不构成阻塞项。
- 最高严重性：无。
- 重新审查：是。设计包包含 DR-001、DR-002 和 DR-003 的 Stage 3 返工更新记录，本次审查验证了其当前解决状态。

## 独立 PRD 重建
- 预期链上职责：在现有 SmartWallet 账户上实现已冻结的 `ITransferWithAuthorization` 接口；通过现有验证器路由验证直接 EIP-712 类型数据签名；强制执行未使用的随机 `bytes32` 授权 nonce、开放时间窗口、绑定 `{token, from=account, to, value, validAfter, validBefore, authorizationNonce}`、CEI nonce 标记、keyHash 选定的钩子执行、原生/ERC-20 结算、取消操作、getter 函数和 ERC-165 检测。
- 预期链下职责：构建类型数据载荷、生成随机 nonce、收集 ECDSA/passkey/外部验证器签名、在前面添加 TWA `keyHash(32)` 信封、选择中继器/促成方、配置每个密钥的钩子、索引事件以及协调支付状态。
- 混合职责：每个密钥的支出策略在链下配置，但由选定钩子在链上强制执行；后端协调依赖链上 `TransferAuthorizationUsed` 和 `TransferAuthorizationCanceled` 事件。
- 关键用户流程：促成方通过 `executeTransferWithAuthorization` 进行结算；收款方通过 `receiveWithAuthorization` 进行原子拉取；中继器进行有签名取消；账户以空签名进行自调用取消；状态/域/接口发现。
- 关键资金/资产流程：从账户到 `to` 的单一流出；`NATIVE_ASSET` 哨兵选择带检查的原生转账；其他所有 `token` 值使用 ERC-20 转账语义；除 nonce 终态性之外，不新增托管、手续费、退款或会计余额。
- 关键权限与角色：`executeTransferWithAuthorization` 无需许可，需有效的所有者密钥签名；`receiveWithAuthorization` 要求 `msg.sender == to`；有签名取消需要已注册的账户密钥；空签名取消要求 `msg.sender == address(this)`；UUPS 升级保持 `onlySelf`。
- 预期状态机：成功执行/接收后 `Unused -> Used`；取消后 `Unused -> Canceled`；Used 和 Canceled 均为终态，以相同的 `bool=true` 标志编码，仅通过事件加以区分。
- 不可协商的安全不变量：nonce 一次性使用；nonce 与账户/4337 nonce 相互隔离；收款人/金额签名绑定；转账前 CEI；TWA 钩子行为与相同参数 execute（含自调用保护）同构；直接类型数据摘要，不使用 ERC-1271/MessageSignLib 包装；独立的 typehash；开放时间窗口；ERC-7201 存储隔离；原生重入性受 CEI 加瞬态锁约束。
- PRD 模糊点：`InvalidRecipient(to)` 触发规则未明确说明；设计将其解析为零地址及哨兵收款人拒绝。取消形式 A 的权限被描述为所有者签名；设计将其解释为通过 `_verifyTwaSignature` 的任何已注册账户密钥，并记录了残留的恶意抢先风险。Passkey 的 gas 目标故意保持开放，因为 PRD 将 passkey 排除在 ECDSA `<120k` 目标之外。
- 上下文衍生约束：现有 SmartWallet 使用 UUPS、solady EIP-712 域 `SmartWallet`/`1.1.0`、`Static.NATIVE_ETH`、keyHash 验证器路由、围绕 `_batchCall` 的每个密钥钩子、ERC-7201 命名空间风格、`onlySelf` 升级授权，以及当前必须迁移至 Cancun 以支持瞬态存储的 `evm_version=shanghai`。

## Stage 2.0 流程说明
| 流程信号 | 报告证据 | 审查用途 | 是否单独构成阻塞 |
|---------|---------|---------|----------------|
| 子代理记录 | Stage 2 最终 `output.md` 缺失；`.oli-work/stage02-analysis/rework-interface.md` 和 `rework-security.md` 存在 | 仅诊断用途；直接审查最终制品 | 否 |
| 选定模式参考 | 设计包引用账户抽象和可升级性；由于存在角色/权限，访问控制也适用 | 针对现有 SmartWallet、UUPS、ERC-7201 和权限边界的检查清单路由 | 否 |
| 上下文/现有代码分析 | `REQUIREMENTS_ANALYSIS.md` 和 `DESIGN.md` 列出了现有代码约束和受影响文件 | 路由针对性源代码抽查 | 否 |
| 返工解决 | `REQUIREMENTS_ANALYSIS.md` 记录了 DR-001、DR-002、DR-003 的解决方案 | 防循环验证 | 否 |

## 上下文一致性检查
| 上下文来源 | 约束/信号 | 设计处理方式 | 结果 | 备注 |
|-----------|---------|------------|------|------|
| PRD 补充：EIP 草案 | 冻结接口形状、typehash、`NATIVE_ASSET`、nonce 模型、`INTERFACE_ID` | 已采纳；PRD 专属验证器信封和钩子规则覆盖通用参考实现示例 | 通过 | 补充文档实质性内容，非占位符 |
| PRD 补充 vs PRD | EIP 示例提及 ERC-1271/20 字节验证器地址，而 PRD 规定直接摘要和 `keyHash(32)` 信封 | 设计遵从 PRD，并要求包装摘要回归测试失败 | 通过 | PRD 权威性得到正确保留 |
| Circle USDC 技术上下文 | EIP-3009 开放区间、接收方调用者检查、取消/已使用终态性 | 设计镜像了开放窗口、`msg.sender == to` 以及终态 nonce 行为 | 通过 | 上下文与 PRD 语义吻合 |
| 现有 SmartWallet 源码 | `_batchCall` 钩子 + 自调用保护、keyHash 验证器路由、solady EIP-712、ERC-7201、`onlySelf` UUPS | 设计复用这些模式并记录了差异 | 通过 | 针对性源码阅读证实了关键声明 |
| 现有 Foundry 配置 | `evm_version=shanghai`，优化器运行次数 2000 | 设计要求 Cancun 及优化器重新调优 | 通过 | 实现阶段构建门控，非设计阻塞项 |
| 业务上下文 | 无 | 记录为无业务上下文 | 通过 | 无冲突 |

## PRD 直接至设计检查
| PRD 条目 | 独立理解 | 设计处理方式 | 结果 | 问题 |
|---------|---------|------------|------|------|
| G-1 / FR-1 / FR-2 / FR-5 | 账户级标准结算接口及 ERC-165 发现 | 冻结接口，函数规范 FN-001/FN-002/FN-006，公共常量 | 通过 | 无 |
| G-2 | 任意 ERC-20 加原生资产，无需代币级支持 | `NATIVE_ASSET` 原生路径，SafeERC20 ERC-20 路径，USDT/无返回值测试 | 通过 | 无 |
| G-3 / 状态语义 | 通过随机 nonce、终态和收款人/金额绑定防止重放/欺诈 | 单个 `mapping(bytes32=>bool)`，直接摘要，仅事件区分 Used/Canceled | 通过 | 无 |
| G-4 / PRD §7 | 复用现有验证器路由进行 ECDSA 和 passkey；直接类型数据摘要 | FN-101 和 `INTERFACE_SPEC.md` §8 为 ECDSA/passkey/外部验证器指定 `keyHash(32) || ownerSignature` | 通过 | 无 |
| G-5 / PRD 不变量 5 | TWA 必须像 execute 一样应用签名密钥的支出策略 | FN-103 使用已验证的 keyHash 选择钩子，并复制 `_batchCall` 自调用保护 | 通过 | 无 |
| FR-3 | 通过有签名请求或账户自调用进行取消；已取消为终态 | FN-003 涵盖形式 A/B，发出 `Canceled`，并标记 nonce 为已使用 | 通过 | 无 |
| FR-4 | 状态 getter 和域分隔符 getter | FN-004/FN-005 已指定 | 通过 | 无 |
| NFR-1 | 字节码 <= EIP-170；ECDSA 路径 <120k gas；passkey 基线单独测试 | 设计记录了优化器重新调优、大小和 gas 门控 | 通过 | 无 |
| NFR-2 / R-1 | 重放/抢先/原生重入安全性 | CEI 加瞬态锁加接收 typehash | 通过 | 无 |
| R-3 / FR-1-AC-8 | ERC-1271/MessageSignLib 包装摘要必须失败 | 仅使用直接 `hashTypedData(structHash)`，需要负测试 | 通过 | 无 |
| §12 PRD 至 TD 交接 | PRD 固定条目不可更改；TD 拥有 slot、常量、锁和优化器 | 设计将固定需求与实现阶段细节分离 | 通过 | 无 |

## 覆盖率索引检查
| 检查项 | 结果 | 备注 |
|-------|------|------|
| 原始 PRD ID 保留 | 通过 | G、FR、AC、NFR、不变量、依赖、风险和度量 ID 均已保留。 |
| 范围分类 | 通过 | 链上、链下、混合和超出范围的边界已明确说明。 |
| 覆盖目标 | 通过 | 关键 PRD 条目映射到规范设计函数 ID、不变量和测试。 |
| 假设/开放问题 | 通过 | TD 级假设已记录；剩余开放项为非阻塞性的度量/偏好项。 |
| 补充文档处理 | 通过 | EIP 草案约束仅在与 PRD 一致时采纳；验证器信封和摘要路径以 PRD 为准。 |
| 现有代码约束 | 通过 | 现有架构、受影响文件、保留行为和全局影响均已索引。 |

## 确定性包完整性检查
| 文档 | 状态 | 缺失分组 | 备注 |
|-----|------|---------|------|
| requirements_analysis | ok | 无 | 确定性检查字符数 `23487` |
| design | ok | 无 | 确定性检查字符数 `53939` |
| interface_spec | ok | 无 | 确定性检查字符数 `21789` |
| security_spec | ok | 无 | 确定性检查字符数 `18814` |

## 规范设计检查
| 检查项 | 结果 | 备注 |
|-------|------|------|
| 超出 PRD 的 schema 扩展：每个 PRD 中未涉及的存储字段均有 (a) PRD 锚定的理由，(b) 对 PRD 定义相关字段的语义影响分析，(c) 对受影响 PRD 下游行为的明确分析 | 通过 | 唯一持久化的 TWA 字段是 PRD 定义的 `mapping(bytes32=>bool)`；瞬态锁为非持久化且由 PRD 安全需求驱动。 |
| 函数规范可在无需猜测的情况下实现 | 通过 | FN-001..FN-006 和 FN-101..FN-106 包含输入、检查、状态变更、事件/错误、外部调用和测试。 |
| 状态机和终态规则 | 通过 | Unused/Used/Canceled 终态性、仅事件区分、revert 时 CEI 回滚以及重放/幂等性均已明确说明。 |
| 资产和资金流设计 | 通过 | 原生/ERC-20 分支、SafeERC20、无手续费/托管、精确金额转移和价值守恒均已指定。 |
| 部署/初始化/升级 | 通过 | UUPS 保留、无新初始化器、ERC-7201 命名空间、Cancun、优化器和存储布局门控均已指定。 |
| 自一致性检查 | 通过 | 每个命名不变量均有强制执行点；自调用一致性问题由 FN-103 步骤 3 解决。 |

## 叠加一致性检查
| 叠加文档 | 设计参考 | 结果 | 备注 |
|---------|---------|------|------|
| `INTERFACE_SPEC.md` | FN-001..FN-006，FN-101，§10 事件/状态 | 通过 | 后端信封、类型数据、错误、事件索引和结算协调与 `DESIGN.md` 一致。 |
| `SECURITY_SPEC.md` | 不变量，FN-102/FN-103/FN-106，§11 资金流 | 通过 | 安全叠加层源自设计并新增了具体的测试/审计义务。 |
| `REQUIREMENTS_ANALYSIS.md` | 完整 PRD 基线和设计 ID | 通过 | 覆盖率索引未被用作替代 PRD，亦未折叠关键内容。 |

## 安全合约检查
| 检查项 | 结果 | 备注 |
|-------|------|------|
| 零地址保护：每个 `address` 类型的构造函数参数和存储 slot 要么指定了零地址保护，要么有明确记录的不需要的理由 | 通过 | 无新构造函数参数；`to==0` 被拒绝；`token==0` 预期通过 SafeERC20/无代码代币失败；`validator==0` 映射到 `InvalidSignature`；`hook==0` 设计上表示无钩子；`from` 为派生值。 |
| 签名/重放合约 | 通过 | 直接类型数据摘要、域分离、typehash 分离、随机 nonce 以及短/未注册签名失败均已指定。 |
| 访问控制矩阵 | 通过 | 无需许可的 execute、仅收款方的 receive、有签名/自调用取消、未变更的 UUPS `onlySelf` 以及自目标保护均已明确说明。 |
| 资金流安全 | 通过 | 无未经授权的资金流出路径；钩子和签名检查在转账之前执行；失败时原子性 revert。 |
| 原生重入性 | 通过 | CEI 加瞬态锁和 Cancun 门控均已指定。 |
| 资金锁定/不支持代币 | 通过 | TWA 不持有资金；ERC-20 失败时 revert；手续费/变基残留记录为名义金额转账语义。 |

## 现有代码增量审查
| 检查项 | 结果 | 备注 |
|-------|------|------|
| 现有代码模式已识别 | 通过 | `SOURCE_MANIFEST.md` 和基线记录 `codebase_mode=existing_code_change`。 |
| 增量分类 | 通过 | 新 TWA 逻辑视为 B 类；继承/ERC-165/Foundry 变更视为 A 类。 |
| 当前规范已保留 | 通过 | 现有验证器、钩子、EIP-712 域、UUPS、ERC-7201、自定义错误和 Foundry 布局均已保留。 |
| 全局影响已审查 | 通过 | 字节码、存储、构建 EVM、后端事件/错误和测试均已覆盖。 |
| 基线构建失败已处理 | 通过 | 记录为来自 Stage 1 的依赖/环境问题；Stage 4 必须恢复依赖访问。 |
| 兼容性风险 | 通过 | ABI 新增为追加性质；现有接口已保留。 |

## 模式参考审查
| 模式/规则 | 设计处理方式 | 结果 | 备注 |
|---------|------------|------|------|
| 账户抽象 | 保留现有 SmartWallet/EntryPoint/模块模型；无新 EntryPoint/paymaster | 通过 | TWA 是账户级结算路径，不是钱包框架的重新设计。 |
| 可升级性/存储 | 保留 UUPS、`onlySelf`、禁用初始化器和 ERC-7201 命名空间策略 | 通过 | 下游需要存储布局和干运行升级测试。 |
| 访问控制 | 使用现有 keyHash 所有者模型、钩子设置和 `onlySelf`；未新增不受支持的管理员角色 | 通过 | 没有意外的角色成为价值接收方。 |
| 后端接口规则 | 后端可调用函数、事件、错误、类型数据、幂等性和 Java 备注均已存在 | 通过 | 结算对取消事件协调现为绑定性约束。 |
| 安全规范规则 | 威胁模型、不变量、访问矩阵、资金流、外部调用、风险和审计假设均已存在 | 通过 | 产品特定内容，非通用内容。 |

## 返工/防循环审查
| 条目 | Stage 2.0 响应 | 审查方评估 | 结果 |
|-----|--------------|----------|------|
| DR-001 Used vs Canceled 协调 | `INTERFACE_SPEC.md` §6/§6.1 和 `SECURITY_SPEC.md` §5/§9 声明 `state==true`/`AuthorizationAlreadyUsed` 为终态但不是结算证明 | 充分；后端必须要求匹配的 `TransferAuthorizationUsed` 事件并拒绝将 `Canceled` 视为已支付 | 通过 |
| DR-002 验证器特定信封 | `INTERFACE_SPEC.md` §8 为 ECDSA、内置 passkey 和外部验证器信封规则指定了 32 字节前缀 | 充分，可用于后端/测试构建；解决了之前的开放问题 | 通过 |
| DR-003 自目标钩子同构 | `DESIGN.md` FN-103 步骤 3 和 `SECURITY_SPEC.md` INV-HOOK-ISOMORPHISM 复制了以已验证 keyHash 为键的 `_batchCall` 自调用保护 | 充分；原生自目标发散已关闭，控制案例已记录 | 通过 |
| 用户驱动的重新运行范围 | `REWORK_HISTORY.md` 表示无用户驱动的返工 | 不适用 | 通过 |

## 维度结果
| 维度 | 结果 | 备注 |
|-----|------|------|
| PRD 解读和智能合约范围 | 通过 | 直接 PRD 职责和链下边界均已保留。 |
| PRD 覆盖率/就绪性索引质量 | 通过 | 覆盖率索引轻量、保留 ID 且可追溯。 |
| 架构和图表 | 通过 | 架构、流程、序列和状态图语义清晰。 |
| 模块和接口设计 | 通过 | 新的 mixin/接口及现有继承变更范围明确且精确。 |
| 后端集成接口规范 | 通过 | 类型数据、事件、错误、信封和协调规则可实现。 |
| 函数规范 | 通过 | 函数 ID 涵盖检查、输入、状态变更、事件/错误、外部调用和 revert 案例。 |
| 状态和资金流正确性 | 通过 | nonce 终态性、CEI 回滚、事件区分、原生/ERC-20 路径和价值守恒均已指定。 |
| 安全合约质量 | 通过 | 不变量、访问矩阵、风险缓解措施以及审计/测试义务均具体明确。 |
| 需求到设计到测试的可追溯性 | 通过 | 每个关键 FR/AC/NFR/不变量均映射到设计和测试目标。 |
| 现有代码增量安全性（如适用） | 通过 | 增量优先行为、保留的规范和全局影响均已记录。 |
| 可实现性 | 通过 | Stage 4 可依据文档实现，无需实质性猜测；剩余选择为实现门控。 |
| 可测试性/可审计性 | 通过 | Stage 5/6/8 具有具体的单元、模糊、不变量、集成、gas、存储和安全目标。 |

## 完整性自检
- 维度结果表中的每一行均已评估：是。
- 每个命名不变量均已检查具体强制执行点：是。已检查的资金/会计不变量包括 `INV-NONCE-ONCE`、`INV-NONCE-ISOLATION`、`INV-RECIPIENT-BOUND`、`INV-CEI`、`INV-HOOK-ISOMORPHISM`、`INV-TIME-WINDOW`、`INV-TYPESEP`、`INV-NO-NATIVE-BURN` 和 `INV-VALUE-CONSERVATION`。
- 资金流失败矩阵已检查：是。余额不足、钩子 revert、转账失败、原生重入、手续费/残留代币语义以及取消对结算协调均已覆盖。
- 叠加矛盾已检查：是。`DESIGN.md`、`INTERFACE_SPEC.md` 和 `SECURITY_SPEC.md` 之间未发现剩余矛盾。

## 阻塞项
- 无。

## 非阻塞说明
- Stage 2 最终 `output.md` 在刷新后的工作空间/输入包中不可用。这仅是流程遥测缺口；最终制品和 rework-lite 证据足以支持制品质量审查。
- `optimizer_runs`、具体 ERC-7201 slot 值、字节码大小、gas 数值和 passkey 基线是有效的 Stage 4/5 实现和验证门控，非设计阻塞项。
- 基线构建失败已记录为未解决的依赖访问/子模块问题；Stage 4 必须在实现验证之前恢复依赖。
- 取消形式 A 被任何已注册账户密钥授权，记录为带有恶意抢先残留风险的假设；未发现资金损失路径，且该解释在 PRD 的所有者/验证器路由模型下是可辩护的。

## 先前返工响应审查
- 条目：DR-001 结算协调
- Stage 2.0 响应：新增了 `TransferAuthorizationUsed` 和 `TransferAuthorizationCanceled` 之间基于事件的区分；移除了将裸 `AuthorizationAlreadyUsed` 作为结算证明的做法。
- 审查方评估：充分。

- 条目：DR-002 签名信封
- Stage 2.0 响应：新增了针对 ECDSA、passkey 和外部验证器的验证器特定信封章节。
- 审查方评估：充分。

- 条目：DR-003 自调用一致性
- Stage 2.0 响应：新增了 FN-103 自调用保护及安全/测试矩阵。
- 审查方评估：充分。
