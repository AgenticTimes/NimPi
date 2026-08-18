## npi — 极简编码 agent（Nim）入口。
## `npi -p "..."` 打印模式 · `npi` 全屏 TUI（stdin 非 TTY 时退化为 REPL）· `-r` 恢复最近会话。

import std/[os, strutils, asyncdispatch, json, terminal, tables]
import ./types
import ./llm
import ./agent
import ./session
import ./tui
import ./skills
import ./compaction
import ./slash
import ./templates

type
  CliArgs = object
    prompt*: string
    printMode*: bool
    provider*: string
    model*: string
    baseUrl*: string
    apiKey*: string
    sessionDir*: string
    resume*: bool
    noSession*: bool
    maxIterations*: int
    listModels*: bool

  AgentDriver = object
    client*: LlmClient
    agent*: Agent

proc parseArgs(argv: seq[string]): CliArgs =
  result.provider = getEnv("NPI_PROVIDER", "openai")
  result.model = getEnv("NPI_MODEL", if result.provider == "anthropic": "claude-sonnet-4-5"
                                    elif result.provider == "gemini": "gemini-2.0-flash"
                                    else: "gpt-4o-mini")
  result.baseUrl = getEnv("NPI_BASE_URL", "")
  result.apiKey = if result.provider == "anthropic":
      getEnv("ANTHROPIC_API_KEY", getEnv("NPI_API_KEY", ""))
    elif result.provider == "gemini":
      getEnv("GEMINI_API_KEY", getEnv("NPI_API_KEY", ""))
    else:
      getEnv("OPENAI_API_KEY", getEnv("NPI_API_KEY", ""))
  result.sessionDir = getEnv("NPI_SESSION_DIR", os.getCurrentDir() / ".npi/sessions")
  result.maxIterations = 10
  var positional: seq[string] = @[]
  var i = 0
  while i < argv.len:
    let a = argv[i]
    case a
    of "-p": result.printMode = true
    of "-r": result.resume = true
    of "--no-session": result.noSession = true
    of "--list-models": result.listModels = true
    of "--provider":
      inc i; if i < argv.len: result.provider = argv[i]
    of "--model":
      inc i; if i < argv.len: result.model = argv[i]
    of "--base-url":
      inc i; if i < argv.len: result.baseUrl = argv[i]
    of "--api-key":
      inc i; if i < argv.len: result.apiKey = argv[i]
    of "-h", "--help":
      stdout.write("""npi — 极简编码 agent（Nim）

用法:
  npi -p "指令"             打印模式：流式输出后退出
  npi -r                    恢复最近会话（进入 TUI/REPL）
  npi "指令"                带参数：print 完成后进入交互
  npi                       TUI 全屏交互；stdin 非 TTY 退化为 REPL
  npi --provider anthropic  使用 Anthropic (Claude)
  npi --provider gemini     使用 Google Gemini
  npi --list-models         列出可用模型（简表）

选项:
  -p                 print 模式，不进入交互
  -r                 恢复最近会话
  --provider <p>     openai|anthropic|gemini (默认 openai 或 $NPI_PROVIDER)
  --model <id>       模型 (默认 gpt-4o-mini 或 $NPI_MODEL)
  --base-url <url>   OpenAI/Anthropic 兼容 base url (默认 $NPI_BASE_URL)
  --api-key <key>    API key (默认 $OPENAI_API_KEY / $ANTHROPIC_API_KEY / $GEMINI_API_KEY)
  --no-session       不落盘会话
  -h, --help         帮助
""")
      quit(0)
    else:
      if a.startsWith("-") and a.len == 1:
        positional.add a
      elif a.startsWith("-"):
        # 未知长选项忽略，避免误伤
        discard
      else:
        positional.add a
    inc i
  if positional.len > 0:
    result.prompt = positional.join(" ")

proc systemPrompt(cwd: string): string =
  result = """You are npi, a coding agent that helps with programming tasks in the current repository.

You have access to tools: read, write, edit, bash, ls, grep, find.
- read <path> — read a file
- write <path> <content> — write a file
- edit <path> <oldText> <newText> — replace text
- bash <command> — run a shell command (cwd: $1)
- ls <path> — list a directory
- grep <pattern> <path> — search text
- find <path> <name> — find files by name

Work iteratively: inspect, then edit, then verify. Keep responses concise. When done, summarize what you changed.""" % cwd
  # 注入 Agent Skills（对齐 pi skills 系统）
  let skills = loadSkills(cwd)
  let skillsPrompt = skills.skills.formatSkillsForPrompt()
  if skillsPrompt.len > 0:
    result.add "\n\n" & skillsPrompt

proc historyToChat(history: seq[Message]): seq[ChatMessage] =
  for m in history:
    case m.kind
    of mkUser:
      result.add ChatMessage(role: "user", content: m.userContent)
    of mkAssistant:
      var tcs: seq[JsonNode] = @[]
      for c in m.assistantContent:
        if c.kind == ctToolCall:
          tcs.add %*{
            "id": c.id, "type": "function",
            "function": {"name": c.name, "arguments": $c.arguments}
          }
      result.add ChatMessage(role: "assistant",
        content: if m.assistantContent.len == 0: "" else: m.assistantContent[0].text,
        toolCalls: tcs)
    of mkToolResult:
      result.add ChatMessage(role: "tool", toolCallId: m.toolCallId, toolName: m.toolName, content: m.toolText)

proc runConversation*(driver: AgentDriver, session: var Session,
                      userInput: string,
                      onDelta: proc(d: string): void {.closure.},
                      onTool: proc(name: string): void {.closure.}): seq[Message] =
  ## 执行一轮完整对话（可能多轮工具调用）。
  let userMsg = Message(kind: mkUser, userContent: userInput)
  session.append(userMsg)
  var history = session.messages

  # 上下文压缩：超阈值则把最早消息压缩为摘要（对齐 pi compaction）
  let compSettings = driver.agent.compactionSettings
  let comp = prepareCompaction(history, compSettings)
  if comp.compacted:
    # 替换历史：摘要消息 + 最近保留消息
    var newHistory: seq[Message] = @[]
    if comp.summary.len > 0:
      newHistory.add Message(kind: mkUser, userContent: comp.summary)
    for i in comp.cutIndex ..< history.len:
      newHistory.add history[i]
    history = newHistory
    session.messages = newHistory

  var msgs = @[ChatMessage(role: "system", content: driver.agent.systemPromptText)]
  msgs.add historyToChat(history)

  var iterations = 0
  while iterations < driver.agent.maxIterations:
    inc iterations
    # 注入助手工具声明
    var payloads = newSeq[StreamPayload]()
    waitFor driver.client.stream(msgs, driver.agent.tools) do (e: StreamPayload):
      case e.kind
      of seTextDelta:
        if not onDelta.isNil: onDelta(e.textDelta)
      of seToolCallStart:
        if not onTool.isNil: onTool(e.toolName)
      of seEnd: discard
      payloads.add e

    # 组装 assistant 消息
    var content: seq[Content] = @[]
    var tcs: seq[JsonNode] = @[]
    var anyTool = false
    var stop = srStop
    for p in payloads:
      case p.kind
      of seTextDelta:
        content.add newTextContent(p.textDelta)
      of seToolCallStart:
        content.add newToolContent(p.toolId, p.toolName, p.toolArgs)
        tcs.add %*{
          "id": p.toolId, "type": "function",
          "function": {"name": p.toolName, "arguments": $p.toolArgs}
        }
        anyTool = true
      of seEnd:
        stop = p.stopReason

    let asstMsg = Message(kind: mkAssistant, assistantContent: content, stopReason: stop)
    session.append(asstMsg)
    history.add asstMsg

    # 更新给 LLM 的 assistant 消息（含 tool_calls）
    msgs[^1] = ChatMessage(role: "assistant",
      content: if content.len == 0 or content[0].kind != ctText: ""
               else: content[0].text,
      toolCalls: tcs)

    if not anyTool:
      break

    # 执行工具
    for c in content:
      if c.kind == ctToolCall:
        let r = driver.agent.handler(c.name, c.arguments, driver.agent.cwd)
        let tr = Message(kind: mkToolResult, toolCallId: c.id,
                         toolName: c.name, toolText: r.text, isError: r.isError)
        session.append(tr)
        history.add tr
        msgs.add ChatMessage(role: "tool", toolCallId: c.id, toolName: c.name, content: r.text)

  return history

proc runTui*(driver: AgentDriver, session: var Session, cwd: string): int =
  ## 全屏 TUI 交互循环。
  var tui = initTui()
  # slash 命令分发上下文（只捕获 ref/基本类型避免 memory-safety）
  let commands = buildCommands()
  var sessionMsgCount = session.messages.len
  let slashCtx = proc(name: string): string {.closure.} =
    case name.split(' ')[0]
    of "model": return "当前模型: " & driver.client.opts.model & " (" & driver.client.opts.provider & ")"
    of "compact": return "会话已压缩（当前 MVP 自动按 context window 压缩）"
    of "new": return "可用 --no-session 开启新会话"
    of "resume": return "可用 npi -r 恢复最近会话"
    of "session": return "会话消息数: " & $sessionMsgCount
    of "skill":
      let arg = name["skill".len .. ^1].strip
      if arg.len == 0: return "用法: /skill <技能名>. 使用 /help 查看可用命令"
      return "技能 " & arg & " 需在 system prompt 中注入后由模型匹配"
    else: return name
  tui.addLine("npi — Nim 编码 agent。输入问题，Enter 发送，Ctrl+C 退出。")
  let templates = loadTemplates(cwd)  # 加载 prompt 模板
  tui.render()
  var currentMark = 0
  while not tui.exitApp:
    # 轮询：非阻塞，需要一个小的 sleep
    let ev = tui.poll()
    if ev.kind == evQuit or ev.kind == evCtrlC:
      tui.exitApp = true
      break
    elif ev.kind == evEnter:
      let text0 = tui.input.strip
      if text0.len == 0: discard
      # prompt 模板展开优先：/name 命中模板 → 替换为展开内容转为对话
      var text = text0
      if text0.startsWith("/") and not commands.hasKey(parseSlash(text0).command):
        let expanded = expandPromptTemplate(text0, templates)
        if expanded != text0:
          tui.addLine("> " & text0 & "（模板展开）")
          text = expanded
      if text.startsWith("/"):
        # slash 命令分发
        if text == text0 and text0.startsWith("/"):
          tui.addLine("> " & text)
        let r = handleSlash(commands, text, slashCtx)
        if r.shouldQuit:
          tui.exitApp = true
          break
        if r.output.len > 0:
          tui.addLine(r.output)
        tui.render()
        tui.input = ""
        tui.cursor = 0
      else:
        tui.addLine("> " & text)
        tui.setStatus("正在思考… (Ctrl+C 中断)")
        tui.render()
        var acc = ""
        tui.addLine("")
        currentMark = tui.history.len
        discard runConversation(driver, session, text) do (d: string):
          acc.add d
          # 流式追加到最后一条 assistant 行
          if tui.history.len >= currentMark:
            tui.history[currentMark - 1].text = acc
            tui.render()
        do (name: string):
          tui.addLine("  [工具] " & name & " …")
          tui.render()
        if acc.len > 0 and tui.history.len >= currentMark:
          tui.history[currentMark - 1].text = acc
        tui.setStatus("npi — Enter 发送 · ↑/↓ 滚动 · Ctrl+C 退出")
        tui.input = ""
        tui.cursor = 0
        tui.scrollOffset = 0
        tui.render()
    else:
      tui.handleInput(ev)
      tui.render()
    os.sleep(10)
  tui.deinit()
  return 0

proc runRepl*(driver: AgentDriver, session: var Session, cwd: string): int =
  ## 简易 REPL（stdin 非 TTY 时用）。
  let commands = buildCommands()
  var sessionMsgCount = session.messages.len
  let slashCtx = proc(name: string): string {.closure.} =
    case name.split(' ')[0]
    of "model": return "当前模型: " & driver.client.opts.model
    of "compact": return "会话已压缩"
    of "new": return "可用 --no-session 开启新会话"
    of "resume": return "可用 npi -r 恢复最近会话"
    of "session": return "会话消息数: " & $sessionMsgCount
    of "skill": return name
    else: return name
  while true:
    stdout.write("> ")
    stdout.flushFile()
    let line = stdin.readLine()
    if line.strip.len == 0: continue
    let templates = loadTemplates(cwd)
    var input = line.strip
    # 模板展开优先（/name 命中模板且非 slash 命令 → 转对话）
    if input.startsWith("/") and not commands.hasKey(parseSlash(input).command):
      let expanded = expandPromptTemplate(input, templates)
      if expanded != input:
        input = expanded
    if input.startsWith("/"):
      let r = handleSlash(commands, input, slashCtx)
      if r.shouldQuit: break
      if r.output.len > 0: echo r.output
      continue
    var acc = ""
    discard runConversation(driver, session, input) do (d: string):
      acc.add d
      stdout.write(d)
      stdout.flushFile()
    do (name: string):
      echo "\n  [工具] " & name
    echo ""
    stdout.flushFile()
  return 0

proc printMessage(d: string) =
  stdout.write(d)
  stdout.flushFile()

proc main() =
  let args = parseArgs(commandLineParams())
  if args.listModels:
    stdout.write("默认模型: " & args.model & "\n")
    quit(0)
  if args.apiKey.len == 0 and args.baseUrl.len == 0:
    stderr.write("错误: 未设置 OPENAI_API_KEY（或用 --api-key）。\n")
    quit(1)

  let cwd = getCurrentDir()
  var agent = newAgent(nil, cwd)
  agent.maxIterations = args.maxIterations
  agent.compactionSettings = defaultCompactionSettings()
  # 可配置 context window（测试/调优用）
  let cwEnv = getEnv("NPI_CONTEXT_WINDOW", "")
  if cwEnv.len > 0:
    try:
      agent.compactionSettings.contextWindow = parseInt(cwEnv)
    except ValueError: discard
  agent.setSystemPrompt(systemPrompt(cwd))

  let client = newLlmClient(ClientOptions(
    provider: args.provider,
    apiKey: args.apiKey, baseUrl: args.baseUrl,
    model: args.model, timeoutMs: 300000))
  let driver = AgentDriver(client: client, agent: agent)

  # 会话
  var session = Session()
  if not args.noSession:
    if args.resume:
      # 找最近会话
      if dirExists(args.sessionDir):
        var newest = ""
        for f in walkFiles(args.sessionDir / "session-*.jsonl"):
          if newest.len == 0 or f > newest: newest = f
        if newest.len > 0:
          session.load(newest)
    else:
      session = newSession(args.sessionDir)

  # 首次提示词（若有）
  if args.prompt.len > 0:
    var acc = ""
    discard runConversation(driver, session, args.prompt) do (d: string):
      acc.add d
      stdout.write(d)
      stdout.flushFile()
    do (name: string):
      echo "\n  [工具] " & name
    echo "\n"

    if args.printMode:
      quit(0)

  # 交互模式
  if isatty(stdout):
    discard runTui(driver, session, cwd)
  else:
    discard runRepl(driver, session, cwd)

main()
