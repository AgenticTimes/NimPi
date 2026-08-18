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
npi --provider anthropic "用 Claude 处理"   # Anthropic (需 ANTHROPIC_API_KEY)
npi --api-key sk-...                           # 覆盖 OPENAI_API_KEY / ANTHROPIC_API_KEY
npi --no-session                               # 不落盘
```

## Provider

支持两家 LLM provider，用 `--provider` 或环境变量 `NPI_PROVIDER` 切换：

| provider | 默认模型 | API key | endpoint |
|----------|----------|---------|----------|
| `openai`（默认） | `gpt-4o-mini` | `OPENAI_API_KEY` | OpenAI Chat Completions |
| `anthropic` | `claude-sonnet-4-5` | `ANTHROPIC_API_KEY` | Anthropic Messages API (`/v1/messages`) |
| `gemini` | `gemini-2.0-flash` | `GEMINI_API_KEY` | Gemini `streamGenerateContent` |

```bash
NPI_PROVIDER=anthropic npi -p "修复这个 bug"
```

TUI 交互：输入 Enter 发送（流式渲染），↑/↓ 滚动，Ctrl+C 退出。

## 架构

```
src/
  npi.nim          CLI 入口 + agent 循环驱动（连接 LLM/tools/会话/TUI/REPL）
  types.nim        Message/Role/Content/ToolCall/Usage（对齐 pi-ai wire）
  llm.nim          三 provider 流式（openai/anthropic/gemini）
  agent.nim        工具集（read/write/edit/bash/ls/grep/find）
  session.nim      JSONL 会话读写
  tui.nim          illwill 全屏界面（消息区/输入/滚动）
  skills.nim       Agent Skills：发现 SKILL.md + frontmatter + XML 注入（对齐 pi skills.ts）
  compaction.nim   上下文压缩：token 估算/切点/摘要化（对齐 pi compaction.ts）
  slash.nim        slash 命令系统（注册表+解析+分发）
  templates.nim    prompt 模板：参数解析+占位符替换+展开（对齐 pi prompt-templates.ts）
  modelresolver.nim 模型解析：provider/model:thinking+默认回退（对齐 pi model-resolver.ts）
```

## 能力

- **Skills**：放入 `.npi/skills/<name>/SKILL.md`，自动注入 system prompt（XML 格式）；`disable-model-invocation: true` 不注入。
- **Compaction**：长会话超过 context window 自动把早期消息压缩为摘要；`NPI_CONTEXT_WINDOW` 可配。
- **Slash 命令**：TUI/REPL 里 `/model`、`/compact`、`/session`、`/quit`、`/help` 等。
- **Prompt 模板**：`.npi/prompts/<name>.md`（frontmatter+body），输入 `/name args` 展开；支持 `$1` `$@` `${@:N:L}` `${N:-default}`。
- **Model 解析**：`--model anthropic/sonnet:high` 可切 provider+thinking；未指定按 provider 默认。

## 测试

```bash
nim c -r --path:$(dirname $(ls ~/.nimble/pkgs2/illwill-*/ 2>/dev/null | head -1)) tests/test_core.nim   # 39 测试
```

## 会话

默认存到 `./.npi/sessions/session-<ts>.jsonl`，用 `NPI_SESSION_DIR` 覆盖；`-r` 恢复最近。

## 开发

- 环境变量：`OPENAI_API_KEY`/`ANTHROPIC_API_KEY`/`GEMINI_API_KEY`、`NPI_MODEL`、`NPI_BASE_URL`、`NPI_PROVIDER`、`NPI_SESSION_DIR`、`NPI_CONTEXT_WINDOW`、`NPI_AGENT_DIR`
- comet 工作流归档见 `docs/comet/archive/`（8 个 change）
