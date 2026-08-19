# NPI Fuzzy — Specification

## 目标
把 pi fuzzy.ts 的模糊匹配逻辑完整移植到 Nim（fzf 风格：低分更优）。

## 范围
- `src/fuzzy.nim`：
  - `FuzzyMatch`（matches/score）
  - `fuzzyMatch(query, text)`：小写、顺序子序列；连续奖励 -5/个、间隙惩罚 +2/char、词边界 -10、位置 +0.1*i、完全匹配 -100；字母数字交换变体
  - `fuzzyFilter[T](items, query, getText)`：空白/slash token 化，全 token 匹配才保留，按总分升序

## 非目标
- TUI 接入（选择器/命令面板）—— 后续 change

## 验收
- [ ] 空 query 匹配 score 0
- [ ] 顺序子序列匹配
- [ ] 顺序错误不匹配
- [ ] 完全匹配最低分
- [ ] 字母数字交换变体
- [ ] token 过滤（多 token 全匹配）
- [ ] 排序（最优在前）
- [ ] 单测覆盖
