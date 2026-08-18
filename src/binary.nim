## 二进制检测：grep/read 跳过二进制文件避免乱码输出。
## NUL 字节 + 控制字符比例阈值检测。

import std/[os, strutils, unicode]

const
  BinarySampleLen = 1024        ## 检测采样长度
  MaxNulBytes = 1               ## 允许的 NUL 字节数（>1 即二进制）
  MaxControlRatio = 0.30        ## 控制字符比例阈值（文本通常远低于此）

proc isBinaryContent*(content: string, sampleLen = BinarySampleLen): bool =
  ## 检测内容是否二进制：
  ## 1. 前 sampleLen 字节中 NUL(0x00) 超过 MaxNulBytes
  ## 2. 或控制字符（除 \t\n\r）比例超阈值
  ## 纯文本（UTF-8）应返回 false。
  let sample = if content.len > sampleLen: content[0 ..< sampleLen] else: content
  var nulCount = 0
  var controlCount = 0
  for ch in sample:
    let b = ord(ch)
    if b == 0:
      inc nulCount
    elif b < 0x20 and b notin [0x09, 0x0a, 0x0d]:
      inc controlCount
  if nulCount > MaxNulBytes:
    return true
  let total = max(1, sample.len)
  result = controlCount / total > MaxControlRatio

proc isBinaryFile*(path: string): bool =
  ## 读前 sample 检测文件是否二进制。
  if not fileExists(path):
    return false
  try:
    let f = open(path, fmRead)
    var buf = newString(BinarySampleLen)
    let n = f.readChars(buf, 0, BinarySampleLen)
    f.close()
    if n > 0:
      buf.setLen(n)
      return isBinaryContent(buf)
    return false
  except CatchableError:
    return false