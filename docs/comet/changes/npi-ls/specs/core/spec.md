# NPI Ls — Specification

## 目标
为 npi 的 ls 工具实现 pi 的格式语义：排序、目录标记、dotfiles、上限。

## 范围
- `src/lsdir.nim`：
  - `listDir(path, limit)`：读取目录项，字母序排序，目录加 `/` 后缀，含 dotfiles
  - 条目上限（默认 500，对齐 pi DEFAULT_LIMIT）
  - 输出经 truncateHead 字节截断（50KB）
  - 返回条目 + 截断/上限通知
- 接入 agent.nim 的 ls 工具：替换无格式 walkDir

## 非目标
- 符号链接解析 —— 后续
- 递归列目录 —— 后续

## 验收
- [ ] 字母序排序
- [ ] 目录加 / 后缀
- [ ] 含 dotfiles
- [ ] 条目上限
- [ ] truncateHead 截断
- [ ] agent ls 接入
- [ ] 单测覆盖
