# NPI AuthIntegrate — Specification

## 目标
把 authstorage 接入 CLI apiKey 解析（对齐 pi 凭据层级：运行时覆盖 > auth.json > env）。

## 范围
- `npi.nim` parseArgs/main：apiKey 解析顺序
  1. `--api-key`（运行时覆盖，最高）
  2. auth.json 持久凭据（NPI_AGENT_DIR/auth.json）
  3. env（OPENAI_API_KEY 等）
- 用 RuntimeCredentials 组合（credentials 模块已实现覆盖层）

## 非目标
- 凭据写入 CLI（/auth 命令）—— 后续
- credentials/diagnostics/exec 接入 —— 独立 API

## 验收
- [ ] auth.json 凭据优先于 env
- [ ] --api-key 最高优先
- [ ] 无凭据回退 env
- [ ] 现有单测全绿
- [ ] 集成单测
