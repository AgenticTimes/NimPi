## Find 工具：对齐 pi `tools/find.ts` 的 glob 文件查找。
## 纯 Nim 递归遍历 + glob 匹配（*、?、**），跳过隐藏，返回相对路径。

import std/[os, strutils, algorithm, re]
import ./gitignore

const
  DefaultFindLimit = 50

type
  FindOptions* = object
    pattern*: string
    limit*: int
    includeHidden*: bool

proc defaultFindOptions*(): FindOptions =
  FindOptions(limit: DefaultFindLimit)

# ---------------------------------------------------------------------------
# glob 匹配：把 glob 转成匹配函数（支持 * ? 与路径级 **）
# ---------------------------------------------------------------------------

proc globToRegex(pattern: string): string =
  ## 把 glob 转成 PCRE 正则（Nim re）。
  ## 支持：** 任意多级、* 单段、? 单字符、{a,b} brace、[abc]/[a-z]/[!abc] 字符类。
  var rx = ""
  var i = 0
  while i < pattern.len:
    let c = pattern[i]
    if c == '*':
      if i + 1 < pattern.len and pattern[i+1] == '*':
        rx.add ".*"
        inc i
      else:
        rx.add "[^/]*"
    elif c == '?':
      rx.add "[^/]"
    elif c == '{':
      # brace 展开：{a,b} → (a|b)
      let close = pattern.find('}', i)
      if close > i:
        let inner = pattern[i+1 ..< close]
        let parts = inner.split(',')
        rx.add "(" & parts.join("|") & ")"
        i = close
      else:
        rx.add "\\{"
    elif c == '[':
      # 字符类：支持 [abc] [a-z] [!abc]
      let close = pattern.find(']', i+1)
      if close > i:
        var cls = pattern[i+1 ..< close]
        var negate = false
        if cls.startsWith("!"):
          negate = true
          cls = cls[1 .. ^1]
        # 转义类内特殊字符（- 保留作区间）
        var escaped = ""
        for ch in cls:
          if ch in [']', '\\', '^']:
            escaped.add "\\" & ch
          else:
            escaped.add ch
        rx.add "["
        if negate: rx.add "^"
        rx.add escaped & "]"
        i = close
      else:
        rx.add "\\["
    elif c in ['.', '(', ')', '+', '|', '^', '$', '{', '}', '\\']:
      rx.add "\\" & c
    else:
      rx.add c
    inc i
  result = "^" & rx & "$"

proc matchGlob*(pattern: string, path: string): bool =
  ## 用 glob 匹配路径。`**` 支持多级，`*`/`?` 单级；全路径锚定。
  # 特殊情况：pattern 用 ** 开头或含 / 处理
  let rxStr = globToRegex(pattern)
  let rx = re(rxStr, {reIgnoreCase, reStudy})
  # 用 find 判断匹配（返回位置 int，-1 表示无匹配），避免 match 重载歧义
  result = find(path, rx) >= 0

# ---------------------------------------------------------------------------
# 遍历
# ---------------------------------------------------------------------------

proc isHiddenEntry(name: string): bool =
  name.startsWith(".") and name notin [".", ".."]

proc findPath*(root: string, opts: FindOptions): seq[string] =
  ## 从 root 递归遍历，返回匹配 pattern 的相对路径，直到 limit。
  result = @[]
  if not dirExists(root):
    return
  let limit = if opts.limit > 0: opts.limit else: DefaultFindLimit
  let matcher = buildIgnoreMatcher(root)
  var found: seq[string] = @[]

  proc walk(dir: string, relDir: string, found: var seq[string], m: GitIgnoreMatcher) =
    if found.len >= limit: return
    var entries: seq[string] = @[]
    for kind, p in walkDir(dir):
      entries.add p
    entries.sort()
    for p in entries:
      if found.len >= limit: return
      let name = extractFilename(p)
      if not opts.includeHidden and isHiddenEntry(name):
        continue
      let relPath = if relDir.len == 0: name else: relDir / name
      let pIsDir = dirExists(p)
      if isIgnored(m, relPath, pIsDir):
        continue
      if fileExists(p) and matchGlob(opts.pattern, relPath):
        found.add relPath
      if pIsDir:
        walk(p, relPath, found, m)

  walk(root, "", found, matcher)
  result = found

proc formatFindResults*(results: seq[string]): string =
  if results.len == 0: return "no results"
  results.join("\n")