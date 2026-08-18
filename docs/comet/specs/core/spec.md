# NPI Find — Specification

## 目标
为 npi 的 find 工具实现纯 Nim 文件查找，对齐 pi `find.ts`：不依赖 shell find。

## 范围
- `src/find.nim`：
  - glob 匹配：`*`（段内任意）、`?`（单字符）、`**`（多级）
  - `findPath(pattern, root)`：递归遍历，返回相对路径列表
  - 跳过隐藏目录/文件（对齐 pi 尊重忽略）
  - 结果上限（默认 50，对齐 find limit）
  - 排序稳定
- 接入 agent.nim 的 find 工具：替换 shell find

## 非目标
- .gitignore 解析 —— 后续
- 完整 glob 库（brace/character class）—— 后续
- fd 集成 —— 后续

## 验收
- [ ] glob `*` / `?` 匹配
- [ ] `**` 多级递归匹配
- [ ] findPath 返回相对路径
- [ ] 跳过隐藏目录/文件
- [ ] 结果上限
- [ ] agent find 工具接入
- [ ] 单测覆盖
