# NPI CacheStats — Specification

## 目标
为 npi 实现 prompt cache 缺失检测（对齐 pi cache-stats.ts 核心）：判断每轮请求是否有效利用缓存。

## 范围
- `src/cachestats.nim`：
  - `CACHE_TTL_MS` 常量（5 分钟，对齐 pi）
  - `PreviousRequest`：promptTokens/modelKey/timestamp/reportedCache
  - `detectMiss(prev, usage, now)`：missedTokens = min(prev.promptTokens, promptTokens) - cacheRead；低于噪声底线(1024)不计；首轮/无缓存活动不计
  - `CacheWaste` 累计（missedTokens/missCount）
- 接入（可选）：runConversation 每轮检测

## 非目标
- 成本计算（missedCost）—— 无成本模型，简化
- 模型变化检测 —— 简化跳过

## 验收
- [ ] CACHE_TTL_MS 常量
- [ ] detectMiss 首轮不计
- [ ] 缓存命中时 missedTokens 小/0
- [ ] 未命中时 missedTokens = 差值
- [ ] 噪声底线过滤
- [ ] CacheWaste 累计
- [ ] 单测覆盖
