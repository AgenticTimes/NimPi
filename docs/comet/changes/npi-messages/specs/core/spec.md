# NPI Messages — Specification

## 目标
为 npi 的 compaction 摘要对齐 pi 的标准格式：`<summary>` XML 包裹，替代当前无格式前缀拼接。

## 范围
- `src/messages.nim`：
  - `COMPACTION_SUMMARY_PREFIX/SUFFIX` 常量（对齐 pi）
  - `formatCompactionSummary(summary)`：`PREFIX + summary + SUFFIX`
  - `createCompactionSummaryMessage(summary, tokensBefore)`：返回带摘要的消息（对齐 pi 结构）
- 接入 compaction.nim：prepareCompaction 的 summary 用 formatCompactionSummary 包裹

## 非目标
- bashExecution/custom/branchSummary 消息类型 —— 后续
- convertToLlm 全量 —— 后续

## 验收
- [ ] COMPACTION_SUMMARY_PREFIX/SUFFIX 常量与 pi 一致
- [ ] formatCompactionSummary 用 <summary> 包裹
- [ ] createCompactionSummaryMessage 含 summary+tokensBefore
- [ ] compaction 摘要接入新格式
- [ ] 单测覆盖
