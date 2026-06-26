# INTEGRATION_TEST.md — 账户级带授权转账（TWA）集成测试报告

Stage 6.0 对内联入 `SmartWallet` ERC-4337 / UUPS 账户中的账户级 `TransferWithAuthorization`（TWA）结算接口的端到端集成测试。被测系统为通过真实 `SmartWalletFactory` 部署并初始化的真实 `SmartWalletEntry` 账户；TWA 以内联方式编译进该账户字节码。未修改任何合约源码、生产脚本或 `foundry.toml`。

## 结论：通过

所有计划集成场景均已执行并通过。断言验证了跨多笔交易、多参与者/密钥、两个独立部署账户、ERC-20/原生代币/手续费转移代币资金流、授权 nonce 生命周期、4337-nonce 与 TWA-nonce 隔离、UUPS 升级，以及已使用（Used）与已取消（Canceled）事件调和合约的真实端到端行为。未发生任何禁止的源码变更。未发现任何阻塞性实现缺陷、单元测试缺口或集成测试设计问题，因此不生成 `rework_request.md`。

## 环境
- 链：EVM — 以太坊主网语义，Cancun / EIP-1153（瞬态存储），`solc 0.8.29`，`evm_version=cancun`，`optimizer_runs=100`。
- 本地环境：Foundry `forge 1.7.1` 进程内 EVM（无分叉、无广播、无测试网/主网、无真实密钥）。
- 源码路径：`src/`
- 测试路径：`test/`（集成测试位于 `test/integration/`）
- 脚本路径：`script/`
- 集成测试命令：`forge test --match-path 'test/integration/' -vvv`（以及使用 `--skip 'test/Recovery.t.sol'` 的全套回归运行）。
- 部署地址：无外部地址——所有被测合约（账户实现、工厂、EntryPoint、验证器）均在 `setUp()` 中本地部署；`NATIVE_ASSET` 为 `0xEeee…EEeE` 哨兵常量。
- 上游输入快照（无源码变更基线）：`../inputs/A-05/okx-smart-wallet-dev`。
- 恢复套件限制：私有子模块 `lib/smart-wallet-recovery` 无法被当前工作节点克隆。仅 `test/Recovery.t.sol` 引入了该子模块；`src/` 不依赖它。所有 Forge 命令均使用 `--skip 'test/Recovery.t.sol'`，该限制作为非阻塞项继承自 Stage 1.0/5.0，不在 TWA 变更范围内。
- Stage 1.0 的 `baseline_build_status=failed` 源于陈旧的 Stage-1 快照（当时库尚未拉取）。在本 Stage 6 工作空间中，所有必需库均已存在，`forge build` 及现有 41 个 TWA 单元测试均通过。

## Stage 5 就绪状态
`docs/process/TEST_REPORT.md` 结论为**通过**（针对 `src/TransferWithAuthorization.sol` 的单元/模糊/不变量测试：行覆盖率/分支覆盖率均为 100%；无 Stage 4 缺陷）。Stage 6 继续推进。

## 集成测试计划

所有集成测试均位于 `test/integration/TransferWithAuthorizationIntegration.t.sol`，复用 `test/Base.t.sol` 中的真实部署框架（`SmartWalletFactory.createAccount` → ERC-1967 克隆 → `initialize`）。
测试源自已审批文档（DESIGN §4/§10/§11/§14/§16，SECURITY_SPEC §2/§5/§8，INTERFACE_SPEC §5/§6.1/§8）、真实实现以及 Stage 5 测试——而非假定的协议语义。测试刻意针对 Stage 5 函数级单元/模糊/不变量测试未覆盖的跨步骤/跨角色/跨账户/跨模块/跨交易行为。

约定（遵循 `foundry-integration-rules.md` 时间控制指南）：使用 `vm.warp(10_000)` 设置稳定基准时间；授权窗口使用绝对字面量（例如 `validAfter=9_000`，`validBefore=11_000`）；warp 目标为绝对值，绝不基于可能缓存的 `block.timestamp` 链式计算。签名采用真实的 `keyHash(32) ‖ ownerSignature` 信封，对直接的 `hashTypedData(structHash)` 摘要（INTERFACE_SPEC §8）进行签名，并按账户分别签名，以真实地测试跨账户绑定行为。

### 用户旅程矩阵
| 旅程 | 参与者 | 步骤 | 预期最终状态 | 测试用例 |
|------|--------|------|-------------|---------|
| 所有者授权 → 中继方结算 ERC-20 → 后续重放被拒绝 | 所有者（签名者）、中继方、接收方 | 为账户充值；中继方在 tx1 中结算；推进区块；中继方在 tx2 中重放 | 接收方仅被一次入账；nonce 终结；重放回滚 `AuthorizationAlreadyUsed`；账户仅被扣款一次 | `test_journey_erc20SettleThenReplayInLaterTxReverts` |
| 所有者撤销待处理授权，后续结算被拒绝 | 所有者（管理员，通过账户自调用）、中继方 | 所有者调用 `execute([self cancel form B])`；之后中继方尝试结算已取消的 nonce | nonce 终结（已取消）；`TransferAuthorizationCanceled` 已发出；结算回滚 `AuthorizationAlreadyUsed`；无资金转移 | `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts` |
| 收款方在其合约流程中原子性拉取应收款项 | 所有者（签名者）、合约收款方 | 向合约收款方签署接收授权；收款方从其自身逻辑调用 `receiveWithAuthorization` | 收款方合约获得入账；nonce 终结；非收款方提交被拒绝 | `test_multiActor_executePermissionless_receivePayeeGatedContractPayee` |
| 通过重提相同签名授权从瞬态故障中恢复 | 所有者（签名者）、管理员、中继方 | 在 tx1 中结算被策略/余额阻塞；所有者在 tx2 中修复条件；中继方在 tx3 中重提相同签名 | 首次尝试不消耗 nonce 且余额不变；最终尝试完成一次结算 | `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature`，`test_recovery_insufficientBalanceThenFundThenRetrySameSignature` |

### 多参与者场景矩阵
| 场景 | 参与者/角色 | 预期交互 | 负面参与者用例 | 测试用例 |
|------|-----------|---------|--------------|---------|
| 同一账户上的多个所有者密钥各自授权结算；每密钥 hook 隔离 | 管理员 ECDSA 密钥（无 hook）、非管理员 ECDSA 密钥（有 hook） | 每个密钥的结算选择该密钥自身的 hook；管理员密钥结算不调用任何 hook；带 hook 密钥结算恰好调用一次其 hook，传入精确的 `Call` | 不适用（隔离正向验证） | `test_multiActor_perKeyHookIsolationAcrossOwners` |
| `execute` 无需许可 vs `receive` 收款方门控 | 任意中继方、合约收款方 | 任意中继方结算执行授权；仅收款方结算接收授权 | 非收款方中继方提交接收授权回滚 `CallerNotPayee`；未注册密钥授权回滚 `InvalidSignature` | `test_multiActor_executePermissionless_receivePayeeGatedContractPayee` |
| 竞争中继方抢先提交相同签名授权 | 中继方 A、中继方 B（抢先方）、接收方 | 首个提交者向签名绑定的接收方结算；失败方的提交回滚 | 抢先运行结果中立：资金流向已签名的 `to`/`value`；失败方回滚 `AuthorizationAlreadyUsed`（R-2，INV-RECIPIENT-BOUND） | `test_multiActor_frontRunIsOutcomeNeutral` |

### 部署/初始化矩阵
| 组件 | 初始化参数 | 角色设置 | 预期初始状态 | 重新初始化失败测试 |
|------|-----------|---------|------------|----------------|
| 通过 `SmartWalletFactory.createAccount` 的 `SmartWalletEntry` 账户（全新，多所有者） | `InitialOwner[]` = 两个密钥（ECDSA），`salt` | 两个初始所有者均注册为**管理员**（`packSettings(true,0,0)`）；`WalletInitialized` | TWA 接口立即生效：`supportsInterface(0x86c5a9e1)==true`，`TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR()` == 账户 EIP-712 域分隔符；在新初始化账户上成功执行一次 ERC-20 结算 | `test_deploy_reinitializeReverts`（再次调用 `initialize` 回滚 `InvalidInitialization`） |
| `test_deploy_freshMultiOwnerAccountTwaLiveAndSettles` 覆盖初始化接线 + 首次结算 | | | | |

### 跨合约交互矩阵
| 交互 | 组件 | 预期调用 | 失败模式 | 测试用例 |
|------|------|---------|---------|---------|
| 两个独立部署账户间的授权重放 | 账户 A、账户 B（两者注册相同所有者密钥） | 为账户 A 授权的结算不得在账户 B 上执行 | 账户 B 重新计算 `from=address(this)=B` 并使用 B 的域分隔符（`verifyingContract=B`），因此 A 的签名回滚 `InvalidSignature`；B 余额不变；授权在 A 上仍可结算 | `test_crossAccount_authorizationDoesNotReplayAcrossAccounts` |
| 账户 ↔ 通过 `SafeERC20` 与手续费转移代币的 ERC-20 交互 | 账户、手续费转移 ERC-20、接收方 | 结算通过 `safeTransfer` 转移名义 `value`；代币收取手续费 | 账户扣款 `value`；接收方入账 `value − fee`；事件日志记录**名义** `value`；nonce 消耗（DESIGN §11，SECURITY_SPEC §4"结算名义价值，无内部记账假设"） | `test_fundFlow_feeOnTransferTokenSettlesNominalValue` |
| 账户 ↔ 合约原生代币接收方 | 账户、合约接收方 | 原生代币结算通过检查的 `to.call{value}` 转发价值 | `receive()` 回滚的接收方将回滚向上传播；账户余额 + nonce 不变 | `test_failure_nativeRecipientRevertRollsBackFully` |
| 账户 ↔ 每密钥消费 hook 合约 | 账户、hook 合约 | 结算调用已验证密钥的 `preCheck`/`postCheck` | 阻塞性 hook 回滚并还原已消耗的 nonce | `test_multiActor_perKeyHookIsolationAcrossOwners`，`test_recovery_hookBlockThenRemoveHookThenRetrySameSignature` |
| 账户 ↔ UUPS 新实现 | 账户、V2 实现 | 所有者通过 `executeWithRelayer` 自授权 `upgradeToAndCall` | TWA 授权 nonce 状态（ERC-7201 命名空间）在升级后持久保留；重放仍然回滚 | `test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade` |

### 资金流场景矩阵
| 流程 | 资产 | 初始余额 | 最终余额 | 记账检查 | 测试用例 |
|------|------|---------|---------|---------|---------|
| 多次连续 ERC-20 结算耗尽账户 | Mock ERC-20 | 账户已充值，接收方余额为 0 | 账户 = 初始 − Σvalue；接收方 = Σvalue | Σ 接收方入账 == Σ 账户扣款 == 总流出；守恒 | `test_fundFlow_sequentialErc20SettlementsConserveAndDrain` |
| 原生代币与 ERC-20 结算交错进行 | ETH + Mock ERC-20 | 账户两者均已充值 | 每个账本按各自 Σvalue 扣款 | 原生代币和代币账本在同一账户生命周期中各自独立守恒 | `test_fundFlow_mixedNativeAndErc20Conserve` |
| 手续费转移代币结算 | 手续费转移 ERC-20 | 账户已充值 | 账户 −value；接收方 +(value−fee) | 名义价值结算；事件记录 `value`；除 nonce 标志外无内部记账 | `test_fundFlow_feeOnTransferTokenSettlesNominalValue` |
| 自接收方外部代币支付（对照组） | Mock ERC-20 | 账户已充值 | 净零（账户即接收方） | `to`==账户但 `token`==外部的普通 ERC-20 支付**不是**自调用；净零结算 | 覆盖在 `test_multiActor_perKeyHookIsolationAcrossOwners` 对照断言中 |

### 状态连续性矩阵
| 场景 | 步骤序列 | 中间状态检查 | 最终状态检查 | 测试用例 |
|------|---------|------------|------------|---------|
| TWA 授权 nonce 空间与 4337/原生 nonce 隔离 | 中继方 `executeWithRelayer`（消耗 4337 nonce 0→1）；然后 TWA 结算 | 中继方执行后：`getNonce(0)==1`；TWA 结算后：`getNonce(0)` 不变 | `getNonce(0)` 仅由 4337 路径推进；TWA nonce 终结仅通过 TWA 路径；两者互不写入对方的空间（INV-NONCE-ISOLATION） | `test_stateContinuity_twaNonceIsolatedFrom4337Nonce` |
| 独立授权 nonce 独立推进 | 结算 n1；取消 n2（form A）；保留 n3 | n1 已使用，n2 已取消，n3 未使用 | n1/n2 终结（重放回滚）；n3 仍可在后续结算 | `test_stateContinuity_independentNoncesProgressIndependently` |
| 授权 nonce 在 UUPS 升级后持久性 | 结算 n；升级实现；查询/重放 n | n 在升级前终结 | 升级后 n 仍然终结；重放回滚；新实现标记生效 | `test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade` |

### 故障/恢复矩阵
| 故障场景 | 触发条件 | 预期回滚/错误 | 恢复/下一状态 | 测试用例 |
|---------|---------|-------------|-------------|---------|
| 每密钥 hook 阻塞消费 | 带 hook 的非管理员密钥结算 | hook 自定义错误；nonce 未使用；无资金转移 | 所有者通过 `execute` 移除 hook；相同签名重新提交后结算 | `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature` |
| 账户余额不足 | `value` > 账户余额 | 转账回滚；nonce 未使用；余额不变 | 所有者为账户充值；相同签名重新提交后结算 | `test_recovery_insufficientBalanceThenFundThenRetrySameSignature` |
| 授权已过期 | `block.timestamp >= validBefore` | `AuthorizationExpired` | 原授权无法恢复；新授权（新 nonce + 新窗口）可结算 | `test_failure_expiredAuthorizationReissueWorks` |
| 原生代币接收方拒绝 ETH | 合约接收方 `receive()` 回滚 | 接收方回滚向上传播 | nonce 未使用；账户余额不变；可改为目标其他接收方 | `test_failure_nativeRecipientRevertRollsBackFully` |

### Solidity 最佳实践工作流矩阵
| 工作流 | 最佳实践规则 | 无效端到端场景 | 预期无部分效果检查 | 测试用例 |
|--------|-----------|-------------|----------------|---------|
| 结算失败时先拒绝后执行 | CEI；在被拒绝的工作流完成前无状态/余额变更 | hook 阻塞、余额不足、原生代币接收方回滚、授权窗口过期 | 回滚后：账户余额、接收方余额、TWA nonce 状态和 4337 nonce 均不变 | `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature`，`test_recovery_insufficientBalanceThenFundThenRetrySameSignature`，`test_failure_nativeRecipientRevertRollsBackFully`，`test_failure_expiredAuthorizationReissueWorks` |
| 完整生命周期内 nonce 仅终结一次 | nonce 最多结算或取消一次 | 结算后重放；取消后结算 | 第二次终结转换回滚 `AuthorizationAlreadyUsed`；余额最多变动一次 | `test_journey_erc20SettleThenReplayInLaterTxReverts`，`test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts`，`test_stateContinuity_independentNoncesProgressIndependently` |

### 上下文推导场景覆盖
| 上下文来源 | 流程/约束 | 场景/检查 | 状态 | 备注 |
|----------|---------|---------|-----|-----|
| `context.technical` = Circle USDC 仓库（EIP-3009 起源：`transferWithAuthorization`/`receiveWithAuthorization`/`cancelAuthorization`） | 开区间有效窗口 | 过期后重新签发 + 旅程/恢复测试中的窗口边界 | 已覆盖 | OKX TWA 刻意将 EIP-3009 语义移至账户层（随机 nonce、信封、收款方拉取）；差异出自已审批设计，非冲突 |
| `context.technical`（Circle USDC） | 收款方门控接收（防抢先） | 合约收款方接收 + 非收款方拒绝 + 抢先中立性 | 已覆盖 | 匹配已审批 FR-2 / R-2 |
| `context.technical`（Circle USDC） | 取消使 nonce 终结 | 所有者取消后结算被拒绝；已使用与已取消事件调和 | 已覆盖 | OKG 设计新增 DR-001 仅事件区分 |
| `context.business` | — | — | 未提供 | 无业务上下文文件；按上下文加载策略记录 |
| PRD 关联补充 `eip-account-level-transfer-with-authorization.md` | 账户级 TWA EIP 草案（类型哈希/信封/ERC-165 id） | 类型哈希/域/接口接线通过部署 + 每次结算进行测试 | 已覆盖（通过已审批文档） | PRD/INTERFACE_SPEC §8 是信封结构的权威依据 |

### 事件与可观测性矩阵
| 流程 | 预期事件 | 索引字段 | 测试用例 |
|------|---------|---------|---------|
| 成功结算 | `TransferAuthorizationUsed(token, from, to, value, authorizationNonce)` | `token`、`from`、`to` 已索引；`value`、`authorizationNonce` 在数据中（nonce **不可**按主题过滤） | `test_journey_erc20SettleThenReplayInLaterTxReverts`，`test_observability_usedVsCanceledDistinguishableOnlyByEvent` |
| 取消 | `TransferAuthorizationCanceled(authorizer, authorizationNonce)` | `authorizer`（==账户）、`authorizationNonce` 均已索引（nonce **可**按主题过滤） | `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts`，`test_observability_usedVsCanceledDistinguishableOnlyByEvent` |
| 已使用与已取消调和（INTERFACE_SPEC §6.1，DR-001） | 两个终结 nonce 的 `transferAuthorizationState==true`；仅事件可区分 | 证明后端必须通过事件而非链上状态进行调和 | `test_observability_usedVsCanceledDistinguishableOnlyByEvent` |

### Mock/测试夹具合理性说明
| Mock/夹具 | 真实依赖项 | 已建模行为 | 已省略行为 | 安全性依据 | 覆盖的失败模式 |
|----------|----------|----------|----------|----------|-------------|
| `MockERC20`（来自 `test/Base.t.sol`） | 标准 ERC-20 | 余额、铸币、返回 true 的 `transfer` | 手续费/变基 | 精确价值守恒是被测属性；被测系统（账户）为真实合约 | 通过标准回滚实现余额不足 |
| `IntegrationFeeOnTransferERC20` | 手续费转移 ERC-20（例如通缩代币） | 从发送方扣除 `value`，向接收方入账 `value−fee`，将 `fee` 路由至汇聚地址，返回 true | 变基、黑名单 | 建模扣款与实收金额之间的真实差异，以验证"结算名义价值"设计说明而非假定 | 接收方入账金额减少已记录 |
| `IntegrationContractPayee` | 拉取应收款项的合约收款方 | 从自身逻辑调用 `receiveWithAuthorization`，使得 `msg.sender == to` | 无关业务逻辑 | 测试真实的收款方门控路径；不替代被测系统 | 非收款方提交被拒绝 |
| `IntegrationRecordingHook` | 每密钥消费策略 hook | 记录 `preCheck`/`postCheck` 调用次数及精确 `Call`（目标/价值/数据）和执行者 | 生产策略存储/限额 | 通过真实结算路径证明每密钥 hook 选择 + 隔离；不绕过 hook | 不适用（正向验证） |
| `IntegrationBlockingHook` | 阻塞性消费策略 hook | 在 `preCheck` 中回滚 | 策略内部机制 | 证明 hook 回滚端到端还原已消耗的 nonce，以及移除 hook 后可恢复 | hook 驱动回滚 + CEI 还原 |
| `RevertingNativeRecipient` | 拒绝 ETH 的合约接收方 | `receive()` 回滚 | 任意妨碍行为 | 证明原生代币腿失败时完全回滚（无部分效果） | 原生代币接收方拒绝 |
| `TwaWalletV2`（`is SmartWallet layout at 0x653ff6dc…`） | 真实的下一个 UUPS 实现 | 相同存储布局 + `isUpgraded()` 标记 | 新业务逻辑 | 忠实的升级目标，以便针对真实 `upgradeToAndCall` 而非存根测试存储持久性 | 不适用（正向验证） |
| `Base` 部署框架（`SmartWalletFactory`、`EntryPoint`、`ECDSAValidator`、`PasskeyValidator`、EIP-2470） | 生产账户/工厂部署与验证器路由 | 真实 CREATE2 克隆 + `initialize` + 真实验证器注册 | 生产部署脚本（由 Stage 9 负责） | 账户、工厂和验证器均为真实合约；仅外部代币/接收方/hook 外围组件使用 Mock | 重新初始化拒绝、跨账户绑定 |

## 执行证据
- `forge test --match-path 'test/integration/*' --skip 'test/Recovery.t.sol' -vv` → **19 通过，0 失败**（`.oli-work/forge-integration.log`）。
- 全套回归 `FOUNDRY_INVARIANT_RUNS=16 FOUNDRY_INVARIANT_DEPTH=16 forge test --skip 'test/Recovery.t.sol'` → 跨 26 个测试套件 **429 通过，0 失败，0 跳过**（`.oli-work/forge-full-suite.log`）；19 个新集成测试加上 410 个继承的单元/模糊/不变量测试，无回归。
- `forge build` 针对已恢复库干净编译；`Compiler run successful!`。
- 无源码变更门控 `check_no_source_changes.py --forbid-prefix src --forbid-prefix script --forbid-file foundry.toml --baseline-dir ../../inputs/A-05/okx-smart-wallet-dev` → `status: ok`，`violations: []`（`.oli-work/no-source-change.json`）。禁止前缀下唯一变更的文件（`foundry.toml`、`src/*`）均为 `inherited_from_baseline`（与 A-05 输入快照字节完全相同）；Stage 6 唯一新增的文件为 `test/integration/TransferWithAuthorizationIntegration.t.sol` 和 `docs/process/INTEGRATION_TEST.md`。

### Foundry 子模块/库环境说明（构建卫生）
仓库的 `.gitmodules` 记录的库 gitlink 提交比源码实际编译所用的工作树版本更新（例如 `lib/account-abstraction` gitlink → v0.8.0，但 `src/ERC4337Account.sol` 需要工作树中的 v0.7.0 API），且 `lib/smart-wallet-recovery` 是私有、不可克隆的子模块，仅由已跳过的 `test/Recovery.t.sol` 使用。当 `forge` 重新编译时，它会自动运行 `git submodule update --init`，否则会将每个已初始化库重置为（不兼容的）gitlink 提交并导致构建失败。本 Stage 将库恢复至 A-05 工作提交（离线 `git checkout`），并为每个子模块设置了 `git config submodule.lib/<name>.update none`（仅为 `.git/config` 变更——未跟踪、非禁止路径、不出现在 `git status` 中），从而使库固定在源码编译所需的版本上。未修改任何已跟踪文件（包括 `.gitmodules`）。这是一项环境/构建卫生观察，非合约行为问题；为 Stage 7.0/9.0 提供参考（gitlink/工作树版本漂移应在生产部署前进行调和）。

## 场景结果
| 场景 | 预期 | 实际 | 结果 |
|------|------|------|------|
| `test_deploy_freshMultiOwnerAccountTwaLiveAndSettles` | 全新多所有者工厂账户：两个所有者均为管理员，TWA id + 域分隔符生效，ERC-20 结算正常 | 符合预期 | 通过 |
| `test_deploy_reinitializeReverts` | 第二次 `initialize` 回滚 `InvalidInitialization` | 按预期回滚 | 通过 |
| `test_crossAccount_authorizationDoesNotReplayAcrossAccounts` | 账户 A 的授权在账户 B 上回滚 `InvalidSignature`（无资金转移），在账户 A 上仍可结算 | 符合预期 | 通过 |
| `test_journey_erc20SettleThenReplayInLaterTxReverts` | 结算一次（事件 + 精确扣款/入账），后续重放回滚 `AuthorizationAlreadyUsed`，无第二次入账 | 符合预期 | 通过 |
| `test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts` | 所有者通过真实 `execute` 自调用取消（取消事件），后续结算回滚，无资金转移 | 符合预期 | 通过 |
| `test_stateContinuity_twaNonceIsolatedFrom4337Nonce` | 中继方执行将 4337 nonce 从 0 推进至 1；TWA 结算保持其为 1；两个空间相互独立 | 符合预期 | 通过 |
| `test_stateContinuity_independentNoncesProgressIndependently` | n1 已使用，n2 已取消，n3 仍可结算；两个终结 nonce 均拒绝重放 | 符合预期 | 通过 |
| `test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade` | nonce 状态在 UUPS `upgradeToAndCall` 后保留；升级后重放仍然回滚 | 符合预期 | 通过 |
| `test_multiActor_perKeyHookIsolationAcrossOwners` | 管理员密钥结算不调用任何 hook；带 hook 密钥结算调用其 hook 一次，传入精确调用；自接收方外部代币净零（对照组） | 符合预期 | 通过 |
| `test_multiActor_executePermissionless_receivePayeeGatedContractPayee` | 任意中继方结算执行授权；非收款方接收回滚 `CallerNotPayee`；合约收款方成功拉取 | 符合预期 | 通过 |
| `test_multiActor_frontRunIsOutcomeNeutral` | 抢先方向已签名接收方结算；失败方回滚 `AuthorizationAlreadyUsed`；无重复入账 | 符合预期 | 通过 |
| `test_fundFlow_sequentialErc20SettlementsConserveAndDrain` | Σ 接收方入账 = Σ 账户扣款 = 已追踪流出；账户守恒 | 符合预期 | 通过 |
| `test_fundFlow_mixedNativeAndErc20Conserve` | 原生代币和代币账本各自按各自价值精确扣款/入账 | 符合预期 | 通过 |
| `test_fundFlow_feeOnTransferTokenSettlesNominalValue` | 账户扣款完整 `value`，接收方入账 `value − fee`，事件记录名义 `value`，nonce 终结 | 符合预期 | 通过 |
| `test_recovery_hookBlockThenRemoveHookThenRetrySameSignature` | hook 阻塞（nonce 未使用，无资金转移）；所有者移除 hook；相同签名随后结算 | 符合预期 | 通过 |
| `test_recovery_insufficientBalanceThenFundThenRetrySameSignature` | 余额不足结算回滚（nonce 未使用）；充值后相同签名结算 | 符合预期 | 通过 |
| `test_failure_expiredAuthorizationReissueWorks` | 过期授权回滚 `AuthorizationExpired`；新窗口的新授权结算 | 符合预期 | 通过 |
| `test_failure_nativeRecipientRevertRollsBackFully` | 向拒绝合约的原生代币结算回滚；账户余额 + nonce 不变 | 符合预期 | 通过 |
| `test_observability_usedVsCanceledDistinguishableOnlyByEvent` | 两个 nonce 在状态中均已终结；`Used` 将 nonce 放入数据（非主题），`Canceled` 将 nonce 作为已索引主题 | 符合预期 | 通过 |

## 失败分析
- 无。19 个集成场景和 410 个继承的单元/模糊/不变量测试全部通过。未发现任何实现缺陷、单元测试缺口或集成测试设计缺陷。

| 失败用例 | 命令 | 预期 | 实际 | 根因层次 | 目标 Stage |
|---------|------|------|------|---------|-----------|
| 无 | 不适用 | 不适用 | 在接受的恢复套件跳过条件下，所有集成场景和完整回归套件均通过 | 不适用 | 不适用 |

## 观察到的设计风险
- 未发现端到端阻塞性合约设计风险。针对 Stage 7.0 的两项信息性观察：
  - **手续费转移/非标准代币记账（属设计决策，非缺陷）：** `executeTransferWithAuthorization` 通过 `SafeERC20.safeTransfer` 结算名义 `value`，并在 `TransferAuthorizationUsed` 中发出名义 `value`，而手续费转移代币向接收方实际入账金额少于 `value`（已在 `test_fundFlow_feeOnTransferTokenSettlesNominalValue` 中验证）。这符合已审批设计（"结算名义价值；除 nonce 标志外无内部记账假设"）。需要获取此类代币实际收款金额的链下调和逻辑，必须读取代币自身的 `Transfer` 事件，而非 TWA 事件的 `value`。
  - **库 gitlink 与工作树版本漂移（构建卫生，非合约行为）：** 参见上文 Foundry 子模块说明。建议在 Stage 9.0 生产部署前，将 `.gitmodules` gitlink 与源码编译所用版本进行调和。

## 返工集成解决方案
- 不适用——这是首次 Stage 6 集成运行（`../last/` 不存在；无 Stage 6 `rework_request.md` 注入）。无先前集成测试可复用。

## 集成覆盖说明
- **已覆盖用户旅程：** 授权→中继→结算→重放被拒绝；所有者撤销→结算被拒绝；合约收款方拉取；通过重提相同签名授权从瞬态故障中恢复。
- **已覆盖参与者/角色交互：** 管理员与非管理员所有者密钥（每密钥 hook 隔离）；无需许可的 `execute` 中继方与收款方门控的 `receive`；抢先中继方（结果中立）；未注册/非收款方负面参与者。
- **已覆盖部署/初始化路径：** 两个所有者均为管理员的全新多所有者工厂部署；新初始化账户上 TWA 接口 id + 域分隔符生效；重新初始化拒绝。
- **已覆盖跨合约交互：** 两个独立部署账户（跨账户重放被域/`from` 绑定拒绝）；账户↔通过 `SafeERC20` 与 ERC-20 交互（包括手续费转移代币）；账户↔合约原生代币接收方（成功和回滚）；账户↔每密钥 hook；账户↔UUPS 新实现。
- **已覆盖资金流：** 多次连续 ERC-20 结算（守恒 + 耗尽）；交错的原生代币 + ERC-20（独立账本守恒）；手续费转移名义价值结算；外部代币自接收方净零对照组。
- **已覆盖状态连续性路径：** TWA 授权 nonce 空间与 4337/原生 nonce 隔离；独立 nonce 独立推进；UUPS 升级后授权 nonce 持久性。
- **已覆盖故障/恢复路径：** hook 阻塞、余额不足、授权窗口过期、拒绝原生代币接收方——每种情况均不留下部分效果（账户余额、接收方余额、nonce 状态、4337 nonce 不变），且在适用情况下，可通过修复条件并重新提交相同签名或重新签发新授权来恢复。
- **已覆盖上下文推导流程：** Circle USDC EIP-3009 传承（开区间窗口、收款方门控接收、取消终结性）已测试；OKX 账户级差异（随机 nonce、keyHash 信封、收款方拉取、仅事件区分已使用/已取消）已测试。未提供业务上下文。
- **Solidity 最佳实践工作流验证：** 每个被拒绝工作流上的先拒绝后执行（CEI/无部分效果）；完整生命周期内 nonce 仅终结一次；结果中立的抢先运行。
- **事件/可观测性：** `TransferAuthorizationUsed`（token/from/to 已索引；value+nonce 在数据中）和 `TransferAuthorizationCanceled`（authorizer+nonce 已索引）已验证；已使用与已取消的绑定调和规则（仅通过事件而非链上 `transferAuthorizationState` 可区分）已端到端验证。
- **剩余非阻塞缺口：** 私有 `test/Recovery.t.sol` 套件已跳过（不可克隆子模块，不在 TWA 变更范围内）；外部验证器（非内置）TWA 信封和 passkey 端到端已在 Stage 5 单元级别覆盖，此处不再重复测试；库 gitlink/工作树版本漂移为 Stage 7.0/9.0 的环境事项。
