# NPI ProviderConfig — Specification

## 目标
为 npi 补全模型配置的 provider 层（对齐 pi ProviderConfigSchema 核心字段）。

## 范围
- `src/modelconfig.nim` 扩展：
  - `ProviderDefinition`：name/baseUrl/apiKey/api/oauth/headers/authHeader/models
  - `parseProviderDefinition(j)`：提取字段
  - `loadModelsJson` 扩展：解析 providers 表
  - `findProvider(config, id)`
- 接入（可选）：llm 用 provider 配置的 baseUrl/apiKey

## 非目标
- compat/thinkingLevelMap —— 后续
- modelOverrides —— 后续

## 验收
- [ ] ProviderDefinition 字段解析
- [ ] providers 表解析
- [ ] findProvider
- [ ] headers 解析
- [ ] 单测覆盖
