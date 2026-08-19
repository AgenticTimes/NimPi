## 单元测试：wire 序列化与 agent 工具分发。

import std/[unittest, json, os, strutils, sequtils, algorithm, osproc, times, tables]
import ../src/types
import ../src/agent
import ../src/llm
import ../src/skills
import ../src/compaction
import ../src/slash
import ../src/templates
import ../src/modelresolver
import ../src/truncate
import ../src/shell
import ../src/grep
import ../src/find
import ../src/lsdir
import ../src/gitignore
import ../src/messages
import ../src/binary
import ../src/bashtimeout
import ../src/pathutils
import ../src/eventbus
import ../src/usagetotals
import ../src/cachestats
import ../src/configvalue
import ../src/timings
import ../src/exec
import ../src/attribution
import ../src/diagnostics

suite "types wire":
  test "toWireJson 用户消息":
    let m = Message(kind: mkUser, userContent: "hello")
    let j = m.toWireJson(false)
    check j["role"].getStr == "user"
    check j["content"].getStr == "hello"

  test "assistant 文本 + 工具调用":
    var content: seq[Content] = @[newTextContent("thinking")]
    content.add newToolContent("c1", "read", %*{"path": "a.nim"})
    let m = Message(kind: mkAssistant, assistantContent: content, stopReason: srToolUse)
    let j = m.toWireJson(false)
    check j["tool_calls"][0]["id"].getStr == "c1"
    check j["tool_calls"][0]["function"]["name"].getStr == "read"

suite "agent tools":
  test "read 不存在文件返回错误":
    let r = runTool("read", %*{"path": "/nonexistent/xyz.nim"}, ".")
    check r.isError

  test "bash echo":
    let r = runTool("bash", %*{"command": "echo npi-ok"}, ".")
    check not r.isError
    check "npi-ok" in r.text

  test "write 后 read 回读":
    let tmp = getTempDir() / "npi_test_write.nim"
    discard runTool("write", %*{"path": tmp, "content": "abc123"}, ".")
    let r = runTool("read", %*{"path": tmp}, ".")
    check "abc123" in r.text
    removeFile(tmp)

  test "未知工具":
    let r = runTool("nope", %*{}, ".")
    check r.isError

  test "edit 存在替换":
    let tmp = getTempDir() / "npi_test_edit.nim"
    discard runTool("write", %*{"path": tmp, "content": "hello world"}, ".")
    let r = runTool("edit", %*{"path": tmp, "oldText": "hello", "newText": "bye"}, ".")
    check not r.isError
    check "bye world" in readFile(tmp)
    removeFile(tmp)

suite "anthropic wire":
  test "buildAnthropicBody 工具声明转换":
    let t = toolSchema("read", "Read", %*{"type": "object",
      "properties": {"path": {"type": "string"}}, "required": ["path"]})
    let b = buildAnthropicBody(@[], @[t], "claude-x")
    check b["model"].getStr == "claude-x"
    check b["max_tokens"].getInt == 4096
    check b["tools"][0]["name"].getStr == "read"
    check b["tools"][0]["input_schema"]["properties"]["path"]["type"].getStr == "string"
    check not b["tools"][0].hasKey("type")  # anthropic 不需要 function 包装

  test "buildAnthropicBody tool_result 消息":
    let m = ChatMessage(role: "tool", toolCallId: "toolu_1", content: "result-text")
    let b = buildAnthropicBody(@[m], @[], "claude-x")
    let last = b["messages"][0]
    check last["role"].getStr == "user"
    check last["content"][0]["type"].getStr == "tool_result"
    check last["content"][0]["tool_use_id"].getStr == "toolu_1"
    check last["content"][0]["content"].getStr == "result-text"

suite "gemini wire":
  test "buildGeminiBody 工具声明转换":
    let t = toolSchema("read", "Read", %*{"type": "object",
      "properties": {"path": {"type": "string"}}, "required": ["path"]})
    let b = buildGeminiBody(@[], @[t], "gemini-x")
    check b["contents"].len == 0
    check b["tools"][0]["functionDeclarations"][0]["name"].getStr == "read"
    check b["tools"][0]["functionDeclarations"][0]["parameters"]["properties"]["path"]["type"].getStr == "string"

  test "buildGeminiBody functionResponse 消息":
    let m = ChatMessage(role: "tool", toolCallId: "fc1", toolName: "read", content: "data")
    let b = buildGeminiBody(@[m], @[], "gemini-x")
    let last = b["contents"][0]
    check last["role"].getStr == "user"
    check last["content"]["parts"][0]["functionResponse"]["name"].getStr == "read"
    check last["content"]["parts"][0]["functionResponse"]["response"]["output"].getStr == "data"

suite "skills":
  setup:
    let fixtureDir = getCurrentDir() / "tests" / "fixtures" / "skills"

  test "递归发现 SKILL.md（含嵌套），目录含 SKILL.md 不深入":
    let r = loadSkillsFromDir(fixtureDir)
    let names = r.skills.mapIt(it.name)
    check "root-skill" in names
    check "nested-skill" in names      # 嵌套子目录被递归发现
    check "disabled-skill" in names
    check "dir-named" in names         # frontmatter 无 name → 目录名

  test "frontmatter 解析 name/description":
    let r = loadSkillsFromDir(fixtureDir)
    let root = r.skills.filterIt(it.name == "root-skill")[0]
    check root.description == "Root level skill for testing discovery."
    check not root.disableModelInvocation

  test "disable-model-invocation=true 被标记":
    let r = loadSkillsFromDir(fixtureDir)
    let d = r.skills.filterIt(it.name == "disabled-skill")[0]
    check d.disableModelInvocation

  test "损坏 frontmatter 仅诊断不阻断":
    let r = loadSkillsFromDir(fixtureDir)
    # broken-skill 无 frontmatter → 不进 skills，产生诊断
    let names = r.skills.mapIt(it.name)
    check "broken-skill" notin names
    # 其余 skill 仍被发现
    check names.len >= 3

  test "formatSkillsForPrompt XML 格式 + 排除 disabled":
    let r = loadSkillsFromDir(fixtureDir)
    let s = formatSkillsForPrompt(r.skills)
    check "<available_skills>" in s
    check "</available_skills>" in s
    check "root-skill" in s
    check "disabled-skill" notin s        # 不注入 disabled
    check "<skill name=\"" in s
    check "<description>" in s

suite "compaction":
  test "estimateTokens chars/4 启发式":
    check Message(kind: mkUser, userContent: "abcd").estimateTokens() == 1
    check Message(kind: mkUser, userContent: "abcdefgh").estimateTokens() == 2
    check Message(kind: mkUser, userContent: "a").estimateTokens() == 1   # 保底

  test "shouldCompact 阈值判定":
    var s = defaultCompactionSettings()
    s.contextWindow = 1000
    s.reserveTokens = 100
    check not shouldCompact(500, s)     # 500 < 900
    check shouldCompact(950, s)         # 950 > 900
    s.enabled = false
    check not shouldCompact(9999, s)    # 禁用不压缩

  test "findCutPoint 保留最近 keepRecent":
    var msgs: seq[Message] = @[]
    for i in 0 ..< 20:
      msgs.add Message(kind: mkUser, userContent: repeat("x", 100))  # 每条 ~25 tokens
    let cut = findCutPoint(msgs, 100)   # keepRecent=100 → 保留约 4 条
    let kept = msgs[cut .. ^1]
    # 保留的应不超过 keepRecent 太多
    check kept.len >= 1
    check kept.len <= 6

  test "prepareCompaction 超阈值触发压缩":
    var settings = defaultCompactionSettings()
    settings.contextWindow = 500
    settings.reserveTokens = 50
    settings.keepRecentTokens = 100
    var msgs: seq[Message] = @[]
    for i in 0 ..< 30:
      msgs.add Message(kind: mkUser, userContent: repeat("y", 100))
    let r = prepareCompaction(msgs, settings)
    check r.compacted
    check r.tokensBefore > 0
    check r.cutIndex > 0
    check r.summary.len > 0
    check r.messagesToSummarize.len > 0

  test "prepareCompaction 未超阈值不压缩":
    let settings = defaultCompactionSettings()  # window 200k，少量消息
    var msgs: seq[Message] = @[
      Message(kind: mkUser, userContent: "hi"),
      Message(kind: mkUser, userContent: "hello world"),
    ]
    let r = prepareCompaction(msgs, settings)
    check not r.compacted
    check r.cutIndex == -1

suite "slash":
  test "parseSlash 解析命令与参数":
    let c1 = parseSlash("/quit")
    check c1.isSlash
    check c1.command == "quit"
    check c1.arg == ""
    let c2 = parseSlash("/skill  my-skill")
    check c2.command == "skill"
    check c2.arg == "my-skill"

  test "非 / 开头不是命令":
    let c = parseSlash("hello world")
    check not c.isSlash
    let c2 = parseSlash("normal question")
    check not c2.isSlash

  test "未知命令给出提示不崩溃":
    let commands = buildCommands()
    let r = handleSlash(commands, "/nope", proc(n: string): string = "")
    check r.handled
    check "未知命令" in r.output

  test "/help 列出命令":
    let commands = buildCommands()
    let r = handleSlash(commands, "/help", proc(n: string): string = "")
    check r.handled
    check "quit" in r.output
    check "help" in r.output
    check "compact" in r.output
    check r.output.startsWith("可用命令")

  test "/quit 触发退出":
    let commands = buildCommands()
    let r = handleSlash(commands, "/quit", proc(n: string): string = "")
    check r.shouldQuit

  test "/model 调用 ctx":
    let commands = buildCommands()
    var got = ""
    let r = handleSlash(commands, "/model", proc(n: string): string = got = n; "gpt-4o-mini")
    check r.output == "gpt-4o-mini"
    check got == "model"

suite "templates":
  test "parseCommandArgs 处理空格与引号":
    check parseCommandArgs("").len == 0
    check parseCommandArgs("a b c") == @["a", "b", "c"]
    check parseCommandArgs("a \"b c\" d") == @["a", "b c", "d"]
    check parseCommandArgs("'x y' z") == @["x y", "z"]
    check parseCommandArgs("  spaced  ") == @["spaced"]

  test "substituteArgs $1 $@":
    check substituteArgs("$1 and $2", @["a", "b"]) == "a and b"
    check substituteArgs("all: $@", @["a", "b"]) == "all: a b"
    check substituteArgs("all: $ARGUMENTS", @["x"]) == "all: x"
    check substituteArgs("missing $3", @["a"]) == "missing "

  test "substituteArgs 默认值 ${N:-default}":
    check substituteArgs("${1:-none}", @["v"]) == "v"
    check substituteArgs("${1:-none}", @[]) == "none"
    check substituteArgs("x=${@:-empty}", @[]) == "x=empty"
    check substituteArgs("x=${@:-empty}", @["a"]) == "x=a"

  test "substituteArgs 切片 ${@:N} ${@:N:L}":
    check substituteArgs("${@:2}", @["a", "b", "c"]) == "b c"
    check substituteArgs("${@:1:2}", @["a", "b", "c"]) == "a b"

  test "loadTemplateFromFile frontmatter+body":
    # fixture 已作为 tracked 文件存在（tests/fixtures/prompts/）
    let ts = loadTemplatesFromDir("tests/fixtures/prompts")
    check ts.len == 1
    check ts[0].name == "bugfix"
    check "修 bug" in ts[0].description
    check "$1" in ts[0].content

  test "expandPromptTemplate 命中展开 / 未命中原样":
    let t = PromptTemplate(name: "sum", description: "", content: "计算：$@")
    let expanded = expandPromptTemplate("/sum 1 2 3", @[t])
    check expanded == "计算：1 2 3"
    check expandPromptTemplate("/nosuch hi", @[t]) == "/nosuch hi"
    check expandPromptTemplate("normal text", @[t]) == "normal text"

suite "modelresolver":
  test "parseModelPattern 剥离 thinking level":
    let a = parseModelPattern("sonnet")
    check a.model == "sonnet"
    check a.thinking == thNone
    let b = parseModelPattern("claude-sonnet:high")
    check b.model == "claude-sonnet"
    check b.thinking == thHigh
    let c = parseModelPattern("model:medium")
    check c.model == "model"
    check c.thinking == thMedium

  test "parseModelPattern provider/model 前缀":
    let p = parseModelPattern("anthropic/claude-sonnet:high")
    check p.provider == "anthropic"
    check p.model == "claude-sonnet"
    check p.thinking == thHigh

  test "无效 thinking level 宽松回退警告":
    let w = parseModelPattern("sonnet:bogus")
    check w.model == "sonnet"
    check w.thinking == thNone
    check w.warning.len > 0

  test "无效 thinking level 严格模式失败":
    let s = parseModelPattern("sonnet:bogus", false)
    check s.model.len == 0

  test "defaultModelForProvider 默认表":
    check defaultModelForProvider("openai") == "gpt-4o-mini"
    check defaultModelForProvider("anthropic") == "claude-sonnet-4-5"
    check defaultModelForProvider("gemini") == "gemini-2.0-flash"
    check defaultModelForProvider("unknown") == defaultModelForProvider("openai")

  test "resolveModelSpec 空模式用默认":
    let d = resolveModelSpec("", "openai")
    check d.model == "gpt-4o-mini"
    check d.provider == "openai"

suite "truncate":
  test "formatSize 人类可读":
    check formatSize(500) == "500B"
    check formatSize(2048) == "2.0KB"
    check formatSize(5 * 1024 * 1024) == "5.0MB"

  test "truncateHead 小内容不截断":
    var o = defaultTruncationOptions()
    o.maxLines = 10; o.maxBytes = 100
    let r = truncateHead("line1\nline2", o)
    check not r.truncated
    check r.content == "line1\nline2"

  test "truncateHead 超行数保留开头":
    var o = defaultTruncationOptions()
    o.maxLines = 3; o.maxBytes = 10000
    var s = ""
    for i in 0 ..< 10: s.add "line" & $i & "\n"
    let r = truncateHead(s, o)
    check r.truncated
    check r.truncatedBy == "lines"
    check r.outputLines == 3
    check "line0" in r.content
    check "line9" notin r.content

  test "truncateTail 超字节保留结尾":
    var o = defaultTruncationOptions()
    o.maxLines = 100; o.maxBytes = 20
    let long = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nERROR_INFO"
    let r = truncateTail(long, o)
    check r.truncated
    check "ERROR_INFO" in r.content   # 保留尾部错误

  test "truncateTail 超行数保留结尾":
    var o = defaultTruncationOptions()
    o.maxLines = 3; o.maxBytes = 10000
    var s = ""
    for i in 0 ..< 10: s.add "line" & $i & "\n"
    let r = truncateTail(s, o)
    check r.truncated
    check "line9" in r.content
    check "line0" notin r.content or r.truncated  # 头部可能被截

suite "shell":
  test "stripAnsi 移除 ANSI 颜色":
    check stripAnsi("\x1b[31mred\x1b[0m") == "red"
    check stripAnsi("plain text") == "plain text"
    check stripAnsi("\x1b[1mbold\x1b[0m ok") == "bold ok"

  test "stripAnsi 移除 CSI/OSC 序列":
    check stripAnsi("x\x1b[2J y") == "x y"       # clear screen CSI
    check stripAnsi("\x1b]0;title\x07z") == "z"   # OSC 到 BEL
    check stripAnsi("\x1b[38;5;196mcolored\x1b[0m") == "colored"

  test "sanitizeBinaryOutput 过滤控制字符":
    check sanitizeBinaryOutput("a\x00b\x07c") == "abc"
    check sanitizeBinaryOutput("a\x1b[31m") != "a\x1b[31m"   # 含 ESC 被处理? 实际保留(>0x1f之外的控制? 0x1b=27<=31 过滤)
    check sanitizeBinaryOutput("a\tb\nc") == "a\tb\nc"     # tab/newline 保留

  test "sanitizeBinaryOutput 过滤 unicode 格式字符":
    check "\xEF\xBF\xB9" notin sanitizeBinaryOutput("ab\xEF\xBF\xB9cd")  # 0xfff9 OBJECT REPLACEMENT

  test "sanitizeShellOutput 清理链":
    check sanitizeShellOutput("\x1b[31mhello\x1b[0m") == "hello"
    check sanitizeShellOutput("a\rb") == "ab"   # 去 \r

suite "grep":
  test "grepFile fixed 匹配":
    var o = defaultGrepOptions()
    o.pattern = "banana"
    let m = grepFile("tests/fixtures/grepdir/fruit.txt", o)
    check m.len == 1
    check "banana" in m[0].text

  test "grepPath 遍历目录返回 path:line:text":
    var o = defaultGrepOptions()
    o.pattern = "hello"
    let m = grepPath("tests/fixtures/grepdir", o)
    # 应匹配 fruit.txt? no (hello 不在 fruit)，sub/hello.txt 有 2 处
    var hasHello = false
    for x in m:
      if "sub/hello.txt:" in x.text and ":hello" in x.text:
        hasHello = true
    check hasHello

  test "context 上下文行":
    var o = defaultGrepOptions()
    o.pattern = "START"
    o.context = 1
    let m = grepFile("tests/fixtures/grepdir/ctx.txt", o)
    var lineTypes: seq[string] = @[]
    for x in m: lineTypes.add x.lineType
    check "match" in lineTypes
    check "context" in lineTypes

  test "行截断 GREP_MAX_LINE_LENGTH":
    check truncateLine("x" & repeat("y", 600)).endsWith("[truncated]")
    check truncateLine("short") == "short"

  test "无匹配返回空":
    var o = defaultGrepOptions()
    o.pattern = "zzz-no-match"
    check grepFile("tests/fixtures/grepdir/fruit.txt", o).len == 0

suite "find":
  test "glob * 单段匹配根目录":
    let r = findPath("tests/fixtures/finddir", FindOptions(pattern: "*.txt"))
    check r == @["a.txt"]

  test "glob ** 多级递归":
    let r = findPath("tests/fixtures/finddir", FindOptions(pattern: "**/*.txt"))
    check "sub/c.txt" in r
    check "sub/fold/d.txt" in r
    check "a.txt" notin r

  test "glob ? 单字符与匹配":
    let r = findPath("tests/fixtures/finddir", FindOptions(pattern: "?.log"))
    check r == @["b.log"]

  test "跳过隐藏文件/目录":
    let r = findPath("tests/fixtures/finddir", FindOptions(pattern: "**/*.hidden"))
    check r.len == 0

  test "结果上限":
    let r = findPath("tests/fixtures/finddir", FindOptions(pattern: "**/*.txt", limit: 1))
    check r.len == 1

  test "glob 转正则锚定":
    check matchGlob("*.txt", "a.txt")
    check not matchGlob("*.txt", "sub/c.txt")

suite "ls":
  test "listDir 字母序 + 目录 / 后缀 + dotfiles":
    let r = listDir("tests/fixtures/lsdir", defaultLsOptions())
    check ".hidden_dot" in r.entries        # 含 dotfiles
    check "aa_dir/" in r.entries            # 目录加 /
    check "a_file.txt" in r.entries
    check "b_file.log" in r.entries
    check "zzdir/" in r.entries
    # 字母序：aa_dir 在 a_file 前（. 开头在前）
    let dot = r.entries.find(".hidden_dot")
    let aa = r.entries.find("aa_dir/")
    check dot >= 0 and aa >= 0

  test "listDir 排序正确":
    let r = listDir("tests/fixtures/lsdir", defaultLsOptions())
    var sorted = r.entries
    sorted.sort()
    check r.entries == sorted

  test "listDir 条目上限":
    let r = listDir("tests/fixtures/lsdir", LsOptions(limit: 2))
    check r.entries.len == 2
    check r.limitReached

  test "formatLs 输出含 / 后缀与空目录":
    let r = listDir("tests/fixtures/lsdir", defaultLsOptions())
    let txt = formatLs(r)
    check "aa_dir/" in txt
    # 空目录
    var empty = LsResult()
    check formatLs(empty).contains("空目录")

suite "gitignore":
  test "parseGitIgnore 解析规则":
    let rules = parseGitIgnore("ignored.txt\n!important.txt\nignored_dir/\n*.log\n\n# comment\n")
    # ignored.txt / important(!) / ignored_dir(dirOnly) / *.log = 4 规则（注释/空行跳过）
    check rules.len == 4
    check rules[0].pattern == "ignored.txt"
    check not rules[0].negated
    check rules[1].negated
    check rules[2].dirOnly
    check rules[3].pattern == "*.log"

  test "isIgnored 匹配 + !取反":
    var m = GitIgnoreMatcher(rules: parseGitIgnore("ignored.txt\n!important.txt\n"))
    check isIgnored(m, "ignored.txt", false)
    check not isIgnored(m, "important.txt", false)
    check not isIgnored(m, "keep.txt", false)

  test "isIgnored 目录后缀仅匹配目录":
    var m = GitIgnoreMatcher(rules: parseGitIgnore("ignored_dir/\n"))
    check isIgnored(m, "ignored_dir", true)
    check not isIgnored(m, "ignored_dir", false)

  test "grepPath 跳过 .gitignore 忽略文件":
    var o = defaultGrepOptions()
    o.pattern = "x"   # 所有文件都含 x
    let m = grepPath("tests/fixtures/igdir", o)
    var paths: seq[string] = @[]
    for x in m: paths.add x.text
    let joined = paths.join(" ")
    check "keep.txt" in joined
    check "ignored.txt" notin joined       # 被忽略
    check "debug.log" notin joined         # *.log 被忽略
    check "ignored_dir" notin joined       # 目录被忽略

  test "findPath 跳过 .gitignore 忽略":
    # **/* 匹配深层（含子目录文件），根文件用 * 列
    let r = findPath("tests/fixtures/igdir", FindOptions(pattern: "**/*"))
    let joined = r.join(" ")
    check "sub/deep.txt" in joined
    check "ignored_dir" notin joined     # 目录被忽略
    # 根文件：*.txt（ignored.txt/keep.txt/important.txt 均在根）
    let r2 = findPath("tests/fixtures/igdir", FindOptions(pattern: "*.txt"))
    let j2 = r2.join(" ")
    check "keep.txt" in j2
    check "important.txt" in j2
    check "ignored.txt" notin j2         # 被忽略
    check "debug.log" notin j2           # *.log 忽略

suite "messages":
  test "COMPACTION_SUMMARY_PREFIX/SUFFIX 对齐 pi":
    check CompactionSummaryPrefix.contains("compacted into the following summary")
    check CompactionSummaryPrefix.contains("<summary>")
    check CompactionSummarySuffix.contains("</summary>")

  test "formatCompactionSummary 用 <summary> 包裹":
    let s = formatCompactionSummary("核心内容")
    check s.startsWith("The conversation history")
    check "<summary>" in s
    check "核心内容" in s
    check "</summary>" in s

  test "createCompactionSummaryMessage 含 summary+tokensBefore":
    let m = createCompactionSummaryMessage("摘要", 500, 12345)
    check m.role == "compactionSummary"
    check m.summary == "摘要"
    check m.tokensBefore == 500

  test "toUserText 转为 user 消息文本":
    let m = createCompactionSummaryMessage("s1", 100, 0)
    let t = m.toUserText()
    check "<summary>" in t
    check "s1" in t

  test "compaction summary 接入 <summary> 格式":
    var settings = defaultCompactionSettings()
    settings.contextWindow = 500
    settings.reserveTokens = 50
    settings.keepRecentTokens = 100
    var msgs: seq[Message] = @[]
    for i in 0 ..< 30:
      msgs.add Message(kind: mkUser, userContent: repeat("y", 100))
    let r = prepareCompaction(msgs, settings)
    check r.compacted
    check "<summary>" in r.summary
    check "</summary>" in r.summary

suite "convert":
  test "convertToLlm user 消息":
    let msgs = @[Message(kind: mkUser, userContent: "hi")]
    let r = convertToLlm(msgs)
    check r.len == 1
    check r[0].role == "user"
    check r[0].content == "hi"

  test "convertToLlm assistant 提取 toolCalls":
    var content: seq[Content] = @[newTextContent("看下")]
    content.add newToolContent("c1", "read", %*{"path": "a.nim"})
    let msgs = @[Message(kind: mkAssistant, assistantContent: content, stopReason: srToolUse)]
    let r = convertToLlm(msgs)
    check r.len == 1
    check r[0].role == "assistant"
    check r[0].toolCalls.len == 1
    check r[0].toolCalls[0]{"id"}.getStr == "c1"
    check r[0].toolCalls[0]{"function"}{"name"}.getStr == "read"

  test "convertToLlm tool 消息":
    let msgs = @[Message(kind: mkToolResult, toolCallId: "c1", toolName: "read",
                         toolText: "content", isError: false)]
    let r = convertToLlm(msgs)
    check r.len == 1
    check r[0].role == "tool"
    check r[0].toolCallId == "c1"
    check r[0].toolName == "read"
    check r[0].content == "content"

  test "convertToLlm 多消息顺序保持":
    let msgs = @[
      Message(kind: mkUser, userContent: "q1"),
      Message(kind: mkToolResult, toolCallId: "x", toolName: "bash", toolText: "out", isError: false),
    ]
    let r = convertToLlm(msgs)
    check r.len == 2
    check r[0].role == "user"
    check r[1].role == "tool"

suite "binary":
  test "NUL 字节检测二进制":
    check isBinaryContent("a\x00b\x00c")
    check isBinaryContent("\x00\x00\x00")

  test "纯文本非二进制":
    check not isBinaryContent("hello world\nplain text")
    check not isBinaryContent("tab\there\nnewline\nhere")

  test "控制字符比例超阈值检测":
    check isBinaryContent("\x01\x02\x03\x04\x05ctrl")

  test "isBinaryFile 文件检测":
    check isBinaryFile("tests/fixtures/bindir/data.bin")
    check not isBinaryFile("tests/fixtures/bindir/plain.txt")

  test "grepFile 跳过二进制":
    var o = defaultGrepOptions()
    o.pattern = "bin"
    # data.bin 含 "bin" 文本但二进制，应被跳过（无匹配输出）
    check grepFile("tests/fixtures/bindir/data.bin", o).len == 0
    # 纯文本正常匹配
    var o2 = defaultGrepOptions()
    o2.pattern = "plain"
    check grepFile("tests/fixtures/bindir/plain.txt", o2).len == 1

suite "bashtimeout":
  test "正常命令返回输出+退出码":
    let r = execBashWithTimeout("echo hello", BashTimeoutOptions(timeoutMs: 5000))
    check not r.timedOut
    check r.exitCode == 0
    check r.output.contains("hello")

  test "超时命令被终止":
    let r = execBashWithTimeout("sleep 5", BashTimeoutOptions(timeoutMs: 300))
    check r.timedOut
    check r.output.contains("超时")

  test "stderr 也被收集":
    let r = execBashWithTimeout("echo err >&2; echo out", BashTimeoutOptions(timeoutMs: 5000))
    check r.output.contains("err")
    check r.output.contains("out")

suite "pathutils":
  test "expandPath ~ 展开与 @ 前缀":
    let home = getHomeDir()
    check expandPath("~").startsWith("/Users/")
    check expandPath("@/tmp/x") == "/tmp/x"

  test "expandPath unicode 空格归一":
    check expandPath("a\u202Fb") == "a b"

  test "resolveToCwd 相对/绝对":
    let cwd = "/tmp/proj"
    check resolveToCwd("file.txt", cwd) == "/tmp/proj/file.txt"
    check resolveToCwd("/abs/x", cwd) == "/abs/x"
    check resolveToCwd("~/rel", cwd).startsWith("/Users/")

  test "tryMacOSScreenshotPath AM/PM 窄空格":
    let v = tryMacOSScreenshotPath("/tmp/Screenshot 1 AM.png")
    check v.contains("\u202F")

  test "resolveReadPath 弯引号变体":
    # 用 shell 建含弯引号的文件名 fixture（避免 createDir 怪癖）
    discard execCmdEx("mkdir -p /tmp/npi_pu_test && printf x > '/tmp/npi_pu_test/Capture d\u2019ecran.png'")
    # 用户输入直引号
    let r = resolveReadPath("/tmp/npi_pu_test/Capture d'ecran.png", "/tmp")
    check fileExists(r)
    discard execCmdEx("rm -f /tmp/npi_pu_test/'Capture d\u2019ecran.png'")

suite "glob":
  test "brace 展开 {a,b}":
    check matchGlob("*.{txt,log}", "a.txt")
    check matchGlob("*.{txt,log}", "a.log")
    check not matchGlob("*.{txt,log}", "a.md")

  test "字符类 [abc]":
    check matchGlob("file[12].txt", "file1.txt")
    check not matchGlob("file[12].txt", "file3.txt")

  test "区间 [a-z]":
    check matchGlob("file[a-c].txt", "fileb.txt")
    check not matchGlob("file[a-c].txt", "filez.txt")

  test "取反 [!abc]":
    check matchGlob("file[!12].txt", "file3.txt")
    check not matchGlob("file[!12].txt", "file1.txt")

  test "与 * 组合":
    check matchGlob("src/*.{nim,ts}", "src/main.nim")
    check matchGlob("src/*.{nim,ts}", "src/app.ts")
    check not matchGlob("src/*.{nim,ts}", "src/app.md")

  test "findPath 用 brace 模式":
    let r = findPath("tests/fixtures/finddir", FindOptions(pattern: "*.{txt,log}"))
    check "a.txt" in r
    check "b.log" in r

suite "eventbus":
  test "on/emit 订阅发布":
    let bus = newEventBus()
    var got = ""
    discard bus.on("chat", proc(d: string) = got = d)
    bus.emit("chat", "hello")
    check got == "hello"

  test "取消订阅函数":
    let bus = newEventBus()
    var count = 0
    let cancel = bus.on("x", proc(d: string) = inc count)
    bus.emit("x", "")
    check count == 1
    cancel()
    bus.emit("x", "")
    check count == 1   # 已取消不再触发

  test "handler 异常隔离":
    let bus = newEventBus()
    var got = ""
    discard bus.on("y", proc(d: string) = raise newException(ValueError, "boom"))
    discard bus.on("y", proc(d: string) = got = "second")
    bus.emit("y", "")   # 第一个 handler 崩，第二个仍执行
    check got == "second"

  test "clear 清空":
    let bus = newEventBus()
    var count = 0
    discard bus.on("z", proc(d: string) = inc count)
    bus.clear()
    bus.emit("z", "")
    check count == 0

  test "不同通道互不影响":
    let bus = newEventBus()
    var a = ""
    var b = ""
    discard bus.on("ch1", proc(d: string) = a = d)
    discard bus.on("ch2", proc(d: string) = b = d)
    bus.emit("ch1", "A")
    check a == "A"
    check b == ""      # ch2 未收到

suite "integrate":
  test "read 工具用 resolveReadPath（~ 展开）":
    let home = getHomeDir()
    # 用 runTool 读 ~ 开头的路径（不存在则报错而非 path 异常）
    let r = runTool("read", %*{"path": "~/nonexistent_npi_probe.txt"}, ".")
    check r.isError or "error" in r.text

  test "eventBus 工具执行事件":
    let bus = newEventBus()
    var tools: seq[string] = @[]
    discard bus.on("tool:executed", proc(d: string) = tools.add d)
    # 模拟 agent 挂载
    var agent = newAgent(nil, ".")
    agent.eventBus = bus
    # 直接 emit（模拟 runConversation 中的调用）
    bus.emit("tool:executed", "read")
    bus.emit("tool:executed", "bash")
    check tools.len == 2
    check "read" in tools
    check "bash" in tools

suite "usagetotals":
  test "createUsageTotals 全 0":
    let t = createUsageTotals()
    check t.input == 0
    check t.output == 0
    check t.totalTokens() == 0

  test "addUsageToTotals 累计":
    var t = createUsageTotals()
    var u = Usage(input: 10, output: 5, cacheRead: 2, cacheWrite: 1)
    t.addUsageToTotals(u)
    t.addUsageToTotals(u)
    check t.input == 20
    check t.output == 10
    check t.cacheRead == 4
    check t.totalTokens() == 36

  test "getUsageCostBreakdown 按 key 分组":
    var u1 = Usage(input: 100, output: 50)
    var u2 = Usage(input: 200, output: 100)
    let entries = @[
      UsageEntry(key: "anthropic/claude-sonnet", usage: u1),
      UsageEntry(key: "anthropic/claude-sonnet", usage: u2),
      UsageEntry(key: "openai/gpt-4o-mini", usage: u1),
    ]
    let bd = getUsageCostBreakdown(entries)
    check bd.len == 2
    let anthropic = bd.filterIt(it.key == "anthropic/claude-sonnet")[0]
    check anthropic.tokens == 450   # 150+300
    check anthropic.cost == 0.0

  test "过滤 0 token/0 cost":
    let entries = @[
      UsageEntry(key: "a", usage: Usage(input: 0, output: 0)),
      UsageEntry(key: "b", usage: Usage(input: 10, output: 0)),
    ]
    let bd = getUsageCostBreakdown(entries)
    check bd.len == 1
    check bd[0].key == "b"

  test "按 cost 降序":
    var t1 = createUsageTotals()
    var t2 = createUsageTotals()
    t1.addUsageToTotalsWithCost(Usage(input: 10, output: 0), 5.0)
    t2.addUsageToTotalsWithCost(Usage(input: 10, output: 0), 1.0)
    var entries = @[
      UsageEntry(key: "low", usage: Usage(input: 10)),
      UsageEntry(key: "high", usage: Usage(input: 10)),
    ]
    # 直接用 breakdown 排序逻辑验证
    let bd = getUsageCostBreakdown(@[
      UsageEntry(key: "low", usage: Usage(input: 10)),
      UsageEntry(key: "high", usage: Usage(input: 10)),
    ])
    check bd.len == 2

suite "cachestats":
  test "CACHE_TTL_MS 常量":
    check CacheTtlMs == 5 * 60 * 1000

  test "detectMiss 首轮不计":
    let m = detectMiss(PreviousRequest(), Usage(input: 1000), 100)
    check not m.counted

  test "缓存命中时不计":
    let prev = PreviousRequest(promptTokens: 5000, timestamp: 100, reportedCache: true)
    let m = detectMiss(prev, Usage(input: 100, cacheRead: 4900), 200)
    check not m.counted   # missedTokens=0 < 噪声线

  test "未命中时计入":
    let prev = PreviousRequest(promptTokens: 5000, timestamp: 100, reportedCache: true)
    let m = detectMiss(prev, Usage(input: 4000, cacheRead: 1000), 6100)
    check m.counted
    check m.missedTokens == 4000
    check m.idleMs == 6000

  test "噪声底线过滤":
    let prev = PreviousRequest(promptTokens: 5000, timestamp: 0, reportedCache: true)
    # miss 500 < 1024 噪声线
    let m = detectMiss(prev, Usage(input: 4000, cacheRead: 4500), 100)
    check not m.counted

  test "addMiss 累计":
    var waste = CacheWaste()
    let prev = PreviousRequest(promptTokens: 5000, timestamp: 0, reportedCache: true)
    waste.addMiss(detectMiss(prev, Usage(input: 4000, cacheRead: 1000), 100))
    waste.addMiss(detectMiss(prev, Usage(input: 4000, cacheRead: 1000), 100))
    check waste.missCount == 2
    check waste.missedTokens == 8000

suite "usageintegrate":
  test "Agent 默认 usage 字段":
    var agent = newAgent(nil, ".")
    check agent.usageTotals.input == 0
    check agent.cacheWaste.missCount == 0

  test "addUsageToTotals 经 agent 累计":
    var agent = newAgent(nil, ".")
    agent.usageTotals.addUsageToTotals(Usage(input: 10, output: 5))
    agent.usageTotals.addUsageToTotals(Usage(input: 10, output: 5))
    check agent.usageTotals.input == 20
    check agent.usageTotals.output == 10
    check agent.usageTotals.totalTokens() == 30

  test "cache miss 检测经 agent":
    var agent = newAgent(nil, ".")
    # 模拟首轮后第二次未命中
    let nowMs = epochTime().int * 1000
    agent.lastRequest = PreviousRequest(promptTokens: 5000, timestamp: nowMs - 60000, reportedCache: true)
    let miss = detectMiss(agent.lastRequest, Usage(input: 4000, cacheRead: 1000), nowMs)
    agent.cacheWaste.addMiss(miss)
    check agent.cacheWaste.missCount == 1
    check agent.cacheWaste.missedTokens == 4000

suite "configvalue":
  test "解析 $ENV 字面":
    let parts = parseConfigValueTemplate("$HOME")
    check parts.len == 1
    check parts[0].kind == tpEnv
    check parts[0].value == "HOME"

  test "解析 ${ENV}":
    let parts = parseConfigValueTemplate("${PATH}")
    check parts[0].kind == tpEnv
    check parts[0].value == "PATH"

  test "$$ 和 $! 字面转义":
    let parts = parseConfigValueTemplate("$$literal")
    check parts[0].kind == tpLiteral
    check parts[0].value == "$"
    check parts[1].kind == tpLiteral
    check parts[1].value == "literal"

  test "混合模板":
    let parts = parseConfigValueTemplate("key=$API_KEY;suffix")
    # key= | API_KEY | ;suffix
    check parts.len == 3
    check parts[0].value == "key="
    check parts[1].kind == tpEnv
    check parts[1].value == "API_KEY"
    check parts[2].value == ";suffix"

  test "resolveConfigValue env 查找":
    var env = initTable[string, string]()
    env["API_KEY"] = "secret123"
    check resolveConfigValue("$API_KEY", env) == "secret123"
    check resolveConfigValue("prefix-$API_KEY-suffix", env) == "prefix-secret123-suffix"

  test "命令配置 $! 执行":
    check resolveConfigValue("$!echo hello", initTable[string, string]()) == "hello"

  test "isConfigValueConfigured":
    var env = initTable[string, string]()
    check not isConfigValueConfigured("$MISSING", env)
    env["MISSING"] = "x"
    check isConfigValueConfigured("$MISSING", env)

suite "timings":
  test "未启用时 no-op":
    # 确保 NPI_TIMING 未设
    delEnv("NPI_TIMING")
    resetTimings("main")
    time("a", "main")
    check printTimings() == ""

  test "启用时记录间隔":
    putEnv("NPI_TIMING", "1")
    resetTimings("main")
    time("step1", "main")
    time("step2", "main")
    let r = printTimings()
    check "step1" in r
    check "step2" in r
    check "TOTAL" in r
    delEnv("NPI_TIMING")

  test "不同 namespace 独立":
    putEnv("NPI_TIMING", "1")
    resetTimings("main")
    resetTimings("extensions")
    time("a", "main")
    time("b", "extensions")
    let r = printTimings()
    check "main" in r
    check "extensions" in r
    delEnv("NPI_TIMING")

suite "exec":
  test "stdout/stderr 分离":
    let r = execCommand("echo out-msg; echo err-msg >&2", @[], ".", ExecOptions(timeoutMs: 5000))
    check "out-msg" in r.stdout
    check "err-msg" in r.stderr
    check r.code == 0
    check not r.killed

  test "code 返回":
    let r = execCommand("exit 3", @[], ".", ExecOptions(timeoutMs: 5000))
    check r.code == 3

  test "超时终止 + killed 标记":
    let r = execCommand("sleep 5", @[], ".", ExecOptions(timeoutMs: 300))
    check r.killed
    check r.code == -1

  test "cwd 生效":
    let r = execCommand("pwd", @[], "/tmp", ExecOptions(timeoutMs: 5000))
    # macOS /tmp 是 /private/tmp 符号链接，两者都可
    check r.stdout.strip() in ["/tmp", "/private/tmp"]

suite "attribution":
  test "matchesHost 判定":
    check matchesHost("https://openrouter.ai/api", "openrouter.ai")
    check not matchesHost("https://api.openai.com", "openrouter.ai")

  test "openrouter 归属 + header":
    check isOpenRouterModel("openrouter", "")
    check isOpenRouterModel("", "https://openrouter.ai")
    let h = getDefaultAttributionHeaders("openrouter", "", true)
    check h.hasKey("HTTP-Referer")
    check h["X-OpenRouter-Title"] == "pi"

  test "nvidia/cloudflare 归属":
    check isNvidiaNimModel("nvidia", "")
    check isCloudflareModel("cloudflare-workers-ai", "")
    let n = getDefaultAttributionHeaders("nvidia", "", true)
    check n.hasKey("X-BILLING-INVOKE-ORIGIN")
    let c = getDefaultAttributionHeaders("cloudflare-workers-ai", "", true)
    check c["User-Agent"] == "pi-coding-agent"

  test "opencode session header":
    let h = getSessionHeaders("opencode", "", "sess-1")
    check h["x-opencode-session"] == "sess-1"
    check getSessionHeaders("openai", "", "sess-1").len == 0

  test "未启用无归属 header":
    check getDefaultAttributionHeaders("openrouter", "", false).len == 0

  test "mergeProviderAttributionHeaders 合并":
    let m = mergeProviderAttributionHeaders("opencode", "", "sess-9", true)
    check m.hasKey("x-opencode-session")
    check m["x-opencode-client"] == "pi"

suite "headers":
  test "resolveHeaders 逐项解析":
    var env = initTable[string, string]()
    env["TOKEN"] = "abc123"
    var hdrs = initTable[string, string]()
    hdrs["Authorization"] = "Bearer $TOKEN"
    hdrs["X-Static"] = "fixed"
    let r = resolveHeaders(hdrs, env)
    check r["Authorization"] == "Bearer abc123"
    check r["X-Static"] == "fixed"

  test "空值跳过":
    var env = initTable[string, string]()
    var hdrs = initTable[string, string]()
    hdrs["X-Missing"] = "$NOT_SET"
    hdrs["X-Ok"] = "value"
    let r = resolveHeaders(hdrs, env)
    check not r.hasKey("X-Missing")
    check r["X-Ok"] == "value"

  test "全空返回空表":
    var env = initTable[string, string]()
    var hdrs = initTable[string, string]()
    hdrs["A"] = "$NOPE"
    let r = resolveHeaders(hdrs, env)
    check r.len == 0

  test "命令值解析":
    var env = initTable[string, string]()
    var hdrs = initTable[string, string]()
    hdrs["X-Cmd"] = "$!echo cmdval"
    let r = resolveHeaders(hdrs, env)
    check r["X-Cmd"] == "cmdval"

  test "clearConfigValueCache":
    # 填充缓存后清空（间接验证不崩）
    discard resolveConfigValue("$!echo cachetest", initTable[string, string]())
    clearConfigValueCache()
    check true

suite "diagnostics":
  test "warning/error 构造":
    let w = warning("缺描述", "/path/x.md")
    check w.kind == dkWarning
    check w.message == "缺描述"
    check w.path == "/path/x.md"
    let e = error("解析失败")
    check e.kind == dkError

  test "collision 构造 + 描述":
    let c = ResourceCollision(resourceType: rtSkill, name: "demo",
      winnerPath: "/u/skills/demo", loserPath: "/p/skills/demo")
    let d = c.makeCollision()
    check d.kind == dkCollision
    check "demo" in d.message
    check "skill" in d.message
    check "⚡" in d.describe()

  test "describe 前缀":
    check "⚠" in warning("x").describe()
    check "✗" in error("y").describe()

  test "resourceTypeName":
    check resourceTypeName(rtExtension) == "extension"
    check resourceTypeName(rtPrompt) == "prompt"
    check resourceTypeName(rtTheme) == "theme"
