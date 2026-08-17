## 单元测试：wire 序列化与 agent 工具分发。

import std/[unittest, json, os, strutils]
import ../src/types
import ../src/agent

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
