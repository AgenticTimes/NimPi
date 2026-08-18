## Ls 工具：对齐 pi `tools/ls.ts` 的目录列表语义。
## 字母序、目录加 / 后缀、含 dotfiles、条目上限、truncateHead 字节截断。

import std/[os, strutils, algorithm, tables]
import ./truncate

const
  DefaultLsLimit* = 500

type
  LsOptions* = object
    limit*: int

  LsResult* = object
    entries*: seq[string]       ## 格式化条目（目录带 / 后缀）
    truncated*: bool
    limitReached*: bool
    totalCount*: int

proc defaultLsOptions*(): LsOptions =
  LsOptions(limit: DefaultLsLimit)

proc listDir*(path: string, opts: LsOptions): LsResult =
  ## 读取目录项：字母序、目录加 /、含 dotfiles、上限。
  result.totalCount = 0
  if not dirExists(path):
    return
  var names: seq[string] = @[]
  var isDir: Table[string, bool] = initTable[string, bool]()
  for kind, p in walkDir(path):
    let name = extractFilename(p)
    names.add name
    isDir[name] = kind == pcDir or kind == pcLinkToDir
  names.sort()
  result.totalCount = names.len
  let limit = if opts.limit > 0: opts.limit else: DefaultLsLimit
  var shown = 0
  for name in names:
    if shown >= limit:
      result.limitReached = true
      break
    result.entries.add (if isDir.getOrDefault(name, false): name & "/" else: name)
    inc shown

proc formatLs*(r: LsResult): string =
  ## 格式化输出 + 截断/上限通知（对齐 pi notices）。
  var text = r.entries.join("\n")
  if text.len > 0: text.add "\n"
  # 字节截断（对齐 pi truncateHead 50KB）
  var t = truncateHead(text, defaultTruncationOptions())
  if t.truncated:
    result = t.content & "\n... [truncated " & formatSize(t.totalBytes) & "]\n"
  else:
    result = text
  if r.limitReached:
    result.add "(达到 " & $r.entries.len & " 条目上限，用更大 limit 查看更多)\n"
  if result.len == 0:
    result = "(空目录)\n"