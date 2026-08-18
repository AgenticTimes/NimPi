## Token 用量统计：对齐 pi `usage-totals.ts`。
## UsageTotals 累计、addUsageToTotals、getUsageCostBreakdown（按 provider/model 成本分解）。

import std/[tables, algorithm, strutils]
import ./types

type
  UsageTotals* = object
    input*: int
    output*: int
    cacheRead*: int
    cacheWrite*: int
    cost*: float

  UsageBreakdownEntry* = object
    key*: string          ## "provider/model"
    cost*: float
    tokens*: int

  UsageEntry* = object
    key*: string          ## 归属键（provider/model）
    usage*: Usage

proc createUsageTotals*(): UsageTotals =
  UsageTotals(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0)

proc addUsageToTotals*(totals: var UsageTotals, usage: Usage) =
  ## 累计 usage 到 totals（对齐 pi addUsageToTotals）。
  totals.input += usage.input
  totals.output += usage.output
  totals.cacheRead += usage.cacheRead
  totals.cacheWrite += usage.cacheWrite
  totals.cost += 0.0   # 简化：成本由外部输入（pi 用 usage.cost.total）

proc addUsageToTotalsWithCost*(totals: var UsageTotals, usage: Usage, cost: float) =
  totals.input += usage.input
  totals.output += usage.output
  totals.cacheRead += usage.cacheRead
  totals.cacheWrite += usage.cacheWrite
  totals.cost += cost

proc getUsageCostBreakdown*(entries: seq[UsageEntry]): seq[UsageBreakdownEntry] =
  ## 按 key（provider/model）分组统计 token+cost，过滤 0，按 cost 降序。
  ## 对齐 pi getUsageCostBreakdown。
  var totalsByKey = initTable[string, UsageTotals]()
  for e in entries:
    if not totalsByKey.hasKey(e.key):
      totalsByKey[e.key] = createUsageTotals()
    totalsByKey[e.key].addUsageToTotals(e.usage)
  for key, totals in totalsByKey:
    let tokens = totals.input + totals.output + totals.cacheRead + totals.cacheWrite
    if totals.cost > 0.0 or tokens > 0:
      result.add UsageBreakdownEntry(key: key, cost: totals.cost, tokens: tokens)
  # 按 cost 降序（对齐 pi sort b.cost - a.cost）
  result.sort(proc(a, b: UsageBreakdownEntry): int =
    if b.cost > a.cost: 1
    elif b.cost < a.cost: -1
    else: 0)

proc totalTokens*(t: UsageTotals): int =
  t.input + t.output + t.cacheRead + t.cacheWrite