## 事件总线：对齐 pi `event-bus.ts`。
## on/emit/clear，handler 异常隔离，返回取消函数。

import std/[tables]

type
  EventHandler* = proc(data: string): void {.closure.}

  EventBus* = ref object
    handlers*: Table[string, seq[tuple[id: int, handler: EventHandler]]]
    nextId*: int

proc newEventBus*(): EventBus =
  EventBus(handlers: initTable[string, seq[tuple[id: int, handler: EventHandler]]](), nextId: 0)

proc on*(bus: EventBus, channel: string, handler: EventHandler): proc(): void =
  ## 订阅通道。返回取消订阅函数（对齐 pi on 返回 unsubscribe）。
  let id = bus.nextId
  inc bus.nextId
  if not bus.handlers.hasKey(channel):
    bus.handlers[channel] = @[]
  bus.handlers[channel].add (id: id, handler: handler)
  result = proc() =
    if bus.handlers.hasKey(channel):
      var hs = bus.handlers[channel]
      var kept: seq[tuple[id: int, handler: EventHandler]] = @[]
      for h in hs:
        if h.id != id:
          kept.add h
      bus.handlers[channel] = kept

proc emit*(bus: EventBus, channel: string, data: string) =
  ## 发布事件。handler 异常隔离：单个 handler 崩溃不影响其它。
  if not bus.handlers.hasKey(channel):
    return
  # 复制副本避免 handler 内取消导致迭代问题
  let hs = bus.handlers[channel]
  for h in hs:
    try:
      if not h.handler.isNil:
        h.handler(data)
    except CatchableError:
      # 错误隔离（对齐 pi safeHandler try/catch）
      discard

proc clear*(bus: EventBus) =
  ## 清空所有订阅（对齐 pi clear）。
  bus.handlers.clear()