# DEPLOY_RUNBOOK.md — okx-smart-wallet-dev（账户级带授权转账 / TWA）

> 针对 OKX SmartWallet 账户上 TWA 增量变更的运营商部署检查清单。请**按顺序**执行各步骤，不得跳过任何步骤。若触发任何 **STOP** 条件，须立即停止操作，归档所列证据，并在继续前参阅 `docs/delivery/EMERGENCY_PLAN.md`。

## 部署状态：就绪（READY）

上游审计流水线阶段结论 = **PASS**（`docs/process/AUDIT_REPORT.md`：裁定 WARN，0 个已确认 Critical/High，5 个在 `FAIL_ON=critical` 下不阻塞的 Medium 建议）。实现/测试评审 = **APPROVED**（`docs/process/DEV_REVIEW.md`）。本阶段已验证范围内生产构建为 PASS。所有必要的部署参数、依赖地址、链 ID 及所有者/管理员目标均已知晓并记录于下。

本 Runbook **本身不广播任何交易**：所有活跃（未注释）命令均为演习安全命令。广播操作为运营商的主动行为（步骤 9），仅以注释模板形式呈现。

---

## 1. 项目信息

| 字段 | 值 |
|-------|-------|
| 代码仓库 | `https://gitlab.okg.com/web3-wallet/smart-wallet-infra/okx-smart-wallet-dev.git` |
| 基础分支 | `dev` |
| 工作分支 | `feature/aa-auth-4.0` |
| 提交 SHA | `<COMMIT_SHA>`（运营商记录实际部署的提交） |
| 目标链 | EVM — **以太坊主网** |
| 链 ID | **1** |
| EVM 版本 | **Cancun**（EIP-1153 瞬态存储）— **必须满足** |
| 环境 | 生产环境（首次上线） |
| 发布标识符 | `<RELEASE_ID>`（运营商自行分配；与盐值一起记录） |
| Solidity / 工具链 | solc `0.8.29`，Foundry；`evm_version=cancun`，`optimizer=true`，`optimizer_runs=100`（`foundry.toml`） |
| 部署脚本 | `script/deploy.s.sol`（合约 `DeployInit`） |
| 上下文状态 | 技术层面 = Circle USDC（仅作 EIP-3009 语义参考，不约束本次部署）；业务层面 = 无。无部署惯例冲突。 |

---

## 2. 运营商安全规则

1. **禁止**将真实私钥放在命令行上。部署脚本从 `DEPLOYER_PRIVATE_KEY` 环境变量读取密钥。演习时请使用无资金、无权限的**一次性**密钥。
2. **禁止**在 `docs/` 目录下的任何文件中写入字面 RPC URL。请使用 `$RPC_URL` / `$FORK_RPC_URL` 环境变量或 `<rpc-endpoint>` 占位符；仅在执行时于 shell 中提供真实端点。
3. **本 Runbook 中所有活跃（未注释）命令均为演习安全命令** — 均不携带广播标志、验证标志或私钥标志。正式广播命令仅以注释模板形式出现在步骤 9 中；仅当下方所有检查门控全部通过后，才在您自己的 shell 中取消注释。
4. **硬性前提条件 — 切勿部署到非 Cancun 链。** TWA 原生重入锁使用 EIP-1153 瞬态存储，非 Cancun 链不支持此特性（DESIGN §12 DEP-6，§14）。广播前须确认 `chainId == 1` 且已激活 Cancun。X Layer（chainId 196 / 测试网 1952）为已记录的兼容备选链；主网为首次上线目标。
5. 实现合约与工厂合约**无所有者且不可变** — 部署时无需设置代理管理员、全局暂停或升级管理员。部署时请勿分配所有者/管理员；每个账户的所有者在账户创建时单独设置，该步骤不属于运营商部署操作。
6. 切勿让 `forge` 自动运行 `git submodule update` — 这可能会重置已漂移但可正常工作的 `lib/` gitlink 并破坏构建。请**离线**构建（`FOUNDRY_OFFLINE=true`），并在打包前协调 `lib/` gitlink。
7. 将 `script/deploy.s.sol` 和 `foundry.toml` 构建设置视为本次发布的冻结内容。任何源码变更都会使大小余量和下方的部署后事实失效，需要重新运行完整检查清单。
8. 在部署日志中记录所有生成的地址、盐值和提交 SHA；在每个步骤中归档所列证据。

---

## 3. 部署前检查清单

在进入第 4 节之前，**必须完成每一项**。每项格式：操作 / 命令或确认 / 预期输出 / STOP 条件 / 证据。

### 3.1 — 在审计提交处进行干净检出
- **操作：** 检出工作分支；确认在目标提交处树是干净的。
- **命令：**
  ```bash
  git rev-parse HEAD
  git status --porcelain
  ```
- **预期：** `git rev-parse HEAD` 输出您记录为 `<COMMIT_SHA>` 的提交；`git status --porcelain` 无任何输出。
- **STOP 条件：** 树不干净，或 HEAD ≠ 目标提交。
- **证据：** 提交 SHA 及干净状态输出。

### 3.2 — 确认链标识与 Cancun 激活状态
- **操作：** 确认目标 RPC 为以太坊主网（chainId 1）且已激活 Cancun。只读操作；使用您 shell 中的 `$RPC_URL`。
- **命令：**
  ```bash
  # $RPC_URL 必须在您的 shell 中导出；切勿写入本文件。
  cast chain-id --rpc-url "$RPC_URL"
  ```
- **预期：** `1`。
- **STOP 条件：** 值不为 `1`，或链未激活 Cancun（安全规则 4 / DEP-6）。
- **证据：** chain-id 输出及确认 Cancun 激活的说明。

### 3.3 — 协调 `lib/` 子模块 gitlink 漂移（审计 LOW）
- **操作：** 确认 `lib/` 子模块 gitlink 与锁定的依赖状态一致；切勿对已漂移但可正常工作的 lib 执行网络子模块更新。
- **命令：**
  ```bash
  git submodule status
  ```
- **预期：** 版本与锁定状态（`foundry.lock`）一致；无会改变已编译字节码的漂移。
- **STOP 条件：** gitlink 漂移会影响已编译库（solady / OZ / account-abstraction / webauthn-sol）；须先协调至锁定版本；切勿让 forge 自动重置它们。
- **证据：** `git submodule status` 输出。

### 3.4 — 协调 `package.json` 部署脚本路径（预先存在的仓库不一致问题）
- **操作：** 注意 `package.json` 中的 `deploy` npm 脚本指向**不存在的** `script/deploy/DeployInit.s.sol`。真实的部署脚本为 `script/deploy.s.sol`（见 `README.md` §Deploy）。请按本 Runbook 直接运行 `forge`，或在依赖 `yarn deploy` 之前协调 npm 路径。
- **确认（手动）：** 运营商确认将直接调用 `forge script script/deploy.s.sol`，而非使用失效的 `yarn deploy` 别名。
- **STOP 条件：** 任何流水线步骤依赖 `yarn deploy` 别名解析 — 须先修正 npm `deploy`/`deploy:broadcast` 路径。
- **证据：** 部署日志中注明使用了哪种调用路径以及 npm 脚本是否已协调。

### 3.5 — 生产构建 + EIP-170 大小检查（审计 M-02；EIP-170 余量）
- **操作：** 运行**范围内生产构建并附带大小检查**。使用 `forge build src script` — **不得**使用裸 `forge build`，后者会因 `test/Recovery.t.sol` 导入未初始化的私有 `lib/smart-wallet-recovery` 依赖而失败（审计 M-02）。离线构建。
- **命令：**
  ```bash
  FOUNDRY_OFFLINE=true forge build src script --sizes
  ```
- **预期：** 退出码 `0`；`SmartWalletEntry` 运行时大小 **≤ 24,576 字节**（EIP-170）。阶段 9 记录：`SmartWalletEntry = 24,510 B`（余量 **66 B**），`SmartWalletFactory = 2,218 B`。
- **STOP 条件：** 构建失败，或 `SmartWalletEntry` 运行时超过 24,576 字节，或其大小超过 24,510 B 但未经批准的大小缓解措施。余量仅有 66 字节。
- **证据：** 完整的 `--sizes` 输出及退出码；与 24,510 B / 66 B 基准对比。

### 3.6 — 确认已归档的确定性密钥扫描与静态检查（阶段 9）
- **操作：** 审查本阶段运行的已归档密钥扫描和静态部署检查结果。不需要重新运行阶段内置的安全脚本（这些脚本随部署技能包提供，不属于仓库的一部分）。
- **确认：** 打开 `docs/delivery/DEPLOY_CHECK.md`，确认该提交的密钥扫描和静态检查记录为通过。
- **STOP 条件：** `DEPLOY_CHECK.md` 记录了任何失败的密钥/静态检查，或该文件不存在。
- **证据：** 引用 `docs/delivery/DEPLOY_CHECK.md`。

### 3.7 — 确认必需的部署环境变量（不打印值）
- **操作：** 确认部署脚本读取的两个环境变量已导出，**不打印其值**。脚本读取 `DEPLOYER_PRIVATE_KEY`（`vm.envUint`）和 `DEPLOY_FACTORY_SALT`（`vm.envBytes32`）。
- **命令：**
  ```bash
  # 仅检查存在性 — 不打印密钥值。
  test -n "$DEPLOYER_PRIVATE_KEY" && echo "DEPLOYER_PRIVATE_KEY: set" || echo "DEPLOYER_PRIVATE_KEY: MISSING"
  test -n "$DEPLOY_FACTORY_SALT"  && echo "DEPLOY_FACTORY_SALT: set"  || echo "DEPLOY_FACTORY_SALT: MISSING"
  ```
- **预期：** 两者均输出 `set`。演习时，`DEPLOYER_PRIVATE_KEY` 为一次性密钥；`DEPLOY_FACTORY_SALT` 为运营商选择并记录的有文档、可重现的 `bytes32` 盐值（例如 `keccak256("okx-smart-wallet:twa:v1.1.0")`）。
- **STOP 条件：** 任一变量为 `MISSING`，或无法为演习确认使用了一次性密钥。
- **证据：** `set`/`MISSING` 输出行（不含密钥值）及已记录的盐值 + 发布 ID。

### 3.8 — 运行运营商 Fork 演习（部署前步骤）
- **操作：** 执行 `docs/delivery/DEPLOY_DRY_RUN.md` 中的运营商可运行 Fork 演习（本阶段因未配置 Fork RPC 而推迟）。该方案包含精确的命令、Fork 设置和断言。
- **确认：** 严格按照 `docs/delivery/DEPLOY_DRY_RUN.md` 中的规范运行演习（使用 `$FORK_RPC_URL` 占位符和一次性密钥；不广播）。
- **预期：** 两个合约均在 Fork 上成功部署，`SmartWalletFactory.IMPLEMENTATION()` 与已部署的 `SmartWalletEntry` 匹配，冒烟测试路径（创建账户 → ERC-20 结算 → 重放回滚）按文档描述运行。
- **STOP 条件：** 演习未通过任何断言，或无法获取 Fork RPC 端点。
- **证据：** 演习控制台日志及其生成的地址/断言。

---

## 4. 部署数据

| 参数 | 值 | 来源 |
|-----------|-------|--------|
| 部署方式 | **通过 EIP-2470 Singleton Factory 进行 CREATE2**（仅当工厂不存在时降级为普通 CREATE） | `script/deploy.s.sol`，`script/IDeployFactory.s.sol` |
| EIP-2470 Singleton Factory | `0xce0042B868300000d44A59004Da54A005ffdcf9f`（所有链地址相同） | `script/deploy.s.sol`（`DEPLOY_FACTORY`） |
| 主网上是否存在工厂？ | **是**（使用 CREATE2；不预期降级） | 部署事实 |
| 盐值 | `DEPLOY_FACTORY_SALT`（`bytes32`，运营商提供的环境变量；两次部署使用相同盐值；有文档、可重现） | `script/deploy.s.sol` |
| ERC-4337 EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032`（硬编码；链上必须存在；非构造函数参数） | `src/ERC4337Account.sol:18` |
| `NATIVE_ASSET` 哨兵值 | `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`（常量，非地址依赖） | `src/libraries/Static.sol` / DESIGN §6 |
| 预测的 CREATE2 地址 | `keccak256(0xff ++ 0xce0042…ffdcf9f ++ salt ++ keccak256(initCode))[12:]`（EIP-2470 直接使用盐值，不混入 msg.sender） | 部署事实 |
| TWA `INTERFACE_ID` | `0x86c5a9e1`（ERC-165） | `src/TransferWithAuthorization.sol:35` |
| `SmartWalletEntry` 运行时大小 | 24,510 B（EIP-170 上限 24,576 B，余量 66 B） | 阶段 9 `--sizes` |
| `SmartWalletFactory` 运行时大小 | 2,218 B | 阶段 9 `--sizes` |

### 所有者 / 管理员 / 角色 / 紧急目标

| 目标 | 部署时的值 |
|-------------|----------------------|
| 实现合约所有者/管理员 | **无** — `SmartWalletEntry` 无所有者且不可变；构造函数设置 `IMPLEMENTATION = address(this)` 并调用 `_disableInitializers()`（无 msg.sender 权限；永不初始化） |
| 工厂所有者/管理员 | **无** — `SmartWalletFactory` 从构造函数**参数**中设置不可变的 `IMPLEMENTATION`，而非 `msg.sender`；无所有者 |
| 代理管理员 | **无** — UUPS；升级权限 `_authorizeUpgrade` 为 `onlySelf`（按账户） |
| 全局暂停 / 升级管理员 | **无**（无全局暂停或终止开关；DESIGN §13） |
| 每账户所有者 | 稍后在账户创建时通过 `initialize(InitialOwner[])` 设置（调用者提供，`onlyFactory`）— **不属于**运营商部署步骤 |
| 不变量（通过缺失断言） | 所有者/管理员/角色永远不会是 Singleton Factory 地址 |

---

## 5. 上下文衍生的部署约束

- **技术上下文（Circle USDC / EIP-3009）：** 仅作语义参考（开放窗口、收款方受限接收、nonce 终止性、取消）。不同系统（FiatToken）；其部署脚本不约束本仓库。无冲突。
- **业务上下文：** 无。
- **净效果：** 除 DESIGN 已编码内容外无额外部署约束（Cancun 要求，收款方受限语义）。

---

## 6. 审计建议处理（与操作相关的发现）

所有发现均不阻塞部署（0 个 Critical/High；5 个 Medium）。

| ID | 严重程度 | 部署时的操作处理 |
|----|----------|-------------------------------------|
| **M-02** — 默认 `forge build` 在继承恢复套件导入时失败 | MEDIUM | 使用 `forge build src script` 构建（步骤 3.5），切勿使用裸 `forge build`；打包前可选择性地恢复私有 `smart-wallet-recovery` 依赖。生产 src+script 可干净编译。 |
| **EIP-170 余量** | MEDIUM | `SmartWalletEntry` 运行时为 24,510 B — 仅比上限少 66 B。部署前重新运行 `--sizes`（步骤 3.5），禁止在无大小缓解措施的情况下增大源码。 |
| **子模块 gitlink 漂移** | LOW | 打包前协调 `lib/` gitlink（步骤 3.3）；离线构建；切勿让 forge 自动重置它们。 |
| **M-03** — 最后管理员生命周期可能导致自调用管理功能不可用 | MEDIUM | 每账户、部署后的生命周期注意事项 — 非部署步骤。纳入监控；参见 `docs/delivery/EMERGENCY_PLAN.md`。 |
| **M-04 / M-05** — 所有者过期验证使用 `block.timestamp`；内置验证器可能回滚 / 执行无限制的证明工作量 | MEDIUM | Bundler 兼容性 / 燃气消耗攻击残留风险 — 监控项，无资金损失。参见 `docs/delivery/EMERGENCY_PLAN.md`。 |
| **M-01** — 非标准 `SIG_VALIDATION_FAILED` 打包 | MEDIUM | Bundler 兼容性建议；无资金损失；已跟踪，不阻塞部署。 |

将 M-01/M-03/M-04/M-05 纳入 `docs/delivery/EMERGENCY_PLAN.md` 作为监控/残留风险；M-02 / 大小 / 子模块问题由上述部署前检查清单处理。

---

## 7. 部署顺序

通过 EIP-2470 Singleton Factory 进行确定性 CREATE2 部署。`script/deploy.s.sol`（`DeployInit`）在一次 `run()` 中执行两个步骤。

| # | 合约 | 构造函数参数 | 部署机制 | 备注 |
|---|----------|------------------|------------------|-------|
| 1 | **SmartWalletEntry**（UUPS 账户实现；内联 TWA） | **无** | `IDeployFactory.deploy(type(SmartWalletEntry).creationCode, salt)` | 无所有者；构造函数中调用 `_disableInitializers()`。符合 CREATE2 条件（无 msg.sender 权限）。 |
| 2 | **SmartWalletFactory** | `address _implementation` = **步骤 1 中的 SmartWalletEntry 地址** | `IDeployFactory.deploy(abi.encodePacked(type(SmartWalletFactory).creationCode, abi.encode(impl)), salt)` | 不可变的 `IMPLEMENTATION` 从参数设置；无所有者。符合 CREATE2 条件。 |

两次部署使用相同盐值；由于初始化代码不同，生成的地址也不同。跨链相同地址要求：相同的初始化代码（相同的编译器设置）+ 相同的盐值 + 工厂存在。CREATE 降级（原因 `factory-unavailable`）仅适用于不存在 EIP-2470 的情况 — 主网上不预期发生。

---

## 8. 真实部署命令模板（不含密钥值）

> **活跃**命令（步骤 8）为演习安全的模拟命令。**正式**模板（步骤 9）为有意注释 — 每行以 `#` 开头。仅在第 3 节所有检查门控全部通过后，才在您自己的 shell 中取消注释。切勿内联私钥或字面 RPC URL。

### 步骤 8 — 最终模拟（演习安全；活跃）
- **操作：** 在目标 RPC 上**不广播**地模拟部署，重新确认脚本端到端运行正常（包括其 `IMPLEMENTATION()` 断言）。
- **命令：**
  ```bash
  # $RPC_URL 和部署环境变量在您的 shell 中导出（此处绝不写入）。
  # 活跃命令仅为模拟（无广播/验证/密钥标志）。
  FOUNDRY_OFFLINE=true forge script script/deploy.s.sol:DeployInit --rpc-url "$RPC_URL"
  ```
- **预期：** 模拟完成；日志输出部署者地址、盐值、模拟的 `SmartWallet 实现地址`、`SmartWalletFactory 地址`、`SmartWallet implementation address verified on SmartWalletFactory!` 及 `DeployInit script completed successfully`。
- **STOP 条件：** 模拟回滚、`IMPLEMENTATION()` 断言失败或预测地址不符预期。
- **证据：** 包含两个模拟地址的完整模拟日志。

### 步骤 9 — 正式广播（注释模板 — 主动取消注释后部署）
- **操作：** 所有检查门控通过后进行广播。在您自己的 shell 中取消注释以下其中一个模板（不要编辑此已提交文件来取消注释）。密钥由脚本从 `DEPLOYER_PRIVATE_KEY` 环境变量读取；切勿在命令行中传递。

  ```bash
  # ===== 取消注释以广播（生产部署）=====
  # 前提条件：chainId 1（Cancun），第 3 节已全部通过，一次性密钥已替换
  # 为 $DEPLOYER_PRIVATE_KEY 中真实的有资金的部署者密钥，盐值 + 发布 ID 已记录。
  #
  # FOUNDRY_OFFLINE=true forge script script/deploy.s.sol:DeployInit \
  #   --rpc-url "$RPC_URL" \
  #   --broadcast
  #
  # ===== 可选：广播 + 区块浏览器源码验证 =====
  # 通过您的 shell 环境变量提供区块浏览器 API 密钥（如 $ETHERSCAN_API_KEY）；不得内联。
  #
  # FOUNDRY_OFFLINE=true forge script script/deploy.s.sol:DeployInit \
  #   --rpc-url "$RPC_URL" \
  #   --broadcast \
  #   --verify
  ```

- **预期：** 脚本通过 EIP-2470 工厂广播两次 CREATE2 部署，输出最终的实现合约地址和工厂地址，且 `IMPLEMENTATION()` 断言成立。交易在链上确认。
- **STOP 条件：** 交易回滚/未能确认、`IMPLEMENTATION()` 断言失败，或已部署地址与步骤 8 / 演习地址不符。
- **证据：** 广播日志、`broadcast/` 运行产物、两个链上地址、交易哈希、盐值、`<COMMIT_SHA>` / `<RELEASE_ID>`。

---

## 9. 部署后验证检查清单

针对**广播**地址运行所有检查（全部只读）。将 `<SmartWalletEntry>` / `<SmartWalletFactory>` 替换为已部署地址；`$RPC_URL` 来自您的 shell。您也可以运行 `script/VerifyDeployment.s.sol`（参见 `docs/delivery/DEPLOY_DRY_RUN.md` §6）一次性执行所有检查。

### 9.1 — 工厂指向实现合约
```bash
cast call <SmartWalletFactory> "IMPLEMENTATION()(address)" --rpc-url "$RPC_URL"
```
- **预期：** 等于已部署的 `<SmartWalletEntry>` 地址。**若不符则 STOP。** **证据：** 命令输出。

### 9.2 — 两个地址均有非零代码
```bash
cast code <SmartWalletEntry>   --rpc-url "$RPC_URL"
cast code <SmartWalletFactory> --rpc-url "$RPC_URL"
```
- **预期：** 两者均有非空字节码（非 `0x`）；各自等于其预测的 CREATE2 地址。**若任一返回 `0x` 或与预测地址不符则 STOP。** **证据：** 两个输出 + 预测地址与实际地址的对比。

### 9.3 — 已声明 TWA ERC-165 接口
```bash
cast call <SmartWalletEntry> "supportsInterface(bytes4)(bool)" 0x86c5a9e1 --rpc-url "$RPC_URL"
```
- **预期：** `true`。**若为 `false` 则 STOP。** **证据：** 命令输出。

### 9.4 — EntryPoint 为标准 v0.7 地址
```bash
cast call <SmartWalletEntry> "entryPoint()(address)" --rpc-url "$RPC_URL"
```
- **预期：** `0x0000000071727De22E5E9d8BAf0edAc6f37da032`。**若为其他地址则 STOP。** **证据：** 命令输出。

### 9.5 — 存储布局：TWA 命名空间不发生冲突
```bash
forge inspect SmartWalletEntry storageLayout
```
- **预期：** TWA ERC-7201 命名空间与账户自定义存储根 `0x653ff6dc…` 明显不同；无重叠（R-4）。**若有重叠则 STOP。** **证据：** 存储布局输出 / 已归档的差异。

### 9.6 — 字节码大小符合 EIP-170（重新确认）
```bash
FOUNDRY_OFFLINE=true forge build src script --sizes
```
- **预期：** `SmartWalletEntry` 运行时 ≤ 24,576 B（基准 24,510 B，余量 66 B）。**若超过上限则 STOP。** **证据：** `--sizes` 输出。

### 9.7 — Fork 冒烟测试（按演习方案）
- **确认：** 确认 `docs/delivery/DEPLOY_DRY_RUN.md` 中的正常路径冒烟测试（通过工厂创建账户、正常路径 ERC-20 结算、重放回滚）已在 Fork 上执行。主网上通过 Fork 演习（步骤 3.8）验证，而非通过转移生产资金验证。**若任何冒烟断言失败则 STOP。** **证据：** 引用演习冒烟日志。

---

## 10. 紧急情况与停止条件

若发生以下**任何**情况，**立即停止部署**（不广播；若已在广播中，停止并评估）：

- 目标链未激活 Cancun 或 `chainId != 1`（安全规则 4 / DEP-6 — 硬性前提条件）。
- 生产构建失败，或 `SmartWalletEntry` 超过 EIP-170 的 24,576 B 上限 / 在无批准缓解措施的情况下超过 24,510 B 基准。
- `docs/delivery/DEPLOY_CHECK.md` 记录了失败的密钥/静态检查，或在任何产物中检测到密钥值。
- Fork 演习（`docs/delivery/DEPLOY_DRY_RUN.md`）未通过任何断言。
- 必需的环境变量（`DEPLOYER_PRIVATE_KEY`、`DEPLOY_FACTORY_SALT`）缺失，或演习使用了非一次性密钥。
- 步骤 8 的模拟回滚或 `IMPLEMENTATION()` 断言失败。
- 广播交易回滚/未能确认，或已部署地址与模拟/预测的 CREATE2 地址不符。
- 任何部署后验证（第 9 节）失败。

**能力说明：** 这些合约**没有链上暂停、终止开关或恢复机制**（DESIGN §13）。运营商无法通过链上手段停止已部署的账户。已记录的缓解措施为：每账户 `cancel` 未使用的授权，加上链下风险控制。请勿假设存在链上紧急停止机制。

**部署后需监控的残留风险**（审计，不阻塞部署）：M-03（最后管理员生命周期可能导致每账户自管理不可用）、M-04 / M-05（Bundler 兼容性 / 验证燃气消耗攻击）、M-01（非标准签名失败打包）。将这些纳入监控方案。

---

## 11. 紧急预案参考

如需了解事件响应、残留风险监控（M-01 / M-03 / M-04 / M-05）、"无链上暂停/恢复"能力声明，以及 `cancel` + 链下风险控制缓解程序，请参阅 **`docs/delivery/EMERGENCY_PLAN.md`**。

---

## 12. 手动审批 / 确认记录

广播前记录每一项。（签署人在执行时由运营商/审批人填写。）

| 项目 | 记录值 | 确认人 | 日期 |
|------|----------------|--------------|------|
| 审计流水线阶段结论 = PASS | PASS（WARN；0 Critical/High） | | |
| DEV_REVIEW = APPROVED | APPROVED | | |
| 已部署提交 `<COMMIT_SHA>` | | | |
| 发布标识符 `<RELEASE_ID>` | | | |
| `DEPLOY_FACTORY_SALT`（已记录，可重现） | | | |
| chainId = 1，Cancun 激活已确认（步骤 3.2） | | | |
| 生产构建 + 大小（步骤 3.5）：24,510 B / 余量 66 B | | | |
| 密钥及静态检查 PASS（`DEPLOY_CHECK.md`，步骤 3.6） | | | |
| Fork 演习 PASS（`DEPLOY_DRY_RUN.md`，步骤 3.8） | | | |
| `lib/` 子模块漂移已协调（步骤 3.3） | | | |
| `package.json` 部署路径协调已确认（步骤 3.4） | | | |
| 步骤 8 模拟 PASS | | | |
| 广播授权（步骤 9） | | | |
| 已部署 `SmartWalletEntry` 地址 | | | |
| 已部署 `SmartWalletFactory` 地址 | | | |
| 部署后验证（第 9 节）全部 PASS | | | |

---

*DEPLOY_RUNBOOK.md 结束。本 Runbook 不含任何密钥值、字面 RPC URL 或私钥。广播/验证/私钥标志仅出现在步骤 9 中以注释（`#` 前缀）模板行的形式呈现。*
