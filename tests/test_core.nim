## 单元测试：wire 序列化与 agent 工具分发。

import std/[unittest, json, os, strutils]
import ../src/types
import ../src/agent
import ../src/llm

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
