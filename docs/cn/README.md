# OKX 智能钱包 — 账户级授权转账（TWA）中文文档导读

> **英文文档为权威来源。** 本目录下的中文文档仅供中文读者参考阅读；如中英文内容存在分歧，以英文版为准。

---

## 概述

本分支（`feature/aa-auth-4.0`）在 OKX 智能钱包现有代码基础上，新增**账户级离线签名授权转账（Transfer With Authorization，TWA）**功能。该功能允许账户所有者通过 EIP-712 签名的方式，授权第三方在指定时间窗口内从账户发起 ERC-20 或原生 ETH 转账结算。

英文根目录 README：[../../README.md](../../README.md)

---

## 中文镜像文档索引

### 需求与设计

| 文档 | 中文镜像路径 | 英文原文路径 |
|---|---|---|
| 产品需求文档（PRD）| [process/REQUIREMENTS.md](process/REQUIREMENTS.md) | [../../docs/process/REQUIREMENTS.md](../../docs/process/REQUIREMENTS.md) |
| 需求分析 | [process/REQUIREMENTS_ANALYSIS.md](process/REQUIREMENTS_ANALYSIS.md) | [../../docs/process/REQUIREMENTS_ANALYSIS.md](../../docs/process/REQUIREMENTS_ANALYSIS.md) |
| 技术设计 | [process/DESIGN.md](process/DESIGN.md) | [../../docs/process/DESIGN.md](../../docs/process/DESIGN.md) |
| 设计评审 | [process/DESIGN_REVIEW.md](process/DESIGN_REVIEW.md) | [../../docs/process/DESIGN_REVIEW.md](../../docs/process/DESIGN_REVIEW.md) |
| 后端接口规范 | [process/INTERFACE_SPEC.md](process/INTERFACE_SPEC.md) | [../../docs/process/INTERFACE_SPEC.md](../../docs/process/INTERFACE_SPEC.md) |
| 安全规范 | [process/SECURITY_SPEC.md](process/SECURITY_SPEC.md) | [../../docs/process/SECURITY_SPEC.md](../../docs/process/SECURITY_SPEC.md) |
| 现有代码库基线 | [process/EXISTING_CODEBASE_BASELINE.md](process/EXISTING_CODEBASE_BASELINE.md) | [../../docs/process/EXISTING_CODEBASE_BASELINE.md](../../docs/process/EXISTING_CODEBASE_BASELINE.md) |

### 测试与验证

| 文档 | 中文镜像路径 | 英文原文路径 |
|---|---|---|
| 单元/模糊/不变量测试报告 | [process/TEST_REPORT.md](process/TEST_REPORT.md) | [../../docs/process/TEST_REPORT.md](../../docs/process/TEST_REPORT.md) |
| 集成测试报告 | [process/INTEGRATION_TEST.md](process/INTEGRATION_TEST.md) | [../../docs/process/INTEGRATION_TEST.md](../../docs/process/INTEGRATION_TEST.md) |
| 实现与测试评审 | [process/DEV_REVIEW.md](process/DEV_REVIEW.md) | [../../docs/process/DEV_REVIEW.md](../../docs/process/DEV_REVIEW.md) |
| 安全审计报告 | [process/AUDIT_REPORT.md](process/AUDIT_REPORT.md) | [../../docs/process/AUDIT_REPORT.md](../../docs/process/AUDIT_REPORT.md) |

### 交付与运营

| 文档 | 中文镜像路径 | 英文原文路径 |
|---|---|---|
| 后端合约接口交接 | [delivery/CONTRACT_INTERFACE.md](delivery/CONTRACT_INTERFACE.md) | [../../docs/delivery/CONTRACT_INTERFACE.md](../../docs/delivery/CONTRACT_INTERFACE.md) |
| 部署运行手册 | [delivery/DEPLOY_RUNBOOK.md](delivery/DEPLOY_RUNBOOK.md) | [../../docs/delivery/DEPLOY_RUNBOOK.md](../../docs/delivery/DEPLOY_RUNBOOK.md) |
| 部署就绪检查清单 | [delivery/DEPLOY_CHECK.md](delivery/DEPLOY_CHECK.md) | [../../docs/delivery/DEPLOY_CHECK.md](../../docs/delivery/DEPLOY_CHECK.md) |
| Fork 预演计划 | [delivery/DEPLOY_DRY_RUN.md](delivery/DEPLOY_DRY_RUN.md) | [../../docs/delivery/DEPLOY_DRY_RUN.md](../../docs/delivery/DEPLOY_DRY_RUN.md) |
| 应急响应计划 | [delivery/EMERGENCY_PLAN.md](delivery/EMERGENCY_PLAN.md) | [../../docs/delivery/EMERGENCY_PLAN.md](../../docs/delivery/EMERGENCY_PLAN.md) |
| 最终交付报告 | [delivery/DELIVERY_REPORT.md](delivery/DELIVERY_REPORT.md) | [../../docs/delivery/DELIVERY_REPORT.md](../../docs/delivery/DELIVERY_REPORT.md) |

### 流程记录

| 文档 | 中文镜像路径 | 英文原文路径 |
|---|---|---|
| Oli 运行配置 | [process/OLI_RUN_CONFIG.md](process/OLI_RUN_CONFIG.md) | [../../docs/process/OLI_RUN_CONFIG.md](../../docs/process/OLI_RUN_CONFIG.md) |
| 来源清单 | [process/SOURCE_MANIFEST.md](process/SOURCE_MANIFEST.md) | [../../docs/process/SOURCE_MANIFEST.md](../../docs/process/SOURCE_MANIFEST.md) |
| 返工历史 | [process/REWORK_HISTORY.md](process/REWORK_HISTORY.md) | [../../docs/process/REWORK_HISTORY.md](../../docs/process/REWORK_HISTORY.md) |

---

## 关键集成说明

**后端接入最重要事项：** `signature` 参数格式为 `keyHash（32字节）|| ownerSignature`。链上合约从 `signature[:32]` 中恢复 `keyHash`，路由至已注册的验证器，并对**直接** EIP-712 typed-data 摘要进行验证。请勿使用 ERC-1271 或 personal-sign 包装摘要——合约会明确拒绝包装后的摘要。

ABI 文件：[../../docs/delivery/abi/ITransferWithAuthorization.abi.json](../../docs/delivery/abi/ITransferWithAuthorization.abi.json)

---

## 镜像清单

[MIRROR_MANIFEST.json](MIRROR_MANIFEST.json) 记录了每个英文源文件的哈希值，用于增量镜像计划。

---

## 说明

- 所有部署、链上浏览器验证和生产密钥操作均为操作员手动执行。本流程不会向任何实时网络广播交易，也不会访问生产密钥。
- 目标链：以太坊主网，Cancun 版本（需要 EIP-1153 瞬态存储）。
- 构建命令：`forge build`。（原私有内部子模块 `lib/smart-wallet-recovery` 及其集成测试 `test/Recovery.t.sol` 已移除，不再需要内部 GitLab 访问权限。）
