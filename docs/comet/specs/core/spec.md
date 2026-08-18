# NPI Providers — Specification

## 目标
为 npi 增加第二家 LLM provider（Anthropic），与现有 OpenAI 兼容 provider 并存、可切换。

## 范围
- `LlmClient` 抽象 provider 类型：`openai` 与 `anthropic`
- Anthropic Messages API 流式（SSE `content_block_delta`），支持文本与 `tool_use` 工具调用
- CLI `--provider anthropic` 与 `NPI_PROVIDER` 环境变量切换
- 复用现有 agent 循环/工具/会话，不改动其接口

## 非目标
- Gemini / Mistral 等多 provider —— 后续 change
- 会话压缩 / extensions / RPC —— 后续 change

## 验收
- [ ] `--provider anthropic` 可切换，默认仍为 openai
- [ ] Anthropic 流式文本解析（content_block_delta text_delta）
- [ ] Anthropic `tool_use` 工具调用可被 agent 循环执行并回填 tool_result
- [ ] 用 mock Anthropic SSE 验证端到端 agent 循环 2 轮
- [ ] 现有单元测试仍全绿
