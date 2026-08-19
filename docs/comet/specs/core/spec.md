# NPI CredIntegrate — Specification

## 目标
把 credentials 模块接入 CLI 凭据解析（对齐 pi 的 RuntimeCredentials 用法：运行时覆盖 + 持久 store）。

## 范围
- `npi.nim` main：凭据解析统一走 RuntimeCredentials
  - baseLookup：auth.json（持久）+ env
  - 覆盖：--api-key 显式（setRuntimeApiKey）
  - read(provider) 返回最终 key
- 简化现有 authintegrate 的分支逻辑

## 非目标
- diagnostics/exec 接入 —— 独立 API
- 凭据写入 CLI —— 后续

## 验收
- [ ] RuntimeCredentials 组合解析
- [ ] --api-key 覆盖最高
- [ ] auth.json 次之
- [ ] env 兜底
- [ ] 现有单测全绿
- [ ] 集成单测
