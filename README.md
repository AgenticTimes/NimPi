# npi — 极简编码 agent（Nim）

用 [Nim](https://nim-lang.org/) 编写的极简编码 agent，二进制名 `npi`。对齐 pi-coding-agent 的主链路（agent 循环 + 工具 + LLM 流式），带全屏 TUI。

- **产品形态参照**：[earendil-works/pi](https://github.com/earendil-works/pi)（终端编码 agent）
- **工程参照**：`mpi`（MoonBit）/ `mpi-rust`（Rust）同族实现

## 安装

需要 [Nim 工具链](https://nim-lang.org/install.html)（验证版本 2.2.10）。

```bash
nimble install -y          # 首次：装依赖（illwill）
cd npi && nimble build
# 产物：./npi
alias npi="$PWD/npi"
```

## 使用

```bash
npi -p "修复这个 bug"                          # print：流式输出后退出
npi -r                                         # 恢复最近会话
npi                                            # 默认 TUI；stdin 非 TTY 退化为 REPL
npi --model gpt-4o-mini --base-url https://api.openai.com/v1 "你好"
npi --api-key sk-...                           # 覆盖 OPENAI_API_KEY
npi --no-session                               # 不落盘
```

TUI 交互：输入 Enter 发送（流式渲染），↑/↓ 滚动，Ctrl+C 退出。

## 架构

```
src/
  npi.nim     CLI 入口 + agent 循环驱动（连接 LLM/tools/会话/TUI）
  types.nim   Message/Role/Content/ToolCall/Usage（对齐 pi-ai wire）
  llm.nim     OpenAI 兼容流式（SSE 解析）
  agent.nim   工具集（read/write/edit/bash/ls/grep/find）
  session.nim JSONL 会话读写
  tui.nim     illwill 全屏界面（消息区/输入/滚动）
```

## 测试

```bash
nim c -r --path:$(dirname $(ls ~/.nimble/pkgs2/illwill-*/ 2>/dev/null | head -1)) tests/test_core.nim
```

## 会话

默认存到 `./.npi/sessions/session-<ts>.jsonl`，用 `NPI_SESSION_DIR` 覆盖。

## 开发

- 环境变量：`OPENAI_API_KEY` / `NPI_API_KEY`、`NPI_MODEL`、`NPI_BASE_URL`、`NPI_SESSION_DIR`
- comet 工作流 change 见 `docs/comet/changes/`
