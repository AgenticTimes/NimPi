# NPI SettingsIntegrate — Specification

## 目标
把 settings 模块接入 agent 实际路径，消除 0-ref 孤岛。

## 范围
- `agent.nim` newAgent：compactionSettings 用 settings.defaultSettings().compaction 初始化（映射 reserveTokens/keepRecentTokens/contextWindow）
- npi.nim：agent 创建处不再重复设置 compaction（保留 NPI_CONTEXT_WINDOW 覆盖）

## 非目标
- 完整 settings 加载 —— 用默认值
- exec/diagnostics 接入 —— 独立 API

## 验收
- [ ] newAgent compactionSettings 来自 settings
- [ ] NPI_CONTEXT_WINDOW 仍可覆盖
- [ ] 现有单测全绿
- [ ] 集成单测
