## 运行时凭据：对齐 pi `runtime-credentials.ts`。
## RuntimeCredentials：运行时 API key 覆盖层（非持久，覆盖 base store）。

import std/[os, tables]

type
  ## base 凭据查找函数：给定 providerId 返回持久/环境凭据（可空）
  CredentialLookup* = proc(providerId: string): string {.closure.}

  RuntimeCredentials* = ref object
    baseLookup*: CredentialLookup
    overrides*: Table[string, string]

proc newRuntimeCredentials*(baseLookup: CredentialLookup): RuntimeCredentials =
  RuntimeCredentials(baseLookup: baseLookup, overrides: initTable[string, string]())

proc setRuntimeApiKey*(rc: RuntimeCredentials, providerId: string, apiKey: string) =
  ## 设置运行时覆盖（对齐 pi setRuntimeApiKey）。
  rc.overrides[providerId] = apiKey

proc removeRuntimeApiKey*(rc: RuntimeCredentials, providerId: string) =
  ## 移除覆盖（对齐 pi removeRuntimeApiKey）。
  if rc.overrides.hasKey(providerId):
    rc.overrides.del(providerId)

proc hasRuntimeApiKey*(rc: RuntimeCredentials, providerId: string): bool =
  rc.overrides.hasKey(providerId)

proc read*(rc: RuntimeCredentials, providerId: string): string =
  ## 读取凭据：覆盖优先，否则回退 base（对齐 pi read）。
  if rc.overrides.hasKey(providerId):
    return rc.overrides[providerId]
  if not rc.baseLookup.isNil:
    let base = rc.baseLookup(providerId)
    if base.len > 0:
      return base
  ""

proc list*(rc: RuntimeCredentials): seq[string] =
  ## 列出覆盖的 providerId（对齐 pi list，合并 base）。
  var seen = initTable[string, bool]()
  # base 的 provider（通过常见 env 探测——简化：只列覆盖）
  for pid in rc.overrides.keys:
    if not seen.hasKey(pid):
      seen[pid] = true
      result.add pid
  # base 可能有的 provider（此处省略探测，覆盖即可）