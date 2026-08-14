# SECURITY_SPEC.md — 安全规范 (TWA)

> 本文档是 `DESIGN.md` 的安全覆盖层。作为具有约束力的实现合约：以下每条不变量、访问控制规则、资金流规则和状态机安全规则均**必须**被实现（或标注 N/A 并说明理由）。引用 `DESIGN.md` 中的规范 ID（`FN-*`、`INV-*`）和章节；不重新推导完整行为。依据：`.oli-work/stage02-analysis/security.md`。

严重等级采用流程规范模式（`oli-contract-common`）：CRITICAL / HIGH / MEDIUM / LOW / INFO。

## 1. 威胁模型

- **攻击者能力**：
  - 内存池抢跑者：可提取已签名的授权并在预定促进者之前提交。结果中性——`to`/`value` 受签名约束（INV-RECIPIENT-BOUND）；攻击者仅承担 gas 费用。对于需要原子收款的合约收款方，`receiveWithAuthorization`（`msg.sender==to`）是防御手段（R-2）。
  - 恶意中继者：任意提交者；无法更改收款方/金额/nonce；无法复用已结算的 nonce。
  - 恶意/非标准 ERC-20（例如 USDT 无返回值、通缩型 transfer、可重入 `transfer`）：通过 SafeERC20 返回值检查（FN-103）和重入锁处理。
  - 可重入原生收款方：`to.call{value}` 转发 gas 且可重入。受 CEI（FN-102 第 5 步）和瞬态锁（FN-106）约束。
  - 受限会话/代理密钥：可能尝试使用 TWA 绕过其自身的每密钥钩子限制（R-7）。从结构上阻断——授权签名的 keyHash 与选择钩子的 keyHash 相同（INV-HOOK-ISOMORPHISM）。
  - 跨链/跨账户/跨类型重放者：被 EIP-712 域（chainId + verifyingContract）和不同的 typehash（INV-TYPESEP）阻断。
- **特权角色假设**：所有者为已注册的 `keyHash`（具有不同的 admin/expiration/hook 配置）。验证器受信任，故障关闭（`_validateSignature` 中使用 try/catch）。EntryPoint 不在 TWA 路径上。`address(this)` 自调用是取消形式 B 和 UUPS 升级的唯一权限来源。
- **用户错误/恶意用户**：签名时窗口过宽，或收款方错误/为零地址——通过 `InvalidRecipient` 守卫（SD-1）和钱包 UI 的类型化数据展示（EIP "钓鱼风险"）缓解。
- **外部依赖故障**：存在 bug 或恶意的每密钥钩子（由所有者配置，半可信）只能阻止该密钥自身的支出（对该密钥的 griefing），永远无法超越账户权限。失败的验证器返回 false（故障关闭）。
- **链特定风险面**：要求 Cancun 支持 EIP-1153 瞬态存储（DEP-6，RR-1）；原生资产重入（ERC-7528 注意事项）。

## 2. 安全不变量

| ID | 陈述 | 相关状态 | 相关函数 | 重要性 | Stage 5.0 测试 |
|----|------|----------|----------|--------|----------------|
| INV-NONCE-ONCE | 每个 `authorizationNonce` 最多被消费一次；Used 和 Canceled 为终态且互斥（PRD inv 1）。 | `authorizationStates` | FN-102, FN-003 | 防止双花/重放 | 不变量：同一 nonce 不能被结算两次 |
| INV-NONCE-ISOLATION | TWA nonce 空间与原生/4337 nonce 完全隔离（PRD inv 2）。 | TWA ERC-7201 命名空间 vs `NonceManager._nonces` | FN-105 | 正常账户操作不能使支付失效，反之亦然 | 存储布局 + 不变量（无路径同时写入两者） |
| INV-RECIPIENT-BOUND | `to` 和 `value` 在签名中受密码学约束；任何提交者均无法改变结算结果（PRD inv 3）。 | 已签名摘要 | FN-101, FN-104 | 防篡改/防抢跑 | 模糊测试：修改 to/value ⇒ 验证失败 |
| INV-CEI | nonce 标志在转账前被设置；任何结算回滚都会将其还原（PRD inv 4）。 | `authorizationStates` | FN-102（第 5 步在第 6 步之前），FN-106 | 防止重入重放 | 重入 + 不变量 |
| INV-HOOK-ISOMORPHISM | 成功的 TWA 结算以字节相同的 `Call` 调用 keyHash 选定的钩子，**并应用与 `_batchCall` 相同的自调用规则**——`Call.target == address(this)` 会触发 `NonAdminSelfCall` 回滚，除非经过验证的签名 keyHash 为 admin 或内置的 `address(this)` 密钥——与具有相同参数的 `execute` 调用完全一致（PRD inv 5，G-5，R-7；DR-003）。仅有两处已声明的故意差异：(i) 在 TWA 下钩子的 `executor` 为中继者，而在 `execute` 下为密钥 EOA；(ii) ERC-20 路径通过 SafeERC20 而非原始 `_call`——均不影响钩子计数或自调用决策。 | `_ownerSettings[keyHash].hook`，`_ownerSettings[keyHash]`（isAdmin） | FN-103（第 3-6 步） | 受限密钥不能通过 TWA 绕过其钩子，也不能访问 `execute` 会阻止的特权自调用路径 | 钩子测试：TWA 与 `execute` 的一致性；绕过尝试回滚；自目标一致性 {admin,non-admin}×{native,token==self} + 控制测试（DESIGN §16） |
| INV-TIME-WINDOW | 结算仅在开区间 `(validAfter, validBefore)` 内有效。 | — | FN-102 第 2 步 | 有效期有界 | 边界测试（`==` 边界回滚） |
| INV-TYPESEP | Execute / Receive / Cancel 授权不可互换（不同的 typehash）。 | typehash 常量 | FN-001/002/003, FN-104 | 无跨类型重放 | 负向：跨类型提交失败 |
| INV-NO-NATIVE-BURN (SD-1) | `to == address(0)` 被拒绝，防止通过 `to.call{value}` 向零地址静默销毁原生 ETH。 | — | FN-001, FN-002 | 冻结接口中原本未使用的 `InvalidRecipient` 是防销毁守卫 | 单元测试：零地址收款方触发 `InvalidRecipient` 回滚 |
| INV-VALUE-CONSERVATION | 成功结算时将精确的 `value` 转移至 `to`；任何失败都会回滚整个交易，余额保持不变。 | 账户余额 | FN-103 第 5 步，FN-102 | 无部分/超额结算，无卡账资金 | 单元测试 + 不变量 |

## 3. 访问控制矩阵

| 函数 | 所需角色/签名者 | 允许调用者 | 必须回滚的情形 | 备注 |
|------|----------------|------------|----------------|------|
| FN-001 `executeTransferWithAuthorization` | 无（无需许可）+ 有效所有者密钥签名 | 持有有效已签名授权的任意调用者 | 无效/过期/已用 nonce；窗口外；无效签名；`to==0`；**非 admin 密钥自目标（`NonAdminSelfCall`：原生 `to==self` 或 ERC-20 `token==self`；FN-103 第 3 步，DR-003）**；钩子策略违规；转账失败；重入 | NFR-3 "execute 必须无需许可"；自调用守卫与 `_batchCall` 一致 |
| FN-002 `receiveWithAuthorization` | `msg.sender == to` + 有效签名（RECEIVE typehash） | 仅收款方 | `msg.sender != to`（`CallerNotPayee`）；+ 所有 FN-001 条件；跨类型签名 | R-2 防抢跑 |
| FN-003 `cancelTransferAuthorization`（形式 A） | 任意已注册账户密钥签名（CANCEL typehash） | 中继者提交 | nonce 已用/已取消；无效签名 | 账户范围 nonce（A-6）；griefing 残余（§8） |
| FN-003 `cancelTransferAuthorization`（形式 B） | `msg.sender == address(this)` | 账户自调用（在 execute/UserOp 内） | 签名为空且 `msg.sender != address(this)`（`NotFromSelf`） | 复用 `onlySelf` |
| FN-004 / FN-005（getter） | 无（视图） | 任意人 | — | 无状态变更 |
| FN-006 `supportsInterface` | 无（视图） | 任意人 | — | — |
| `_authorizeUpgrade`（已有） | `onlySelf` | 仅账户自身 | 非自身升级 | 不变；无新角色（PRD §7） |

## 4. 资金流安全规则

- **流入**：TWA 不新增流入。
- **流出授权**：每笔流出需要所有者对绑定的 `{token,to,value,window,nonce}` 的有效签名、未使用的 nonce、处于开放时间窗口内，以及（若已配置）通过每密钥钩子（FN-101→FN-102→FN-103）。
- **转账前记账**：在转账前设置 nonce 标志（CEI，FN-102 第 5 步）。
- **手续费/退款**：无（精确 `value`，无协议费）。
- **防卡账**：TWA 不持有资金；失败的转账会回滚整个交易（INV-VALUE-CONSERVATION）。
- **代币/原生资产假设**：ERC-20 通过 `SafeERC20.safeTransfer`（返回值已检查，兼容 USDT；PRD §12）；原生资产通过带检查的 `to.call{value}`。`token == NATIVE_ASSET` 选择原生路径。通缩型/变基型代币以名义 `value` 结算（账户层面，除 nonce 标志外无内部记账假设）。

## 5. 状态机安全规则

- 有效转换：Unused→Used（FN-001/002），Unused→Canceled（FN-003）。参见 `DESIGN.md §10`。
- 拒绝的转换：Used/Canceled→任意状态 ⇒ `AuthorizationAlreadyUsed`。
- 终态保护：每个 nonce 使用单个 `bool`；一旦为 `true` 永不清除（无函数将其设回 false）。
- 幂等性/重放：CEI + 瞬态锁；已回滚的结算将 nonce 保持为 Unused（FR-1-AC-6）。
- **Used 与 Canceled 在链上无法区分（DR-001）：**两者设置相同的 `bool`；`transferAuthorizationState(nonce)` 和 `AuthorizationAlreadyUsed` 回滚**不**揭示达到了哪种终态。区别**仅**体现在不同的事件 `TransferAuthorizationUsed` 与 `TransferAuthorizationCanceled` 中（NFR-4）。这是一条业务控制/链下记账安全规则：后端结算对账**必须**通过事件加以区分，**不得**将已取消的 nonce 视为已支付（`INTERFACE_SPEC.md` §6.1 中的约束性集成合约）。链上资金安全不受影响——`cancel` 不转移资金且 `INV-NONCE-ONCE` 成立——但链下将已取消状态误读为已结算将使 `cancel` 作为撤销控制的功能失效。

## 6. 外部调用/依赖风险

- **ERC-20 `transfer`**：外部调用；SafeERC20 处理非标准返回值；可重入代币受锁约束。
- **原生 `to.call{value}`**：重入风险面；CEI + 瞬态锁；gas 转发给收款方。
- **每密钥钩子 `preCheck`/`postCheck`**：由所有者配置，半可信；回滚将撤销结算；无法提升权限。`preCheck` 在现有 `IHook` 中为 `payable`——TWA 不向其转发 value（与 `_batchCall` 一致）。**Executor 注意事项：**在 TWA 下，`executor` 参数为中继者（`msg.sender`），而非签名密钥；受约束的密钥通过基于 keyHash 的钩子选择来标识，而非通过 `executor`。一个以 `executor` 为依据对限额计数的钩子将与 `execute`（executor = 密钥的 EOA）产生偏差——见 §9 第 12 条。
- **验证器合约**：`_validateSignature` 中的外部 `validateSignature` 被 try/catch 包裹（故障关闭）。
- **依赖失败**：验证器缺失/无效 ⇒ `getVerifiedValidator` 返回 0 ⇒ `InvalidSignature`（正确拒绝）。

## 7. 链特定安全要求（EVM）

- **CEI**：强制排序——检查、标记 nonce 已用（效果）、转账（交互）（FN-102）。
- **SafeERC20**：ERC-20 路径必需（FN-103）；保留原始 `_call` 路径缺失的返回值检查（RR-2）。
- **重入**：FN-001/FN-002 上的瞬态（EIP-1153）锁（FN-106）；要求 `evm_version=cancun`（RR-1）。
- **签名域分离**：EIP-712 域包含 chainId + verifyingContract（账户）；直接 `hashTypedData(structHash)` 摘要，无 ERC-1271/MessageSignLib 包装（R-3）。
- **可升级性存储安全**：新的 ERC-7201 命名空间，支持追加，与 `0x653ff6dc…` 无碰撞；通过 `forge inspect storageLayout` 验证（R-4）。
- **精度/舍入**：不适用——TWA 转移精确的 `value`，无换算/定价。
- **低级调用处理**：原生发送检查成功状态并在失败时回滚；ERC-20 通过 SafeERC20。

## 8. 已知风险与缓解措施

| 风险（PRD） | 描述 | 严重等级 | 缓解措施 | 残余风险 | 必须测试/审计 |
|------------|------|----------|----------|----------|---------------|
| R-1 | 原生转账重入 | HIGH | CEI + 瞬态锁（FN-102/FN-106） | 低（锁正确性） | 重入 + 不变量（测试 + 审计） |
| R-2 | execute 抢跑收款方的原子流程 | MEDIUM | `to` 绑定 + `receiveWithAuthorization`（`msg.sender==to`）+ 不同 typehash | 低 | 跨类型 + 接收测试 |
| R-3 | 错误的签名包装（ERC-1271/MessageSignLib） | HIGH | 直接 `hashTypedData(structHash)`；FN-101；ERC-1271 包装摘要必须失败回归测试（FR-1-AC-8，§10 指标） | 低 | 负向回归（测试 + 审计） |
| R-4 | 升级存储碰撞 | MEDIUM | 独立的 ERC-7201 命名空间 + 存储布局检查 | 低 | 存储布局门控 |
| R-5 | 知识集中 | LOW | PRD + DESIGN + EIP 草案 + 完整测试覆盖 | 低 | 文档/审查 |
| R-6 | 与 executeWithRelayer / Allowance 重叠 | MEDIUM | 定位为附加标准层（随机独立 nonce、receive pull、同构策略） | 低 | 设计审查 |
| R-7 | 受限密钥通过 TWA 绕过其钩子 | HIGH | 相同 keyHash 路由验证器 + 选择钩子（INV-HOOK-ISOMORPHISM） | **可接受残余：无钩子配置的非 admin 密钥在 TWA 上不受约束支出——与当前 `execute` 相同；依赖"为密钥配置钩子"的操作不变量** | 钩子一致性 + 绕过测试（测试 + 审计） |
| R-9 | 内联 + 低 optimizer_runs 提高 gas / EIP-170 | HIGH | optimizer_runs 二分搜索；任何影响大小的变更后重新测量 NFR-1（<120k）+ 字节码（≤24,576） | 中（Stage 4.0 调优） | `--sizes` + gas 报告 |

### 安全衍生需求（零地址/哨兵全面扫描——与 PRD 原创条目不同）

已扫描 TWA delta 引入或使用的所有地址类型输入/插槽：

| ID | 地址输入/插槽 | 是否需要守卫？ | 决定 |
|----|--------------|----------------|------|
| SD-1 | `to`（FN-001/FN-002 参数） | **是** | 当 `to == address(0)` 时回滚 `InvalidRecipient(to)`——防止通过 `to.call{value}` 向零地址静默销毁原生 ETH（该调用返回 success）。遗漏的严重等级：CRITICAL（资金损失）。这补充了 PRD 对 `InvalidRecipient` 遗漏的触发规则。 |
| SD-2 | `to == NATIVE_ASSET` 哨兵 | 建议 | 同样拒绝 `to == NATIVE_ASSET`（0xEeee…EEeE）——无意义的收款方；回滚 `InvalidRecipient(to)`。 |
| SD-3 | `token`（FN-001/FN-002 参数） | 隐式 | `token == address(0)`（非哨兵）路由至 ERC-20 路径；`SafeERC20.safeTransfer` 向无代码地址会回滚——严格来说无需额外守卫，但 Stage 4.0 应确认回滚是干净的。 |
| SD-4 | `validator`（来自 `getVerifiedValidator(keyHash)`） | **是（已有）** | `validator == address(0)` ⇒ `InvalidSignature()`（FN-101 第 3 步）——已执行。 |
| SD-5 | 每密钥 `hook`（来自 `getHook(settings)`） | 否（设计如此） | `hook == address(0)` 表示"无钩子"⇒ 跳过——符合预期；无钩子残余在 R-7 下已记录。 |
| SD-6 | `from`（= `address(this)`） | 否 | 派生值，对已部署账户永远不为零。 |

**自调用守卫与收款方扫描的关系（DR-003）。** FN-103 自调用守卫（`Call.target == address(this)` ⇒ 对非 admin 密钥触发 `NonAdminSelfCall`）与 SD-1/SD-2 **正交**：SD-1（`to == address(0)`）和 SD-2（`to == NATIVE_ASSET`）在 FN-001/FN-002 中于结算**前**运行，约束 `to`；自调用守卫在 FN-103 **内部**运行（在收款方检查和签名验证之后），约束构建的 `Call.target`（原生路径为 `to`，ERC-20 路径为 `token`）。`address(this)` 与 `0`/哨兵是不同的值，因此不存在重叠、双重回滚或缺口。该守卫还关闭了 SD-1/SD-2 未覆盖的"原生自发送为空操作"的残余风险。CEI/重入不受影响——守卫回滚会像任何其他结算回滚一样撤销 CEI nonce 写入。

## 9. 供审查和审计的安全假设（Stage 3.0 / 7.0 / 8.0 必须验证）

1. `_verifyTwaSignature` 返回的 keyHash 与 `_settleWithHook` 中用于选择钩子的值**相同**（无任何路径使路由与钩子选择产生偏差）——这是针对 R-7/G-5 的结构性防绕过机制。
2. CEI 排序在所有路径上成立：nonce 标志在任何外部转账之前写入；任意位置的回滚都会将其还原（FR-1-AC-6）。
3. 提供给 `_validateSignature` 的摘要是**直接**的 `hashTypedData(structHash)`；在 TWA 路径的任何位置均无 ERC-1271/`MessageSignLib` 包装（R-3）；包装摘要回归测试失败。
4. 瞬态重入锁在整个结算过程中被正确设置/清除，且已配置 `evm_version=cancun`（RR-1）。
5. TWA ERC-7201 命名空间与 `0x653ff6dc…` 不碰撞，并在升级中支持追加（R-4）；`forge inspect storageLayout` 已确认。
6. ERC-20 结算使用 SafeERC20（返回值已检查），而非原始 `_call`（RR-2）；USDT 类代币可正确结算（G-2）。
7. 开区间窗口 `(validAfter, validBefore)` 以严格的 `<`/`>` 语义执行（边界 `==` 回滚）。
8. 不同的 typehash 使 execute/receive/cancel 授权不可互换（INV-TYPESEP）。
9. `SIGNATURE_ENVELOPE_MIN_LENGTH`（=32）和 `keyHash(32)‖ownerSignature` 信封与验证切片逻辑匹配；过短的信封触发 `InvalidSignature` 回滚（FR-1 边界 1）。
10. 无钩子密钥的残余风险（R-7）是已接受的、有文档记录的行为（与 `execute` 相同），而非静默缺口——配置上必须为受限密钥附加钩子。
11. 取消形式 A 的权限（账户范围 nonce 上的任意已注册密钥，A-6）是可接受的；其最坏情形是 griefing（取消待处理支付），永远不会造成资金损失；密钥管理可缓解此问题。
12. 每密钥 SpendingPolicyHook 从其自身配置/基于 keyHash 的选择推导受约束密钥，**而非**从 `executor` 参数推导（在 TWA 下 `executor` 为中继者，而非签名者）。Stage 7.0/8.0 必须验证钩子不以 `executor` 为依据计算支出限额；否则 TWA 与 `execute` 的记账将产生偏差，INV-HOOK-ISOMORPHISM 对该钩子将不成立（`DESIGN.md` FN-103 设计注释 2）。
13. **自调用守卫（DR-003）：** TWA 结算自调用守卫（`DESIGN.md` FN-103 第 3 步）从**经过验证的 keyHash** 的 `_ownerSettings`（`isAdmin` 或内置 `address(this)` 密钥）计算 `allowSelfCall`，**而非**从 `msg.sender`/`executor`（中继者）计算。Stage 7.0/8.0 必须验证：非 admin 密钥的自目标结算（原生 `to == address(this)`，或 ERC-20 `token == address(this)`）与 `execute` 完全一致地触发 `NonAdminSelfCall` 回滚；admin/self 密钥可以自目标；合法的自接收（`token` = 外部 ERC-20，`to` = 该账户）**不被**阻止（控制用例）。此守卫使 INV-HOOK-ISOMORPHISM 在自目标路径上成立；ERC-20 路径上的守卫是出于原因一致性（`transfer` 选择器回退路径本已回滚），不得移除。
14. **结算对账（DR-001）：** 后端对账通过事件（`TransferAuthorizationUsed` vs `TransferAuthorizationCanceled`）区分 Used 与 Canceled，**而非**通过 `transferAuthorizationState`/`AuthorizationAlreadyUsed`（§5；`INTERFACE_SPEC.md` §6.1）。Stage 7.0/8.0 必须验证后端接口/交接文档中未指示将裸 `AuthorizationAlreadyUsed`（或 `state==true`）视为"已结算"，以及 Stage 4.0 的 `docs/delivery/CONTRACT_INTERFACE.md` 中包含相同的事件对账规则。
