# NPI ConfigIntegrate — Specification

## 目标
把 configvalue 的 resolveConfigValue 接入 CLI apiKey 解析，消除 0-ref 孤岛。

## 范围
- `npi.nim` parseArgs：apiKey 获取后用 resolveConfigValue 解析（支持 `$ENV`、`$!cmd`、字面量模板）
- 空 env 时保持原行为

## 非目标
- 完整配置系统 —— 仅 apiKey 模板
- exec/diagnostics 接入 —— 独立 API 模块保留

## 验收
- [ ] apiKey 支持 $ENV 模板
- [ ] apiKey 支持 $!cmd 模板
- [ ] 字面 apiKey 不变
- [ ] 现有单测全绿
- [ ] 集成单测
