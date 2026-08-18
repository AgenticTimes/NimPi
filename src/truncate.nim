## 输出截断：对齐 pi `tools/truncate.ts`。
## truncateHead（文件读取保头部）/ truncateTail（bash 保尾部）/ formatSize。
## 行数与字节双限制，先到先截；不返回半行（tail 最后一行超限的边界除外）。

import std/[strutils]

const
  DefaultMaxLines* = 2000
  DefaultMaxBytes* = 50 * 1024

type
  TruncationOptions* = object
    maxLines*: int
    maxBytes*: int

  TruncationResult* = object
    content*: string
    truncated*: bool
    truncatedBy*: string     ## "lines" | "bytes" | ""
    totalLines*: int
    totalBytes*: int
    outputLines*: int
    maxLines*: int
    maxBytes*: int

proc defaultTruncationOptions*(): TruncationOptions =
  TruncationOptions(maxLines: DefaultMaxLines, maxBytes: DefaultMaxBytes)

proc formatSize*(bytes: int): string =
  ## 人类可读字节大小（对齐 pi formatSize）。
  if bytes < 1024:
    result = $bytes & "B"
  elif bytes < 1024 * 1024:
    result = formatFloat(bytes / 1024, ffDecimal, 1) & "KB"
  else:
    result = formatFloat(bytes / (1024 * 1024), ffDecimal, 1) & "MB"

proc splitLinesForCounting(content: string): seq[string] =
  ## 按行拆分；末尾不产生额外空行。
  if content.len == 0: return
  var lines = content.split("\n")
  if content.endsWith("\n") and lines.len > 0:
    lines.setLen(lines.len - 1)
  result = lines

proc truncateHead*(content: string, opts: TruncationOptions): TruncationResult =
  ## 保留开头 N 行/字节。不返回半行；首行超限返回空。
  let maxLines = opts.maxLines
  let maxBytes = opts.maxBytes
  let totalBytes = content.len
  let lines = splitLinesForCounting(content)
  let totalLines = lines.len
  result.maxLines = maxLines
  result.maxBytes = maxBytes
  result.totalLines = totalLines
  result.totalBytes = totalBytes
  result.truncatedBy = ""
  if totalLines <= maxLines and totalBytes <= maxBytes:
    result.content = content
    result.outputLines = totalLines
    return
  # 首行超限
  if lines.len > 0 and lines[0].len > maxBytes:
    result.content = ""
    result.truncated = true
    result.truncatedBy = "bytes"
    result.outputLines = 0
    return
  var outLines: seq[string] = @[]
  var outBytes = 0
  var by = "lines"
  for i in 0 ..< lines.len:
    if i >= maxLines: by = "lines"; break
    let line = lines[i]
    let lb = line.len + (if i > 0: 1 else: 0)
    if outBytes + lb > maxBytes:
      by = "bytes"
      break
    outLines.add line
    outBytes += lb
  if outLines.len >= maxLines and outBytes <= maxBytes:
    by = "lines"
  result.content = outLines.join("\n")
  result.truncated = true
  result.truncatedBy = by
  result.outputLines = outLines.len

proc truncateTail*(content: string, opts: TruncationOptions): TruncationResult =
  ## 保留末尾 N 行/字节（bash 输出保错误）。可能返回部分首行（超限边界）。
  let maxLines = opts.maxLines
  let maxBytes = opts.maxBytes
  let totalBytes = content.len
  let lines = splitLinesForCounting(content)
  let totalLines = lines.len
  result.maxLines = maxLines
  result.maxBytes = maxBytes
  result.totalLines = totalLines
  result.totalBytes = totalBytes
  result.truncatedBy = ""
  if totalLines <= maxLines and totalBytes <= maxBytes:
    result.content = content
    result.outputLines = totalLines
    return
  var outLines: seq[string] = @[]
  var outBytes = 0
  var by = "lines"
  for i in countdown(lines.high, 0):
    if outLines.len >= maxLines: by = "lines"; break
    let line = lines[i]
    let lb = line.len + (if outLines.len > 0: 1 else: 0)
    if outBytes + lb > maxBytes:
      by = "bytes"
      if outLines.len == 0:
        # 最后一行超限：从尾部截取（近似，Nim 按字符）
        let keep = min(line.len, maxBytes)
        outLines.add line[^keep .. ^1]
        outBytes = keep + 1
      break
    outLines.add line
    outBytes += lb
  if outLines.len >= maxLines and outBytes <= maxBytes:
    by = "lines"
  # outLines 从末尾收集，逆序还原
  var ordered: seq[string] = @[]
  for i in countdown(outLines.high, 0):
    ordered.add outLines[i]
  result.content = ordered.join("\n")
  result.truncated = true
  result.truncatedBy = by
  result.outputLines = ordered.len