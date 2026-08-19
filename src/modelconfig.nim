## 模型配置：对齐 pi `model-config.ts` 的 ModelDefinitionSchema / ProviderConfigSchema 核心字段。
## 模型 + provider 数据结构、models.json 解析（无 typebox 校验，缺省用默认）。

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

  ProviderDefinition* = object
    name*: string
    baseUrl*: string
    apiKey*: string
    api*: string
    oauth*: string          ## "radius"
    authHeader*: bool
    headers*: Table[string, string]
    models*: seq[ModelDefinition]

  ModelConfig* = object
    models*: seq[ModelDefinition]
    providers*: seq[ProviderDefinition]
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

proc parseHeaders(j: JsonNode): Table[string, string] =
  result = initTable[string, string]()
  if j.isNil or j.kind != JObject: return
  for k, v in j:
    if v.kind == JString:
      result[k] = v.str

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
    headers: parseHeaders(j{"headers"}))

proc parseProviderDefinition*(j: JsonNode): ProviderDefinition =
  ## 提取 provider 字段（对齐 pi ProviderConfigSchema 核心）。
  result = ProviderDefinition(
    name: j{"name"}.getStr(""),
    baseUrl: j{"baseUrl"}.getStr(""),
    apiKey: j{"apiKey"}.getStr(""),
    api: j{"api"}.getStr(""),
    oauth: j{"oauth"}.getStr(""),
    authHeader: j{"authHeader"}.getBool,
    headers: parseHeaders(j{"headers"}),
    models: @[])
  let ms = j{"models"}
  if not ms.isNil and ms.kind == JArray:
    for m in ms:
      if m.kind == JObject:
        result.models.add parseModelDefinition(m)

proc loadModelsJson*(path: string): ModelConfig =
  ## 读 models.json → 模型/provider 列表（对齐 pi loadModels，无 schema 校验）。
  result = ModelConfig(models: @[], providers: @[], sourcePath: path)
  if not fileExists(path):
    return
  let content = readFile(path)
  let j = parseJson(content)
  # providers 表（对齐 ModelsConfigSchema）
  let provs = j{"providers"}
  if not provs.isNil and provs.kind == JObject:
    for pid, pdef in provs:
      if pdef.kind == JObject:
        var p = parseProviderDefinition(pdef)
        if p.name.len == 0:
          p.name = pid
        result.providers.add p
  # models 表
  let models = j{"models"}
  if models.isNil or models.kind != JObject:
    return
  for id, def in models:
    if def.kind != JObject: continue
    var m = parseModelDefinition(def)
    if m.id.len == 0:
      m.id = id
    result.models.add m

proc findProvider*(config: ModelConfig, id: string): Option[ProviderDefinition] =
  ## 按 id 查找 provider（无则 none）。
  for p in config.providers:
    if p.name == id:
      return some(p)
  none(ProviderDefinition)

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