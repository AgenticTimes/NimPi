# NPI Core — Specification

## 目标
在 `npi/` 用 Nim 实现极简编码 agent，对齐 `mpi`（MoonBit）主链路，带 TUI。

## 范围
- CLI：`-p`(print) / 默认 TUI / stdin 非 TTY 退化为 REPL；`-r` 恢复会话
- LLM：OpenAI 兼容流式（SSE 解析），多轮工具调用
- 工具：read / write / edit / bash / ls / grep / find
- 会话：JSONL 落盘（`.npi/sessions/`）
- TUI：illwill 全屏，消息区 + 输入 + 滚动

## 非目标
- 多 provider（Anthropic/Gemini）——后续迭代
- 会话压缩 / extensions / RPC ——后续迭代

## 验收
- [ ] `npi -p "cmd"` 流式输出后退出
- [ ] mock SSE 下 agent 循环可完成 文本→工具→结果→最终文本
- [ ] 会话 JSONL 落盘完整（含工具调用与结果）
- [ ] 7 个核心单测全绿
- [ ] TUI 启动/退出不崩溃，输入可发送
