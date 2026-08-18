## 单元测试：wire 序列化与 agent 工具分发。

import std/[unittest, json, os, strutils, sequtils]
import ../src/types
import ../src/agent
import ../src/llm
import ../src/skills
import ../src/compaction

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
