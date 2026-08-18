## Compaction：对齐 pi `compaction.ts` 的上下文压缩纯函数。
## 估算 context tokens、超阈值判定、切点选择、旧消息摘要化。

import std/[strutils]
import ./types

type
  CompactionSettings* = object
    enabled*: bool
    reserveTokens*: int      ## 上下文窗口保留余量
    keepRecentTokens*: int   ## 切点后保留的最近 token 数
    contextWindow*: int      ## 模型上下文窗口大小

  CompactionResult* = object
    compacted*: bool
    tokensBefore*: int
    cutIndex*: int           ## 切点：>=cutIndex 的消息保留
    summary*: string         ## 总结旧消息的文本（空表示未压缩）
    messagesToSummarize*: seq[Message]

const
  DefaultContextWindow* = 200000
  DefaultReserveTokens* = 16384
  DefaultKeepRecentTokens* = 20000

proc defaultCompactionSettings*(): CompactionSettings =
  CompactionSettings(enabled: true, reserveTokens: DefaultReserveTokens,
                     keepRecentTokens: DefaultKeepRecentTokens,
                     contextWindow: DefaultContextWindow)

proc messageText(m: Message): string =
  case m.kind
  of mkUser: m.userContent
  of mkAssistant:
    var sb = ""
    for c in m.assistantContent:
      case c.kind
      of ctText, ctThinking: sb.add c.text & "\n"
      of ctToolCall: sb.add "[tool: " & c.name & "]\n"
      of ctImage: sb.add "[image]\n"
    sb
  of mkToolResult: "[tool " & m.toolName & "]: " & m.toolText

proc estimateTokens*(m: Message): int =
  ## chars/4 保守启发式（对齐 pi estimateTokens）。
  ## 保守（高估）：每 4 字符算 1 token，向上取整。
  let chars = m.messageText().len
  result = (chars + 3) div 4
  # 短消息保底
  if result == 0: result = 1

proc estimateMessagesTokens*(messages: seq[Message]): int =
  for m in messages:
    result += m.estimateTokens()

proc shouldCompact*(contextTokens: int, settings: CompactionSettings): bool =
  ## 超阈值判定：contextTokens > window - reserveTokens
  if not settings.enabled: return false
  contextTokens > settings.contextWindow - settings.reserveTokens

proc findCutPoint*(messages: seq[Message], keepRecentTokens: int): int =
  ## 从最新往回累积 token，找到切点。返回第一个保留的消息 index。
  ## 结果 >= 该 index 的消息保留（<= keepRecentTokens）。
  var accumulated = 0
  var cut = 0
  for i in countdown(messages.high, 0):
    let t = messages[i].estimateTokens()
    if t == 0: continue
    accumulated += t
    if accumulated >= keepRecentTokens:
      cut = i
      break
    cut = i
  cut

proc summarizeMessages*(msgs: seq[Message]): string =
  ## 精简摘要：只保留每条消息的关键内容前缀，大幅缩小体积。
  ## MVP 不调 LLM（对齐 pi 的精炼摘要语义：压缩旧消息为要点）。
  if msgs.len == 0: return ""
  var sb = "（前文已压缩，摘要如下）\n"
  var shown = 0
  for m in msgs:
    let t = m.messageText().strip
    if t.len == 0: continue
    # 每条只保留前 60 字符，控制摘要体积
    var seg = if t.len > 60: t[0 ..< 60] & "…" else: t
    # 跳过重复题目，最多展示 30 条
    if shown >= 30: break
    sb.add seg & "\n"
    inc shown
  result = sb

proc prepareCompaction*(messages: seq[Message],
                        settings: CompactionSettings): CompactionResult =
  ## 估算并决定是否压缩。若应压缩，返回切点 + 待摘要消息。
  result.tokensBefore = messages.estimateMessagesTokens()
  result.compacted = shouldCompact(result.tokensBefore, settings)
  result.cutIndex = -1
  if not result.compacted:
    return
  result.cutIndex = findCutPoint(messages, settings.keepRecentTokens)
  if result.cutIndex <= 0:
    # 全部都要保留或切点太靠前，无法安全压缩
    result.compacted = false
    result.cutIndex = -1
    return
  result.messagesToSummarize = messages[0 ..< result.cutIndex]
  result.summary = result.messagesToSummarize.summarizeMessages()