# NPI Truncate — Specification

## 目标
为 npi 实现工具输出的智能截断，对齐 pi `tools/truncate.ts`：行数与字节双限制，先到先截。

## 范围
- `src/truncate.nim`：
  - `TruncationOptions`（maxLines=2000, maxBytes=50KB）
  - `truncateHead(content)`:保留开头 N 行/字节（文件读取），不返回半行
  - `truncateTail(content)`:保留末尾 N 行/字节（bash 输出，保留错误信息）
  - `formatSize(bytes)`: B/KB/MB 人类可读
- 接入 agent.nim：read 用 truncateHead，bash 用 truncateTail（替换现在 50000 硬截断）

## 非目标
- 超大输出的临时文件 offload（fullOutputPath）—— 后续
- ANSI/二进制清理 —— 后续（单独 shell 清理）
- grep 行内截断 —— 后续

## 验收
- [ ] truncateHead 保留开头，超限标记
- [ ] truncateTail 保留结尾，超限标记
- [ ] 行数/字节限制先到先截
- [ ] formatSize 格式正确
- [ ] read/bash 工具接入
- [ ] 单测覆盖
