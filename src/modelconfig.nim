## 模型配置：对齐 pi `model-config.ts` 的 ModelDefinitionSchema 核心字段。
## 模型数据结构 + models.json 解析（无 typebox 校验，提取字段用默认）。

import std/[os, json, tables, options]

type
  ModelCost* = object
    input*: float          ## $/M tokens
    output*: float
    cacheRead*: float
    cacheWrite*: float

  ModelDefinition* = object
    id*: string
    name*: string
    api*: string
    baseUrl*: string
    reasoning*: bool
    cost*: ModelCost
    contextWindow*: int
    maxTokens*: int
    headers*: Table[string, string]

  ModelConfig* = object
    models*: seq[ModelDefinition]
    sourcePath*: string

proc emptyModelCost*(): ModelCost =
  ModelCost(input: 0.0, output: 0.0, cacheRead: 0.0, cacheWrite: 0.0)

proc parseModelCost*(j: JsonNode): ModelCost =
  ## 解析 cost（$M tokens，对齐 pi ModelCostSchema）。
  result = emptyModelCost()
  if j.isNil: return
  result.input = j{"input"}.getFloat(0.0)
  result.output = j{"output"}.getFloat(0.0)
  result.cacheRead = j{"cacheRead"}.getFloat(0.0)
  result.cacheWrite = j{"cacheWrite"}.getFloat(0.0)

proc parseModelDefinition*(j: JsonNode): ModelDefinition =
  ## 从 JSON 提取模型字段（对齐 pi ModelDefinitionSchema 核心，缺省用默认）。
  result = ModelDefinition(
    id: j{"id"}.getStr(""),
    name: j{"name"}.getStr(""),
    api: j{"api"}.getStr(""),
    baseUrl: j{"baseUrl"}.getStr(""),
    reasoning: j{"reasoning"}.getBool,
    cost: parseModelCost(j{"cost"}),
    contextWindow: j{"contextWindow"}.getInt(0),
    maxTokens: j{"maxTokens"}.getInt(0),
    headers: initTable[string, string]())
  let h = j{"headers"}
  if not h.isNil and h.kind == JObject:
    for k, v in h:
      if v.kind == JString:
        result.headers[k] = v.str

proc loadModelsJson*(path: string): ModelConfig =
  ## 读 models.json → 模型列表（对齐 pi loadModels，无 schema 校验）。
  result = ModelConfig(models: @[], sourcePath: path)
  if not fileExists(path):
    return
  let content = readFile(path)
  let j = parseJson(content)
  # models.json 结构：{"models": {"<id>": {...}}}
  let models = j{"models"}
  if models.isNil or models.kind != JObject:
    return
  for id, def in models:
    if def.kind != JObject: continue
    var m = parseModelDefinition(def)
    if m.id.len == 0:
      m.id = id
    result.models.add m

proc findModel*(config: ModelConfig, id: string): Option[ModelDefinition] =
  ## 按 id 查找模型（无则 none）。
  for m in config.models:
    if m.id == id:
      return some(m)
  none(ModelDefinition)

proc contextWindowFor*(config: ModelConfig, id: string, default: int = 200000): int =
  ## 模型的 contextWindow（无则默认，衔接 compaction）。
  let m = findModel(config, id)
  if m.isSome and m.get.contextWindow > 0:
    m.get.contextWindow
  else:
    default