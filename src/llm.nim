## LLM 提供方：OpenAI 兼容 Chat Completions 流式（SSE）解析。
## 对齐 pi `pi-ai` 的 stream 事件接口，只保留 streamSimple 所需的最小面。

import std/[httpclient, json, strutils, asyncdispatch]
import ./types

type
  LlmError* = object of CatchableError

  StreamEvent* = enum
    seTextDelta     ## 文本增量
    seToolCallStart ## 工具调用开始（含完整 name/arguments，非增量）
    seEnd           ## 流结束（含 stopReason / usage）

  StreamPayload* = object
    case kind*: StreamEvent
    of seTextDelta:
      textDelta*: string
    of seToolCallStart:
      toolId*: string
      toolName*: string
      toolArgs*: JsonNode
    of seEnd:
      stopReason*: StopReason
      usage*: Usage

  ChatMessage* = object
    role*: string
    content*: string
    toolCallId*: string
    toolCalls*: seq[JsonNode]   ## 已有 assistant tool_calls（来自历史）

  ClientOptions* = object
    apiKey*: string
    baseUrl*: string        ## 默认 https://api.openai.com/v1
    model*: string
    timeoutMs*: int

  LlmClient* = ref object
    opts*: ClientOptions

proc newLlmClient*(opts: ClientOptions): LlmClient =
  result = LlmClient(opts: opts)
  if result.opts.baseUrl.len == 0:
    result.opts.baseUrl = "https://api.openai.com/v1"

proc toJson*(m: ChatMessage): JsonNode =
  ## 组装成 Chat Completions 的 message 对象。
  result = newJObject()
  result["role"] = %m.role
  case m.role
  of "assistant":
    if m.toolCalls.len > 0:
      result["content"] = %""
      var arr = newJArray()
      for tc in m.toolCalls:
        arr.add tc
      result["tool_calls"] = arr
    else:
      result["content"] = %m.content
  of "tool":
    result["tool_call_id"] = %m.toolCallId
    result["content"] = %m.content
  else:
    result["content"] = %m.content

proc buildBody*(messages: seq[ChatMessage], tools: seq[JsonNode], model: string): JsonNode =
  result = newJObject()
  result["model"] = %model
  var arr = newJArray()
  for m in messages:
    arr.add m.toJson()
  result["messages"] = arr
  if tools.len > 0:
    var tarr = newJArray()
    for t in tools:
      tarr.add t
    result["tools"] = tarr
  result["stream"] = %true

proc parseSseLine(line: string): tuple[event: string, data: string] =
  ## 解析单行 SSE：`event: x` 或 `data: {...}`。返回 event 名与 data 内容。
  result = (event: "", data: "")
  if line.startsWith("event:"):
    result.event = line[6..^1].strip
  elif line.startsWith("data:"):
    result.data = line[5..^1].strip

proc stream*(client: LlmClient, messages: seq[ChatMessage],
             tools: seq[JsonNode],
             onEvent: proc(e: StreamPayload): void {.closure.}) {.async.} =
  ## 发起流式请求，逐块解析 SSE，把增量事件交给 onEvent 回调。
  let model = client.opts.model
  let body = buildBody(messages, tools, model)
  let http = newAsyncHttpClient(
    headers = newHttpHeaders([
      ("Authorization", "Bearer " & client.opts.apiKey),
      ("Content-Type", "application/json"),
      ("Accept", "text/event-stream")
    ]))
  var full = ""
  var toolName = ""
  var toolId = ""
  var toolArgs = ""
  var inTool = false
  var finalStop = srStop
  var usage = Usage()
  try:
    let resp = await http.post(client.opts.baseUrl & "/chat/completions", body = $body)
    if not resp.status.startsWith("200"):
      raise newException(LlmError, "HTTP " & resp.status)
    var line = ""
    let strm = resp.bodyStream
    while true:
      let (hasData, chunk) = await read(strm)
      if not hasData or chunk.len == 0: break
      full.add chunk
      # 按行切分
      while true:
        let nl = full.find('\n')
        if nl < 0: break
        let cur = full[0 ..< nl]
        full = full[nl+1 .. ^1]
        let (ev, data) = parseSseLine(cur)
        if ev == "" and data.len == 0: continue
        if ev == "error":
          raise newException(LlmError, "SSE error: " & data)
        if data == "[DONE]":
          break
        var j: JsonNode
        try:
          j = parseJson(data)
        except CatchableError:
          continue
        let choice = j{"choices"}[0]
        if choice.isNil: continue
        let delta = choice{"delta"}
        if not delta.isNil:
          let c = delta{"content"}
          if not c.isNil and c.kind == JString and c.str.len > 0:
            onEvent(StreamPayload(kind: seTextDelta, textDelta: c.str))
          let tc = delta{"tool_calls"}
          if not tc.isNil:
            for tcc in tc:
              let idx = tcc{"index"}.getInt(0)
              let f = tcc{"function"}
              if not f.isNil:
                let n = f{"name"}
                if not n.isNil and n.kind == JString and n.str.len > 0:
                  toolName = n.str
                  toolId = tcc{"id"}.getStr("")
                  inTool = true
                let a = f{"arguments"}
                if not a.isNil and a.kind == JString:
                  toolArgs.add a.str
        let fr = choice{"finish_reason"}
        if not fr.isNil and fr.kind == JString:
          case fr.str
          of "tool_calls": finalStop = srToolUse
          of "length": finalStop = srLength
          of "stop": finalStop = srStop
          else: finalStop = srStop
        let u = choice{"message"}{"usage"}
        if not u.isNil:
          usage.input = u{"prompt_tokens"}.getInt(0)
          usage.output = u{"completion_tokens"}.getInt(0)
          usage.totalTokens = usage.input + usage.output
    # 收尾工具调用
    if inTool:
      var args: JsonNode = newJObject()
      if toolArgs.len > 0:
        try: args = parseJson(toolArgs)
        except CatchableError: args = newJObject()
      onEvent(StreamPayload(kind: seToolCallStart, toolId: toolId,
                            toolName: toolName, toolArgs: args))
    onEvent(StreamPayload(kind: seEnd, stopReason: finalStop, usage: usage))
  finally:
    http.close()

proc complete*(client: LlmClient, messages: seq[ChatMessage],
               tools: seq[JsonNode]): Future[seq[StreamPayload]] {.async.} =
  ## 便捷封装：拉取完整事件序列。
  result = newSeq[StreamPayload]()
  await client.stream(messages, tools) do (e: StreamPayload):
    result.add e
