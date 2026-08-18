# NPI Gemini — Specification

## 目标
为 npi 增加 Google Gemini provider，支持流式推理与函数调用，验证 provider 抽象的三家横向扩展。

## 范围
- `LlmClient` provider 增加 `gemini` 分支
- Gemini API `generateContent` 流式（SSE/`streamGenerateContent`），支持 content/functionCall
- CLI `--provider gemini` / `NPI_PROVIDER=gemini` 切换，默认 openai
- 复用 agent 循环/工具/会话，不改接口

## 非目标
- Mistral 等更多 provider —— 后续 change
- 会话压缩 / extensions / RPC —— 后续 change

## 验收
- [ ] `--provider gemini` 可切换，默认仍 openai
- [ ] Gemini 流式文本解析（text 增量）
- [ ] Gemini `functionCall` 工具调用可执行并回填 `functionResponse`
- [ ] mock Gemini SSE 端到端 agent 循环 2 轮
- [ ] 现有单测仍全绿（10 项及以上）
