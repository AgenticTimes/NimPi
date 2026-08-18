# NPI Compaction — Specification

## 目标
为 npi 实现上下文压缩，长会话超过阈值时自动把最早的 user/assistant/tool 消息压缩为一条摘要，保留最近的消息。

## 范围
- `src/compaction.nim` 纯函数：
  - `estimateTokens(msg)` chars/4 保守启发式（对齐 pi）
  - `estimateContextTokens(messages)` 估算整体 context tokens
  - `shouldCompact(contextTokens, contextWindow, settings)`：contextTokens > window - reserveTokens
  - `findCutPoint(messages, keepRecentTokens)`：从最新往回累积，找到切点（cut point）
  - `prepareCompaction(messages)`：切点前的消息标记为待摘要，返回摘要文本
- 集成到 runConversation：每轮 LLM 调用前估算，超阈值则用 LLM 生成摘要并替换旧消息
- 阈值可配置：窗口默认 200k tokens、reserve 16k、keepRecent 20k（对齐 pi 默认）

## 非目标
- 多轮 split-turn 精确切点 —— 简化为一处切点
- 断点续传/前次摘要迭代 —— 同一会话内单次压缩
- fileOps 操作提取 —— 后续 change

## 验收
- [ ] estimateTokens 用 chars/4 启发式
- [ ] shouldCompact 阈值判定正确（window - reserve）
- [ ] findCutPoint 保留最近 keepRecentTokens，找到切点
- [ ] 超阈值时触发压缩，旧消息替换为摘要
- [ ] 未超阈值不压缩（历史不变）
- [ ] 单测覆盖估算/切点/压缩
