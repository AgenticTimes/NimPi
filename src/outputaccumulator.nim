## 流式输出累积器：对齐 pi `core/tools/output-accumulator.ts`。
## 有界内存 tail 快照、行/字节统计、UTF-8 跨 chunk 边界、超限时全文保存到临时文件。

import std/[os, strutils, random]

import ./truncate

type
  OutputAccumulatorOptions* = object
    maxLines*: int
    maxBytes*: int
    tempFilePrefix*: string

  OutputAccumulator* = ref object
    maxLines*: int            ## 行上限
    maxBytes*: int            ## 字节上限
    maxRollingBytes*: int     ## tail 滚动窗口 = max(2*maxBytes, 1)
    tempFilePrefix*: string
    rawChunks*: seq[string]   ## 未超限时内存保留的原始 chunk
    tailText*: string
    tailBytes*: int
    tailStartsAtLineBoundary*: bool
    totalRawBytes*: int
    totalDecodedBytes*: int
    completedLines*: int
    totalLines*: int
    currentLineBytes*: int
    hasOpenLine*: bool
    finished*: bool
    pendingBytes*: string     ## UTF-8 跨 chunk 边界的未完成字节序列
    tempFilePath*: string     ## 空 = 未创建临时文件

  OutputSnapshot* = object
    content*: string
    truncation*: TruncationResult
    fullOutputPath*: string   ## 空 = 无临时文件

const
  DefaultMaxLines* = 2000
  DefaultMaxBytes* = 50 * 1024

proc defaultOutputAccumulatorOptions*(): OutputAccumulatorOptions =
  OutputAccumulatorOptions(maxLines: DefaultMaxLines, maxBytes: DefaultMaxBytes,
                           tempFilePrefix: "npi-output")

proc newOutputAccumulator*(options: OutputAccumulatorOptions = defaultOutputAccumulatorOptions()): OutputAccumulator =
  result = OutputAccumulator(
    maxLines: if options.maxLines > 0: options.maxLines else: DefaultMaxLines,
    maxBytes: if options.maxBytes > 0: options.maxBytes else: DefaultMaxBytes,
    tempFilePrefix: if options.tempFilePrefix.len > 0: options.tempFilePrefix else: "npi-output",
  )
  result.maxRollingBytes = max(result.maxBytes * 2, 1)
  result.tailStartsAtLineBoundary = true

proc byteLength*(text: string): int =
  ## UTF-8 字节数（对齐 pi Buffer.byteLength）。
  text.len

proc utf8IncompleteSuffix(s: string): int =
  ## 返回字符串末尾未完成的 UTF-8 序列字节数（0=完整）。
  ## 判定规则：向前扫描，若结尾是 0x80-0xBF 续字节，找到其引导字节。
  let n = s.len
  if n == 0:
    return 0
  # 结尾是 ASCII 或完整多字节字符的引导字节（其后无续字节）→ 完整
  let last = s[n-1].uint8
  if last < 0x80 or last >= 0xC0:
    return 0
  # 结尾是续字节：往回找引导字节
  var i = n - 1
  var cont = 0
  while i >= 0 and (s[i].uint8 and 0xC0) == 0x80:
    inc cont
    dec i
  if i < 0:
    return 0  # 全续字节，无法判定（按完整处理）
  let lead = s[i].uint8
  let expected =
    if lead >= 0xF0: 4
    elif lead >= 0xE0: 3
    elif lead >= 0xC0: 2
    else: 1
  if cont + 1 < expected:
    return cont + 1  # 引导字节 + 部分续字节 = 未完成
  0

proc trimTail(a: OutputAccumulator): void =
  ## 裁剪 tailText 到 maxRollingBytes，避免切分 UTF-8 字符。
  if a.tailText.len <= a.maxRollingBytes:
    a.tailBytes = a.tailText.len
    return
  var start = a.tailText.len - a.maxRollingBytes
  while start < a.tailText.len and (a.tailText[start].uint8 and 0xC0) == 0x80:
    inc start
  a.tailStartsAtLineBoundary =
    if start == 0: a.tailStartsAtLineBoundary
    else: a.tailText[start-1] == '\n'
  a.tailText = a.tailText[start .. ^1]
  a.tailBytes = a.tailText.len

proc appendDecodedText(a: OutputAccumulator, text: string): void =
  ## 处理已解码的文本：行统计 + tail 维护。
  if text.len == 0:
    return
  a.totalDecodedBytes += text.len
  a.tailText.add text
  a.tailBytes += text.len
  if a.tailBytes > a.maxRollingBytes * 2:
    a.trimTail()
  var newlines = 0
  var lastNewline = -1
  var i = text.find('\n')
  while i >= 0:
    inc newlines
    lastNewline = i
    i = text.find('\n', i + 1)
  if newlines == 0:
    a.currentLineBytes += text.len
    a.hasOpenLine = true
  else:
    a.completedLines += newlines
    let tail = text[lastNewline+1 .. ^1]
    a.currentLineBytes = tail.len
    a.hasOpenLine = tail.len > 0
  a.totalLines = a.completedLines + (if a.hasOpenLine: 1 else: 0)

proc shouldUseTempFile(a: OutputAccumulator): bool =
  a.totalRawBytes > a.maxBytes or
    a.totalDecodedBytes > a.maxBytes or
    a.totalLines > a.maxLines

proc ensureTempFile(a: OutputAccumulator): void =
  if a.tempFilePath.len > 0:
    return
  let id = rand(int64.high).toHex(16)
  a.tempFilePath = getTempDir() / (a.tempFilePrefix & "-" & id & ".log")
  var content = ""
  for chunk in a.rawChunks:
    content.add chunk
  writeFile(a.tempFilePath, content)
  a.rawChunks = @[]

proc append*(a: OutputAccumulator, data: string): void =
  ## 追加 UTF-8 字节 chunk（流式，可跨调用切分多字节字符）。
  if a.finished:
    raise newException(ValueError, "Cannot append to a finished output accumulator")
  a.totalRawBytes += data.len
  # 拼接 pending 序列，处理跨 chunk 的多字节字符
  let combined = a.pendingBytes & data
  let incomplete = utf8IncompleteSuffix(combined)
  var decodable = ""
  if incomplete > 0:
    a.pendingBytes = combined[combined.len - incomplete .. ^1]
    decodable = combined[0 ..< combined.len - incomplete]
  else:
    a.pendingBytes = ""
    decodable = combined
  a.appendDecodedText(decodable)
  if a.tempFilePath.len > 0 or a.shouldUseTempFile():
    a.ensureTempFile()
    # 原始 chunk 追加写入临时文件
    var f = open(a.tempFilePath, fmAppend)
    defer: f.close()
    f.write(data)
  elif data.len > 0:
    a.rawChunks.add data

proc finish*(a: OutputAccumulator): void =
  ## 结束累积：冲刷 pending 序列，必要时创建临时文件。幂等。
  if a.finished:
    return
  a.finished = true
  if a.pendingBytes.len > 0:
    a.appendDecodedText(a.pendingBytes)
    a.pendingBytes = ""
  if a.shouldUseTempFile():
    a.ensureTempFile()

proc getSnapshotText(a: OutputAccumulator): string =
  if a.tailStartsAtLineBoundary:
    a.tailText
  else:
    let firstNewline = a.tailText.find('\n')
    if firstNewline == -1: a.tailText
    else: a.tailText[firstNewline+1 .. ^1]

proc snapshot*(a: OutputAccumulator, persistIfTruncated = false): OutputSnapshot =
  ## 截断快照：content + truncation + 可选全文路径。
  let snapText = a.getSnapshotText()
  let tailTruncation = truncateTail(snapText, TruncationOptions(
    maxLines: a.maxLines, maxBytes: a.maxBytes))
  let truncated = a.totalLines > a.maxLines or a.totalDecodedBytes > a.maxBytes
  var truncatedBy: string
  if truncated:
    if tailTruncation.truncatedBy.len > 0:
      truncatedBy = tailTruncation.truncatedBy
    elif a.totalDecodedBytes > a.maxBytes:
      truncatedBy = "bytes"
    else:
      truncatedBy = "lines"
  else:
    truncatedBy = ""
  result.truncation = tailTruncation
  result.truncation.truncated = truncated
  result.truncation.truncatedBy = truncatedBy
  result.truncation.totalLines = a.totalLines
  result.truncation.totalBytes = a.totalDecodedBytes
  result.truncation.maxLines = a.maxLines
  result.truncation.maxBytes = a.maxBytes
  result.content = tailTruncation.content
  if persistIfTruncated and truncated:
    a.ensureTempFile()
  result.fullOutputPath = a.tempFilePath

proc getLastLineBytes*(a: OutputAccumulator): int =
  a.currentLineBytes

proc closeTempFile*(a: OutputAccumulator): void =
  ## 临时文件已同步写入，close 为幂等 no-op（对齐 pi closeTempFile 语义）。
  discard
