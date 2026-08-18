## 路径解析：对齐 pi `path-utils.ts`。
## expandPath / resolveToCwd / resolveReadPath（~ 展开、@ 前缀、unicode 空格、macOS 变体容错）。

import std/[os, strutils, unicode]

const NarrowNoBreakSpace = "\u202F"

proc expandPath*(filePath: string): string =
  ## ~ 展开 + 去 @ 前缀 + unicode 空格归一（对齐 pi expandPath）。
  result = filePath
  # 去 @ 前缀（pi stripAtPrefix）
  if result.startsWith("@"):
    result = result[1 .. ^1]
  # unicode 空格归一：窄不换行空格 → 普通空格
  result = result.replace(NarrowNoBreakSpace, " ")
  # ~ 展开
  if result == "~":
    result = getHomeDir().strip(leading = false, trailing = true)
  elif result.startsWith("~/"):
    result = getHomeDir() / result[2 .. ^1]

proc resolveToCwd*(filePath: string, cwd: string): string =
  ## 相对 cwd 解析（含 ~/绝对路径），对齐 pi resolveToCwd。
  let expanded = filePath.expandPath()
  if expanded.startsWith("/"):
    result = expanded
  elif expanded.startsWith("~"):
    result = expanded   # expandPath 已展开 ~
  else:
    result = cwd / expanded

proc tryMacOSScreenshotPath*(p: string): string =
  ## AM/PM 前的空格替换为窄不换行空格（对齐 pi tryMacOSScreenshotPath）。
  var parts = p.split(" ")
  # 简化：把 "X AM." 形式中的空格改窄空格
  var bufs = ""
  var i = 0
  while i < parts.len:
    bufs.add parts[i]
    if i + 1 < parts.len and
       (parts[i+1].toLowerAscii.startsWith("am.") or
        parts[i+1].toLowerAscii.startsWith("pm.")):
      bufs.add NarrowNoBreakSpace
    else:
      bufs.add " "
    inc i
  if bufs.endsWith(" "): bufs.setLen(bufs.len - 1)
  result = bufs

proc tryCurlyQuoteVariant*(p: string): string =
  ## 直引号 → 弯引号 U+2019（对齐 pi）。
  result = p.replace("'", "\u2019")

proc resolveReadPath*(filePath: string, cwd: string): string =
  ## 解析路径；不存在则尝试 macOS 变体（AM/PM、弯引号），对齐 pi resolveReadPath。
  let resolved = resolveToCwd(filePath, cwd)
  if fileExists(resolved):
    return resolved
  # AM/PM 变体
  let amPmVariant = tryMacOSScreenshotPath(resolved)
  if amPmVariant != resolved and fileExists(amPmVariant):
    return amPmVariant
  # 弯引号变体
  let curlyVariant = tryCurlyQuoteVariant(resolved)
  if curlyVariant != resolved and fileExists(curlyVariant):
    return curlyVariant
  result = resolved