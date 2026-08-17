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
    provider*: string       ## "openai" | "anthropic"
    apiKey*: string
    baseUrl*: string
    model*: string
    timeoutMs*: int
    anthropicVersion*: string   ## Anthropic 需要的 x-api-version 头

  LlmClient* = ref object
    opts*: ClientOptions

proc newLlmClient*(opts: ClientOptions): LlmClient =
  result = LlmClient(opts: opts)
  if result.opts.provider.len == 0:
    result.opts.provider = "openai"
  if result.opts.baseUrl.len == 0:
    result.opts.baseUrl = if result.opts.provider == "anthropic":
        "https://api.anthropic.com"
      else:
        "https://api.openai.com/v1"
  if result.opts.anthropicVersion.len == 0:
    result.opts.anthropicVersion = "2023-06-01"

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

# ---------------------------------------------------------------------------
# Anthropic Messages API：body 构造 + SSE 解析
# ---------------------------------------------------------------------------

proc chatToAnthropic(m: ChatMessage): JsonNode =
  ## 把内部 ChatMessage 转成 Anthropic messages 数组项。
  result = newJObject()
  case m.role
  of "user":
    result["role"] = %"user"
    result["content"] = %m.content
  of "assistant":
    result["role"] = %"assistant"
    var blocks = newJArray()
    if m.content.len > 0:
      blocks.add %*{"type": "text", "text": m.content}
    for tc in m.toolCalls:
      let id = tc{"id"}.getStr("")
      let name = tc{"function"}{"name"}.getStr("")
      var args: JsonNode = newJObject()
      try: args = parseJson(tc{"function"}{"arguments"}.getStr("{}"))
      except CatchableError: args = newJObject()
      blocks.add %*{"type": "tool_use", "id": id, "name": name, "input": args}
    result["content"] = blocks
  of "tool":
    result["role"] = %"user"
    # Anthropic tool_result 放在 user 消息的 content block
    result["content"] = newJArray()
    result["content"].add %*{
      "type": "tool_result",
      "tool_use_id": m.toolCallId,
      "content": m.content
    }
  else:
    result["role"] = %m.role
    result["content"] = %m.content

proc buildAnthropicBody*(messages: seq[ChatMessage], tools: seq[JsonNode], model: string): JsonNode =
  result = newJObject()
  result["model"] = %model
  result["max_tokens"] = %4096
  var arr = newJArray()
  for m in messages:
    arr.add m.chatToAnthropic()
  result["messages"] = arr
  if tools.len > 0:
    var tarr = newJArray()
    for t in tools:
      # Anthropic 工具 schema：不需要 "type": "function" 包装
      let f = t{"function"}
      if not f.isNil:
        tarr.add %*{
          "name": f{"name"}.getStr(""),
          "description": f{"description"}.getStr(""),
          "input_schema": f{"parameters"}
        }
      else:
        tarr.add t
    result["tools"] = tarr
  result["stream"] = %true

proc streamAnthropic(client: LlmClient, messages: seq[ChatMessage],
                     tools: seq[JsonNode],
                     onEvent: proc(e: StreamPayload): void {.closure.}) {.async.} =
  ## Anthropic Messages 流式解析：content_block_delta / content_block_start / message_delta。
  let body = buildAnthropicBody(messages, tools, client.opts.model)
  let http = newAsyncHttpClient(
    headers = newHttpHeaders([
      ("x-api-key", client.opts.apiKey),
      ("anthropic-version", client.opts.anthropicVersion),
      ("Content-Type", "application/json"),
      ("Accept", "text/event-stream")
    ]))
  var full = ""
  var finalStop = srStop
  var usage = Usage()
  # 工具调用累积
  var toolId = ""
  var toolName = ""
  var toolArgs = ""
  var inTool = false
  try:
    let resp = await http.post(client.opts.baseUrl & "/v1/messages", body = $body)
    if not resp.status.startsWith("200"):
      raise newException(LlmError, "HTTP " & resp.status)
    let strm = resp.bodyStream
    while true:
      let (hasData, chunk) = await read(strm)
      if not hasData or chunk.len == 0: break
      full.add chunk
      while true:
        let nl = full.find('\n')
        if nl < 0: break
        let cur = full[0 ..< nl]
        full = full[nl+1 .. ^1]
        let (ev, data) = parseSseLine(cur)
        if ev == "" and data.len == 0: continue
        if data == "[DONE]": break
        var j: JsonNode
        try: j = parseJson(data)
        except CatchableError: continue
        let jt = j{"type"}.getStr("")
        case jt
        of "content_block_delta":
          let d = j{"delta"}
          let dt = d{"type"}.getStr("")
          if dt == "text_delta":
            let tx = d{"text"}.getStr("")
            if tx.len > 0:
              onEvent(StreamPayload(kind: seTextDelta, textDelta: tx))
          elif dt == "input_json_delta":
            toolArgs.add d{"partial_json"}.getStr("")
        of "content_block_start":
          let cb = j{"content_block"}
          if not cb.isNil and cb{"type"}.getStr("") == "tool_use":
            toolId = cb{"id"}.getStr("")
            toolName = cb{"name"}.getStr("")
            var temp: JsonNode
            try: temp = cb{"input"}
            except CatchableError: discard
            inTool = true
            toolArgs = ""
        of "message_delta":
          let stop = j{"delta"}{"stop_reason"}.getStr("")
          case stop
          of "tool_use": finalStop = srToolUse
          of "max_tokens": finalStop = srLength
          of "end_turn": finalStop = srStop
          else: finalStop = srStop
          let u = j{"usage"}
          if not u.isNil:
            usage.input = u{"input_tokens"}.getInt(0)
            usage.output = u{"output_tokens"}.getInt(0)
            usage.totalTokens = usage.input + usage.output
        else: discard
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

proc stream*(client: LlmClient, messages: seq[ChatMessage],
             tools: seq[JsonNode],
             onEvent: proc(e: StreamPayload): void {.closure.}) {.async.} =
  ## 发起流式请求，按 provider 分派到对应解析。
  if client.opts.provider == "anthropic":
    await client.streamAnthropic(messages, tools, onEvent)
    return
  # ---- OpenAI 兼容（Chat Completions）----
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
