## 会话落盘：JSONL 格式，每行一条消息（对齐 pi 的会话文件思路）。

import std/[json, os, times]
import ./types

type
  Session* = object
    dir*: string
    id*: string
    path*: string
    messages*: seq[Message]

proc newSession*(dir: string): Session =
  result = Session(dir: dir, id: $getTime().toUnix)
  if dir.len > 0:
    createDir(dir)
    result.path = dir / ("session-" & result.id & ".jsonl")

proc load*(s: var Session, path: string) =
  ## 从 JSONL 加载历史消息。
  s.path = path
  s.id = splitFile(path).name
  if fileExists(path):
    for line in lines(path):
      if line.len == 0: continue
      let j = parseJson(line)
      let kind = j{"kind"}.getStr("user")
      case kind
      of "user":
        s.messages.add Message(kind: mkUser, userContent: j{"content"}.getStr(""))
      of "assistant":
        var content: seq[Content]
        for c in j{"content"}:
          let ck = c{"kind"}.getStr("text")
          if ck == "toolCall":
            content.add newToolContent(c{"id"}.getStr(""), c{"name"}.getStr(""), c{"arguments"})
          else:
            content.add newTextContent(c{"text"}.getStr(""))
        s.messages.add Message(kind: mkAssistant, assistantContent: content)
      of "toolResult":
        s.messages.add Message(kind: mkToolResult,
          toolCallId: j{"toolCallId"}.getStr(""),
          toolName: j{"toolName"}.getStr(""),
          toolText: j{"content"}.getStr(""),
          isError: j{"isError"}.getBool)

proc append*(s: var Session, m: Message) =
  ## 追加并落盘。
  s.messages.add m
  if s.path.len == 0: return
  var j = newJObject()
  case m.kind
  of mkUser:
    j["kind"] = %"user"
    j["content"] = %m.userContent
  of mkAssistant:
    j["kind"] = %"assistant"
    var c = newJArray()
    for x in m.assistantContent:
      var xj = newJObject()
      case x.kind
      of ctToolCall:
        xj["kind"] = %"toolCall"
        xj["id"] = %x.id
        xj["name"] = %x.name
        xj["arguments"] = x.arguments
      else:
        xj["kind"] = %"text"
        xj["text"] = %x.text
      c.add xj
    j["content"] = c
  of mkToolResult:
    j["kind"] = %"toolResult"
    j["toolCallId"] = %m.toolCallId
    j["toolName"] = %m.toolName
    j["content"] = %m.toolText
    j["isError"] = %m.isError
  let f = open(s.path, fmAppend)
  try: f.writeLine($j)
  finally: f.close()
