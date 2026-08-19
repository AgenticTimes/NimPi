# NPI ModelConfig — Specification

## 目标
为 npi 实现模型配置解析（对齐 pi model-config.ts 的 ModelDefinitionSchema 核心字段）。

## 范围
- `src/modelconfig.nim`：
  - `ModelCost`：input/output/cacheRead/cacheWrite
  - `ModelDefinition`：id/name/api/baseUrl/reasoning/cost/contextWindow/maxTokens/headers
  - `parseModelDefinition(j)`：从 JSON 提取字段（无 typebox 校验，缺省用默认）
  - `loadModelsJson(path)`：读 models.json → seq[ModelDefinition]
- 接入（可选）：modelresolver 用 contextWindow

## 非目标
- typebox schema 校验 —— 提取字段即可
- provider 配置（ProviderConfigSchema）—— 仅模型定义
- thinkingLevelMap/compat —— 后续

## 验收
- [ ] ModelDefinition 字段解析
- [ ] cost 嵌套解析
- [ ] models.json 加载
- [ ] 缺字段用默认
- [ ] 单测覆盖
