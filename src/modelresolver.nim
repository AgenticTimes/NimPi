## 模型解析：对齐 pi `model-resolver.ts` 的 parseModelPattern / defaultModelPerProvider 语义。
## 解析 `model`、`provider/model`、`model:thinking-level`，支持按 provider 默认回退。

import std/[strutils, tables]

type
  ThinkingLevel* = enum
    thNone, thLow, thMedium, thHigh

  ParsedModel* = object
    model*: string
    provider*: string        ## 模式里显式指定的 provider（无则空）
    thinking*: ThinkingLevel
    warning*: string

## 默认模型表（对齐 pi defaultModelPerProvider，取 npi 支持的三家 + 通用别名）
proc defaultModelForProvider*(provider: string): string =
  case provider.toLowerAscii
  of "openai": "gpt-4o-mini"
  of "anthropic": "claude-sonnet-4-5"
  of "gemini", "google": "gemini-2.0-flash"
  of "deepseek": "deepseek-v4-pro"
  of "openrouter": "kimi-k2.6"
  else: "gpt-4o-mini"

proc isValidThinkingLevel*(s: string): bool =
  ## 对齐 pi isValidThinkingLevel（低/中/高）。
  s.toLowerAscii in ["low", "medium", "high", "none"]

proc parseThinkingLevel(s: string): ThinkingLevel =
  case s.toLowerAscii
  of "low": thLow
  of "medium": thMedium
  of "high": thHigh
  else: thNone

proc parseModelPattern*(pattern: string,
                        allowInvalidThinkingFallback = true): ParsedModel =
  ## 解析模型模式。逻辑：
  ## 1. 若含 `/`，前半是 provider，后半是 model id
  ## 2. 递归剥离最后一个 `:suffix`，若 suffix 是合法 thinking level 则采用，
  ##    否则（严格模式）拒绝 或（宽松）剥离并警告。
  ## 返回值：model + provider + thinking + warning。
  var rest = pattern.strip
  # 先分离 provider（`provider/model` 或 `provider:model`）
  var provider = ""
  if rest.contains('/'):
    let sp = rest.find('/')
    provider = rest[0 ..< sp]
    rest = rest[sp+1 .. ^1]
  elif rest.count(':') >= 1:
    # 可能 provider:model —— 但 model:thinking 也含 :，先按 thinking 剥离判断
    discard

  # 递归剥离 :suffix
  result.thinking = thNone
  var effective = rest
  while effective.contains(':') and effective.len > 1:
    let lastColon = effective.rfind(':')
    if lastColon <= 0:
      # :前缀 无法剥离，直接保留（如 :bogus）
      break
    let suffix = effective[lastColon+1 .. ^1].strip
    if isValidThinkingLevel(suffix):
      result.thinking = parseThinkingLevel(suffix)
      effective = effective[0 ..< lastColon]
      break
    else:
      if not allowInvalidThinkingFallback:
        # 严格模式：把 :suffix 当 model id 一部分失败
        result.warning = "无效 thinking level \"" & suffix & "\"（严格模式）"
        return ParsedModel(model: "", warning: result.warning)
      # 宽松：剥离并警告
      result.warning = "无效 thinking level \"" & suffix & "\" 已忽略，使用默认。"
      effective = effective[0 ..< lastColon]
      break

  result.model = effective
  result.provider = provider

proc resolveModelSpec*(pattern: string, fallbackProvider: string): ParsedModel =
  ## 解析 user 提供的模型模式；未显式指定 provider 时用 fallbackProvider 填充。
  result = parseModelPattern(pattern)
  if result.provider.len == 0:
    result.provider = fallbackProvider
  if result.model.len == 0:
    # 空模式：用 provider 默认
    result.model = defaultModelForProvider(result.provider)
  # 无 thinking level 时显式 none
  if result.model.len == 0:
    result.warning = "无法解析模型模式: " & pattern