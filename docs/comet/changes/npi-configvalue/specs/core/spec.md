# NPI ConfigValue — Specification

## 目标
为 npi 实现配置值解析（对齐 pi resolve-config-value.ts）：支持环境变量、shell 命令、字面量的配置模板。

## 范围
- `src/configvalue.nim`：
  - `parseConfigValueTemplate(config)`：解析 `$ENV`、`${ENV}`、`$!cmd`、`$$`/`$!` 字面、混合字面量
  - `resolveConfigValue(config, env)`：env 查找 + 命令执行（$! 前缀）+ 结果缓存
  - `getConfigValueEnvVarNames` / `isConfigValueConfigured` / `getMissingConfigValueEnvVarNames`
- 接入：CLI apiKey 解析可用（可选）

## 非目标
- 完整 shell 执行安全 —— 命令由用户配置提供
- resolveHeaders —— 后续

## 验收
- [ ] 解析 $ENV 字面
- [ ] 解析 ${ENV}
- [ ] $!cmd 命令执行
- [ ] $$ / $! 字面转义
- [ ] 混合模板
- [ ] env 未配置返回 missing
- [ ] 单测覆盖
