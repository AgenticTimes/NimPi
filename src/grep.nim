## Grep 工具：对齐 pi `tools/grep.ts` 的核心搜索。
## 纯 Nim 按行搜索（不依赖 shell grep）：pattern / case / fixedString / context / 格式 path:line:text。

import std/[os, strutils, re, algorithm]

const
  GrepMaxLineLength = 500
  DefaultMaxMatches = 100

type
  GrepOptions* = object
    pattern*: string
    caseSensitive*: bool
    fixedString*: bool      ## true=字面匹配，false=正则
    context*: int           ## 上下行数
    maxMatches*: int        ## 匹配上限

  GrepMatch* = object
    lineNumber*: int        ## 1-based
    lineType*: string       ## "match" | "context"
    text*: string

proc defaultGrepOptions*(): GrepOptions =
  GrepOptions(caseSensitive: false, fixedString: true, maxMatches: DefaultMaxMatches)

proc truncateLine*(line: string, maxChars = GrepMaxLineLength): string =
  ## 行截断（对齐 pi GREP_MAX_LINE_LENGTH + [truncated]）。
  if line.len <= maxChars:
    result = line
  else:
    result = line[0 ..< maxChars] & "... [truncated]"

proc makeMatcher(pattern: string, caseSensitive: bool, fixedString: bool): proc(line: string): bool =
  ## 构造匹配函数。
  if fixedString:
    if caseSensitive:
      return proc(line: string): bool = line.contains(pattern)
    else:
      let p = pattern.toLowerAscii
      return proc(line: string): bool = line.toLowerAscii.contains(p)
  else:
    # regex：Nim re find 返回匹配位置 int（-1 表示无匹配）
    let rx = re(pattern)
    return proc(line: string): bool =
      let pos = find(line, rx)
      return pos >= 0

proc grepFile*(path: string, opts: GrepOptions): seq[GrepMatch] =
  ## 按行搜索单个文件，返回匹配 + context 行。
  var content = ""
  try:
    content = readFile(path)
  except CatchableError:
    return
  let lines = content.splitLines()
  let matcher = makeMatcher(opts.pattern, opts.caseSensitive, opts.fixedString)
  let ctx = if opts.context > 0: opts.context else: 0
  var matchCount = 0
  for i, line in lines:
    if matchCount >= opts.maxMatches: break
    if matcher(line):
      inc matchCount
      let startLine = max(0, i - ctx)
      let endLine = min(lines.high, i + ctx)
      # 已输出的 context 行追踪（防重复）
      var emitted = newSeq[bool](lines.len)
      for j in max(0, startLine) .. min(lines.high, endLine):
        if emitted[j]: continue
        if matcher(lines[j]):
          result.add GrepMatch(lineNumber: j + 1, lineType: "match", text: truncateLine(lines[j]))
          emitted[j] = true
        elif j >= i - ctx and j <= i + ctx:
          result.add GrepMatch(lineNumber: j + 1, lineType: "context", text: truncateLine(lines[j]))
          emitted[j] = true

proc isSkipDir(dir: string): bool =
  let base = extractFilename(dir)
  base in [".git", ".npi", "node_modules", ".worktrees"] or base.startsWith(".")

proc grepPath*(path: string, opts: GrepOptions): seq[GrepMatch] =
  ## 遍历目录或文件，聚合匹配。
  if fileExists(path):
    return grepFile(path, opts)
  if not dirExists(path):
    return
  var files: seq[string] = @[]
  # 递归收集文件（跳过隐藏/.git 目录）
  proc collect(d: string) =
    for kind, p in walkDir(d):
      if kind == pcFile:
        if not extractFilename(p).startsWith("."):
          files.add p
      elif kind == pcDir:
        if not isSkipDir(p):
          collect(p)
  collect(path)
  # 按文件排序保证稳定顺序，跨文件记录已输出数量
  files.sort()
  var total = 0
  for f in files:
    if total >= opts.maxMatches: break
    let m = grepFile(f, opts)
    for mm in m:
      if total >= opts.maxMatches: break
      # 格式 path:line:text（对齐 pi）
      result.add GrepMatch(lineNumber: mm.lineNumber,
        lineType: mm.lineType,
        text: f & ":" & $mm.lineNumber & ":" & mm.text)
      inc total

proc formatGrepResult(matches: seq[GrepMatch]): string =
  ## 输出为文本（含 match/context 标注）。
  var sb = ""
  for m in matches:
    if m.lineType == "context":
      sb.add "  " & m.text & "\n"
    else:
      sb.add m.text & "\n"
  result = sb