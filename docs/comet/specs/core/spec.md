# NPI Binary — Specification

## 目标
为 npi 的 grep/read 工具实现二进制文件检测，跳过二进制避免乱码/爆输出。

## 范围
- `src/binary.nim`：
  - `isBinaryContent(content, sampleLen)`：检测 NUL 字节或控制字符比例超阈值
  - `isBinaryFile(path)`：读前 sample 检测
- 接入 grepFile：二进制文件跳过（不输出乱码）
- 接入 read：二进制提示（可选）

## 非目标
- 完整 magic-number 检测 —— NUL/控制字符足够
- 图片/媒体处理 —— 后续

## 验收
- [ ] NUL 字节检测为二进制
- [ ] 控制字符比例超阈值检测
- [ ] 纯文本非二进制
- [ ] grepFile 跳过二进制
- [ ] 单测覆盖
