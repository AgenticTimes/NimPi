# NPI Slash — Specification

## 目标
为 npi 实现 slash 命令系统：用户以 `/cmd [arg]` 输入命令，TUI 与 REPL 统一解析分发，而非硬编码个别命令。

## 范围
- `src/slash.nim`：
  - `SlashCommand` 类型（name/description/argumentHint/handler）
  - 内置命令注册表：quit、help、model、compact、new、resume、session
  - `parseSlash`：把输入分成 (command, argument)，仅当以 `/` 开头
  - `handleSlash`：分发到命令处理器
- TUI 与 REPL 统一：输入以 `/` 开头且是已知命令 → 执行命令；否则走对话
- 暴露 `help` 列出全部命令（对齐 pi BUILTIN_SLASH_COMMANDS 风格）

## 非目标
- extensions/prompt/skill 来源命令注册 —— 后续 change
- 菜单/选择器 UI（model 选择器、session 树）—— 后续 change
- export 到 HTML / gist share —— 后续 change

## 验收
- [ ] 内置命令注册表含 quit/help/model/compact/new/resume/session
- [ ] parseSlash 正确拆分命令与参数（/cmd、/cmd arg）
- [ ] 非 `/` 开头输入不被当作命令
- [ ] 未知命令给出提示不崩溃
- [ ] TUI 里 /quit 退出、/help 列命令
- [ ] REPL 同样支持命令
- [ ] 单测覆盖解析与分发
