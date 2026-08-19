# NPI Attribution — Specification

## 目标
为 npi 实现 provider 归属判定与 attribution header 生成（对齐 pi provider-attribution.ts）。

## 范围
- `src/attribution.nim`：
  - `matchesHost(baseUrl, expectedHost)`：解析 host 匹配（简化，字符串包含）
  - 归属判定：isOpenRouter/isNvidiaNim/isCloudflare/isOpenCode（provider 名或 baseUrl host）
  - `mergeProviderAttributionHeaders(provider, baseUrl, sessionId, enabled)`：合并归属 header
- 接入：llm 请求头（可选，enabled 开关）

## 非目标
- URL 严格解析 —— host 包含匹配
- telemetry 设置集成 —— enabled 参数

## 验收
- [ ] matchesHost 判定
- [ ] openrouter 归属 + header
- [ ] nvidia 归属 + header
- [ ] cloudflare 归属 + header
- [ ] opencode session header
- [ ] 未启用/未知 provider 无 header
- [ ] 单测覆盖
