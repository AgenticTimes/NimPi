## TUI：基于 illwill 的全屏界面。
## 上半区消息滚动，底部输入框。↑/↓ 滚动，Enter 发送，Ctrl+C 退出。

import illwill
import std/[strutils]
import ./fuzzy

type
  RenderLine* = object
    text*: string
    isError*: bool

  Tui* = ref object
    tb*: TerminalBuffer
    width*, height*: int
    exitApp*: bool
    history*: seq[RenderLine]
    input*: string
    cursor*: int
    scrollOffset*: int
    status*: string
    commands*: seq[string]
    paletteMode*: bool
    paletteIndex*: int

proc initTui*(): Tui =
  illwillInit(fullscreen = true)
  hideCursor()
  result = Tui(exitApp: false, cursor: 0, scrollOffset: 0,
               status: "npi — Enter 发送 · ↑/↓ 滚动 · Ctrl+C 退出",
               commands: @[], paletteMode: false, paletteIndex: 0)
  result.tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  result.width = terminalWidth()
  result.height = terminalHeight()

proc setCommands*(tui: Tui, cmds: seq[string]) =
  ## 设置命令面板可用命令。
  tui.commands = cmds
  if tui.paletteIndex >= cmds.len:
    tui.paletteIndex = 0

proc paletteQuery*(tui: Tui): string =
  ## palette 模式下过滤 query（输入去掉 `/` 前缀）。
  if tui.input.startsWith("/"): tui.input[1 .. ^1]
  else: ""

proc paletteMatches*(tui: Tui): seq[string] =
  ## 当前 fuzzy 过滤后的命令列表（palette 模式用）。
  if tui.paletteMode:
    fuzzyFilter(tui.commands, tui.paletteQuery(), proc(x: string): string = x)
  else:
    tui.commands

proc enterPalette*(tui: Tui) =
  ## 进入命令面板模式。
  tui.paletteMode = true
  tui.paletteIndex = 0
  if not tui.input.startsWith("/"):
    tui.input = "/" & tui.input
    tui.cursor = tui.input.len

proc exitPalette*(tui: Tui) =
  ## 退出命令面板模式。
  tui.paletteMode = false
  tui.paletteIndex = 0

proc addLine*(tui: Tui, text: string, isError = false) =
  tui.history.add RenderLine(text: text, isError: isError)
  # 自动跟随到底部
  tui.scrollOffset = 0

proc setStatus*(tui: Tui, status: string) =
  tui.status = status

proc render*(tui: Tui) =
  var tb = tui.tb
  tb.resetAttributes()
  tb.clear()
  let h = tui.height

  # 状态行（底部第 2 行）
  tb.setForegroundColor(fgCyan, bright = true)
  tb.write(0, h - 2, tui.status[0 ..< min(tui.status.len, tui.width)])

  # 消息区
  tb.setForegroundColor(fgWhite, bright = false)
  let rows = h - 3
  let total = tui.history.len
  # 可见窗口：底部对齐，减去滚动偏移
  let endIdx = total - tui.scrollOffset
  let startIdx = max(0, endIdx - rows)
  var y = 0
  for i in startIdx ..< endIdx:
    var text = tui.history[i].text
    if text.len > tui.width: text = text[0 ..< tui.width]
    if tui.history[i].isError:
      tb.setForegroundColor(fgRed, bright = false)
    else:
      tb.setForegroundColor(fgWhite, bright = false)
    tb.write(0, y, text)
    inc y

  # palette 模式：命令列表覆盖消息区下半
  if tui.paletteMode:
    let matches = tui.paletteMatches()
    tb.setForegroundColor(fgYellow, bright = true)
    tb.write(0, h - 3, "命令面板 — " & tui.paletteQuery() & "（" & $matches.len & " 项）")
    let listRows = max(0, rows - 1)
    for i in 0 ..< min(matches.len, listRows):
      let y = h - 4 - i
      if y < 1: break
      if i == tui.paletteIndex:
        tb.setForegroundColor(fgBlack, bright = false)
        tb.setBackgroundColor(bgCyan)
        tb.write(0, y, "> " & matches[i])
        tb.setBackgroundColor(bgNone)
      else:
        tb.setForegroundColor(fgWhite, bright = false)
        tb.write(0, y, "  " & matches[i])

  # 输入行
  tb.setForegroundColor(fgGreen, bright = true)
  tb.write(0, h - 1, "> ")
  tb.setForegroundColor(fgWhite, bright = false)
  tb.write(2, h - 1, tui.input)
  tb.display()

type
  EventKind* = enum
    evQuit, evEnter, evChar, evBackspace, evLeft, evRight,
    evUp, evDown, evCtrlC

  TuiEvent* = object
    kind*: EventKind
    ch*: char

proc poll*(tui: Tui): TuiEvent =
  let k = getKey()
  case k
  of Key.Escape, Key.CtrlQ: result.kind = evQuit
  of Key.CtrlC: result.kind = evCtrlC
  of Key.Enter: result.kind = evEnter
  of Key.Backspace, Key.CtrlH: result.kind = evBackspace
  of Key.Left, Key.CtrlB: result.kind = evLeft
  of Key.Right, Key.CtrlF: result.kind = evRight
  of Key.Up, Key.CtrlP: result.kind = evUp
  of Key.Down, Key.CtrlN: result.kind = evDown
  of Key.None:
    result.kind = evChar
    result.ch = '\0'
  else:
    # 可打印字符
    if k.ord >= 32 and k.ord <= 126:
      result.kind = evChar
      result.ch = chr(k.ord)
    else:
      result.kind = evChar
      result.ch = '\0'

proc handleInput*(tui: Tui, e: TuiEvent) =
  if tui.paletteMode:
    case e.kind
    of evChar:
      if e.ch != '\0':
        tui.input.insert($e.ch, tui.cursor)
        inc tui.cursor
        tui.paletteIndex = 0
    of evBackspace:
      if tui.cursor > 1 and tui.input.len > 1:
        dec tui.cursor
        tui.input.delete(tui.cursor .. tui.cursor)
        tui.paletteIndex = 0
    of evLeft:
      if tui.cursor > 1: dec tui.cursor
    of evRight:
      if tui.cursor < tui.input.len: inc tui.cursor
    of evUp:
      let m = tui.paletteMatches()
      if m.len > 0 and tui.paletteIndex > 0: dec tui.paletteIndex
    of evDown:
      let m = tui.paletteMatches()
      if tui.paletteIndex + 1 < m.len: inc tui.paletteIndex
    of evEnter:
      # 选中当前命令 → 填回输入框并退出 palette
      let m = tui.paletteMatches()
      if m.len > 0 and tui.paletteIndex < m.len:
        tui.input = m[tui.paletteIndex]
        tui.cursor = tui.input.len
      tui.exitPalette()
    of evQuit, evCtrlC:
      # Esc/Ctrl+C 退出 palette（不退出应用）
      tui.exitPalette()
    return

  case e.kind
  of evChar:
    if e.ch != '\0':
      tui.input.insert($e.ch, tui.cursor)
      inc tui.cursor
      # `/` 开头进入命令面板
      if tui.input.startsWith("/") and tui.commands.len > 0:
        tui.paletteMode = true
        tui.paletteIndex = 0
  of evBackspace:
    if tui.cursor > 0 and tui.input.len > 0:
      dec tui.cursor
      tui.input.delete(tui.cursor .. tui.cursor)
  of evLeft:
    if tui.cursor > 0: dec tui.cursor
  of evRight:
    if tui.cursor < tui.input.len: inc tui.cursor
  of evUp:
    if tui.scrollOffset < tui.history.len: inc tui.scrollOffset
  of evDown:
    if tui.scrollOffset > 0: dec tui.scrollOffset
  else: discard

proc deinit*(tui: Tui) =
  showCursor()
  illwillDeinit()
