## Agent 循环：对齐 pi agent-loop 的简化版。
## 多轮：user → LLM → tool calls → 执行 → 回填 toolResult → 再请求，直到 stop。

import std/[json, strutils, os, osproc]
import ./types
import ./compaction
import ./truncate
import ./shell
import ./grep

type
  ToolResultRaw* = tuple
    callId: string
    name: string
    text: string
    isError: bool

  ToolHandler* = proc(name: string, args: JsonNode, cwd: string): ToolResultRaw {.closure.}

  AgentCallbacks* = object
    onStreamText*: proc(text: string): void {.closure.}
    onToolCall*: proc(name: string): void {.closure.}

  Agent* = object
    history*: seq[Message]
    tools*: seq[JsonNode]
    maxIterations*: int
    compactionSettings*: CompactionSettings
    cwd*: string
    handler*: ToolHandler
    callbacks*: AgentCallbacks
    systemPromptCache*: string
    onComplete*: proc(core: seq[ChatPayload]): void {.closure.}

  ChatPayload* = object
    ## 抽象 AI 往返载荷，TUI 层用它渲染，无需依赖具体 provider。
    role*: string
    text*: string
    toolCalls*: seq[tuple[id, name: string, args: JsonNode]]
    toolResults*: seq[tuple[callId, name, text: string, isError: bool]]
    stopReason*: string

proc toolSchema*(name, desc: string, params: JsonNode): JsonNode =
  ## OpenAI tools 声明。
  %*{
    "type": "function",
    "function": {"name": name, "description": desc, "parameters": params}
  }

proc runTool*(name: string, args: JsonNode, cwd: string): ToolResultRaw =
  ## 内置工具分发：read/write/edit/bash/ls/grep/find。
  case name
  of "read", "cat":
    let path = args{"path"}.getStr("")
    if path.len == 0: return ("", name, "error: missing path", true)
    try:
      let content = readFile(path)
      let t = truncateHead(content, defaultTruncationOptions())
      let text = if t.truncated: t.content & "\n... [truncated " & formatSize(t.totalBytes) &
                    ", showing first " & $t.outputLines & " lines]"
                 else: t.content
      return ("", name, text, false)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  of "write":
    let path = args{"path"}.getStr("")
    let content = args{"content"}.getStr("")
    try:
      createDir(parentDir(path))
      writeFile(path, content)
      return ("", name, "wrote " & path, false)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  of "edit":
    let path = args{"path"}.getStr("")
    let oldText = args{"oldText"}.getStr("")
    let newText = args{"newText"}.getStr("")
    try:
      var s = readFile(path)
      let i = s.find(oldText)
      if i < 0: return ("", name, "error: oldText not found", true)
      s = s[0 ..< i] & newText & s[i + oldText.len .. ^1]
      writeFile(path, s)
      return ("", name, "edited " & path, false)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  of "bash", "sh", "run":
    let cmd = args{"command"}.getStr(args{"cmd"}.getStr(""))
    if cmd.len == 0: return ("", name, "error: missing command", true)
    try:
      let (outp, code) = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})
      let cleaned = outp.sanitizeShellOutput()
      let t = truncateTail(cleaned, defaultTruncationOptions())
      let text = if t.truncated: t.content & "\n... [truncated " & formatSize(t.totalBytes) &
                    ", showing last " & $t.outputLines & " lines]"
                 else: t.content
      return ("", name, text, code != 0)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  of "ls":
    let path = args{"path"}.getStr(".")
    try:
      var sb = ""
      for k in walkDir(path):
        sb.add ($(k.kind) & " " & k.path & "\n")
      return ("", name, sb, false)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  of "grep":
    let pattern = args{"pattern"}.getStr("")
    let path = args{"path"}.getStr(".")
    if pattern.len == 0: return ("", name, "error: missing pattern", true)
    try:
      var opts = defaultGrepOptions()
      opts.pattern = pattern
      opts.fixedString = false   # 正则（对齐 pi 默认）
      if args{"caseSensitive"}.getBool: opts.caseSensitive = true
      let ctx = args{"context"}.getInt(0)
      if ctx > 0: opts.context = ctx
      let m = grepPath(path, opts)
      var text = ""
      for x in m:
        if x.lineType == "context":
          text.add "  " & x.text & "\n"
        else:
          text.add x.text & "\n"
      return ("", name, if text.len == 0: "no matches" else: text, false)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  of "find":
    let path = args{"path"}.getStr(".")
    let name2 = args{"name"}.getStr("*")
    try:
      let cmd = "find " & path & " -name '" & name2.replace("'", "'\\''") & "' 2>/dev/null | head -50"
      let (outp, _) = execCmdEx(cmd, options = {poUsePath})
      return ("", name, if outp.len == 0: "no results" else: outp, false)
    except CatchableError as e:
      return ("", name, "error: " & e.msg, true)
  else:
    return ("", name, "error: unknown tool: " & name, true)

proc defaultTools(): seq[JsonNode] =
  ## 默认声明内置工具集（JSON schema）。
  let strParam = %*{"type": "string"}
  let obj = proc(required: seq[string], props: JsonNode): JsonNode =
    %*{"type": "object", "properties": props, "required": required}
  result = @[
    toolSchema("read", "Read a file's contents",
      obj(@["path"], %*{"path": {"type": "string"}})),
    toolSchema("write", "Write content to a file (overwrites)",
      obj(@["path", "content"], %*{"path": {"type": "string"}, "content": {"type": "string"}})),
    toolSchema("edit", "Replace oldText with newText in a file",
      obj(@["path", "oldText", "newText"],
        %*{"path": {"type": "string"}, "oldText": {"type": "string"}, "newText": {"type": "string"}})),
    toolSchema("bash", "Run a shell command",
      obj(@["command"], %*{"command": {"type": "string"}})),
    toolSchema("ls", "List a directory",
      obj(@[], %*{"path": {"type": "string"}})),
    toolSchema("grep", "Grep for a pattern in a file/path",
      obj(@["pattern"], %*{"pattern": {"type": "string"}, "path": {"type": "string"}})),
  ]

proc `systemPromptText`*(a: Agent): string {.inline.} =
  result = a.systemPromptCache

proc setSystemPrompt*(a: var Agent, text: string) =
  a.systemPromptCache = text

proc newAgent*(handler: ToolHandler, cwd: string): Agent =
  result = Agent(handler: handler, cwd: cwd, maxIterations: 10, tools: defaultTools())
  if result.handler.isNil:
    result.handler = runTool
