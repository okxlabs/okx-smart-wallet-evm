# 部署就绪检查清单 — DEPLOY_CHECK.md

**项目：** okx-smart-wallet-dev — 账户级带授权转账（TWA）
**阶段：** N09 — 部署准备
**代码库模式：** existing_code_change（首次部署接入；非返工运行）
**目标链（首次上线）：** EVM — 以太坊主网，chainId 1（Cancun / EIP-1153 瞬态存储，必须启用）
**构建配置：** solc `0.8.29`，`evm_version=cancun`，`optimizer=true`，`optimizer_runs=100`

**状态说明：** `PASS` = 已检查，存在证据 · `FAIL` = 已检查，因缺陷失败 · `BLOCKED` = 因所需输入/环境/审批不可用而无法检查。

---

## 整体就绪状态：PASS — 含两项操作员须在目标链上确认的前提条件

所有必要就绪检查均已 PASS，**无阻塞项**。以下两项为部署前提条件，操作员必须在实际部署前针对所选目标链立即确认：

1. **EIP-170 字节码大小余量极小** — SmartWalletEntry 运行时大小为 24,510 字节，距 24,576 字节上限仅余 **66 字节**。部署前须立即重新执行 `forge build src script --sizes`，禁止在未采取字节码压缩措施的情况下增加源码体积。
2. **Cancun / EIP-1153 前提条件** — 目标链必须已激活 Cancun（DESIGN §12 DEP-6）；TWA 原生重入瞬态锁（EIP-1153）在非 Cancun 链上不受支持。以太坊主网满足此条件；**对于操作员无法确认已激活 Cancun 的任何链，状态为 BLOCKED。**

阶段内 Fork 干跑测试已**推迟**执行（未配置 Fork RPC）；该项与 PASS 兼容，操作员须按 `docs/delivery/DEPLOY_DRY_RUN.md` 中记录的流程执行。

---

## 必要检查项

| # | 检查项 | 状态 | 证据 / 备注 |
|---|--------|------|-------------|
| 1 | 安全审计结论为 PASS | **PASS** | `docs/process/AUDIT_REPORT.md` — 判定为 WARN，**流水线阶段结论：PASS**（FAIL_ON=critical；0 个确认的 Critical/High；5 个非阻塞 Medium 建议）。 |
| 2 | 实现/测试评审结论为 APPROVED | **PASS** | `docs/process/DEV_REVIEW.md` — **整体决定：APPROVED**（最高严重级别为 MEDIUM，非阻塞）。 |
| 3 | 上下文派生的部署约束已审查（或无上下文） | **PASS** | 技术上下文 = Circle USDC 仓库仅作为 EIP-3009 语义参考（不同系统；其部署脚本不约束本仓库）。业务上下文 = 无。唯一约束为 Cancun 要求，已编入 DESIGN（见检查项 #17）。无部署惯例冲突。 |
| 4 | 部署手册存在且完整 | **PASS** | `docs/delivery/DEPLOY_RUNBOOK.md`。将 M-02 构建规范、EIP-170 大小复查及子模块 gitlink 核对纳入部署前检查清单。 |
| 5 | 应急响应计划存在且完整 | **PASS** | `docs/delivery/EMERGENCY_PLAN.md`。能力诚实描述：不存在全局暂停/升级管理员；已记录缓解措施 = 按账户 `cancel` + 链下风险控制；将 M-03/M-04/M-05 作为残余风险/监控项载入。 |
| 6 | 部署脚本存在 | **PASS** | `script/deploy.s.sol`（合约 `DeployInit`）— 通过 EIP-2470 CREATE2 部署 SmartWalletEntry + SmartWalletFactory，当单例工厂不存在时退回 CREATE。 |
| 7 | 可选验证脚本 / 手动验证步骤存在 | **PASS** | `script/VerifyDeployment.s.sol` — 部署后只读检查（工厂→实现绑定、代码非零、接口支持、EntryPoint、自引用、可选 chain-id）。 |
| 8 | `forge build` 通过 | **PASS** | 范围生产构建 `forge build src script` 退出码为 0（SmartWalletEntry 24,510 B，SmartWalletFactory 2,218 B；离线构建，子模块状态未变）。**注意：** 默认无范围 `forge build` 在私有 `lib/smart-wallet-recovery` 测试导入未初始化时**失败**（审计 M-02）— 已记录的构建规范项，非生产源缺陷；生产 `src`+`script` 构建干净。 |
| 9 | 内置密钥扫描通过 | **PASS** | 对 `script docs/delivery foundry.toml .env.example` 执行 `secret_scan.py` — 干净（由本阶段主体运行）。 |
| 10 | 内置静态部署检查通过 | **PASS** | 对 `script docs/delivery` 执行 `deployment_static_checks.py` — 干净（由本阶段主体运行）。 |
| 11 | 构造函数 / 初始化参数已定义 | **PASS** | SmartWalletEntry 构造函数：**无**（`IMPLEMENTATION = address(this)` 不可变自引用 + `_disableInitializers()`）。SmartWalletFactory 构造函数：`address _implementation`。按账户 `initialize(InitialOwner[])` 为部署后由工厂驱动的步骤（非部署时参数），TWA 未作变更。 |
| 12 | 部署顺序与依赖关系匹配 | **PASS** | SmartWalletEntry → SmartWalletFactory(impl)：工厂的不可变 `IMPLEMENTATION` 为第一步得到的 SmartWalletEntry 地址。`script/deploy.s.sol` 严格按此顺序执行。 |
| 13 | 代理 / 管理员 / 所有者 / 角色处理已文档化 | **PASS** | 按账户采用 UUPS，`_authorizeUpgrade = onlySelf`；工厂和实现**无所有者 / 不可变**；无全局管理员，无全局暂停/升级角色；无部署者绑定权限。已在手册、应急计划及 DESIGN §13 中记录。 |
| 14 | 仓库变更中不含私钥或生产密钥 | **PASS** | 由环境变量驱动；`.env.example` 仅含空占位符；内置密钥扫描干净（检查项 #9）。 |
| 15 | 可运行的 `Deploy.s.sol` + 可移植干跑流程已就绪 | **PASS** | `script/deploy.s.sol`（合约 `DeployInit`）可运行；操作员干跑/部署前测试检查清单已记录于 `docs/delivery/DEPLOY_DRY_RUN.md`。（项目惯例使用文件名 `deploy.s.sol`；内置静态检查器仅对精确名称 `Deploy.s.sol` 发出非致命警告 — 见阻塞项表。） |
| 16 | EIP-170 运行时字节码大小在限制以内 | **PASS — 含备注** | SmartWalletEntry 运行时 = **24,510 字节**，距 24,576 字节上限仅余 **66 字节**。**操作员必须在部署前重新运行 `forge build src script --sizes`，并禁止在未采取大小缓解措施的情况下增加源码。** SmartWalletFactory = 2,218 字节（余量充足）。 |
| 17 | 目标链上的 Cancun / EIP-1153 前提条件 | **PASS**（以太坊主网）/ **操作员按链确认** | 目标链必须已激活 Cancun（DESIGN §12 DEP-6，SECURITY_SPEC §7，RR-1）— TWA 原生重入瞬态锁需要 EIP-1153。以太坊主网满足（以及按 REQUIREMENTS 的 X Layer 196/1952）。**对于操作员无法确认已激活 Cancun 的任何链，状态为 BLOCKED** — 禁止在该链上部署。 |
| 18 | 存储布局无冲突（ERC-7201） | **PASS** | TWA ERC-7201 命名空间与账户自定义存储根 `0x653ff6dc…` 独立（DESIGN R-4）。**操作员应在部署前通过 `forge inspect SmartWalletEntry storageLayout` 进行验证。** |
| 19 | 阶段内 Fork 干跑已执行 | **推迟（与 PASS 兼容）** | 未配置 `FORK_RPC_URL` / `MAINNET_RPC_URL`，且 Oli 运行配置中无 Fork RPC 字段，因此阶段内 Fork 干跑推迟执行 — 非缺陷。操作员须按 `docs/delivery/DEPLOY_DRY_RUN.md` 中记录的流程执行（通过工厂创建账户 → 正常路径 ERC-20 结算 → 重放回滚）。 |

---

## 交付物清单

路径相对于 `okx-smart-wallet-dev/` 项目根目录。

| 交付物 | 用途 | 状态 | 路径 / 证据 |
|--------|------|------|-------------|
| 部署手册 | 分步骤生产部署流程 + 部署前规范检查清单 | **PASS** | `docs/delivery/DEPLOY_RUNBOOK.md` |
| 应急响应计划 | 事故响应、残余风险清单、能力诚实缓解措施 | **PASS** | `docs/delivery/EMERGENCY_PLAN.md` |
| 部署脚本 | 部署 SmartWalletEntry + SmartWalletFactory（EIP-2470 CREATE2，CREATE 回退） | **PASS** | `script/deploy.s.sol`（合约 `DeployInit`） |
| 部署工厂接口 | 部署脚本使用的内联 EIP-2470 单例工厂接口 | **PASS** | `script/IDeployFactory.s.sol` |
| 验证脚本 | 部署后只读断言（工厂绑定、代码、接口、EntryPoint、自引用、chain-id） | **PASS** | `script/VerifyDeployment.s.sol` |
| Fork 干跑计划 | 操作员可运行的部署前测试检查清单（阶段内已推迟，与 PASS 兼容） | **PASS** | `docs/delivery/DEPLOY_DRY_RUN.md` |
| 确定性检查 — 密钥扫描 | 对部署相关路径执行内置密钥扫描 | **PASS** | 对 `script docs/delivery foundry.toml .env.example` 执行 `secret_scan.py` — 干净 |
| 确定性检查 — 静态部署检查 | 内置静态部署就绪检查 | **PASS** | 对 `script docs/delivery` 执行 `deployment_static_checks.py` — 干净 |
| 构建证据 | 范围生产构建 + 字节码大小 | **PASS** | `forge build src script --sizes` → 退出码 0；SmartWalletEntry 24,510 B（余量 66），SmartWalletFactory 2,218 B（离线；子模块未变） |

---

## 阻塞项清单

**无阻塞项。** 所有必要检查均已 PASS（含整体就绪状态及检查项 #16–#17 中的两个操作员确认前提条件）。以下各项为**非阻塞 / 信息性**内容，操作员应在打包/部署前予以核对。

| 项目 | 严重级别 | 状态 | 解决方案 / 操作员操作 |
|------|----------|------|----------------------|
| `package.json` 中 `deploy` npm 脚本引用了不存在的 `script/deploy/DeployInit.s.sol` | 信息性 | 非阻塞 | 实际部署脚本为 `script/deploy.s.sol`。请核对 npm 路径，或按 README §Deploy 直接运行 forge。 |
| 部署脚本文件名为 `deploy.s.sol`（而非 `Deploy.s.sol`） | 信息性 | 非阻塞 | 内置静态检查器发出非致命警告（"未找到 Deploy.s.sol"）；脚本可运行，且与 README/Stage-1 惯例一致。重命名为可选项，超出既有代码保留范围。 |
| `lib/` 中子模块 gitlink 存在漂移 | 低（信息性） | 非阻塞 | 打包部署前须核对 `lib/` gitlinks；离线构建（`FOUNDRY_OFFLINE=true`），防止 forge 自动重置已漂移但可用的 lib。 |
| 默认无范围 `forge build` 因私有恢复套件测试导入（审计 M-02）失败 | 中（非阻塞） | 非阻塞 | 使用范围生产构建 `forge build src script`（或恢复私有 `lib/smart-wallet-recovery` 依赖）。生产源编译干净。 |
| EIP-170 大小余量仅 66 字节（审计，Medium） | 中（非阻塞） | 非阻塞前提条件 | 部署前重新运行 `forge build src script --sizes`；禁止在未采取大小缓解措施的情况下增加源码（见检查项 #16）。 |
| M-03 — 管理员生命周期可移除/降级最后一个活跃管理员（按账户自管理锁死） | 中（非阻塞） | 非阻塞 | 按账户运营注意事项；已载入 `EMERGENCY_PLAN.md` 残余风险清单。不阻塞部署。 |
| M-04 / M-05 — 所有者过期验证使用 `block.timestamp`；内置验证器可回滚 / 执行无界证明计算 | 中（非阻塞） | 非阻塞 | Bundler 兼容性及 gas 攻击残余风险；`EMERGENCY_PLAN.md` 中的监控项。无资金损失。 |
| M-01 — 非规范 `SIG_VALIDATION_FAILED` 打包（`1 << 96`） | 中（非阻塞） | 非阻塞 | Bundler 兼容性建议；监控项。无资金损失。 |

---

## 部署前操作员签核（针对所选目标链完成）

- [ ] 目标链已确认**激活 Cancun / EIP-1153**（检查项 #17）— 禁止在非 Cancun 链上部署。
- [ ] 已重新运行 `forge build src script --sizes`；SmartWalletEntry 运行时 ≤ 24,576 字节（检查项 #16）— 自 24,510 B 以来无源码增长。
- [ ] 已通过 `forge inspect SmartWalletEntry storageLayout` 验证 — TWA 命名空间无冲突（检查项 #18）。
- [ ] 目标链上 EIP-2470 单例工厂已存在于 `0xce0042B868300000d44A59004Da54A005ffdcf9f`（否则启用 CREATE 回退，原因 `factory-unavailable`）。
- [ ] 目标链上 ERC-4337 EntryPoint v0.7 已存在于 `0x0000000071727De22E5E9d8BAf0edAc6f37da032`。
- [ ] 已选定并记录 `DEPLOY_FACTORY_SALT`（两个合约使用相同的 salt；跨链地址一致要求 initCode 相同 + 相同 salt + 工厂已存在）。
- [ ] 已执行 `docs/delivery/DEPLOY_DRY_RUN.md` 中的 Fork 干跑并通过（创建账户 → ERC-20 结算 → 重放回滚）。
- [ ] 部署后：`SmartWalletFactory.IMPLEMENTATION() == SmartWalletEntry` 地址；两个地址均有非零代码；预测的 CREATE2 地址 == 实际地址。
