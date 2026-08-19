## 系统提示词组装：对齐 pi `core/system-prompt.ts` 的 buildSystemPrompt。
## 双分支（customPrompt/默认）、工具可见性过滤、guidelines 去重、context/skills/append/cwd 注入。

import std/[tables, strutils]

import ./skills

type
  ContextFile* = object
    path*: string
    content*: string

  BuildSystemPromptOptions* = object
    customPrompt*: string               ## 空 = 用默认模板
    selectedTools*: seq[string]         ## 空 = 默认工具集
    toolSnippets*: Table[string, string]  ## 工具名 → 单行描述；有 snippet 的工具才可见
    promptGuidelines*: seq[string]      ## 追加 guidelines（trim 后去重注入）
    appendSystemPrompt*: string         ## 追加段
    cwd*: string
    contextFiles*: seq[ContextFile]
    skills*: seq[Skill]                 ## 复用 skills.nim 的 Skill 类型

const
  DefaultSelectedTools* = ["read", "bash", "edit", "write"]

proc defaultToolSnippets*(): Table[string, string] =
  ## npi 内置工具单行描述（对齐 npi 现有系统提示工具行）。
  result = initTable[string, string]()
  result["read"] = "read a file"
  result["write"] = "write a file"
  result["edit"] = "replace text"
  result["bash"] = "run a shell command (cwd: $1)"
  result["ls"] = "list a directory"
  result["grep"] = "search text"
  result["find"] = "find files by name"

const
  DefaultPromptBody* = """You are npi, a coding agent that helps with programming tasks in the current repository.

Available tools:
$TOOLS

Work iteratively: inspect, then edit, then verify. Keep responses concise. When done, summarize what you changed."""
  NpiDocSection* = """In addition to the tools above, you may have access to other custom tools depending on the project.

Guidelines:
$GUIDELINES"""

proc formatContextFiles(contextFiles: seq[ContextFile]): string =
  ## 组装 <project_context> 段（对齐 pi）。
  if contextFiles.len == 0:
    return ""
  var sb = "\n\n<project_context>\n\n"
  sb.add "Project-specific instructions and guidelines:\n\n"
  for f in contextFiles:
    sb.add "<project_instructions path=\"" & f.path & "\">\n"
    sb.add f.content
    sb.add "\n</project_instructions>\n\n"
  sb.add "</project_context>\n"
  result = sb

proc buildSystemPrompt*(options: BuildSystemPromptOptions): string =
  ## 组装系统提示（对齐 pi buildSystemPrompt 双分支语义）。
  let promptCwd = options.cwd.replace("\\", "/")
  let appendSection =
    if options.appendSystemPrompt.len > 0: "\n\n" & options.appendSystemPrompt
    else: ""
  let skills = options.skills

  # customPrompt 分支
  if options.customPrompt.len > 0:
    var prompt = options.customPrompt
    if appendSection.len > 0:
      prompt.add appendSection
    if options.contextFiles.len > 0:
      prompt.add formatContextFiles(options.contextFiles)
    let hasRead = options.selectedTools.len == 0 or "read" in options.selectedTools
    if hasRead and skills.len > 0:
      let sp = skills.formatSkillsForPrompt()
      if sp.len > 0:
        prompt.add "\n\n" & sp
    prompt.add "\nCurrent working directory: " & promptCwd
    return prompt

  # 默认分支
  let tools =
    if options.selectedTools.len > 0: options.selectedTools
    else: @DefaultSelectedTools
  var visibleTools: seq[string] = @[]
  for t in tools:
    if options.toolSnippets.hasKey(t) and options.toolSnippets[t].len > 0:
      visibleTools.add t
  var toolsList =
    if visibleTools.len > 0: ""
    else: "(none)"
  if visibleTools.len > 0:
    var lines: seq[string] = @[]
    for t in visibleTools:
      lines.add "- " & t & ": " & options.toolSnippets[t]
    toolsList = lines.join("\n")

  # guidelines 组装（去重，保持注入顺序）
  var guidelinesList: seq[string] = @[]
  var guidelinesSet = initTable[string, bool]()
  proc addGuideline(g: string) =
    if guidelinesSet.hasKey(g):
      return
    guidelinesSet[g] = true
    guidelinesList.add g

  let hasBash = "bash" in tools
  let hasGrep = "grep" in tools
  let hasFind = "find" in tools
  let hasLs = "ls" in tools
  let hasRead = "read" in tools
  if hasBash and not hasGrep and not hasFind and not hasLs:
    addGuideline("Use bash for file operations like ls, rg, find")
  for g in options.promptGuidelines:
    let normalized = g.strip
    if normalized.len > 0:
      addGuideline(normalized)
  addGuideline("Be concise in your responses")
  addGuideline("Show file paths clearly when working with files")
  var guidelines =
    if guidelinesList.len > 0: ""
    else: "(none)"
  if guidelinesList.len > 0:
    var lines: seq[string] = @[]
    for g in guidelinesList:
      lines.add "- " & g
    guidelines = lines.join("\n")

  var prompt = DefaultPromptBody
    .replace("$TOOLS", toolsList)
  prompt.add "\n\n" & NpiDocSection
  prompt = prompt.replace("$GUIDELINES", guidelines)
  if appendSection.len > 0:
    prompt.add appendSection
  if options.contextFiles.len > 0:
    prompt.add formatContextFiles(options.contextFiles)
  if hasRead and skills.len > 0:
    let sp = skills.formatSkillsForPrompt()
    if sp.len > 0:
      prompt.add "\n\n" & sp
  prompt.add "\nCurrent working directory: " & promptCwd
  result = prompt
