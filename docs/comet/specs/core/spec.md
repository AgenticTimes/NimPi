# NPI Convert — Specification

## 目标
为 npi 把消息转换逻辑集中对齐 pi convertToLlm：内部 Message → LLM ChatMessage。

## 范围
- `src/messages.nim` 新增：
  - `convertToLlm(messages: seq[Message]): seq[ChatMessage]`：
    - mkUser → user
    - mkAssistant → assistant（含 toolCalls 提取，对齐 pi）
    - mkToolResult → tool（toolCallId/toolName/content）
    - 其它/compactionSummary → 跳过或 user（对齐 pi）
- npi.nim 的 historyToChat 改为调用 convertToLlm（移除重复逻辑）

## 非目标
- bashExecution/custom/branchSummary 消息类型 —— 后续
- wire 格式 provider 差异 —— 已由 llm.nim 处理

## 验收
- [ ] convertToLlm user 消息
- [ ] assistant 含 toolCalls 提取
- [ ] tool 消息（toolCallId/toolName）
- [ ] npi.nim 复用 convertToLlm
- [ ] 单测覆盖
