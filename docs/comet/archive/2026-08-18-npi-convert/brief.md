# NPI Convert — Brief

为 npi 实现 convertToLlm 对齐：把内部 Message 转为 LLM wire ChatMessage（user/assistant+toolCalls/tool），集中到 messages.nim 复用。对齐 pi convertToLlm。
