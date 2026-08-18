# NPI PathUtils — Specification

## 目标
为 npi 实现路径解析（对齐 pi path-utils.ts）：用户输入的路径规范化与容错解析。

## 范围
- `src/pathutils.nim`：
  - `expandPath(p)`：~ 展开、去 @ 前缀、unicode 空格归一（\u202F → 普通空格）
  - `resolveToCwd(p, cwd)`：相对 cwd 解析（含 ~/绝对路径）
  - `resolveReadPath(p, cwd)`：解析后若不存在，尝试 macOS 变体（AM/PM 窄空格、NFD、弯引号）
- 接入 read 工具（可选）：resolveReadPath 用于读路径

## 非目标
- 完整 unicode 规范化（NFD 转换需要 unicode 库）—— 基本变体即可
- 异步版本 —— 同步即可

## 验收
- [ ] expandPath ~ 展开 + @ 前缀去除
- [ ] resolveToCwd 相对/绝对/~ 解析
- [ ] resolveReadPath macOS AM/PM 变体
- [ ] resolveReadPath 弯引号变体
- [ ] 单测覆盖
