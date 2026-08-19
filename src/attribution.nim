## Provider 归属：对齐 pi `provider-attribution.ts`。
## matchesHost + openrouter/nvidia/cloudflare/opencode 归属判定 + mergeProviderAttributionHeaders。

import std/[strutils, tables]

const
  OpenRouterHost = "openrouter.ai"
  NvidiaNimHost = "integrate.api.nvidia.com"
  CloudflareApiHost = "api.cloudflare.com"
  CloudflareGatewayHost = "gateway.ai.cloudflare.com"
  OpencodeHost = "opencode.ai"

proc matchesHost*(baseUrl: string, expectedHost: string): bool =
  ## 判定 baseUrl 的 host 是否匹配（简化：host 包含匹配，对齐 pi URL hostname 语义）。
  baseUrl.toLowerAscii.contains(expectedHost.toLowerAscii)

proc isOpenRouterModel*(provider: string, baseUrl: string): bool =
  provider == "openrouter" or baseUrl.contains(OpenRouterHost)

proc isNvidiaNimModel*(provider: string, baseUrl: string): bool =
  provider == "nvidia" or matchesHost(baseUrl, NvidiaNimHost)

proc isCloudflareModel*(provider: string, baseUrl: string): bool =
  provider in ["cloudflare-workers-ai", "cloudflare-ai-gateway"] or
  matchesHost(baseUrl, CloudflareApiHost) or
  matchesHost(baseUrl, CloudflareGatewayHost)

proc isOpenCodeModel*(provider: string, baseUrl: string): bool =
  provider in ["opencode", "opencode-go"] or matchesHost(baseUrl, OpencodeHost)

proc getDefaultAttributionHeaders*(provider: string, baseUrl: string, enabled: bool): Table[string, string] =
  ## 默认归属 header（对齐 pi getDefaultAttributionHeaders，enabled 替代 telemetry 设置）。
  result = initTable[string, string]()
  if not enabled: return
  if isOpenRouterModel(provider, baseUrl):
    result["HTTP-Referer"] = "https://pi.dev"
    result["X-OpenRouter-Title"] = "pi"
    result["X-OpenRouter-Categories"] = "cli-agent"
  elif isNvidiaNimModel(provider, baseUrl):
    result["X-BILLING-INVOKE-ORIGIN"] = "Pi"
  elif isCloudflareModel(provider, baseUrl):
    result["User-Agent"] = "pi-coding-agent"

proc getSessionHeaders*(provider: string, baseUrl: string, sessionId: string): Table[string, string] =
  ## opencode session header（对齐 pi getSessionHeaders）。
  result = initTable[string, string]()
  if sessionId.len == 0: return
  if not isOpenCodeModel(provider, baseUrl): return
  result["x-opencode-session"] = sessionId
  result["x-opencode-client"] = "pi"

proc mergeProviderAttributionHeaders*(provider: string, baseUrl: string,
                                      sessionId: string, enabled: bool): Table[string, string] =
  ## 合并归属 header（对齐 pi mergeProviderAttributionHeaders）。
  result = initTable[string, string]()
  for k, v in getSessionHeaders(provider, baseUrl, sessionId):
    result[k] = v
  for k, v in getDefaultAttributionHeaders(provider, baseUrl, enabled):
    result[k] = v