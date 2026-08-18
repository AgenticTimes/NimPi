## 命令输出清理：对齐 pi `utils/shell.ts` sanitizeBinaryOutput 与 `utils/ansi.ts` stripAnsi。
## 移除 ANSI 转义序列与破坏显示/存储的控制字符。

import std/[strutils, unicode]

proc stripAnsi*(s: string): string =
  ## 移除 ANSI/OSC/CSI 转义序列（对齐 pi ansiRegex 语义）。
  ## 快速路径：无 ESC(0x1B) 或 C1(0x9B) 直接返回。
  if not s.contains('\x1B') and not s.contains('\x9B'):
    return s
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '\x1B' or c == '\x9B':
      # CSI/ESC 序列：从当前字符开始消耗掉完整转义序列
      # ESC ] (OSC) 到 ST (BEL / ESC \ / 0x9C) 或 CSI 到最终字节
      var j = i
      var isOsc = false
      if c == '\x1B' and j + 1 < s.len and s[j+1] == ']':
        isOsc = true
        j += 2
      elif (c == '\x1B' and j + 1 < s.len and (s[j+1] in "[()]")) or c == '\x9B':
        # CSI: ESC[ 或 ESC( 或 C1(0x9B)。跳到引入符之后。
        if c == '\x1B':
          j += 2      # 跳过 ESC + 引入符(如 [)
        else:
          j += 1      # C1 本身
      else:
        # 单 ESC 但非序列开头，跳过该 ESC
        i += 1
        continue
      if isOsc:
        # OSC: 到 BEL / ESC\ / 0x9C
        while j < s.len:
          if s[j] == '\x07':             # BEL
            j += 1
            break
          if s[j] == '\x1B' and j+1 < s.len and s[j+1] == '\\':  # ESC\
            j += 2
            break
          if s[j] == '\x9C':
            j += 1
            break
          inc j
        i = j
        continue
      # CSI: 参数 + 最终字节（含可选中间字符()#;? 与数字参数）
      while j < s.len and (s[j].isDigit or s[j] in ";:?()#"):
        inc j
      if j < s.len:
        # 最终字节：控制函数（@-~ 字母等）
        inc j
      i = j
      continue
    result.add c
    inc i

proc sanitizeBinaryOutput*(s: string): string =
  ## 过滤破坏显示/存储的字符（对齐 pi）：
  ## - 控制字符（0x00-0x1F 除 tab/newline/CR）
  ## - unicode 格式字符（0xfff9-0xfffb）
  ## 保留 tab(0x09) newline(0x0a) CR(0x0d)。
  result = newStringOfCap(s.len)
  for r in s.runes:
    let cp = int(r)
    if cp == 0x09 or cp == 0x0a or cp == 0x0d:
      result.add r
    elif cp <= 0x1f:
      discard                    # 过滤控制字符
    elif cp >= 0xfff9 and cp <= 0xfffb:
      discard                    # 过滤 unicode 格式字符
    else:
      result.add r

proc sanitizeShellOutput*(s: string): string =
  ## bash-executor onData 的清理链：stripAnsi → sanitizeBinaryOutput → 去 \r。
  result = s.stripAnsi().sanitizeBinaryOutput().replace("\r", "")

proc sanitizeUnicode*(s: string): string =
  ## 别名：仅 sanitizeBinaryOutput。保留用于测试可读性。
  result = s.sanitizeBinaryOutput()

when isMainModule:
  # 自检（可选运行: nim c -r src/shell.nim）
  doAssert stripAnsi("\x1b[31mred\x1b[0m") == "red"
  doAssert sanitizeBinaryOutput("a\x00b\x07c") == "abc"
  doAssert sanitizeBinaryOutput("a\tb\nc") == "a\tb\nc"
  echo "shell self-check OK"