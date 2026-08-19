# NPI ConfigIntegrate2 — Specification

## 目标
把 modelconfig/authstorage 接入 llm 初始化（对齐 pi 的模型/provider 配置用途），消除 0-ref。

## 范围
- `llm.nim`：`newLlmClient` 可选接受 models.json 配置——provider 配置的 baseUrl/apiKey 优先（有则用）
- `npi.nim` main：加载 models.json（NPI_MODELS 环境变量/默认），provider 配置的 contextWindow 传入 compaction
- authstorage 供 CLI 凭据（可选，credentials 已覆盖）

## 非目标
- 完整配置系统 —— provider 配置字段最小接入
- credentials/diagnostics/exec 接入 —— 独立 API

## 验收
- [ ] newLlmClient 用 provider 配置 baseUrl/apiKey
- [ ] main 加载 models.json
- [ ] contextWindow 到 compaction
- [ ] 现有单测全绿
- [ ] 集成单测
