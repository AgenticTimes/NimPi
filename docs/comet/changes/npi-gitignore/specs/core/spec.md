# NPI GitIgnore — Specification

## 目标
为 npi 的 grep/find 工具实现 .gitignore 尊重（对齐 pi：respects .gitignore）。

## 范围
- `src/gitignore.nim`：
  - `GitIgnoreRule`：pattern、negated(!)、anchored(/)等
  - `parseGitIgnore(content)`：逐行解析（注释/空行跳过）
  - `buildIgnoreMatcher(root)`：从 root 向上收集 .gitignore/.ignore/.fdignore 累积规则
  - `isIgnored(path, matcher)`：路径匹配判定（含 ! 取反）
  - glob 匹配复用 find.nim 的 glob 语义（*、**、锚定）
- 接入 grepPath/findPath：跳过 isIgnored 的文件/目录

## 非目标
- 完整 gitignore 规范（! 目录反转、** 特殊语义）—— MVP 子集
- git 内建规则（.git/info/exclude、global）—— 后续

## 验收
- [ ] 解析 .gitignore 规则（注释/空行/!取反/锚定）
- [ ] 沿目录向上累积规则
- [ ] isIgnored 判定匹配
- [ ] ! 取反覆盖
- [ ] grepPath/findPath 跳过忽略
- [ ] 单测覆盖
