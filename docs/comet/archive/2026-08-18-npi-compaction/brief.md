# NPI Compaction — Brief

为 npi 实现 pi 的上下文压缩（compaction）：估算 context tokens、超阈值时把最早的对话压缩为摘要保留最新，避免长会话 token 耗尽。对齐 pi compaction.ts 纯函数。
