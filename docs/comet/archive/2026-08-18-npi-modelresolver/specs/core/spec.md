# NPI ModelResolver — Specification

## 目标
为 npi 实现模型解析与默认回退：把模型模式（`model`、`provider/model`、`model:thinking`）解析为 (model, thinkingLevel)，并支持按 provider 的默认回退。

## 范围
- `src/modelresolver.nim`：
  - `parseModelPattern(pattern)`：递归剥离 `:suffix`，返回 (model, thinkingLevel)
  - `resolveModelSpec(pattern, provider)`：解析 user 提供的模式；无指定 provider 或未匹配用给定默认
  - `defaultModelForProvider(provider)`：默认模型表（openai/anthropic/gemini + 通用），对齐 pi defaultModelPerProvider 子集
- thinking level 校验：`low`/`medium`/`high`（对齐 isValidThinkingLevel）
- 集成：CLI `--model` 解析用 parseModelPattern；未指定时按 provider 默认

## 非目标
- 可用模型列表匹配/最优版本选择（alias vs dated）—— 后续 change
- 完整 known-provider 表 —— 只含 npi 支持的 provider
- thinking level 实际注入 —— 仅解析

## 验收
- [ ] parseModelPattern 剥离 `:suffix`（thinking level）
- [ ] defaultModelForProvider 返回对应默认模型
- [ ] 无效 thinking level 回退默认并警告
- [ ] CLI --model 用解析逻辑
- [ ] 单测覆盖解析/默认/警告
