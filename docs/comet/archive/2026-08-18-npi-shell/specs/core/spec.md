# NPI Shell — Specification

## 目标
为 npi 的工具输出做字符清理：移除会破坏显示或存储的控制字符与 ANSI 转义序列。对齐 pi `sanitizeBinaryOutput` 与 `stripAnsi`。

## 范围
- `src/shell.nim`：
  - `stripAnsi(s)`：移除 ANSI/OSC/CSI 转义序列（ESC/C1 引入），对齐 pi ansiRegex
  - `sanitizeBinaryOutput(s)`：过滤控制字符（保 tab/newline/CR）、unicode 格式字符（0xfff9-0xfffb）
  - `sanitizeShellOutput(s)`：stripAnsi + sanitize + 去 \r（对齐 bash-executor onData 链）
- 接入 agent.nim 的 bash 工具：输出经 sanitizeShellOutput 后再 truncateTail

## 非目标
- shell 解析/子进程管理 —— 已有 execCmdEx
- 进程树杀死 —— 后续

## 验收
- [ ] stripAnsi 移除 ANSI 颜色/控制序列
- [ ] stripAnsi 保留普通文本
- [ ] sanitizeBinaryOutput 过滤控制字符（保 tab/newline/CR）
- [ ] 过滤 unicode 格式字符
- [ ] bash 工具经 sanitizeShellOutput 清理
- [ ] 单测覆盖
