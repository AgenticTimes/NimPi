## Prompt 缓存缺失检测：对齐 pi `cache-stats.ts` 核心逻辑（简化版，无成本模型）。
## detectMiss 判定每轮请求是否有效利用 prompt cache。

import std/[times, math]
import ./types

const
  ## 缓存 TTL（对齐 pi CACHE_TTL_MS，Anthropic 默认 5 分钟）
  CacheTtlMs* = 5 * 60 * 1000
  ## 每轮 miss 低于此视为缓存断点粒度噪声（对齐 pi NOISE_FLOOR_TOKENS）
  NoiseFloorTokens = 1024

type
  PreviousRequest* = object
    promptTokens*: int
    modelKey*: string
    timestamp*: int       ## epoch ms
    reportedCache*: bool  ## 之前是否报告过缓存活动

  CacheMiss* = object
    missedTokens*: int
    idleMs*: int
    counted*: bool        ## 是否计入（低于噪声线/首轮则 false）

  CacheWaste* = object
    missedTokens*: int
    missCount*: int

proc promptTokensOf*(usage: Usage): int =
  ## 本轮的 prompt tokens（input + cacheRead + cacheWrite，对齐 pi）。
  result = usage.input + usage.cacheRead + usage.cacheWrite

proc detectMiss*(prev: PreviousRequest, usage: Usage, nowMs: int): CacheMiss =
  ## 计算相对上一请求的缓存缺失（对齐 pi detectMiss 核心，无成本部分）。
  let promptTokens = usage.promptTokensOf()
  # 首轮 / 无 prompt / （零缓存且此前未报告过缓存活动）不计
  if prev.promptTokens <= 0 or promptTokens <= 0:
    return CacheMiss(counted: false)
  if usage.cacheRead + usage.cacheWrite == 0 and not prev.reportedCache:
    return CacheMiss(counted: false)
  let missedTokens = min(prev.promptTokens, promptTokens) - usage.cacheRead
  if missedTokens <= NoiseFloorTokens:
    return CacheMiss(counted: false)
  result = CacheMiss(missedTokens: missedTokens,
                     idleMs: max(0, nowMs - prev.timestamp),
                     counted: true)

proc addMiss*(waste: var CacheWaste, miss: CacheMiss) =
  ## 累计 miss 到 waste（对齐 pi CacheWasteTotals 语义）。
  if not miss.counted: return
  waste.missedTokens += miss.missedTokens
  inc waste.missCount