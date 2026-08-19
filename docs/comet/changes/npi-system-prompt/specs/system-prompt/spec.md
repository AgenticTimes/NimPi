# 完整目标规格：npi system prompt

对齐 pi-coding-agent 的 `core/system-prompt.ts` 的 `buildSystemPrompt`。归档后 `src/systemprompt.nim` 的完整行为如下。

## 类型

```nim
type
  ContextFile* = object
    path*: string
    content*: string

  BuildSystemPromptOptions* = object
    customPrompt*: string          ## 空 = 用默认模板
    selectedTools*: seq[string]    ## 空 = 默认工具集
    toolSnippets*: Table[string, string]  ## 工具名 → 单行描述；有 snippet 的工具才可见
    promptGuidelines*: seq[string] ## 追加 guidelines（trim 后去重注入）
    appendSystemPrompt*: string    ## 追加段
    cwd*: string
    contextFiles*: seq[ContextFile]
    skills*: seq[Skill]            ## 复用 skills.nim 的 Skill 类型
```

## 常量

```nim
const
  DefaultSelectedTools* = ["read", "bash", "edit", "write"]  ## pi 默认；npi 实际传 7 工具
  DefaultToolSnippets* = 内置表   ## read/write/edit/bash/ls/grep/find 单行描述（npi 现有工具行）
  DefaultPromptBody* = npi 现有正文  ## "You are npi, a coding agent that helps with programming tasks in the current repository. ..."
  NpiDocSection* = npi 简版文档说明   ## 省略 pi 专属路径，保留结构
```

## buildSystemPrompt

输入：BuildSystemPromptOptions。返回组装后的完整系统提示字符串。cwd 先做路径归一：`/` 反斜杠替换为 `/`（Windows 语义，对齐 pi `promptCwd`）。

### customPrompt 分支（customPrompt 非空）

1. prompt = customPrompt
2. appendSection = appendSystemPrompt 非空 ? `\n\n` & appendSystemPrompt : ""，若非空则 prompt += appendSection
3. contextFiles 非空 → prompt += `\n\n<project_context>\n\nProject-specific instructions and guidelines:\n\n` + 每个文件 `<project_instructions path="{path}">\n{content}\n</project_instructions>\n\n` + `</project_context>\n`
4. hasRead = selectedTools 为空 或 含 "read"；hasRead 且 skills 非空 → prompt += formatSkillsForPrompt(skills)
5. prompt += 工作目录尾注（与 customPrompt 分支相同格式：`\nCurrent working directory: {promptCwd}`）；结束

### 默认分支（customPrompt 空）

1. tools = selectedTools 非空 ? selectedTools : ["read", "bash", "edit", "write"]
2. visibleTools = tools 中在 toolSnippets 有描述者；toolsList = visibleTools 非空 ? 每项 `- {name}: {snippet}` 换行拼接 : "(none)"
3. guidelines 组装（去重，Set 语义，保持注入顺序）：
   - hasBash 且 无 grep 且 无 find 且 无 ls → "Use bash for file operations like ls, rg, find"
   - promptGuidelines 逐项 trim，非空则注入
   - 固定项：先 "Be concise in your responses"，再 "Show file paths clearly when working with files"
   - 每项去重（已存在则跳过）；guidelines = 每项 `- {g}` 换行拼接
4. prompt = 默认正文（含 `Available tools:\n{toolsList}` 占位替换 + Guidelines 段 + npi 文档说明段）
5. appendSection 非空 → prompt += appendSection
6. contextFiles 非空 → 注入 `<project_context>` 段（同 customPrompt 分支格式）
7. hasRead（tools 含 "read"）且 skills 非空 → prompt += formatSkillsForPrompt(skills)
8. prompt += 工作目录尾注（格式：`\nCurrent working directory: {promptCwd}`）；结束

### 空工具场景

visibleTools 为空 → toolsList = "(none)"（对齐 pi）。

## 接入：npi.nim

`proc systemPrompt(cwd: string, trustProject = true)` 改为委托 buildSystemPrompt：

```nim
proc systemPrompt(cwd: string, trustProject = true): string =
  let skills = loadSkills(cwd, trustProject).skills
  buildSystemPrompt(BuildSystemPromptOptions(
    cwd: cwd,
    selectedTools: @["read", "write", "edit", "bash", "ls", "grep", "find"],
    toolSnippets: defaultToolSnippets(),   # npi 现有工具描述行
    skills: skills))
```

替换原硬编码字符串构造。既有 skills 注入逻辑（formatSkillsForPrompt）由 buildSystemPrompt 内部承担，行为不变。

## 测试（tests/test_core.nim 追加）

- 默认分支：输出含 "Available tools:"、read 工具行、guidelines "Be concise in your responses"、"Current working directory:"
- 无工具可见（snippets 空）→ toolsList "(none)"
- 工具组合：仅 bash（无 grep/find/ls）→ 含 "Use bash for file operations like ls, rg, find"
- 有 grep → 不含该 bash 引导句
- promptGuidelines 重复项 → 只出现一次
- promptGuidelines 空白项 → 跳过
- customPrompt 分支：以 customPrompt 开头，含 append、context、skills（hasRead 时）、cwd
- customPrompt 无 read 工具 → 不含 skills XML
- contextFiles → 含 `<project_context>` 与 `<project_instructions path="...">` 及内容
- appendSystemPrompt → 出现在默认提示之后
- cwd 反斜杠 → 归一为 "/"
- 无 customPrompt 无 context 无 skills → 结构完整（头部/工具/guidelines/cwd）

## 非目标（明确不做）

- pi 文档路径解析（getDocsPath 等）
- pi 完整默认提示文案
- toolSnippets 外部注入机制
- skills XML 格式改动
