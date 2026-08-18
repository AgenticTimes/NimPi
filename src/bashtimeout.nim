## Bash 超时执行：对齐 pi bash-executor 的 timeout 语义。
## startProcess + poll + 超时终止进程树 + 临时文件输出收集。

import std/[os, osproc, times, strutils, posix]

const
  DefaultBashTimeoutMs* = 120000   ## 对齐 pi DEFAULT（2 分钟）

type
  BashTimeoutOptions* = object
    timeoutMs*: int
    cwd*: string

  BashTimeoutResult* = object
    output*: string
    exitCode*: int
    timedOut*: bool

proc defaultBashTimeoutOptions*(): BashTimeoutOptions =
  BashTimeoutOptions(timeoutMs: DefaultBashTimeoutMs)

proc killProcessTree*(pid: int): bool =
  ## 杀进程树（posix kill 负 pid 即进程组）。失败回退单杀。
  if kill(Pid(-pid), SIGKILL) == 0:
    return true
  if kill(Pid(pid), SIGKILL) == 0:
    return true
  false

proc execBashWithTimeout*(cmd: string, opts: BashTimeoutOptions): BashTimeoutResult =
  ## 执行命令带超时。输出（含 stderr）经临时文件收集。
  result.exitCode = -1
  result.timedOut = false
  let timeoutMs = if opts.timeoutMs > 0: opts.timeoutMs else: DefaultBashTimeoutMs
  let cwd = if opts.cwd.len > 0: opts.cwd else: getCurrentDir()
  # 临时输出文件
  let outFile = getTempDir() / ("npi-bash-" & $getTime().toUnix & "-" & $os.getCurrentProcessId() & ".out")
  # 命令 + stderr 重定向到文件
  let fullCmd = "(" & cmd & ") > '" & outFile & "' 2>&1"
  var p: Process
  try:
    p = startProcess("/bin/sh", cwd, ["-c", fullCmd],
                     env = nil, options = {poUsePath})
  except CatchableError as e:
    result.output = "error: failed to start: " & e.msg
    return
  # 轮询等待，超时终止
  let startTime = epochTime()
  var finished = false
  while true:
    if not p.running():
      finished = true
      break
    let elapsedMs = (epochTime() - startTime) * 1000
    if elapsedMs > timeoutMs.float:
      # 超时：杀进程树
      discard killProcessTree(p.processID)
      try: p.terminate()
      except CatchableError: discard
      try: p.kill()
      except CatchableError: discard
      result.timedOut = true
      break
    sleep(50)
  # 收集退出码
  if finished:
    try:
      result.exitCode = p.waitForExit()
    except CatchableError:
      result.exitCode = -1
  try: p.close()
  except CatchableError: discard
  # 读输出
  try:
    if fileExists(outFile):
      result.output = readFile(outFile)
  except CatchableError:
    result.output = ""
  removeFile(outFile)
  if result.timedOut:
    result.output &= "\n[超时，命令已终止 (" & $timeoutMs & "ms)]"