# NPI Settings — Specification

## 目标
为 npi 实现设置结构（对齐 pi settings-manager.ts 的 Settings 接口 + 默认值 + deepMerge）。

## 范围
- `src/settings.nim`：
  - `CompactionSettings`/`BranchSummarySettings`/`RetrySettings`/`TerminalSettings`/`MarkdownSettings`
  - `Settings`：defaultProvider/defaultModel/compaction/retry/terminal/markdown/showCacheMissNotices 等核心字段
  - `defaultSettings()`：默认值（compaction reserve 16384/keepRecent 20000、retry maxRetries 3/baseDelay 2000、terminal showImages true）
  - `deepMergeSettings(base, overrides)`：递归合并（nested 对象）
- 接入（可选）：agent 用 settings.compaction 替代硬编码

## 非目标
- 全量 Settings（packages/extensions/themes 等）—— 核心子集
- 文件读写/persistence —— 仅结构+合并

## 验收
- [ ] 各 settings 结构字段
- [ ] defaultSettings 默认值
- [ ] deepMerge 递归合并
- [ ] 覆盖优先级正确
- [ ] 单测覆盖
