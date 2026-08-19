# NPI Headers — Specification

## 目标
为 npi 补全 header 解析（对齐 pi resolveHeaders）：配置的 header 表用 resolveConfigValue 逐项解析。

## 范围
- `src/headers.nim`（或增强 configvalue.nim）：
  - `resolveHeaders(headers, env)`：逐项 resolve，空值跳过，全空返回 undefined
  - `clearConfigValueCache()`：清命令缓存
- 复用 configvalue.nim 的 resolveConfigValue/命令缓存

## 非目标
- resolveHeadersOrThrow —— 简化，无 throw 版本
- header 大小写规范化 —— 保持原样

## 验收
- [ ] resolveHeaders 逐项解析
- [ ] 空值跳过
- [ ] 全空返回空
- [ ] clearConfigValueCache 清缓存
- [ ] 单测覆盖
