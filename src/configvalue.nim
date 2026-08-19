## 配置值解析：对齐 pi `resolve-config-value.ts`。
## 支持 $ENV / ${ENV} / $!cmd 命令 / $$ $! 字面 / 混合模板。

import std/[strutils, tables, osproc]

type
  TemplatePartKind* = enum
    tpLiteral, tpEnv

  TemplatePart* = object
    kind*: TemplatePartKind
    value*: string       ## literal 文本 或 env 名

  ConfigValueRefKind = enum
    cvrTemplate, cvrCommand

  ConfigValueReference* = object
    case kind*: ConfigValueRefKind
    of cvrTemplate: parts*: seq[TemplatePart]
    of cvrCommand: command*: string

## 命令结果缓存（进程生命周期，对齐 pi commandResultCache）
var commandCache = initTable[string, string]()

const EnvVarNameRe = {'A'..'Z', 'a'..'z', '_', '0'..'9'}

proc isValidEnvName(name: string): bool =
  name.len > 0 and (name[0] in {'A'..'Z', 'a'..'z', '_'}) and
  name.allCharsInSet(EnvVarNameRe)

proc parseConfigValueTemplate*(config: string): seq[TemplatePart] =
  ## 解析配置模板：$ENV ${ENV} $$ $! 字面 + 字面量混合（对齐 pi）。
  result = @[]
  var i = 0
  while i < config.len:
    let dollar = config.find('$', i)
    if dollar < 0:
      # 剩余全字面
      let lit = config[i .. ^1]
      if lit.len > 0:
        result.add TemplatePart(kind: tpLiteral, value: lit)
      break
    # 前面的字面
    if dollar > i:
      result.add TemplatePart(kind: tpLiteral, value: config[i ..< dollar])
    let next = if dollar + 1 < config.len: config[dollar+1] else: '\0'
    if next == '$' or next == '!':
      # $$ 和 $! 是字面 $ 或 !
      result.add TemplatePart(kind: tpLiteral, value: $next)
      i = dollar + 2
      continue
    if next == '{':
      let close = config.find('}', dollar + 2)
      if close < 0:
        result.add TemplatePart(kind: tpLiteral, value: "$")
        i = dollar + 1
        continue
      let name = config[dollar+2 ..< close]
      if isValidEnvName(name):
        result.add TemplatePart(kind: tpEnv, value: name)
      else:
        result.add TemplatePart(kind: tpLiteral, value: config[dollar .. close])
      i = close + 1
      continue
    # $ENV（无花括号）
    var j = dollar + 1
    while j < config.len and config[j] in EnvVarNameRe:
      inc j
    if j > dollar + 1:
      let name = config[dollar+1 ..< j]
      if isValidEnvName(name):
        result.add TemplatePart(kind: tpEnv, value: name)
        i = j
        continue
    # 非 env 的 $，字面
    result.add TemplatePart(kind: tpLiteral, value: "$")
    i = dollar + 1
  # 空配置 → 空
  if result.len == 0:
    result.add TemplatePart(kind: tpLiteral, value: "")

proc resolveTemplate*(parts: seq[TemplatePart], env: Table[string, string]): string =
  ## 解析模板：env 缺失的变量按空处理（对齐 pi resolveTemplate 语义）。
  for p in parts:
    case p.kind
    of tpLiteral: result.add p.value
    of tpEnv:
      if env.hasKey(p.value):
        result.add env[p.value]

proc resolveCommand*(command: string): string =
  ## 执行命令取输出（对齐 pi executeCommand，带缓存）。
  if commandCache.hasKey(command):
    return commandCache[command]
  var output = ""
  try:
    let (outp, _) = execCmdEx(command, options = {poUsePath})
    output = outp.strip()
  except CatchableError:
    output = ""
  commandCache[command] = output
  result = output

proc isCommandConfigValue*(config: string): bool =
  ## 配置是命令形式（$! 开头，对齐 pi）。
  config.len >= 2 and config[0] == '$' and config[1] == '!'

proc getTemplateEnvVarNames*(parts: seq[TemplatePart]): seq[string] =
  for p in parts:
    if p.kind == tpEnv:
      result.add p.value

proc resolveConfigValue*(config: string, env: Table[string, string]): string =
  ## 解析配置值为实际值（对齐 pi resolveConfigValue）。
  if isCommandConfigValue(config):
    result = resolveCommand(config[2 .. ^1])
  else:
    let parts = parseConfigValueTemplate(config)
    result = resolveTemplate(parts, env)

proc getConfigValueEnvVarNames*(config: string): seq[string] =
  if not isCommandConfigValue(config):
    result = parseConfigValueTemplate(config).getTemplateEnvVarNames()

proc isConfigValueConfigured*(config: string, env: Table[string, string]): bool =
  ## 配置是否已解析出非空值（对齐 pi）。
  resolveConfigValue(config, env).len > 0
# ---------------------------------------------------------------------------
# resolveHeaders：header 表逐项解析（对齐 pi resolve-config-value.ts resolveHeaders）
# ---------------------------------------------------------------------------

proc resolveHeaders*(headers: Table[string, string], env: Table[string, string]): Table[string, string] =
  ## 逐项 resolveConfigValue，空值跳过（对齐 pi resolveHeaders）。
  result = initTable[string, string]()
  for key, value in headers:
    let resolved = resolveConfigValue(value, env)
    if resolved.len > 0:
      result[key] = resolved

proc clearConfigValueCache*() =
  ## 清命令结果缓存（对齐 pi clearConfigValueCache）。
  commandCache.clear()
