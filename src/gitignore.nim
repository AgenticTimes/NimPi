## GitIgnore：对齐 pi 的 ignore 语义（grep/find respects .gitignore）。
## 解析 .gitignore/.ignore/.fdignore 规则：!取反、/锚定、*、**、目录后缀。

import std/[os, strutils, re]

type
  IgnoreRule* = object
    pattern*: string      ## 原始 pattern（去掉 !、末尾 / 处理后）
    negated*: bool        ## ! 取反
    anchored*: bool       ## 以 / 开头或含 /（锚定到根）
    dirOnly*: bool        ## 以 / 结尾（仅目录）
    hasSlash*: bool       ## pattern 含 /（非纯文件名）

  GitIgnoreMatcher* = object
    rules*: seq[IgnoreRule]
    baseDir*: string

proc parseGitIgnore*(content: string): seq[IgnoreRule] =
  ## 逐行解析 .gitignore 规则。空行/注释跳过。
  result = @[]
  for rawLine in content.splitLines():
    var line = rawLine.strip
    if line.len == 0 or line.startsWith("#"):
      continue
    var negated = false
    if line.startsWith("!"):
      negated = true
      line = line[1 .. ^1].strip
    if line.len == 0: continue
    var dirOnly = false
    if line.endsWith("/"):
      dirOnly = true
      line = line[0 .. ^2]
    if line.len == 0: continue
    let hasSlash = line.contains('/')
    # 锚定：以 / 开头（去掉）或含 /（相对根）
    var anchored = false
    if line.startsWith("/"):
      anchored = true
      line = line[1 .. ^1]
    result.add IgnoreRule(pattern: line, negated: negated,
                           anchored: anchored, dirOnly: dirOnly,
                           hasSlash: hasSlash)

proc globMatchRule(pattern: string, path: string): bool =
  ## 用 gitignore 语义匹配路径段。
  ## * 匹配任意非 / 段，** 匹配任意多级，锚定整个路径。
  var rx = "^"
  var i = 0
  while i < pattern.len:
    let c = pattern[i]
    case c
    of '*':
      if i + 1 < pattern.len and pattern[i+1] == '*':
        rx.add ".*"
        inc i
      else:
        rx.add "[^/]*"
    of '?':
      rx.add "[^/]"
    of '[':
      # 简单字符类（MVP：不做完整展开，仅当闭合存在）
      let close = pattern.find(']', i+1)
      if close > i:
        rx.add pattern[i .. close]
        i = close
      else:
        rx.add "\\["
    else:
      if c in ['.', '(', ')', '+', '|', '^', '$', '{', '}', '\\']:
        rx.add "\\" & c
      else:
        rx.add c
    inc i
  rx.add "$"
  let re2 = re(rx)
  result = find(path, re2) >= 0

proc matchRule*(rule: IgnoreRule, path: string, isDir: bool): bool =
  ## 判断单个规则是否匹配路径。
  if rule.dirOnly and not isDir:
    return false
  # 相对 baseDir 的路径
  var rel = path
  # 含 / 或锚定的规则匹配整个相对路径；否则匹配任何段（basename 级）
  if rule.hasSlash or rule.anchored:
    # 锚定到根（.gitignore 所在目录）
    result = globMatchRule(rule.pattern, rel)
  else:
    # 无 / 规则匹配任意层级的 basename
    let base = extractFilename(rel)
    if globMatchRule(rule.pattern, base):
      result = true
    else:
      # 也匹配任意父目录段（目录匹配）
      for seg in rel.split('/'):
        if globMatchRule(rule.pattern, seg):
          return true

proc isIgnored*(matcher: GitIgnoreMatcher, path: string, isDir: bool): bool =
  ## 判断路径是否被忽略。最后匹配的规则决定（! 取反覆盖）。
  var ignored = false
  for rule in matcher.rules:
    if matchRule(rule, path, isDir):
      ignored = not rule.negated
  result = ignored

proc collectIgnoreFiles*(dir: string): seq[string] =
  ## 从 dir 向上收集 ignore 文件路径（最近的优先）。
  const names = [".gitignore", ".ignore", ".fdignore"]
  result = @[]
  var cur = dir
  var stack: seq[string] = @[]
  while true:
    for n in names:
      let p = cur / n
      if fileExists(p):
        stack.add p
    let parent = parentDir(cur)
    if parent == cur or cur.len <= 1: break
    cur = parent
  # 根目录的规则优先级低，翻转：从根到叶子顺序（后加的规则在 ignore 库中更高优先）
  for i in countdown(stack.high, 0):
    result.add stack[i]

proc buildIgnoreMatcher*(root: string): GitIgnoreMatcher =
  ## 从 root 收集规则构建 matcher。
  result = GitIgnoreMatcher(baseDir: root)
  let files = collectIgnoreFiles(root)
  for f in files:
    try:
      let content = readFile(f)
      result.rules.add parseGitIgnore(content)
    except CatchableError:
      discard