## 核心类型：对齐 pi `@earendil-works/pi-ai` 的 wire 形状（精简子集）。

import std/json

type
  ContentType* = enum
    ctText, ctImage, ctThinking, ctToolCall

  Content* = object
    case kind*: ContentType
    of ctText, ctThinking:
      text*: string
    of ctImage:
      data*: string
      mimeType*: string
    of ctToolCall:
      id*: string
      name*: string
      arguments*: JsonNode

  StopReason* = enum
    srPending, srStop, srLength, srToolUse, srError, srAborted

  Usage* = object
    input*: int
    output*: int
    cacheRead*: int
    cacheWrite*: int
    totalTokens*: int

  MessageKind* = enum
    mkUser, mkAssistant, mkToolResult

  Message* = object
    case kind*: MessageKind
    of mkUser:
      userContent*: string
    of mkAssistant:
      assistantContent*: seq[Content]
      stopReason*: StopReason
      usage*: Usage
    of mkToolResult:
      toolCallId*: string
      toolName*: string
      toolText*: string
      isError*: bool

## ---- wire 序列化：把 Message 转成 OpenAI Chat Completions / Responses 可用的 JSON ----

proc toWireText(c: Content): JsonNode =
  result = newJObject()
  case c.kind
  of ctText:
    result["type"] = %"text"
    result["text"] = %c.text
  of ctThinking:
    result["type"] = %"thinking"
    result["thinking"] = %c.text
  of ctImage:
    result["type"] = %"image_url"
    result["image_url"] = newJObject()
    result["image_url"]["url"] = %("data:" & c.mimeType & ";base64," & c.data)
  of ctToolCall:
    result["type"] = %"function_call"
    result["id"] = %c.id
    result["name"] = %c.name
    result["arguments"] = c.arguments

proc toWireJson*(m: Message, toolResultsInContent: bool): JsonNode =
  ## OpenAI Chat Completions 请求体里的一项 message。
  result = newJObject()
  case m.kind
  of mkUser:
    result["role"] = %"user"
    result["content"] = %m.userContent
  of mkAssistant:
    result["role"] = %"assistant"
    var content = newJArray()
    for c in m.assistantContent:
      if c.kind == ctToolCall:
        # Chat Completions 用工具调用数组；Responses 用 content 块
        if content.len == 0:
          result["content"] = %""
        continue
      content.add c.toWireText()
    if content.len > 0:
      result["content"] = content
    elif not result.hasKey("content"):
      result["content"] = %""
    # 抽取 tool_calls
    var tcs = newJArray()
    for c in m.assistantContent:
      if c.kind == ctToolCall:
        tcs.add %*{
          "id": c.id,
          "type": "function",
          "function": %*{"name": c.name, "arguments": $c.arguments}
        }
    if tcs.len > 0:
      result["tool_calls"] = tcs
  of mkToolResult:
    result["role"] = %"tool"
    result["tool_call_id"] = %m.toolCallId
    result["content"] = %m.toolText

proc newTextContent*(text: string): Content =
  Content(kind: ctText, text: text)

proc newToolContent*(id, name: string, args: JsonNode): Content =
  Content(kind: ctToolCall, id: id, name: name, arguments: args)
