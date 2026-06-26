# 单元测试、模糊测试与不变量测试结果

## 结论：通过

Stage 5 返工新增并运行了针对已批准账户级 `TransferWithAuthorization` 实现的独立单元测试、模糊测试及不变量覆盖。限定范围的 TWA 测试套件与现有受影响套件均通过，未发现 Stage 4 实现缺陷，且本阶段未引入任何被禁止的生产源码/脚本/foundry 配置变更。

非阻塞性环境限制：私有 `lib/smart-wallet-recovery` 子模块无法被当前工作节点克隆，因此所有 Forge 命令均使用 `--skip 'test/Recovery.t.sol'` 运行。该遗留恢复测试套件不在 TWA 变更范围内，不作为本次运行的 Stage 5 阻塞项。

## 环境

- 目标链：EVM，以太坊主网语义，Cancun / EIP-1153。
- 代码库模式：`existing_code_change`，Stage 5 返工第 2 次尝试。
- 源码路径：`src/`
- 测试路径：`test/`
- 脚本路径：`script/`
- 上游输入快照：`../inputs/A-04/okx-smart-wallet-dev`
- 上下文状态：本 Stage 5 工作区中不存在任何有效的 `.oli-work/context` 文件；已批准的流程文档保留了 Circle USDC EIP-3009 技术背景及 PRD 关联的 TWA EIP 补充说明。未提供业务上下文。
- 恢复套件限制：接受非阻塞性环境限制；所有 Forge 命令均使用 `--skip 'test/Recovery.t.sol'`。
- 已执行命令：
  - `forge test --skip 'test/Recovery.t.sol' -vvv --no-match-test 'invariant'` -> 通过，407 个测试，`.oli-work/forge-scoped-unit-no-invariant.log`
  - `forge test --skip 'test/Recovery.t.sol' --match-test 'testFuzz' -vvv` -> 通过，14 个模糊测试，`.oli-work/forge-scoped-fuzz.log`
  - `FOUNDRY_INVARIANT_RUNS=16 FOUNDRY_INVARIANT_DEPTH=16 forge test --skip 'test/Recovery.t.sol' --match-test 'invariant' -vvv` -> 通过，3 个不变量测试，`.oli-work/forge-scoped-invariant.log`
  - `forge test --skip 'test/Recovery.t.sol' --match-test 'test_passkey' -vvv` -> 通过，2 个 TWA passkey 测试，`.oli-work/forge-passkey-twa.log`
  - `forge coverage --skip 'test/Recovery.t.sol' --report summary` -> 通过，410 个测试，`.oli-work/forge-coverage-scoped-summary.txt`
  - `coverage_gate.py --include-path-regex '^src/transferwithauthorization\.sol$'` -> 通过，100% 行覆盖 / 100% 分支覆盖，`.oli-work/coverage-gate-transfer-with-authorization.json`
  - `coverage_gate.py --exclude-path-regex '(^|/)(script|test|lib)/'` -> 符合预期的既有代码整体生产失败，98.8839% 行覆盖 / 98.8506% 分支覆盖，`.oli-work/coverage-gate-production.json`
  - `check_no_source_changes.py --forbid-prefix src --forbid-prefix script --forbid-file foundry.toml --baseline-dir ../../inputs/A-04/okx-smart-wallet-dev` -> 通过，`.oli-work/no-source-change.json`
  - `forge fmt --check test/Base.t.sol test/TransferWithAuthorization.t.sol test/TransferWithAuthorizationInvariant.t.sol` -> 通过

## 测试计划

### 需求与测试映射矩阵

| 需求 | 预期行为 | 测试文件 / 测试名称 | 状态 |
|------|----------|---------------------|------|
| FR-1 / FR-1-AC-1 | `executeTransferWithAuthorization` 完成签名的 ERC-20/原生资产转账，触发 `TransferAuthorizationUsed` 事件，并将 nonce 标记为终态。 | `TransferWithAuthorization.t.sol::test_executeErc20_happy`、`test_executeNative_happy`、`test_noReturnToken_settlesViaSafeERC20`、`testFuzz_executeErc20MovesExactValue` | 通过 |
| FR-1-AC-2 / INV-NONCE-ONCE | 重用已使用或已取消的 nonce 应回滚，且不能再次移动资金。 | `test_replay_reverts`、`test_cancelFormB_selfThenSettleReverts`、`invariant_nonceSettlesAtMostOncePerTrackedNonce` | 通过 |
| FR-1-AC-3 / INV-TIME-WINDOW | 结算仅在开区间 `(validAfter, validBefore)` 内有效。 | `test_notYetValid_reverts`、`test_expired_reverts` | 通过 |
| FR-1-AC-4 / FR-1 边界 1/2 | 错误签名者、短信封、包装摘要、字段篡改、未注册密钥或格式错误的遗留信封应失败，且 nonce 保持未使用。 | `test_wrongSigner_reverts`、`test_unregisteredKey_revertsAndNonceUnused`、`test_wrappedDigestSignature_revertsAndNonceUnused`、`test_shortEnvelope_reverts`、`test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused`，以及模糊变异测试 | 通过 |
| FR-1-AC-5 / INV-VALUE-CONSERVATION | 账户余额不足或代币操作失败应原子性回滚，nonce 保持未使用且余额不变。 | `test_falseReturnToken_revertsAndNonceUnused`、`test_insufficientErc20Balance_revertsAndNonceUnused`、`test_insufficientNativeBalance_revertsAndNonceUnused`、`invariant_tokenAccountingConservedAcrossSuccessfulSettles` | 通过 |
| FR-1-AC-6 / FR-1-AC-7 / G-5 | 密钥选择的 hook 以等效于 execute 的调用形态被调用；hook 回滚将回滚 nonce。 | `test_hookInvoked_blocksSettle_and_nonceUnconsumed`、`test_recordingHookReceivesExactErc20CallAndExecutor`、`test_recordingHookReceivesExactNativeCallAndExecutor` | 通过 |
| FR-1-AC-8 / R-3 | ERC-1271/MessageSignLib 包装摘要签名应失败；直接类型化数据签名应通过。 | `test_wrappedDigestSignature_revertsAndNonceUnused`，以及正常路径测试 | 通过 |
| G-4 / DR-002 | TWA 使用 `keyHash(32) || ownerSignature`；passkey keyHash 为 `keccak256(abi.encodePacked(pubKeyX,pubKeyY))`；无 `validUntil` 前缀。 | `test_passkeyEnvelope32BytePrefix_settlesErc20`、`test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused` | 通过 |
| FR-2 / FR-2-AC-1..4 | `receiveWithAuthorization` 限收款方调用，使用独立的 typehash，并继承结算安全性。 | `test_receive_happy_byPayee`、`test_receive_callerNotPayee_reverts`、`test_crossTypeReplay_reverts`，以及不变量 `receiveByPayee` 动作 | 通过 |
| FR-3 / FR-3-AC-1..4 | 签名取消和自调用取消可消耗未使用的 nonce，触发取消事件，且后续结算将回滚。 | `test_cancelFormA_signed`、`test_cancelFormB_selfThenSettleReverts`、`test_cancelFormA_invalidSignature_revertsAndNonceUnused`、`test_cancelAlreadyUsedNonce_reverts`，以及不变量 `cancel` 动作 | 通过 |
| FR-4 | `transferAuthorizationState` 对未使用的 nonce 返回 false，对已使用或已取消的 nonce 返回 true；域名获取器与类型化数据哈希匹配。 | `test_transferAuthorizationState_unusedFalse`，以及正常路径/取消测试，`test_domainSeparatorGetterMatchesDigest` | 通过 |
| FR-5 | `supportsInterface(0x86c5a9e1)` 返回 true，且现有 ERC-165/ERC-1271 接口 id 得以保留。 | `test_supportsInterface` | 通过 |
| NFR-2 / R-1 | 原生资产和代币结算重入攻击不能双花或消耗嵌套 nonce。 | `test_nativeReentrancyCannotConsumeNestedNonce`，以及不变量重放动作 | 通过 |
| NFR-3 / DR-003 | 非管理员密钥不能通过 TWA 自指向；管理员/自调用语义与 execute 一致。 | `test_nonAdminNativeSelfTarget_revertsAndNonceUnused`、`test_nonAdminTokenSelfTarget_revertsAndNonceUnused`、`test_adminNativeSelfTarget_succeedsNetZero`、`test_externalTokenToWalletRecipient_succeedsForNonAdmin` | 通过 |
| NFR-4 / DR-001 | 已使用与已取消状态通过事件区分；布尔状态仅为终态。 | 已使用/已取消事件断言及后端交接规则审查 | 通过 |

### 函数与测试映射矩阵

| 函数 | 正常路径 | 边界条件 | 回滚/错误 | 事件 | 状态变更 | 状态 |
|------|----------|----------|-----------|------|----------|------|
| `executeTransferWithAuthorization` | ERC-20、原生资产、无返回值代币、passkey、模糊金额/收款方/时间窗口 | 零值、全额资金余额、开区间边界相等性、32 字节 passkey 前缀 | 重放、错误签名者、未注册密钥、包装摘要、短信封、遗留 38 字节 passkey 信封、无效收款方、余额不足、false 返回代币、不可支付 `msg.value`、重入、hook 回滚、自指向保护 | `TransferAuthorizationUsed` | nonce false -> true；精确资产移动；回滚时复原 | 通过 |
| `receiveWithAuthorization` | 收款方调用 ERC-20 结算 | receive typehash | 调用方非收款方、execute 签名载荷、共享结算失败 | `TransferAuthorizationUsed` | 与 execute 相同 | 通过 |
| `cancelTransferAuthorization` | 签名形式 A 和自调用空签名形式 B | 已终态 nonce | 错误签名、非自调用空签名 | `TransferAuthorizationCanceled` | nonce false -> true；无资产移动 | 通过 |
| `transferAuthorizationState` | 使用前为 false，使用/取消后为 true | 任意未使用 nonce | 不适用 | 不适用 | 仅视图 | 通过 |
| `TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR` | 与 `hashTypedData` 组合匹配 | 不适用 | 不适用 | 不适用 | 仅视图 | 通过 |
| `supportsInterface` | TWA id 及现有 id | 未知 id | 不适用 | 不适用 | 仅视图 | 通过 |
| 公共常量 | 精确 typehash、`INTERFACE_ID`、`NATIVE_ASSET`、`SIGNATURE_ENVELOPE_MIN_LENGTH` | 不适用 | 不适用 | 不适用 | 仅视图 | 通过 |

### 安全不变量与测试映射矩阵

| 不变量 | 测试类型 | 处理器 / 测试名称 | 状态 |
|--------|----------|-------------------|------|
| INV-NONCE-ONCE | 不变量 + 单元 | `TransferWithAuthorizationHandler`；`invariant_nonceSettlesAtMostOncePerTrackedNonce` | 通过 |
| INV-NONCE-ISOLATION | 不变量 | `invariant_twaDoesNotAdvanceNativeNonceSpace`；普通 execute nonce 不受 TWA 影响 | 通过 |
| INV-RECIPIENT-BOUND | 模糊/单元 | 篡改 `to` 和 `value` 会使签名失效 | 通过 |
| INV-CEI | 单元/不变量 | hook/代币/原生资产回滚使 nonce 保持未使用；嵌套重入结算被阻止 | 通过 |
| INV-HOOK-ISOMORPHISM | 单元 | recording hook 捕获精确的 `Call` target/value/data/executor；自调用保护矩阵 | 通过 |
| INV-TIME-WINDOW | 单元 | 相等边界回滚，有效开区间动作通过 | 通过 |
| INV-TYPESEP | 单元 | execute/receive/cancel 跨类型签名失败 | 通过 |
| INV-NO-NATIVE-BURN | 单元 | 零地址和原生资产哨兵收款方在结算前回滚 | 通过 |
| INV-VALUE-CONSERVATION | 单元/模糊/不变量 | 精确 MockERC20/原生资产余额差值及不变量代币记账 | 通过 |

### 权限 / 回滚矩阵

| 函数 | 已授权调用方 | 未授权调用方 | 预期错误 / 回滚 | 测试 |
|------|------------|------------|-----------------|------|
| `executeTransferWithAuthorization` | 持有有效所有者签名的任意中继者 | 错误签名者/密钥或已篡改签名字段 | `InvalidSignature` | 错误签名者、未注册密钥、包装摘要、变异模糊 |
| `executeTransferWithAuthorization` passkey 路径 | 持有有效 passkey 信封的任意中继者 | 遗留 execute 风格 38 字节前缀 | 回滚且 nonce/资金不变 | `test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused` |
| `receiveWithAuthorization` | `msg.sender == to` 且持有有效签名 | 任意 `msg.sender != to` 的调用方 | `CallerNotPayee(caller,to)` | `test_receive_callerNotPayee_reverts` |
| `cancelTransferAuthorization` 形式 A | 持有已注册密钥取消签名的任意中继者 | 持有错误签名的中继者 | `InvalidSignature` | `test_cancelFormA_invalidSignature_revertsAndNonceUnused` |
| `cancelTransferAuthorization` 形式 B | `msg.sender == address(account)` 且持有空签名 | 持有空签名的非自调用调用方 | `NotFromSelf` | `test_cancelFormB_nonSelf_reverts` |
| TWA 自指向结算 | 针对 `target == account` 的管理员密钥或内置自调用密钥 | 非管理员密钥自指向原生 `to` 或 ERC-20 `token` | `NonAdminSelfCall` | 自指向矩阵测试 |

### 状态机矩阵

| 状态 | 有效转换 | 无效转换 | 测试 |
|------|----------|----------|------|
| 未使用 | -> 通过成功的 execute/receive 转为已使用 | 不适用 | 正常路径和不变量处理器 |
| 未使用 | -> 通过签名/自调用取消转为已取消 | 不适用 | 取消测试和不变量处理器 |
| 已使用 | 无进一步转换 | execute/receive/cancel 相同 nonce | 重放和取消后使用测试 |
| 已取消 | 无进一步转换 | execute/receive/cancel 相同 nonce | 取消后结算和不变量终态计数检查 |

### 资金流向矩阵

| 流向 | 资产 | 预期记账 | 负面测试用例 | 测试 |
|------|------|----------|------------|------|
| Execute ERC-20 | Mock ERC-20 | 账户减少 `value`，收款方增加 `value`，nonce 已消耗 | false 返回代币、余额不足、篡改 value | 正常路径、模糊、回滚测试 |
| Execute 原生资产 | 通过 `NATIVE_ASSET` 的 ETH | 账户减少 `value`，收款方增加 `value`，nonce 已消耗 | 余额不足、收款方重入 | 原生资产正常路径和重入测试 |
| Execute passkey ERC-20 | Mock ERC-20 | 与 ECDSA 相同，使用内置 passkey 验证器 | 遗留 38 字节前缀失败 | passkey 信封测试 |
| Receive ERC-20 | Mock ERC-20 | 与 execute 相同，仅限收款方调用 | 非收款方调用、execute 类型签名 | receive 测试 |
| 取消 | 无资产 | 无余额移动；nonce 终态；取消事件 | 无效签名者或已终态 nonce | 取消测试 |
| Hook 路径 | ERC-20/原生资产调用形态 | hook 接收一次调用，可阻止/允许；回滚将复原 nonce 和转账 | 阻止型 hook、自指向非管理员 | hook 测试 |

### 模糊域矩阵

| 目标 | 输入 | 有效域 | `vm.assume` 规则 | 边界值 |
|------|------|--------|-----------------|--------|
| ERC-20 execute 成功 | `to`、`value`、`nonce`、中继者 | 非零/非哨兵收款方；value 限制在账户余额内；新鲜 nonce | 过滤此正面用例中的无效收款方和账户自指向 | `0`、dust、全额资金余额 |
| 签名绑定：value | 签名金额、篡改金额、nonce seed | 两个金额均受限制；变异必须改变已签名字段 | 假设 `mutatedValue != value` | 通过模糊测试的邻近值 |
| 签名绑定：收款方 | 签名收款方、篡改收款方、nonce seed | 两个收款方均非零、非原生哨兵且不同 | 假设收款方已改变 | 任意参与者地址 |
| 不变量处理器动作 | nonce seed、金额 seed、收款方 seed、中继者 seed | 跟踪 8 个 nonce；有效开区间时间窗口；金额限制 <= 当前钱包余额 | 使用 `bound`；不丢弃有效失败 | 对相同 nonce 的重放、混合结算/取消顺序 |

### 不变量处理器与参与者模型

- 处理器：`TransferWithAuthorizationHandler`，位于 `test/TransferWithAuthorizationInvariant.t.sol`。
- 参与者：两名中继者、三名收款方、已初始化的 Alice 智能钱包及已注册的 Alice ECDSA 密钥。
- 动作：`execute`、`receiveByPayee`、`cancel`、`replayExecute`。
- 跟踪状态：8 个 nonce 值、每个 nonce 的结算/取消成功计数、钱包代币余额、收款方代币余额总和、总代币流出量、原生账户 nonce。
- 目标约束：`targetContract(address(handler))` 和显式 `targetSelector` 将模糊调用限制在处理器动作上。

### Mock / Fixture 矩阵

| Mock / Fixture | 真实依赖 | 建模的行为 | 省略的行为 | 安全性说明 |
|----------------|---------|-----------|-----------|-----------|
| `MockERC20` | 标准 ERC-20 | 余额、铸币、正常 `transfer` 返回值 | 手续费/rebase 语义 | 足以满足精确值结算和账户余额差值验证 |
| `FalseReturnERC20` | 非标准代币 | 从 `transfer` 返回 `false` 且不更新余额 | 元数据和授权额度 | 直接针对 SafeERC20 false 返回失败行为 |
| `NoReturnERC20` | USDT 风格代币 | 有状态变更的 `transfer` 但无返回数据 | 授权/额度不需要 | 证明 SafeERC20 接受成功的无返回值转账 |
| `RecordingHook` | 密钥选择的消费 hook | `preCheck`/`postCheck`、精确调用数组、执行者、返回数据哈希 | 生产策略存储/速率限制 | 验证 TWA 以忠实的 execute 等效调用形态调用 hook |
| `RevertingHook` | 阻止型消费 hook | `preCheck` 回滚 | 策略内部机制 | 证明 hook 失败会回滚 nonce 和转账 |
| `ReentrantNativeReceiver` | 恶意原生资产收款方 | 嵌套 TWA 调用尝试及结果记录 | 重入之外的任意回调 griefing | 直接针对 TWA 原生资产转账重入风险 |
| `Base` + `HelperLib` 中的 passkey fixture | 内置 P-256 passkey 验证器 | keyHash 推导、WebAuthn challenge/signature 编码、不含 `validUntil` 的验证器 ownerSignature | 外部 passkey 验证器特定信封 | 证明已批准的内置 passkey TWA 信封，并捕获遗留 38 字节 execute 前缀错误 |
| 不变量处理器 | 对账户 TWA API 的对抗性中继者/收款方 | 有效签名、重复结算/取消/重放序列、代币记账 | passkey/外部验证器有状态活动 | 不变量活动针对 TWA 状态/资金流向属性，而单元测试覆盖 passkey 编码 |

### 既有代码变更覆盖

- 既有有效测试已保留。Stage 5 在 `test/TransferWithAuthorization.t.sol` 和 `test/TransferWithAuthorizationInvariant.t.sol` 中新增了专项 TWA 覆盖。
- 返工第 2 次尝试新增了两个 passkey 专项 TWA 断言：正确的 32 字节 passkey 信封成功；遗留 38 字节 execute 风格前缀被拒绝且 nonce 保持未使用。
- 遗留的 execute、UserOp、授权额度、所有者管理、工厂和恢复行为未被重新模板化。`test/Recovery.t.sol` 因其私有依赖不可用且超出 TWA 变更范围而被排除。
- `test/Base.t.sol` 仅保持测试辅助变更（`vm.envOr("DEPLOY_FACTORY_SALT", bytes32(0))`），不属于生产源码。
- 受影响的 TWA 生产合约覆盖率达到 100% 行覆盖和 100% 分支覆盖。整体生产源码覆盖率因新 TWA 合约之外的遗留文件级缺口而低于 100%。

## 结果

| 测试领域 | 预期 | 实际 | 结果 |
|----------|------|------|------|
| 单元/非不变量套件 | 排除无关私有恢复依赖的限定范围套件通过 | 407 个测试通过，0 个失败 | 通过 |
| 专项模糊套件 | 模糊域通过 | 14 个模糊测试通过，包含 3 个 TWA 模糊测试 | 通过 |
| 专项不变量套件 | 处理器活动保持 nonce/记账不变量 | 3 个 TWA 不变量通过，每个 16 轮 / 256 次调用 | 通过 |
| Passkey TWA 回归 | 内置 passkey 32 字节信封成功；遗留 38 字节前缀被拒绝 | 2 个测试通过 | 通过 |
| 覆盖率运行 | 生成受影响代码的覆盖率证据 | `forge coverage --skip 'test/Recovery.t.sol' --report summary` 通过；410 个测试通过 | 通过 |
| 专项 TWA 覆盖率门控 | 受影响新生产合约 100% 行/分支覆盖 | `src/TransferWithAuthorization.sol`：100% 行 / 100% 分支 | 通过 |
| 整体生产覆盖率门控 | 既有代码基准可将门控范围限定为受影响文件/函数 | 98.8839% 行 / 98.8506% 分支；缺口均为 TWA 合约之外的遗留生产文件 | 接受既有代码限制 |
| 无源码变更门控 | Stage 5 在 `src/`、`script/` 下或 `foundry.toml` 相对 Stage 4 快照无差异 | 状态 `ok`；禁止的生产变更仅继承自 A-04 | 通过 |

## 覆盖率

- 覆盖率命令：`forge coverage --skip 'test/Recovery.t.sol' --report summary`；通过并生成 `.oli-work/forge-coverage-scoped-summary.txt`。
- 受影响新合约覆盖率：`src/TransferWithAuthorization.sol` 行覆盖率 100.00%（70/70），语句覆盖率 100.00%（82/82），分支覆盖率 100.00%（21/21），函数覆盖率 100.00%（11/11）。
- 专项受影响合约门控：通过，100.00% 行覆盖和 100.00% 分支覆盖，`.oli-work/coverage-gate-transfer-with-authorization.json`。
- 排除 `script/`、`test/` 和 `lib/` 后的整体生产源码门控：98.8839% 行覆盖和 98.8506% 分支覆盖，`.oli-work/coverage-gate-production.json`。
- 豁免：仅接受既有代码变更范围限定。`AllowanceManager`、`OwnerManager` 和 `SmartWallet` 中的遗留覆盖率缺口早于新 `TransferWithAuthorization` 生产合约且处于其范围之外；受修改的 TWA 相关行为（`supportsInterface`、hook/自调用路径、通过 TWA 的验证器/域名路由）均已直接测试。
- 豁免安全说明：Stage 5 覆盖率门控依据既有代码测试规则专注于新增/受影响的 TWA 表面；任何 TWA 生产代码行或分支均未被豁免。

## 模糊活动

| 目标 | 输入域 | 假设条件 | 运行次数 | 结果 |
|------|--------|----------|----------|------|
| `testFuzz_executeErc20MovesExactValue` | 收款方地址、`uint96` 金额、nonce seed、中继者地址 | 收款方非零、非原生哨兵、非账户地址；value 限制在钱包代币余额内 | 256 | 通过 |
| `testFuzz_mutatedValueInvalidatesSignature` | 签名金额和篡改金额、nonce seed | 篡改 value 与签名 value 不同 | 256 | 通过 |
| `testFuzz_mutatedRecipientInvalidatesSignature` | 签名收款方和篡改收款方、nonce seed | 收款方非零、非原生哨兵且不同 | 256 | 通过 |
| 既有非 TWA 模糊测试 | 解码和授权额度域 | 既有测试假设条件 | 每个 256 次 | 通过 |

## 不变量活动

| 不变量 | 处理器 | 参与者 | 运行次数 / 深度 | 结果 |
|--------|--------|--------|----------------|------|
| `invariant_nonceSettlesAtMostOncePerTrackedNonce` | `TransferWithAuthorizationHandler` | 两名中继者、三名收款方、Alice 钱包/密钥 | 专项命令 16 轮 / 16 深度；覆盖率期间 256 轮 / 500 深度 | 通过 |
| `invariant_tokenAccountingConservedAcrossSuccessfulSettles` | `TransferWithAuthorizationHandler` | 同上 | 专项命令 16 轮 / 16 深度；覆盖率期间 256 轮 / 500 深度 | 通过 |
| `invariant_twaDoesNotAdvanceNativeNonceSpace` | `TransferWithAuthorizationHandler` | 同上 | 专项命令 16 轮 / 16 深度；覆盖率期间 256 轮 / 500 深度 | 通过 |

## Mock / Fixture 合理性说明

| Mock / Fixture | 真实依赖 | 建模的行为 | 省略的行为 | 安全性说明 | 覆盖的失败模式 |
|----------------|---------|-----------|-----------|-----------|--------------|
| `MockERC20` | ERC-20 代币 | 余额记账、铸币、返回 true 的 `transfer` | 转账手续费/rebase 行为 | 精确转账守恒是被测行为 | 通过标准转账回滚实现余额不足 |
| `FalseReturnERC20` | 非标准 ERC-20 | 无状态变更的 false 返回 | 元数据/授权额度 | 在不削弱被测系统的情况下验证 SafeERC20 false 返回处理 | 代币失败时回滚且 nonce 未使用 |
| `NoReturnERC20` | 无返回值 ERC-20 | 有状态变更的转账但无返回数据 | 授权/额度 | 模拟 USDT 风格成功路径 | 成功的无返回值代币结算 |
| `RecordingHook` | 账户 hook | 精确调用形态、执行者、pre/post 计数、返回数据 | hook 策略限制 | 验证 hook 同构性而非绕过它 | hook 调用形态不匹配将导致断言失败 |
| `RevertingHook` | 账户 hook | preCheck 回滚 | 策略特定存储 | 证明 hook 回滚会回滚结算 | hook 驱动的回滚及 nonce 复原 |
| `ReentrantNativeReceiver` | 恶意原生资产收款方 | 接收期间的嵌套结算尝试 | 无关的 gas griefing | 直接针对 TWA 原生资产转账重入风险 | 嵌套调用被阻止，嵌套 nonce 未使用 |
| passkey fixture | 内置 passkey 验证器和 WebAuthn 辅助工具 | 真实 P-256 签名、WebAuthn auth 对象、passkey keyHash、TWA ownerSignature 布局 | 生产 UI/浏览器流程 | 辅助工具镜像既有项目 passkey 测试，仅变更 TWA 特定的无 `validUntil` 部分 | 错误的 38 字节 execute 风格前缀被拒绝 |
| `TransferWithAuthorizationHandler` | 对账户 TWA API 的对抗性调用者 | 生成有效签名、重复结算/取消/重放尝试、代币记账 | passkey 有状态处理器路径 | 单元测试覆盖 passkey 密码学；不变量处理器覆盖状态机/资金流向属性 | 双重结算、终态、记账、原生 nonce 隔离 |

## 上下文覆盖

| 上下文来源 | 约束 / 信号 | 测试覆盖 | 状态 | 备注 |
|-----------|-----------|---------|------|------|
| 有效 Stage 5 `.oli-work/context` | 当前工作区中不存在业务或技术上下文文件 | 不适用 | 未提供 | 依据上下文加载策略记录 |
| 包含 Circle EIP-3009 上下文的已批准文档 | 开区间、收款方限定 receive、取消/状态终态性 | 时间边界测试、receive 调用方测试、取消终态测试、nonce 不变量 | 已覆盖 | PRD/设计通过将语义迁移至账户级钱包来覆盖代币级差异 |
| 已批准文档中的 PRD 关联 TWA EIP 补充说明 | 接口/typehash/nonce/ERC-165 常量 | 常量/接口/域名测试 | 已覆盖 | PRD 对 32 字节 keyHash 信封和直接摘要具有决定权 |
| 既有 SmartWallet 测试 | 本地 Base 辅助工具、ECDSA/passkey keyHash、hook/自调用模式 | Stage 5 复用 `Base`、既有验证器和 hook fixture；仅新增 TWA 专项 fixture | 已覆盖 | 保留既有代码风格，避免重新模板化 |
| Stage 1 基准 | 私有恢复依赖不可用 | 所有 Forge 命令均以接受的 skip 为范围 | 接受限制 | 恢复功能超出 TWA 变更范围 |

## 失败分析

| 失败用例 | 命令 | 预期 | 实际 | 根因层级 | 目标 Stage |
|---------|------|------|------|----------|-----------|
| 无 | 不适用 | 不适用 | 在接受的恢复 skip 下，单元测试、模糊测试、不变量测试、专项覆盖率及无源码变更门控均通过 | 不适用 | 不适用 |

## 返工测试解决情况

| 事项 | 新增/更新的测试 | 结果 |
|------|--------------|------|
| 第 1 次尝试仅产出骨架输出 | 重建了实质性 Stage 5 交付物：TWA 单元测试、不变量测试、覆盖率日志、报告、输出摘要 | 通过 |
| 全面单元测试 | `test/TransferWithAuthorization.t.sol` 现已覆盖公共常量、getter、ERC-20/原生资产/无返回值路径、receive、cancel、签名、hook、自指向保护、重入及 passkey 信封编码 | 通过 |
| 模糊测试 | 新增/运行了 TWA 模糊测试，覆盖精确 ERC-20 记账及收款方/value 签名绑定 | 通过 |
| 不变量测试 | 新增/运行了 `test/TransferWithAuthorizationInvariant.t.sol` 处理器，覆盖 nonce 终态性、代币记账和原生 nonce 隔离 | 通过 |
| Passkey keyHash / ownerSignature 编码优先级 | 新增 `test_passkeyEnvelope32BytePrefix_settlesErc20` 和 `test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused` | 通过 |
| 恢复依赖限制 | 依据用户指示作为非阻塞项处理；所有 Forge 命令均使用 `--skip 'test/Recovery.t.sol'` 并报告了范围 | 通过 |

未发出 Stage 4 返工请求。
