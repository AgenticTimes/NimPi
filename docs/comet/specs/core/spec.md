# NPI Glob — Specification

## 目标
为 npi find 工具的 glob 补全 brace 展开与字符类支持（对齐 glob 库常用子集）。

## 范围
- `src/glob.nim`（或增强 find.nim）：
  - brace 展开：`{a,b}` → `(a|b)` 正则
  - 字符类：`[abc]`、`[a-z]`、`[!abc]`（取反）
  - 与现有 `*`/`?`/`**` 组合
- 接入 findPath 的 globToRegex

## 非目标
- 嵌套 brace —— 单层即可
- extglob —— 后续

## 验收
- [ ] brace {a,b} 匹配
- [ ] 字符类 [abc] 匹配
- [ ] 区间 [a-z]
- [ ] 取反 [!abc]
- [ ] 与 * 组合
- [ ] 单测覆盖
