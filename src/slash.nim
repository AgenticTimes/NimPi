## Slash 命令：对齐 pi `slash-commands.ts` 的 BuiltinSlashCommand。
## 内置命令注册表 + 解析 + 分发。TUI/REPL 以 `/cmd [arg]` 统一处理。

import std/[strutils, tables, sequtils, algorithm]

type
  SlashCommand* = object
    name*: string
    description*: string
    argumentHint*: string
    ## 处理器，返回处理结果文本（空表示已处理但无输出）
    handler*: proc(arg: string): string {.closure.}

  SlashResult* = object
    handled*: bool
    output*: string
    shouldQuit*: bool

proc quitHandler(arg: string): string =
  ""

proc helpHandler*(commands: Table[string, SlashCommand]): string =
  var sb = "可用命令：\n"
  let names = toSeq(commands.keys).sorted()
  for name in names:
    let c = commands[name]
    sb.add "/" & name
    if c.argumentHint.len > 0:
      sb.add " <" & c.argumentHint & ">"
    sb.add " — " & c.description & "\n"
  result = sb

proc buildCommands*(): Table[string, SlashCommand] =
  ## 内置命令注册表（对齐 pi BUILTIN_SLASH_COMMANDS 子集）。
  result = initTable[string, SlashCommand]()
  result["quit"] = SlashCommand(name: "quit", description: "退出 npi",
    handler: proc(arg: string): string = "")
  result["exit"] = SlashCommand(name: "exit", description: "退出 npi",
    handler: proc(arg: string): string = "")
  result["q"] = SlashCommand(name: "q", description: "退出 npi",
    handler: proc(arg: string): string = "")
  result["help"] = SlashCommand(name: "help", description: "列出所有命令",
    handler: proc(arg: string): string = "")
  result["model"] = SlashCommand(name: "model", description: "显示当前模型", argumentHint: "provider/model",
    handler: proc(arg: string): string = "")
  result["compact"] = SlashCommand(name: "compact", description: "手动压缩会话上下文",
    handler: proc(arg: string): string = "")
  result["new"] = SlashCommand(name: "new", description: "开始新会话",
    handler: proc(arg: string): string = "")
  result["resume"] = SlashCommand(name: "resume", description: "恢复其它会话", argumentHint: "会话名",
    handler: proc(arg: string): string = "")
  result["session"] = SlashCommand(name: "session", description: "显示会话信息",
    handler: proc(arg: string): string = "")
  result["skill"] = SlashCommand(name: "skill", description: "显式调用一个 skill", argumentHint: "skill名",
    handler: proc(arg: string): string = "")

proc parseSlash*(input: string): tuple[command: string, arg: string, isSlash: bool] =
  ## 解析输入。仅当以 `/` 开头视作命令，拆分为 (命令, 参数)。
  let trimmed = input.strip
  if not trimmed.startsWith("/"):
    return (command: "", arg: "", isSlash: false)
  # 去掉前导 "/"
  let body = trimmed[1 .. ^1]
  let sp = body.find(' ')
  if sp < 0:
    return (command: body, arg: "", isSlash: true)
  result = (command: body[0 ..< sp], arg: body[sp+1 .. ^1].strip, isSlash: true)

proc handleSlash*(commands: Table[string, SlashCommand], input: string,
                  ctx: proc(name: string): string {.closure.}): SlashResult =
  ## 分发 slash 命令。返回 handled 与 output。
  let (cmd, arg, isSlash) = parseSlash(input)
  if not isSlash:
    return SlashResult(handled: false, output: "")
  if not commands.hasKey(cmd):
    return SlashResult(handled: true,
      output: "未知命令: /" & cmd & "。用 /help 查看可用命令。")
  let command = commands[cmd]
  case cmd
  of "quit", "exit", "q":
    return SlashResult(handled: true, output: "", shouldQuit: true)
  of "help":
    return SlashResult(handled: true, output: helpHandler(commands))
  of "model":
    # 查询当前模型（通过 ctx 回调）
    return SlashResult(handled: true, output: ctx("model"))
  of "compact":
    return SlashResult(handled: true, output: ctx("compact"))
  of "new", "resume", "session", "skill":
    return SlashResult(handled: true, output: ctx(cmd & (if arg.len > 0: " " & arg else: "")))
  else:
    # 自定义 handler（若存在）
    if not command.handler.isNil:
      return SlashResult(handled: true, output: command.handler(arg))
    return SlashResult(handled: true, output: "命令 /" & cmd & " 未实现。")