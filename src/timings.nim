## 性能计时：对齐 pi `timings.ts`。
## NPI_TIMING=1 开关、reset/time 间隔计时、printTimings 分组输出。

import std/[os, times, tables, strutils]

type
  TimingEntry* = object
    label*: string
    ms*: int

  TimingNamespace* = object
    timings*: seq[TimingEntry]
    lastTime*: int      ## epoch ms

## 命名空间表（对齐 pi Map<TimingLabel, TimingNamespace>）
var timingNamespaces = initTable[string, TimingNamespace]()

proc timingEnabled*(): bool =
  ## 开关：NPI_TIMING=1（对齐 pi PI_TIMING）。
  getEnv("NPI_TIMING", "") == "1"

proc resetTimings*(namespace: string) =
  if not timingEnabled(): return
  timingNamespaces[namespace] = TimingNamespace(timings: @[], lastTime: epochTime().int * 1000)

proc time*(label: string, namespace: string) =
  ## 记录距上次的间隔（对齐 pi time）。
  if not timingEnabled(): return
  let nowMs = epochTime().int * 1000
  if not timingNamespaces.hasKey(namespace):
    resetTimings(namespace)
  var ns = timingNamespaces[namespace]
  ns.timings.add TimingEntry(label: label, ms: nowMs - ns.lastTime)
  ns.lastTime = nowMs
  timingNamespaces[namespace] = ns

proc printTimings*(): string =
  ## 分组输出计时（对齐 pi printTimings，返回文本）。
  if not timingEnabled(): return ""
  var bufs = ""
  for namespace in timingNamespaces.keys:
    let ns = timingNamespaces[namespace]
    var printable: seq[TimingEntry] = @[]
    for t in ns.timings:
      if t.ms >= 0: printable.add t
    if printable.len == 0: continue
    bufs.add "\n--- Startup Timings: " & namespace & " ---\n"
    var total = 0
    for t in printable:
      bufs.add "  " & t.label & ": " & $t.ms & "ms\n"
      total += t.ms
    bufs.add "  TOTAL: " & $total & "ms\n"
    bufs.add repeat("-", namespace.len + 20) & "\n"
  result = bufs