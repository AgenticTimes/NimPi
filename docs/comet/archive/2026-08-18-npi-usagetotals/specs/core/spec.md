# NPI UsageTotals — Specification

## 目标
为 npi 实现 token 用量累计与成本分解（对齐 pi usage-totals.ts）。

## 范围
- `src/usagetotals.nim`：
  - `UsageTotals`：input/output/cacheRead/cacheWrite/cost
  - `createUsageTotals()`、`addUsageToTotals(totals, usage)` 累计
  - `getUsageCostBreakdown(entries)`：按 provider/model 分组统计 token+cost，过滤 0，按 cost 降序
- 接入：runConversation 每轮 assistant usage 累计（可选，先提供纯函数）

## 非目标
- 会话条目类型全量 —— 用简化 entry（provider/model/usage）
- 成本模型 —— 用 usage.cost 输入

## 验收
- [ ] createUsageTotals 全 0
- [ ] addUsageToTotals 正确累计
- [ ] getUsageCostBreakdown 按 model 分组
- [ ] 过滤 0 成本/0 token
- [ ] 按 cost 降序
- [ ] 单测覆盖
