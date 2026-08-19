# 完整目标规格：npi output accumulator

对齐 pi-coding-agent 的 `core/tools/output-accumulator.ts`。归档后 `src/outputaccumulator.nim` 的完整行为如下。

## 类型

```nim
type
  OutputAccumulator* = ref object
    maxLines*: int            ## 行上限（默认 2000）
    maxBytes*: int            ## 字节上限（默认 50KB）
    maxRollingBytes*: int     ## tail 滚动窗口 = max(2*maxBytes, 1)
    tempFilePrefix*: string   ## 临时文件前缀（默认 "npi-output"）
    rawChunks*: seq[string]   ## 未超过上限时内存保留的原始 chunk
    tailText*: string         ## 解码后的 tail 文本
    tailBytes*: int
    tailStartsAtLineBoundary*: bool
    totalRawBytes*: int
    totalDecodedBytes*: int
    completedLines*: int
    totalLines*: int
    currentLineBytes*: int    ## 当前未完成行字节数
    hasOpenLine*: bool
    finished*: bool
    pendingBytes*: string     ## UTF-8 跨 chunk 边界的未完成字节序列
    tempFilePath*: string     ## 空 = 未创建临时文件

  OutputSnapshot* = object
    content*: string
    truncation*: TruncationResult
    fullOutputPath*: string   ## 空 = 无临时文件
```

## 常量（对齐 pi）

```nim
const
  DefaultMaxLines* = 2000
  DefaultMaxBytes* = 50 * 1024
```

## 构造

`newOutputAccumulator*(options: OutputAccumulatorOptions = default): OutputAccumulator`，options 含 maxLines/maxBytes/tempFilePrefix，缺省用常量。maxRollingBytes = max(2*maxBytes, 1)。

## append

输入：UTF-8 字节串 chunk（流式，可跨调用切分多字节字符）。行为：

1. finished 时抛错 `Cannot append to a finished output accumulator`。
2. totalRawBytes += chunk.len。
3. 拼接 pendingBytes + chunk 后，判定末尾是否含未完成 UTF-8 序列（多字节字符的续字节 0x80-0xBF 不足）；是则把未完成字节存入 pendingBytes，其余字节解码为文本处理；否则全部解码。
4. 解码文本进入行统计：统计 '\n' 数量；无换行则 currentLineBytes += 字节数、hasOpenLine=true；有换行则 completedLines += 换行数，最后一段（最后一个 '\n' 之后）成为当前行。
5. totalLines = completedLines + (hasOpenLine ? 1 : 0)。
6. tailText 追加解码文本；tailBytes 超 2*maxRollingBytes 时裁剪（见 trimTail）。
7. 临时文件已创建或 shouldUseTempFile() 为真 → 原始 chunk 写入临时文件；否则追加进 rawChunks。

## finish

finished 置 true；将 pendingBytes 作为完整文本解码处理（此时是完整字符，直接计入）；若 shouldUseTempFile() 则创建临时文件。幂等：重复调用直接返回。

## snapshot

输入：可选 persistIfTruncated。行为：

1. 取快照文本：tailStartsAtLineBoundary 为真 → tailText 全量；否则从第一个 '\n' 之后开始（跳过被裁剪的半行）。
2. 调 truncateTail(snapshotText, {maxLines, maxBytes})。
3. truncated = totalLines > maxLines 或 totalDecodedBytes > maxBytes；truncatedBy = tailTruncation.truncatedBy ?? (totalDecodedBytes > maxBytes ? "bytes" : "lines")。
4. 组装 TruncationResult：content/truncated/truncatedBy/totalLines/totalBytes/maxLines/maxBytes 从截断结果与自身统计合成（outputLines/outputBytes/lastLinePartial/firstLineExceedsLimit 由 truncateTail 给出）。
5. persistIfTruncated && truncated → 创建临时文件。
6. 返回 {content, truncation, fullOutputPath}。

## getLastLineBytes

返回 currentLineBytes。

## closeTempFile

若临时文件已创建，关闭写入流（Nim 同步文件写入完成后调用，确保 flush）；未创建则直接返回。幂等。

## 内部：trimTail

tailText 超 maxRollingBytes 时：保留末尾 maxRollingBytes 字节；若起点字节是 UTF-8 续字节（0x80-0xBF 掩码），后移到字符起始；tailStartsAtLineBoundary 更新为（起点前一个字节是 '\n' 或起点为 0）；更新 tailText/tailBytes。

## 内部：shouldUseTempFile

`totalRawBytes > maxBytes 或 totalDecodedBytes > maxBytes 或 totalLines > maxLines`。

## 内部：ensureTempFile

临时文件路径 = `getTempDir() / (tempFilePrefix & "-" & randomHex(8) & ".log")`；创建后把 rawChunks 全部写入（对齐 pi 把已收集 chunk 灌入 WriteStream），清空 rawChunks。幂等：已有路径则跳过。

## 接入：agent.nim bash 工具

`of "bash"` 分支：execBashWithTimeout 得到 br 后，sanitizeShellOutput 清洗，然后：

```nim
var acc = newOutputAccumulator()
acc.append(cleaned)
acc.finish()
let snap = acc.snapshot(persistIfTruncated = true)
var text = snap.content
if snap.truncation.truncated:
  text.add "\n... [truncated " & formatSize(snap.truncation.totalBytes) &
    ", showing last " & $snap.truncation.outputLines & " lines]"
  if snap.fullOutputPath.len > 0:
    text.add "\n[full output: " & snap.fullOutputPath & "]"
return ("", name, text, br.exitCode != 0 or br.timedOut)
```

短输出（未超限）行为与现状一致：无 `[full output]` 后缀，无临时文件残留。

## 测试（tests/test_core.nim 追加）

- append 多 chunk 拼接：("ab","c","def") → finish → content=="abcdef"，totalLines==1（无换行 → hasOpenLine=true，对齐 pi），truncated==false
- UTF-8 跨边界：多字节字符（如 "中" 3 字节）拆成 1+2 字节两个 chunk → finish 后解码正确
- 行统计：3 行输入 → totalLines==3；末尾无换行 → hasOpenLine 语义正确
- 字节超限：maxBytes=10 输出 20 字节 → snapshot.truncated、truncatedBy=="bytes"
- 行超限：maxLines=2 输出 5 行 → content 仅最后 2 行，truncatedBy=="lines"
- 未超限：无临时文件（fullOutputPath 空）
- 超限 + persistIfTruncated：fullOutputPath 非空，文件存在且包含完整输出；closeTempFile 后可读
- finished 后 append → 抛错
- getLastLineBytes：无换行输入返回累计字节
- trimTail 边界：tail 裁剪不切分多字节字符（裁剪后内容可正确解码）
- 随机前缀唯一：两次实例 temp 路径不同

## 非目标（明确不做）

- Node Buffer/WriteStream 异步流语义
- TextDecoder 完整解码器（BOM、invalid 序列替换字符等）
- 非 bash 工具接入
- 改变既有 bash tail 截断显示
