# NPI BashTimeout — Specification

## 目标
为 npi 的 bash 工具实现超时控制（对齐 pi bash-executor 的 timeout/取消语义），命令挂死可终止。

## 范围
- `src/bashtimeout.nim`：
  - `BashTimeoutOptions`：timeoutMs（默认 120000，对齐 pi）、cwd
  - `execBashWithTimeout(cmd, opts)`：startProcess(/bin/sh -c) + poll 轮询，超时 terminate+kill 进程树，输出经临时文件收集
  - 返回 (output, exitCode, timedOut)
- 接入 agent.nim 的 bash 工具：替换 execCmdEx

## 非目标
- 流式输出回调 —— 输出收集即可
- 信号取消（SIGINT 触发）—— 仅超时
- Windows 兼容 —— macOS/Linux

## 验收
- [ ] 正常命令返回输出+退出码
- [ ] 超时命令被终止并标记 timedOut
- [ ] 超时后子进程也被杀（进程树）
- [ ] 输出完整收集（含 stderr）
- [ ] agent bash 接入
- [ ] 单测覆盖
