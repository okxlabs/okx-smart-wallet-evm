# PRD\-账户级离线签名授权转账（Account\-Level Transfer With Authorization）v1\.0\-fix

\&gt; 📋 **Oli Run Config：** [Oli Run Config 文档](https://okg-block.sg.larksuite.com/docx/VckMdRls6omifLx7K6flNbwkgre)

## 1\. 文档概览

<table><tbody>
<tr>
<td>

版本

</td>
<td>

日期

</td>
<td>

作者

</td>
<td>

变更

</td>
</tr>
<tr>
<td>

v1\.0

</td>
<td>

2026\-06\-25

</td>
<td>

rick\.zha

</td>
<td>

初稿

</td>
</tr>
</tbody></table>

- **PRD 版本**：v1\.0

- **文档状态**：可进入自动化设计生成

- **目标链**： Ethereum 主网（chainId 1，已激活 Cancun，支持 EIP\-1153 瞬态存储）

---

## 2\. 背景与动机

### 2\.1 当前情况

给 SmartWallet 的 subkey / session key 做资金管控。owner 可给 subkey 配限额（如某 key 每日/累计仅可花 100 USDC）；只要支出都经过 SmartWallet（execute / executeWithRelayer / executeUserOp），SmartWallet 就能感知该 key 的支出并按其 hook 扣额度、拦截。但若 subkey 走 token 原生 ERC\-3009（签个名，由 facilitator 直接在 token 上走 3009 结算），SmartWallet 完全感知不到 —— 它额度只有 100 却签了 10000 也拦不住、即使在额度内也无法扣减，限额形同虚设。因此要求 x402 / MPP 等支付不走 token 原生 3009，而是必须调用 SmartWallet 自身的 settle 接口结算，使 SmartWallet 能对 subkey 施加 hook 限额。附带价值：原生 3009 要求 token 自身支持，在 SmartWallet 层实现后，对任意 token 都能完成此类结算。

**接口约束要求：** 按 `ITransferWithAuthorization` 接口实现，不得改动接口（函数/事件/错误签名），仅实现函数体逻辑。不要按 ERC\-3009 文本自行理解实现，一律以本接口为准。

```Solidity
interface ITransferWithAuthorization {
  // Events
  event TransferAuthorizationUsed(address indexed token, address indexed from, address indexed to, uint256 value, bytes32 authorizationNonce);
  event TransferAuthorizationCanceled(address indexed authorizer, bytes32 indexed authorizationNonce);
  // Errors
  error AuthorizationAlreadyUsed(bytes32 authorizationNonce);
  error AuthorizationNotYetValid(uint256 validAfter);
  error AuthorizationExpired(uint256 validBefore);
  error InvalidRecipient(address to);
  error CallerNotPayee(address caller, address to);
  // Functions
  function executeTransferWithAuthorization(address token, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce, bytes calldata signature) external; // permissionless
  function receiveWithAuthorization(address token, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 authorizationNonce, bytes calldata signature) external; // only msg.sender == to
  function cancelTransferAuthorization(bytes32 authorizationNonce, bytes calldata signature) external;
  function transferAuthorizationState(bytes32 authorizationNonce) external view returns (bool used);
  function TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR() external view returns (bytes32);
}
```

**参考（权威来源）：**

- EIP \- Account\-Level Transfer With Authorization（设计草案，Lark：https://okg\-block\.sg\.larksuite\.com/wiki/F68jwgXhOigB4KkMRhqlghQHg2e ）—— 本 PRD 的接口、typehash 常量、nonce 模型、ERC\-165 ID 均以此草案为规范来源，任何不一致一律以该文档为准。

### 2\.2 本产品需要实现

本产品在现有 SmartWallet / 验签底座上新增一套账户级 settle 接口（即 §2\.1 的 `ITransferWithAuthorization`）：核心是让 subkey/session key 的 x402/MPP 支付强制经 SmartWallet 结算、从而受其 hook 限额约束；并使任意 token 都能完成此类结算。

- 标准接口 `executeTransferWithAuthorization` / `receiveWithAuthorization`：任意 relayer 凭账户 owner 的 EIP\-712 离线签名转出任意 ERC\-20 或原生币，无需 token 支持 ERC\-3009、无需 4337。

- 随机 bytes32 `authorizationNonce`，与账户 2D nonce 完全独立。

- 转账专用的 EIP\-712 typed data（token/to/value/有效期），验签经 `\_verifyTwaSignature` 对标准 typed\-data digest 直签

- 验签与 relayer 底座复用现有体系（`getVerifiedValidator` \+ validator 路由），不新造一套；ERC\-165 可被外部发现。

- 授权模型与 execute 同构：结算时复用签名 key 自身的 spending policy（hook）。

### 2\.3 目标用户与角色

<table><tbody>
<tr>
<td>

角色

</td>
<td>

描述

</td>
<td>

产品职责

</td>
<td>

禁止能力

</td>
</tr>
<tr>
<td>

Account Owner\(s\) / 签名者

</td>
<td>

账户所有者

</td>
<td>

离线签署转账授权（EIP\-712）

</td>
<td>

不得在无本人签名的情况下让任何人动用账户资金

</td>
</tr>
<tr>
<td>

Relayer / Facilitator

</td>
<td>

任意第三方

</td>
<td>

提交已签名授权上链并代付 gas

</td>
<td>

无权更改收款人 / 金额；无权重复使用同一 authorizationNonce

</td>
</tr>
<tr>
<td>

Payee / 收款方

</td>
<td>

转账接收者

</td>
<td>

接收资金；在 receive 路径下作为 msg\.sender 主动拉款

</td>
<td>

非 to 不得通过 receive 路径结算

</td>
</tr>
<tr>
<td>

Smart Contract System

</td>
<td>

链上执行层

</td>
<td>

执行验签、nonce、时间窗校验与资金转移；结算时施加签名 key 的 hook

</td>
<td>

判断链下业务逻辑之外的策略

</td>
</tr>
<tr>
<td>

Backend / Protocol Layer

</td>
<td>

链下编排层

</td>
<td>

构造 EIP\-712 payload、收集签名、选择并提交 relayer；为受限 key 配置 hook

</td>
<td>

覆盖链上安全约束

</td>
</tr>
<tr>
<td>

subkey

</td>
<td>

被授权/被限制的子 key

</td>
<td>

在 owner 设定的限额/白名单内发起支付（经 SmartWallet settle）

</td>
<td>

不得绕过 hook 限额动用资金；不得超出 owner 设定的额度/白名单

</td>
</tr>
</tbody></table>

### 2\.4 业务目标

<table><tbody>
<tr>
<td>

目标 ID

</td>
<td>

目标

</td>
<td>

目标值

</td>
<td>

衡量方式

</td>
</tr>
<tr>
<td>

G\-1

</td>
<td>

提供账户级离线签名 settle 标准接口（按 §2\.1），外部 facilitator 可直接对接

</td>
<td>

符合 §2\.1 接口定义 \+ ERC\-165 可发现；单笔 ERC\-20（ECDSA）gas \&lt; 120,000

</td>
<td>

接口一致性测试 \+ gas report

</td>
</tr>
<tr>
<td>

G\-2

</td>
<td>

支持任意 ERC\-20 \+ 原生币，无需 token 改造

</td>
<td>

标准 ERC\-20 \+ 非标返回 token（USDT）\+ 原生币 100% 覆盖

</td>
<td>

集成测试

</td>
</tr>
<tr>
<td>

G\-3

</td>
<td>

防重放 / 防抢跑

</td>
<td>

不可成功重放；收款人不可被篡改

</td>
<td>

invariant \+ 边界测试

</td>
</tr>
<tr>
<td>

G\-4

</td>
<td>

复用账户现有验签体系

</td>
<td>

ECDSA 与 passkey 两类 validator 均可签授权并验证通过

</td>
<td>

集成测试

</td>
</tr>
<tr>
<td>

G\-5

</td>
<td>

TWA 与 execute 系列同构：受限 key 的 spending policy 在 TWA 上一致生效

</td>
<td>

配 hook 的 session key 经 TWA 超限额结算一定被 hook revert；TWA 不能绕过 hook

</td>
<td>

hook 执行测试 \+ invariant

</td>
</tr>
</tbody></table>

### 2\.5 与现有底层能力的关系

本接口是新增的独立 settle 入口：facilitator/relayer 直接调用账户本方法结算，不走 executeWithRelayer、也不走 token 原生 3009；与现有 execute / Allowance / Merkle 并存互补、不替代。

---

## 3\. 范围

### 3\.1 本期范围

在 SmartWallet 账户合约上实现 §2\.1 给定的 `ITransferWithAuthorization` 全部方法，不改接口签名、仅实现函数体。明细：

- `executeTransferWithAuthorization`：permissionless，凭离线签名结算单笔转账（P0）

- `receiveWithAuthorization`：要求 msg\.sender == to，独立 typehash 防抢跑（P0）

- 结算复用签名 key 的 spending policy（hook）：execute / receive 结算时跑该 key 的 preCheck/postCheck（P0）

- `cancelTransferAuthorization`：owner 取消未使用授权，含形态 A（签名代提交）\+ 形态 B（账户自调用免签）（P1）

- `transferAuthorizationState` 查询 \+ `TRANSFER\_AUTHORIZATION\_DOMAIN\_SEPARATOR\(\)` getter（P2）

- ERC\-165 接口声明（P2）

- 接入现有 SmartWallet 验签体系（ECDSA / passkey / 外部 validator），经账户 validator 路由（`getVerifiedValidator` \+ `\_validateSignature`）

### 3\.2 不在本期范围

<table><tbody>
<tr>
<td>

项

</td>
<td>

原因

</td>
<td>

后续方向

</td>
</tr>
<tr>
<td>

批量授权转账（一次多笔）

</td>
<td>

按 ERC 单笔，降复杂度与审计面

</td>
<td>

视吞吐需求评估批量变体

</td>
</tr>
<tr>
<td>

allowedTokens 链上白名单 / 限额（账户层）

</td>
<td>

账户层不做 token 限制；限额 / 白名单交由 hook \+ 链下

</td>
<td>

由 SpendingPolicyHook 或后续叠加

</td>
</tr>
<tr>
<td>

链上紧急 pause / kill\-switch

</td>
<td>

依赖 cancel \+ 链下风控

</td>
<td>

监管 / 风控要求再评估

</td>
</tr>
<tr>
<td>

paymaster / gas 赞助集成

</td>
<td>

由 relayer 直接代付 gas

</td>
<td>

N/A

</td>
</tr>
<tr>
<td>

批量 / 多链一次签名

</td>
<td>

已有 Merkle 覆盖

</td>
<td>

复用现有 Merkle

</td>
</tr>
<tr>
<td>

标准代扣（standing allowance）

</td>
<td>

已有 Allowance 覆盖

</td>
<td>

复用现有 Allowance

</td>
</tr>
</tbody></table>

---

## 4\. 功能需求

### FR\-0：使用流程总览

使用流程：

- **支付授权**：带 hook 的 AA owner 签名授权，签名可执行 `executeTransferWithAuthorization`、`receiveWithAuthorization` 方法。

- **facilitator 结算（transfer 路径）**：owner 离线签 `executeTransferWithAuthorization` 签名 → facilitator 拿到签名 → 调 `AA\.executeTransferWithAuthorization` → AA 验签 \+ 跑该 key 的 hook 限制逻辑 \+ 转账。

- **收款合约取款（receive 路径）**：owner 离线签 `receiveWithAuthorization` 授权后，收款合约在自己的业务流程中（要求 msg\.sender == to）调用 `AA\.receiveWithAuthorization`，一次性原子完成扣款，避免被他人抢先执行。

- **取消**：owner 签 Cancel 单经任意 relayer 提交；或账户自调用免签 cancel，作废未用的 nonce。

### FR\-1：执行授权转账（executeTransferWithAuthorization）

**描述：** 任意调用者凭账户 owner 的离线 EIP\-712 签名，触发账户把 value 数量的 token（或原生币）转给 to。

**业务规则：**

1. 签名数据必须包含 from（= 账户自身地址）、token、to、value、validAfter、validBefore、authorizationNonce，按 `ExecuteTransferWithAuthorization` 类型 EIP\-712 签名；from 不作为函数参数，合约以自身地址校验。

2. 必须校验 authorizationNonce 未被使用且未被取消。

3. 必须校验 block\.timestamp 落在开区间 \(validAfter, validBefore\) 内。

4. 必须经 `\_verifyTwaSignature\(structHash, signature\)` 校验签名 —— 对标准 EIP\-712 typed\-data digest `hashTypedData\(structHash\)` 直接验签，经账户 `getVerifiedValidator` \+ `\_validateSignature` 路由完成。

5. 校验通过后必须先标记 authorizationNonce 为已用，再执行转账（CEI）。

6. 结算时必须复用签名 key 自身的 hook。keyHash 取自 `\_verifyTwaSignature` 返回值，把本笔转账表达为一个 Call（ERC\-20 → `token\.transfer\(to,value\)`；原生币 → `\{target:to, value:value\}`），在标记 nonce 已用之后、转账前后执行该 key 的 preCheck / postCheck，与 execute 系列经 `\_batchCall` 的 hook 调用语义一致；该 key 未配 hook 时不触发。hook revert 则整笔回滚。

7. token 为原生币哨兵地址（ERC\-7528）时转原生币，否则按 ERC\-20 转账，兼容非标准返回 token。

8. 任意地址均可调用；不限制签名方为 admin key —— 权限与限额由该 key 的 hook 施加。

9. 必须发出 `TransferAuthorizationUsed` 事件；任一校验失败必须 revert。

**验收标准：**

<table><tbody>
<tr>
<td>

ID

</td>
<td>

Given

</td>
<td>

When

</td>
<td>

Then

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-1

</td>
<td>

余额充足、nonce 未用、在时间窗内、签名有效、（如配 hook）在 policy 内

</td>
<td>

调 executeTransferWithAuthorization

</td>
<td>

转账成功，nonce 标记已用，发出 TransferAuthorizationUsed

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-2

</td>
<td>

authorizationNonce 已被使用

</td>
<td>

再次提交相同 nonce

</td>
<td>

revert（AuthorizationAlreadyUsed），无资金移动

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-3

</td>
<td>

block\.timestamp ≤ validAfter 或 ≥ validBefore

</td>
<td>

提交授权

</td>
<td>

revert（未生效 / 已过期）

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-4

</td>
<td>

签名非账户 owner / 已注册 validator 所签

</td>
<td>

提交授权

</td>
<td>

revert（InvalidSignature），nonce 不被消耗

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-5

</td>
<td>

账户该 token 余额不足

</td>
<td>

提交授权

</td>
<td>

整笔 revert，状态回滚

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-6

</td>
<td>

签名 key 配 SpendingPolicyHook，本笔超限额 / 收款人不在白名单

</td>
<td>

提交授权

</td>
<td>

结算被 hook revert，整笔回滚，nonce 不被消耗

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-7

</td>
<td>

签名 key 配 hook，本笔在额度 / 白名单内

</td>
<td>

提交授权

</td>
<td>

转账成功，hook 记账，与同参数 execute 一致

</td>
</tr>
<tr>
<td>

FR\-1\-AC\-8

</td>
<td>

用 ERC\-1271 message\-wrapper 包装后的 digest 签发的签名

</td>
<td>

经（\_verifyTwaSignature）验签

</td>
<td>

MUST 失败 revert

</td>
</tr>
</tbody></table>

**边界场景：**

1. signature\.length \&lt; `SIGNATURE\_ENVELOPE\_MIN\_LENGTH` 时 MUST revert `InvalidSignature\(\)`（信封长度下界）

2. 信封前 32 字节恢复出的 keyHash 经 `getVerifiedValidator\(keyHash\)` 返回 address\(0\) 时 MUST revert `InvalidSignature\(\)` 

**优先级：** P0

### FR\-2：收款方拉款授权（receiveWithAuthorization）

**描述：** 与 FR\-1 行为一致（含 hook 执行、含验签路径），但仅允许 to 调用，使用独立 typehash，防抢跑 / 跨类型重放。

**业务规则：**

1. 必须校验 msg\.sender == to，否则 revert（CallerNotPayee）。

2. 签名必须使用 `ReceiveWithAuthorization` 类型（与 execute 类型互不可替换）。

3. 其余校验（nonce / 时间窗 / 验签 / CEI / hook / 事件）与 FR\-1 一致 —— 验签同走 `\_verifyTwaSignature`，hook 选择同用其返回的 keyHash。

**验收标准：**

<table><tbody>
<tr>
<td>

ID

</td>
<td>

Given

</td>
<td>

When

</td>
<td>

Then

</td>
</tr>
<tr>
<td>

FR\-2\-AC\-1

</td>
<td>

to 调用、签名有效、nonce 未用、在窗口内、（如配 hook）在 policy 内

</td>
<td>

receiveWithAuthorization

</td>
<td>

转账成功并发出 TransferAuthorizationUsed

</td>
</tr>
<tr>
<td>

FR\-2\-AC\-2

</td>
<td>

msg\.sender \!= to

</td>
<td>

调用

</td>
<td>

revert（CallerNotPayee）

</td>
</tr>
<tr>
<td>

FR\-2\-AC\-3

</td>
<td>

用 Execute 类型签发的授权

</td>
<td>

通过 receiveWithAuthorization 提交

</td>
<td>

验签失败 revert（不可跨类型重放）

</td>
</tr>
<tr>
<td>

FR\-2\-AC\-4

</td>
<td>

签名 key 配 hook，超额度 / 非白名单

</td>
<td>

to 调用

</td>
<td>

结算被 hook revert

</td>
</tr>
</tbody></table>

**优先级：** P0

### FR\-3：取消授权（cancelTransferAuthorization）

**描述：** 账户 owner 取消一个尚未使用的授权 nonce，使其永久作废。提供两种形态。

**业务规则：**

1. 若该 authorizationNonce 已被使用，必须 revert（AlreadyUsed）。

2. 形态 A（签名代提交）：signature 非空时，按 `CancelTransferAuthorization` 类型构造 structHash，经 `\_verifyTwaSignature` 校验账户 owner 签名；任意 relayer 可提交。

3. 形态 B（账户自调用免签）：signature 为空（长度 0）时，必须 msg\.sender == address\(this\)。

4. 取消后必须标记该 nonce 为已用，并发出 `TransferAuthorizationCanceled`；被取消的 nonce 视为已用。

5. 形态 B 的适用场景：核心是省掉一次「专门为取消而签的签名」—— msg\.sender == address\(this\) 只能由账户自调用达成，授权来自外层 execute / 4337（已过 owner 授权）。典型用法：① 同一笔 execute / UserOp 内原子作废一个待结算授权；② passkey 一次生物认证签 UserOp、cancel 搭车；③ 账户内业务流 / 恢复流程程序化作废；④ admin 经 execute 自调用回收 agent 的悬挂授权。

**验收标准：**

<table><tbody>
<tr>
<td>

ID

</td>
<td>

Given

</td>
<td>

When

</td>
<td>

Then

</td>
</tr>
<tr>
<td>

FR\-3\-AC\-1

</td>
<td>

nonce 未用 \+ 有效 owner 签名

</td>
<td>

cancel（形态 A）

</td>
<td>

nonce 标记已用，发出 Canceled，后续对该 nonce 的 execute/receive 均 revert

</td>
</tr>
<tr>
<td>

FR\-3\-AC\-2

</td>
<td>

signature 为空且 msg\.sender \!= address\(this\)

</td>
<td>

调用

</td>
<td>

revert（仅允许账户自调用的免签取消）

</td>
</tr>
<tr>
<td>

FR\-3\-AC\-3

</td>
<td>

nonce 已被使用

</td>
<td>

调用 cancel

</td>
<td>

revert（AlreadyUsed）

</td>
</tr>
<tr>
<td>

FR\-3\-AC\-4

</td>
<td>

signature 为空且 msg\.sender == address\(this\)（经 execute 自调用）

</td>
<td>

调用（形态 B）

</td>
<td>

nonce 标记已用，发出 Canceled

</td>
</tr>
</tbody></table>

**优先级：** P1

### FR\-4：授权状态查询与域分隔符

**业务规则：** `transferAuthorizationState\(nonce\)` 返回是否已用/已取消；`TRANSFER\_AUTHORIZATION\_DOMAIN\_SEPARATOR\(\)` 返回域分隔符；即使不暴露 getter，合约内部仍必须跟踪 nonce 状态。

`authorizationNonce` 管理规则：① 必须是随机生成的 32 字节值；② 每个账户内仅可使用一次；③ 被 cancel 的 nonce 视为已用；④ 用 `mapping\(bytes32 =\&amp;gt; bool\)` 跟踪；⑤ 与账户原生交易 nonce（ERC\-4337 EntryPoint nonce / 框架执行 nonce）完全隔离。

<table><tbody>
<tr>
<td>

ID

</td>
<td>

Given

</td>
<td>

When

</td>
<td>

Then

</td>
</tr>
<tr>
<td>

FR\-4\-AC\-1

</td>
<td>

nonce 已用/已取消

</td>
<td>

查询

</td>
<td>

返回 true

</td>
</tr>
<tr>
<td>

FR\-4\-AC\-2

</td>
<td>

nonce 从未使用

</td>
<td>

查询

</td>
<td>

返回 false

</td>
</tr>
</tbody></table>

**优先级：** P2

### FR\-5：ERC\-165 接口声明

**业务规则：** `INTERFACE\_ID = executeTransferWithAuthorization\.selector ^ receiveWithAuthorization\.selector`（= `0x86c5a9e1`）；`supportsInterface\(0x86c5a9e1\)` 必须返回 true。`INTERFACE\_ID` MUST 声明为 `public constant`。

<table><tbody>
<tr>
<td>

ID

</td>
<td>

Given

</td>
<td>

When

</td>
<td>

Then

</td>
</tr>
<tr>
<td>

FR\-5\-AC\-1

</td>
<td>

接口 ID = 0x86c5a9e1

</td>
<td>

supportsInterface

</td>
<td>

返回 true

</td>
</tr>
<tr>
<td>

FR\-5\-AC\-2

</td>
<td>

未知接口 ID

</td>
<td>

supportsInterface

</td>
<td>

返回 false

</td>
</tr>
</tbody></table>

**优先级：** P2

### 目标到需求追踪

<table><tbody>
<tr>
<td>

目标 ID

</td>
<td>

覆盖需求

</td>
<td>

覆盖说明

</td>
</tr>
<tr>
<td>

G\-1

</td>
<td>

FR\-1, FR\-2, FR\-5

</td>
<td>

账户级 settle 标准接口 \+ ERC\-165 可发现

</td>
</tr>
<tr>
<td>

G\-2

</td>
<td>

FR\-1, FR\-2

</td>
<td>

任意 ERC\-20 \+ 原生币统一接口

</td>
</tr>
<tr>
<td>

G\-3

</td>
<td>

FR\-1, FR\-2, FR\-3

</td>
<td>

nonce 一次性 \+ 时间窗 \+ to 绑定 \+ 可取消

</td>
</tr>
<tr>
<td>

G\-4

</td>
<td>

FR\-1, FR\-2

</td>
<td>

验签复用 validator 路由（`\_verifyTwaSignature`）

</td>
</tr>
<tr>
<td>

G\-5

</td>
<td>

FR\-1, FR\-2

</td>
<td>

结算复用签名 key 的 hook，与 execute 同构；keyHash 与验签同源，结构上保证不可绕过 

</td>
</tr>
</tbody></table>



---

## 5\. 产品级状态语义

<table><tbody>
<tr>
<td>

业务状态

</td>
<td>

含义

</td>
<td>

可进入的下一业务结果

</td>
</tr>
<tr>
<td>

未使用（Unused）

</td>
<td>

该 nonce 从未被消费

</td>
<td>

已使用 / 已取消

</td>
</tr>
<tr>
<td>

已使用（Used）

</td>
<td>

授权被 execute/receive 成功消费

</td>
<td>

终态

</td>
</tr>
<tr>
<td>

已取消（Canceled）

</td>
<td>

授权被 owner 或账户自调用取消

</td>
<td>

终态

</td>
</tr>
</tbody></table>

**产品不变量：**

1. 每个 authorizationNonce 至多被消费一次；已使用与已取消互斥、均终态不可逆。

2. authorizationNonce 空间与账户原生 / ERC\-4337 nonce 完全隔离。

3. 收款人 to 与金额 value 被签名绑定；任何人提交都不改变结算结果。

4. nonce 在转账执行前被标记为已用（CEI），杜绝重入重放。

5. TWA 结算受签名 key 的 spending policy（hook）约束，与 execute / executeWithRelayer / 4337 同构。

---

## 6\. 非功能需求

<table><tbody>
<tr>
<td>

ID

</td>
<td>

类别

</td>
<td>

需求

</td>
<td>

目标 / 衡量方式

</td>
</tr>
<tr>
<td>

NFR\-1

</td>
<td>

Gas / 字节码

</td>
<td>

单笔 ERC\-20 授权转账可预测低成本，且全钱包运行时字节码不超 EIP\-170

</td>
<td>

约束：① 运行时字节码 ≤ 24,576（EIP\-170）；② ECDSA 路径 ≤ 120,000 gas；passkey 单独出基线。typehash 改 public constant 后的 getter 字节码增量须计入 optimizer\_runs 二分（见 §7、R\-9）

</td>
</tr>
<tr>
<td>

NFR\-2

</td>
<td>

安全

</td>
<td>

防重放、防抢跑、原生币重入（CEI \+ 重入锁）

</td>
<td>

安全规格 \+ invariant tests

</td>
</tr>
<tr>
<td>

NFR\-3

</td>
<td>

权限与策略

</td>
<td>

execute MUST 为 permissionless；cancel MUST 受 owner 签名 / 账户自调用限制；TWA 结算 MUST 复用签名 key 的 hook，与 execute 系列同构，MUST NOT 成为绕过 per\-key 限额 / 白名单的旁路

</td>
<td>

Access\-control matrix \+ hook 执行测试覆盖所有外部可调用路径

</td>
</tr>
<tr>
<td>

NFR\-4

</td>
<td>

可观测性

</td>
<td>

所有状态变化可观察

</td>
<td>

事件 \+ 测试验证

</td>
</tr>
</tbody></table>

---

## 7\. 技术需求

<table><tbody>
<tr>
<td>

项

</td>
<td>

内容

</td>
<td>

说明

</td>
</tr>
<tr>
<td>

开发语言

</td>
<td>

Solidity ^0\.8\.29

</td>
<td>

沿用现有 SmartWallet

</td>
</tr>
<tr>
<td>

EVM 版本

</td>
<td>

cancun

</td>
<td>

重入锁用 transient storage（TSTORE/TLOAD，EIP\-1153）。前置：首发链须支持 cancun（DEP\-6 / R\-9）

</td>
</tr>
<tr>
<td>

目标链

</td>
<td>

EVM（首发 Ethereum 主网 chainId 1）

</td>
<td>

跨链由 EIP\-712 域 chainId \+ verifyingContract 隔离

</td>
</tr>
<tr>
<td>

合约结构

</td>
<td>

单合约内联实现（不拆门面 / 链接库），运行时字节码 MUST ≤ EIP\-170 24,576 字节

</td>
<td>

`\[修订于 v1\.1\]` 注意 typehash 改 public constant 后的 getter 字节码增量须计入 optimizer\_runs 二分。采用单合约内联后，hook 的执行可直接复用账户的 `\_batchCall` 路径

</td>
</tr>
<tr>
<td>

**验签路径**

</td>
<td>

走 `\_verifyTwaSignature`（见下方规范）：对标准 EIP\-712 typed\-data digest `hashTypedData\(structHash\)` 直接验签，不经 ERC\-1271 / MessageSignLib 消息包装；签名信封 layout = `keyHash\(32\) ‖ ownerSignature`。

</td>
<td>

keyHash 从信封前 32 字节恢复，既经 `getVerifiedValidator\(keyHash\)` 路由 validator、又用于选中该 key 的hook（同一 keyHash，保证「签名的 key == 受 hook 约束的 key」）。

</td>
</tr>
<tr>
<td>

**typehash 可见性**

</td>
<td>

`EXECUTE\_TRANSFER\_WITH\_AUTHORIZATION\_TYPEHASH`、`RECEIVE\_WITH\_AUTHORIZATION\_TYPEHASH`、`CANCEL\_TRANSFER\_AUTHORIZATION\_TYPEHASH` 以及 `INTERFACE\_ID` MUST 声明为 `public constant`；MUST NOT 为 private / internal。

</td>
<td>

外部可读：facilitator / 审计方可独立读取常量、重建并校验 EIP\-712 digest，且保证接口声明与实现取值一致。常量值仍以 EIP 草案为权威来源、固定不变。

</td>
</tr>
<tr>
<td>

可升级合约

</td>
<td>

是（UUPS）

</td>
<td>

新增 nonce 存储置于独立 ERC\-7201 命名空间

</td>
</tr>
<tr>
<td>

升级权限控制

</td>
<td>

沿用 SmartWallet owner

</td>
<td>

不新增升级权限角色

</td>
</tr>
<tr>
<td>

开发框架

</td>
<td>

Foundry

</td>
<td>

TD 以满足 EIP\-170 \+ NFR\-1 为准动态调整

</td>
</tr>
<tr>
<td>

外部依赖合约

</td>
<td>

OpenZeppelin（SafeERC20、ECDSA）、solady（EIP712）；复用账户现有 ERC712 / OwnerManager / ValidationManager / ERC7201 / Hook

</td>
<td>

不引入新的系统性信任依赖

</td>
</tr>
</tbody></table>

### `\_verifyTwaSignature` 规范（PRD 已定，TD 不得改动语义）

**签名信封布局与校验流程：**

1. **信封 layout**：`keyHash\(32\) ‖ ownerSignature`；权威有效期是签名结构体内的 validAfter / validBefore（开区间）。

2. **长度下界**：`signature\.length \&lt; SIGNATURE\_ENVELOPE\_MIN\_LENGTH` 时 MUST revert `InvalidSignature\(\)`。

3. **恢复 keyHash**：`keyHash = bytes32\(signature\[:32\]\)`。

4. **路由 validator**：`validator = getVerifiedValidator\(keyHash\)`；`validator == address\(0\)` 时 MUST revert `InvalidSignature\(\)`。

5. **标准 digest**：`digest = hashTypedData\(structHash\)` —— 直接使用 EIP\-712 typed\-data digest，不经 ERC\-1271 message wrapper 二次包装。

6. **验签**：`\_validateSignature\(validator, keyHash, digest, signature\[SIGNATURE\_ENVELOPE\_MIN\_LENGTH:\]\)` 为 false 时 MUST revert `InvalidSignature\(\)`。

7. **返回值**：返回授权该操作的 keyHash，供调用方据其选中 hook（与 §6/FR\-1 的 hook 选择共用同一 keyHash）。

---

## 8\. 数据需求

### 8\.1 业务数据对象

<table><tbody>
<tr>
<td>

对象

</td>
<td>

业务字段

</td>
<td>

说明

</td>
</tr>
<tr>
<td>

转账授权

</td>
<td>

token、from（= 账户自身）、to、value、validAfter、validBefore、authorizationNonce、operationType

</td>
<td>

仅作签名校验输入，不持久存储

</td>
</tr>
<tr>
<td>

授权状态

</td>
<td>

authorizationNonce、used 标志

</td>
<td>

链上权威；独立 ERC\-7201 命名空间

</td>
</tr>
<tr>
<td>

Token Configuration

</td>
<td>

NATIVE\_ASSET 哨兵地址（ERC\-7528）

</td>
<td>

原生币与 ERC\-20 统一寻址

</td>
</tr>
<tr>
<td>

Spending Policy（hook）

</td>
<td>

签名 key 的 settings\.hook 及其内部限额 / token / 商户白名单状态

</td>
<td>

hook 合约内权威；TWA 结算时读取并执行 preCheck/postCheck

</td>
</tr>
</tbody></table>

### 8\.2 数据权威边界

- **链上权威：** 资金移动、nonce 已用 / 已取消状态、终态、hook 内的额度记账。

- **链下权威 ** 签名 payload 构造、relayer 选择、收款 UI metadata、事件索引历史、policy 参数配置。

---

## 9\. 依赖与约束

<table><tbody>
<tr>
<td>

ID

</td>
<td>

依赖

</td>
<td>

类型

</td>
<td>

Owner

</td>
<td>

需求状态

</td>
<td>

影响

</td>
<td>

验证 / 兜底

</td>
</tr>
<tr>
<td>

DEP\-1

</td>
<td>

现有验签体系

</td>
<td>

链上协议（同仓库）

</td>
<td>

钱包合约团队

</td>
<td>

Confirmed

</td>
<td>

缺失则无法验签

</td>
<td>

复用已审计代码 \+ 集成测试

</td>
</tr>
<tr>
<td>

DEP\-2

</td>
<td>

现有 EIP\-712 域

</td>
<td>

链上协议（同仓库）

</td>
<td>

钱包合约团队

</td>
<td>

Confirmed

</td>
<td>

域不一致则验不过

</td>
<td>

与账户验签共用同一域

</td>
</tr>
<tr>
<td>

DEP\-3

</td>
<td>

ERC\-7201 命名空间存储

</td>
<td>

链上协议（同仓库）

</td>
<td>

钱包合约团队

</td>
<td>

Confirmed

</td>
<td>

缺失则升级存储不安全

</td>
<td>

新命名空间 \+ storage\-layout 校验

</td>
</tr>
<tr>
<td>

DEP\-4

</td>
<td>

OpenZeppelin SafeERC20 / ECDSA

</td>
<td>

库

</td>
<td>

OpenZeppelin

</td>
<td>

Confirmed

</td>
<td>

转账 / 验签实现

</td>
<td>

锁版本依赖

</td>
</tr>
<tr>
<td>

DEP\-5

</td>
<td>

Relayer / Facilitator 链下服务

</td>
<td>

Backend

</td>
<td>

Pay / Backend 团队

</td>
<td>

Confirmed

</td>
<td>

无 relayer 需用户自提

</td>
<td>

接口 permissionless

</td>
</tr>
<tr>
<td>

DEP\-6

</td>
<td>

首发链支持 cancun EVM

</td>
<td>

链 / 基础设施

</td>
<td>

运维

</td>
<td>

Confirmed

</td>
<td>

不支持则 transient 重入锁失败

</td>
<td>

X Layer 与 Ethereum 主网均已激活 Cancun

</td>
</tr>
<tr>
<td>

DEP\-7

</td>
<td>

现有 Hook 机制（IHook preCheck/postCheck \+ settings\.hook \+ \_batchCall）

</td>
<td>

链上协议（同仓库）

</td>
<td>

钱包合约团队

</td>
<td>

Confirmed

</td>
<td>

缺失则 TWA 无法施加 policy

</td>
<td>

复用 \_batchCall 同款 hook 调用语义

</td>
</tr>
<tr>
<td>

DEP\-8 

</td>
<td>

现有 validator 路由（`getVerifiedValidator` \+ `\_validateSignature`）

</td>
<td>

链上协议（同仓库）

</td>
<td>

钱包合约团队

</td>
<td>

Confirmed

</td>
<td>

缺失则 `\_verifyTwaSignature` 无法路由/验签

</td>
<td>

复用现有 validator 路由 \+ 真实 ECDSA / passkey 端到端验签测试；

</td>
</tr>
</tbody></table>

---

## 10\. 成功指标

<table><tbody>
<tr>
<td>

指标

</td>
<td>

当前值

</td>
<td>

目标值

</td>
<td>

衡量方式

</td>
</tr>
<tr>
<td>

单笔 ERC\-20 授权转账 gas（ECDSA 路径）

</td>
<td>

N/A

</td>
<td>

\&lt; 120,000 gas

</td>
<td>

gas report（cancun \+ 选定 optimizer\_runs，含 hook 路径）

</td>
</tr>
<tr>
<td>

重放攻击成功次数

</td>
<td>

N/A

</td>
<td>

0

</td>
<td>

invariant 测试

</td>
</tr>
<tr>
<td>

篡改收款人成功次数

</td>
<td>

N/A

</td>
<td>

0

</td>
<td>

边界测试

</td>
</tr>
<tr>
<td>

支持 token 覆盖

</td>
<td>

N/A

</td>
<td>

标准 ERC\-20 \+ 非标返回 token（USDT）\+ 原生币全部通过

</td>
<td>

集成测试

</td>
</tr>
<tr>
<td>

外部 facilitator 接口一致性

</td>
<td>

N/A

</td>
<td>

通过 ITransferWithAuthorization \+ ERC\-165 检测

</td>
<td>

接口一致性测试

</td>
</tr>
<tr>
<td>

TWA 绕过 hook 成功次数

</td>
<td>

N/A

</td>
<td>

0

</td>
<td>

hook 执行测试 \+ invariant

</td>
</tr>
<tr>
<td>

SmartWalletEntry 运行时字节码

</td>
<td>

N/A

</td>
<td>

≤ 24,576（EIP\-170）

</td>
<td>

forge build \-\-sizes（含 typehash public constant getter 增量，内联 TD 动态调优后的 optimizer\_runs）

</td>
</tr>
<tr>
<td>

旧 ERC\-1271 包装 digest 验签必败 

</td>
<td>

N/A

</td>
<td>

100% 失败

</td>
<td>

防误包装回归用例（见 FR\-1\-AC\-8）

</td>
</tr>
</tbody></table>

---

## 11\. 风险与缓解措施

<table><tbody>
<tr>
<td>

ID

</td>
<td>

风险

</td>
<td>

影响

</td>
<td>

概率

</td>
<td>

缓解措施

</td>
</tr>
<tr>
<td>

R\-1

</td>
<td>

原生币转账重入

</td>
<td>

High

</td>
<td>

Medium

</td>
<td>

CEI（先标记 nonce 已用再转账）\+ 重入锁（transient）；invariant 验证

</td>
</tr>
<tr>
<td>

R\-2

</td>
<td>

execute 抢在 payee 业务流之前结算

</td>
<td>

Medium

</td>
<td>

Medium

</td>
<td>

to 被签名绑定；合约 payee 用 receiveWithAuthorization \+ 独立 typehash

</td>
</tr>
<tr>
<td>

R\-3 

</td>
<td>

验签接错：误将 EIP\-712 digest 经 ERC\-1271 / MessageSignLib 二次包装

</td>
<td>

High

</td>
<td>

Medium

</td>
<td>

EIP\-712 摘要（`hashTypedData\(structHash\)`）直接喂给 `\_validateSignature`，不经任何 message wrapper；真实 ECDSA / passkey 端到端比对 \+ 信封 layout 一致性测试；旧包装 digest 验签必败用例

</td>
</tr>
<tr>
<td>

R\-4

</td>
<td>

升级导致存储冲突

</td>
<td>

Medium

</td>
<td>

Low

</td>
<td>

独立 ERC\-7201 命名空间；升级前 storage\-layout 校验

</td>
</tr>
<tr>
<td>

R\-5

</td>
<td>

知识集中

</td>
<td>

Low

</td>
<td>

Medium

</td>
<td>

PRD \+ TD \+ EIP 草案 \+ 完整测试覆盖

</td>
</tr>
<tr>
<td>

R\-6

</td>
<td>

与现有 executeWithRelayer / Allowance 重叠

</td>
<td>

Medium

</td>
<td>

High

</td>
<td>

明确定位为「对外标准化 \+ 随机独立 nonce \+ 收款拉款 \+ 与 execute 同构 policy」增量层

</td>
</tr>
<tr>
<td>

R\-7

</td>
<td>

受限 session / agent key 借 TWA 绕过自身 hook

</td>
<td>

High

</td>
<td>

Medium

</td>
<td>

`\_verifyTwaSignature` 返回的 keyHash 同时用于 validator 路由与 hook 选择，从结构上保证「签名的 key == 受 hook 约束的 key」，TWA 与 execute 同构。残留：非 admin 且未配 hook 的 key 可无限额动钱（与 execute 现状一致），依赖「开通时必配 hook」provisioning 不变量兜底

</td>
</tr>
<tr>
<td>

R\-9

</td>
<td>

内联 \+ 低 optimizer\_runs 抬高全钱包 runtime gas

</td>
<td>

High

</td>
<td>

Medium

</td>
<td>

optimizer\_runs 为动态实现旋钮：TD 二分至满足 EIP\-170（含 typehash public constant getter 增量），并以选定 runs 重测 NFR\-1（\&lt;120k）\+ 全量 gas 回归；任何影响字节码体积的改动后 MUST 重测重调 runs

</td>
</tr>
</tbody></table>

---

## 12\. PRD\-to\-TD 交接要求

**TD 阶段负责（PRD 不预设）：**

- 合约接口设计（函数签名、事件、错误码、ERC\-165 detection 细节）。

- 合约结构：单合约内联；二分确定满足 EIP\-170 的 optimizer\_runs（计入 typehash public constant getter 的字节码增量），optimizer\_runs 具体值不由 PRD 写定。

- hook 执行：结算复用账户 `\_batchCall` 的 hook 调用（preCheck/postCheck），把转账表达为 Call；在标记 nonce 已用之后、重入锁内执行；保留 SafeERC20 返回值校验。

- EVM / 重入锁：evm\_version=cancun，重入锁用 transient storage。

- 数据类型选择、Gas 优化策略、storage 布局、ERC\-7201 槽计算、`SIGNATURE\_ENVELOPE\_MIN\_LENGTH` 具体常量值。

**PRD 阶段已定（TD 直接采用，不得改动）：**

- **验签路径 / 签名 layout ：**采用 `\_verifyTwaSignature` —— 信封 layout = `keyHash\(32\) ‖ ownerSignature`；对标准 typed\-data digest（`hashTypedData\(structHash\)`）直接验签，经 `getVerifiedValidator` \+ `\_validateSignature` 路由；MUST NOT 经 `isValidSignature` / MessageSignLib 二次包装。`\_verifyTwaSignature` 返回的 keyHash 同时用于 validator 路由与 spending\-policy hook 选择。

- **typehash 常量可见性：** 三个 typehash 常量与 `INTERFACE\_ID` MUST 声明为 `public constant`，MUST NOT private/internal；常量值仍以「EIP \- Account\-Level Transfer With Authorization」草案为权威来源、固定不变。

- **EIP\-712 域：** 沿用账户现有域（name SmartWallet、version 1\.1\.0、verifyingContract = 账户地址）。不变。

- **跨实现版本重放保护：** 由 EIP\-712 typehash \+ 域（chainId \+ verifyingContract）绑定提供；不再依赖「IMPLEMENTATION 经 D2 绑入 MessageSignLib\.hash 第三参」（该项随 isValidSignature 路径移除）

- TD 仍负责：optimizer\_runs 二分（计入 typehash public constant getter 的字节码增量，满足 EIP\-170 后以选定 runs 重测 NFR\-1 \&lt; 120k 与全量 gas 回归）、storage 布局、ERC\-7201 槽计算、重入锁 transient storage 实现等。

**PRD 完成标志：**

- 所有 FR 均有 Given/When/Then AC，且覆盖至少 2 个失败路径。

- 所有业务状态在状态图中定义，终态明确。

- 所有外部依赖在 §9 列出。

- NFR Gas 目标已量化；安全 / 权限 / 可观测性 / 隐私均有条目。
