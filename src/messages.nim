## 消息工厂：对齐 pi `messages.ts` 的 compaction 摘要格式。
## COMPACTION_SUMMARY_PREFIX/SUFFIX <summary> XML 包裹 + createCompactionSummaryMessage。

import std/json
import ./types
import ./llm

const
  ## 对齐 pi messages.ts COMPACTION_SUMMARY_PREFIX / SUFFIX
  CompactionSummaryPrefix* = """The conversation history before this point was compacted into the following summary:

<summary>
"""
  CompactionSummarySuffix* = """
</summary>"""

  BranchSummaryPrefix* = """The following is a summary of a branch that this conversation came back from:

<summary>
"""
  BranchSummarySuffix* = "</summary>"

type
  CompactionSummaryMessage* = object
    role*: string        ## "compactionSummary"
    summary*: string
    tokensBefore*: int
    timestamp*: int

proc formatCompactionSummary*(summary: string): string =
  ## 用 <summary> XML 包裹摘要（对齐 pi convertToLlm 的 compactionSummary 分支）。
  result = CompactionSummaryPrefix & summary & CompactionSummarySuffix

proc formatBranchSummary*(summary: string): string =
  ## branchSummary 包裹（对齐 pi BRANCH_SUMMARY_PREFIX/SUFFIX）。
  result = BranchSummaryPrefix & summary & BranchSummarySuffix

proc createCompactionSummaryMessage*(summary: string, tokensBefore: int,
                                     timestamp: int): CompactionSummaryMessage =
  ## 创建 compaction 摘要消息（对齐 pi createCompactionSummaryMessage）。
  result = CompactionSummaryMessage(role: "compactionSummary",
    summary: summary, tokensBefore: tokensBefore, timestamp: timestamp)

proc toUserText*(m: CompactionSummaryMessage): string =
  ## 转为 LLM user 消息文本（对齐 pi convertToLlm compactionSummary → user 消息）。
  result = formatCompactionSummary(m.summary)

# ---------------------------------------------------------------------------
# convertToLlm：内部 Message → LLM wire ChatMessage（对齐 pi convertToLlm）
# ---------------------------------------------------------------------------

proc convertToLlm*(messages: seq[Message]): seq[ChatMessage] =
  ## 把内部消息转成 LLM wire 格式（对齐 pi convertToLlm 的 user/assistant/toolResult）。
  ## - mkUser → user
  ## - mkAssistant → assistant（提取 toolCalls）
  ## - mkToolResult → tool
  for m in messages:
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
      result.add ChatMessage(role: "tool", toolCallId: m.toolCallId,
                             toolName: m.toolName, content: m.toolText)
