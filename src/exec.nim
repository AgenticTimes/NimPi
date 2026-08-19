## 命令执行：对齐 pi `exec.ts`。
## execCommand 返回分离 stdout/stderr/code/killed，支持超时（SIGTERM→5s 后 SIGKILL）。
## 区别于 bashtimeout（合并输出），本模块用分离临时文件收集两流。

import std/[os, osproc, times, strutils, posix]

type
  ExecOptions* = object
    timeoutMs*: int
    cwd*: string

  ExecResult* = object
    stdout*: string
    stderr*: string
    code*: int
    killed*: bool

const
  DefaultExecTimeoutMs* = 30000
  KillEscalationMs* = 5000     ## SIGTERM 后升级 SIGKILL 的延迟（对齐 pi）

proc execCommand*(command: string, args: seq[string], cwd: string,
                  opts: ExecOptions): ExecResult =
  ## 执行命令，分离收集 stdout/stderr（对齐 pi execCommand 语义）。
  result.code = -1
  result.killed = false
  let timeoutMs = if opts.timeoutMs > 0: opts.timeoutMs else: DefaultExecTimeoutMs
  let workDir = if cwd.len > 0: cwd else: getCurrentDir()
  let base = getTempDir() / ("npi-exec-" & $getTime().toUnix & "-" & $getCurrentProcessId())
  let outFile = base & ".out"
  let errFile = base & ".err"
  # 构造带重定向的 shell 命令（分离两流）：花括号分组整个命令块，避免分号后重定向只作用最后一条
  var shellCmd = command
  for a in args: shellCmd.add " " & a
  let fullCmd = "{ " & shellCmd & "; } > '" & outFile & "' 2> '" & errFile & "'"
  var p: Process
  try:
    p = startProcess("/bin/sh", workDir, ["-c", fullCmd],
                     env = nil, options = {poUsePath})
  except CatchableError as e:
    result.stdout = ""
    result.stderr = "failed to start: " & e.msg
    return
  # 轮询 + 超时（SIGTERM → 5s 后 SIGKILL）
  let startTime = epochTime()
  var finished = false
  var termSent = false
  var termTime = 0.0
  while true:
    if not p.running():
      finished = true
      break
    let elapsedMs = (epochTime() - startTime) * 1000
    if elapsedMs > timeoutMs.float and not termSent:
      # 超时：先 SIGTERM
      termSent = true
      termTime = epochTime()
      try: p.terminate()
      except CatchableError: discard
      result.killed = true
    if termSent and (epochTime() - termTime) * 1000 > KillEscalationMs.float:
      # SIGTERM 无效，升级 SIGKILL（对齐 pi 5s 后强杀）
      discard kill(Pid(-p.processID), SIGKILL)
      discard kill(Pid(p.processID), SIGKILL)
      try: p.kill()
      except CatchableError: discard
      break
    sleep(50)
  if finished and not result.killed:
    try:
      result.code = p.waitForExit()
    except CatchableError:
      result.code = -1
  else:
    result.code = -1
    result.killed = true
  try: p.close()
  except CatchableError: discard
  # 读分离输出
  try:
    if fileExists(outFile): result.stdout = readFile(outFile)
  except CatchableError: result.stdout = ""
  try:
    if fileExists(errFile): result.stderr = readFile(errFile)
  except CatchableError: result.stderr = ""
  removeFile(outFile)
  removeFile(errFile)