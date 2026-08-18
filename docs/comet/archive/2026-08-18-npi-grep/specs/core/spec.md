# NPI Grep — Specification

## 目标
为 npi 的 grep 工具实现纯 Nim 核心搜索，对齐 pi `grep.ts`：不依赖 shell grep，直接按行搜索。

## 范围
- `src/grep.nim`：
  - `GrepOptions`：pattern、path、caseSensitive、fixedString（正则或字面）、context（前后行数）、maxMatches
  - `grepFile(path, opts)`：按行搜索，返回匹配行 + 行号
  - `grepPath(path, opts)`：遍历目录（跳过 .git/隐藏），聚合匹配
  - 输出格式 `path:line:text`（对齐 pi）
  - 行截断到 GREP_MAX_LINE_LENGTH（500）附 [truncated]；匹配上限限制
- 接入 agent.nim 的 grep 工具：优先 grepPath，路径不存在/目录退化为原逻辑

## 非目标
- .gitignore 解析 —— 后续
- 二进制文件过滤 —— 后续
- 多目录 glob —— 后续

## 验收
- [ ] grepFile 返回匹配行+行号
- [ ] path:line:text 输出格式
- [ ] fixedString / caseSensitive / 正则支持
- [ ] context 上下文行
- [ ] 匹配上限 + 行截断
- [ ] grepPath 遍历目录
- [ ] 单测覆盖
