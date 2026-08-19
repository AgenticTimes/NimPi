# NPI UsageIntegrate — Specification

## 目标
把 usagetotals/cachestats 接入 agent 运行路径，消除孤岛模块。

## 范围
- `Agent` 增加：`usageTotals: UsageTotals`、`cacheWaste: CacheWaste`、`lastRequest: PreviousRequest`、`usageStartMs: int`
- runConversation：seEnd 时累计 usageTotals、检测 cache miss（detectMiss + addMiss）、更新 lastRequest
- 提供 `usageSummary(agent)` 便捷输出

## 非目标
- UI 展示 —— 提供数据
- 成本模型 —— 无

## 验收
- [ ] Agent 字段齐全
- [ ] 每轮 usage 累计
- [ ] cache miss 检测接入
- [ ] lastRequest 更新
- [ ] usageSummary 输出
- [ ] 现有单测全绿
- [ ] 集成单测
