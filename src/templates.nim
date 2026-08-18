## Prompt 模板：对齐 pi `prompt-templates.ts`。
## bash 风格参数解析、占位符替换、模板加载、slash 展开。

import std/[strutils, os, tables]

type
  PromptTemplate* = object
    name*: string
    description*: string
    argumentHint*: string
    content*: string
    filePath*: string

proc parseCommandArgs*(argsString: string): seq[string] =
  ## bash 风格参数解析（支持单/双引号，对齐 pi parseCommandArgs）。
  result = @[]
  var current = ""
  var inQuote = '\0'
  var i = 0
  let s = argsString
  while i < s.len:
    let char = s[i]
    if inQuote != '\0':
      if char == inQuote:
        inQuote = '\0'
      else:
        current.add char
    elif char == '"' or char == '\'':
      inQuote = char
    elif char.isSpaceAscii:
      if current.len > 0:
        result.add current
        current = ""
    else:
      current.add char
    inc i
  if current.len > 0:
    result.add current

proc isAllDigits(s: string): bool =
  s.len > 0 and s.allCharsInSet(Digits)

proc substituteArgs*(content: string, args: seq[string]): string =
  ## 占位符替换（对齐 pi substituteArgs）。
  ## 支持：`$N`、`$@`/`$ARGUMENTS`、`${N:-default}`、`${@:-default}`、
  ## `${@:N}`、`${@:N:L}`。替换后不再递归替换默认/参数值。
  let allArgs = args.join(" ")
  var bufs = ""
  var i = 0
  let s = content
  while i < s.len:
    if s[i] != '$':
      bufs.add s[i]
      inc i
      continue
    # 命中 $
    inc i
    if i < s.len and s[i] == '{':
      # ${...} 形式
      let close = s.find('}', i)
      if close < 0:
        bufs.add "${"
        continue
      let inner = s[i+1 ..< close]
      i = close + 1
      # 区分 ${@:N}[L]（切片）与 ${@:-default}（默认值）、${N:-default}（默认值）
      let isSliceForm =
        (inner.startsWith("@:") or inner.startsWith("ARGUMENTS:")) and
        inner.find(':') + 1 < inner.len and
        inner[inner.find(':')+1].isDigit
      if isSliceForm:
        # rest = 第一个冒号后的完整内容（可能含 :L）
        let rest = inner[inner.find(':')+1 .. ^1]
        let parts = rest.split(':')
        var start = parseInt(parts[0]) - 1
        if start < 0: start = 0
        if parts.len >= 2 and parts[1].len > 0:
          let length = parseInt(parts[1])
          var seg = newSeq[string]()
          let stopIdx = min(start + length, args.len)
          if start < args.len:
            for k in start ..< max(start, stopIdx):
              seg.add args[k]
          bufs.add seg.join(" ")
        else:
          var seg = newSeq[string]()
          if start < args.len:
            for k in start ..< args.len:
              seg.add args[k]
          bufs.add seg.join(" ")
      else:
        # 处理 ${N:-default} 或 ${@:-default}
        let hasDefault = inner.contains(":-")
        var target = inner
        var defaultValue = ""
        if hasDefault:
          let sp = inner.split(":-")
          target = sp[0]
          defaultValue = sp[1]
        if target == "@" or target == "ARGUMENTS":
          let value = allArgs
          bufs.add (if value.len > 0: value else: defaultValue)
        elif target.isAllDigits():
          let idx = parseInt(target) - 1
          if idx >= 0 and idx < args.len and args[idx].len > 0:
            bufs.add args[idx]
          else:
            bufs.add defaultValue
        else:
          bufs.add "${" & inner & "}"
      continue
    # $ 简单形式：$N、$@、$ARGUMENTS
    # 读取连续字母数字
    var name = ""
    while i < s.len and (s[i].isAlphaAscii or s[i] == '@' or s[i].isDigit):
      name.add s[i]
      inc i
    case name
    of "@", "ARGUMENTS":
      bufs.add allArgs
    else:
      if name.isAllDigits():
        let idx = parseInt(name) - 1
        if idx >= 0 and idx < args.len:
          bufs.add args[idx]
        else:
          bufs.add ""
      else:
        # 不是占位符，保留原样
        bufs.add "$" & name
  result = bufs

proc parseTemplateFrontmatter(content: string): tuple[fields: Table[string, string], bodyStart: int] =
  ## 解析 .md 的 frontmatter（--- 围栏）+ 返回正文起点。
  result.bodyStart = -1
  result.fields = initTable[string, string]()
  if not content.startsWith("---\n"):
    return
  let endIdx = content.find("\n---", 4)
  if endIdx < 0:
    return
  for line in content[4 ..< endIdx].splitLines():
    let l = line.strip
    if l.len == 0 or l.startsWith("#"): continue
    let colon = l.find(':')
    if colon <= 0: continue
    let key = l[0 ..< colon].strip
    var val = l[colon+1 .. ^1].strip
    if val.len >= 2 and ((val[0] == '"' and val[^1] == '"') or (val[0] == '\'' and val[^1] == '\'')):
      val = val[1 .. ^2]
    result.fields[key] = val
  # bodyStart: --- 之后
  result.bodyStart = endIdx + 4

proc loadTemplateFromFile(filePath: string): PromptTemplate =
  var content = ""
  try:
    content = readFile(filePath)
  except CatchableError:
    return PromptTemplate()
  let (fm, bodyStart) = parseTemplateFrontmatter(content)
  result.filePath = filePath
  result.name = extractFilename(filePath).replace(".md", "")
  if fm.hasKey("name") and fm["name"].strip.len > 0:
    result.name = fm["name"].strip
  result.description = fm.getOrDefault("description", "").strip
  result.argumentHint = fm.getOrDefault("argument-hint", "").strip
  # body
  if bodyStart >= 0:
    result.content = content[bodyStart .. ^1].strip
  else:
    result.content = content.strip

proc loadTemplatesFromDir*(dir: string): seq[PromptTemplate] =
  ## 递归发现 .md 模板。
  if not dirExists(dir): return
  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      if extractFilename(path).endsWith(".md"):
        let t = loadTemplateFromFile(path)
        if t.name.len > 0 and t.content.len > 0:
          result.add t
    of pcDir:
      result.add loadTemplatesFromDir(path)
    else: discard

proc loadTemplates*(cwd: string): seq[PromptTemplate] =
  ## 加载用户级 ~/.npi/prompts + 项目级 .npi/prompts。
  let userDir = getEnv("NPI_AGENT_DIR", getHomeDir() / ".npi") / "prompts"
  let projectDir = cwd / ".npi" / "prompts"
  result = loadTemplatesFromDir(projectDir)
  result.add loadTemplatesFromDir(userDir)

proc expandPromptTemplate*(text: string, templates: seq[PromptTemplate]): string =
  ## 若以 /name 开头且命中模板，展开；否则原样返回（对齐 pi）。
  if not text.startsWith("/"): return text
  # 匹配 /name 后接参数
  let trimmed = text.strip
  let sp = trimmed.find(' ')
  var tname = ""
  var argsString = ""
  if sp < 0:
    tname = trimmed[1 .. ^1]
  else:
    tname = trimmed[1 ..< sp]
    argsString = trimmed[sp+1 .. ^1]
  for t in templates:
    if t.name == tname:
      let args = parseCommandArgs(argsString)
      return substituteArgs(t.content, args)
  result = text