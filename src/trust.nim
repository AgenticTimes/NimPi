## 项目信任：对齐 pi `trust-manager.ts` + `project-trust.ts`。
## findNearestTrustEntry / getProjectTrustParentPath / getProjectTrustOptions /
## hasTrustRequiringProjectResources / ProjectTrustStore(JSON) / resolveProjectTrusted。

import std/[os, tables, strutils, json, algorithm, options, sequtils]

type
  TrustDecision* = Option[bool]   ## none = 无记录（未决策）

  TrustStoreEntry* = object
    path*: string
    decision*: bool

  TrustUpdate* = object
    path*: string
    decision*: Option[bool]       ## none 表示删除该路径条目

  TrustOption* = object
    label*: string
    trusted*: bool
    updates*: seq[TrustUpdate]
    savedPath*: string            ## 空 = 无持久化（session-only 选项）

  ## trust.json: path -> true/false/absent
  TrustFile* = Table[string, Option[bool]]

  ProjectTrustStore* = object
    trustPath*: string

  UiSelect* = proc(cwd: string, options: seq[TrustOption]): Option[TrustOption] {.closure.}

  ResolveTrustOptions* = object
    cwd*: string
    trustStore*: ProjectTrustStore
    trustOverride*: Option[bool]
    defaultTrust*: string         ## "ask" | "always" | "never"
    uiSelect*: UiSelect           ## nil = 无 UI

const
  ConfigDirName* = ".npi"
  ## 需要信任门禁的项目级资源（对齐 pi 完整 7 项）
  TrustRequiringProjectResources* = [
    "settings.json", "extensions", "skills", "prompts",
    "themes", "SYSTEM.md", "APPEND_SYSTEM.md",
  ]

proc newProjectTrustStore*(agentDir: string): ProjectTrustStore =
  ## trustPath = agentDir/trust.json（对齐 pi ProjectTrustStore 构造）。
  ProjectTrustStore(trustPath: agentDir / "trust.json")

proc normalizeCwd(cwd: string): string =
  ## 规范化路径：优先 realpath（解析符号链接），失败回退原路径（对齐 pi canonicalizePath）。
  try:
    result = expandFilename(cwd)
  except OSError:
    result = cwd

proc findNearestTrustEntry*(data: TrustFile, cwd: string): Option[TrustStoreEntry] =
  ## 从 cwd 沿目录向上查找最近的非 none 条目；none 条目继续向上；根仍未命中返回 none。
  var currentDir = normalizeCwd(cwd)
  while true:
    if data.hasKey(currentDir):
      let v = data[currentDir]
      if v.isSome:
        return some(TrustStoreEntry(path: currentDir, decision: v.get))
    let parentDir = parentDir(currentDir)
    if parentDir == currentDir:
      return none(TrustStoreEntry)
    currentDir = parentDir

proc getProjectTrustParentPath*(cwd: string): string =
  ## 规范化后取父目录；文件系统根返回空串（对齐 pi 返回 undefined）。
  let trustPath = normalizeCwd(cwd)
  let parentDir = parentDir(trustPath)
  if parentDir == trustPath: "" else: parentDir

proc getProjectTrustOptions*(cwd: string, includeSessionOnly = false): seq[TrustOption] =
  ## 固定顺序生成选项列表，label 与 pi 一致。
  let trustPath = normalizeCwd(cwd)
  result = @[
    TrustOption(label: "Trust", trusted: true,
      updates: @[TrustUpdate(path: trustPath, decision: some(true))],
      savedPath: trustPath),
  ]
  let parentPath = getProjectTrustParentPath(cwd)
  if parentPath.len > 0:
    result.add TrustOption(
      label: "Trust parent folder (" & parentPath & ")",
      trusted: true,
      updates: @[TrustUpdate(path: parentPath, decision: some(true)),
                 TrustUpdate(path: trustPath, decision: none(bool))],
      savedPath: parentPath)
  if includeSessionOnly:
    result.add TrustOption(label: "Trust (this session only)", trusted: true,
      updates: @[], savedPath: "")
  result.add TrustOption(label: "Do not trust", trusted: false,
    updates: @[TrustUpdate(path: trustPath, decision: some(false))],
    savedPath: trustPath)
  if includeSessionOnly:
    result.add TrustOption(label: "Do not trust (this session only)", trusted: false,
      updates: @[], savedPath: "")

proc hasTrustRequiringProjectResources*(cwd: string): bool =
  ## cwd/.npi 下存在门禁资源，或 cwd 或其祖先存在 .agents/skills
  ## （用户级 ~/.agents/skills 除外，总是受信任，对齐 pi）。
  let homeDir = normalizeCwd(getHomeDir())
  let userAgentsSkillsDir = homeDir / ".agents" / "skills"
  var currentDir = normalizeCwd(cwd)
  let configDir = currentDir / ConfigDirName
  for entry in TrustRequiringProjectResources:
    if fileExists(configDir / entry) or dirExists(configDir / entry):
      return true
  while true:
    let agentsSkillsDir = currentDir / ".agents" / "skills"
    if agentsSkillsDir != userAgentsSkillsDir and dirExists(agentsSkillsDir):
      return true
    let parentDir = parentDir(currentDir)
    if parentDir == currentDir:
      return false
    currentDir = parentDir

# ---------------------------------------------------------------------------
# ProjectTrustStore：trust.json 读写（对齐 pi；无 proper-lockfile 多进程锁，
# ponytail: 单进程 CLI 足够，若未来多进程共享 store 再补文件锁）
# ---------------------------------------------------------------------------

proc parseTrustFile(content: string, path: string): TrustFile =
  ## 解析校验（对齐 pi readTrustFile 的校验语义）。
  var parsed: JsonNode
  try:
    parsed = parseJson(content)
  except CatchableError as e:
    raise newException(ValueError, "Failed to read trust store " & path & ": " & e.msg)
  if parsed.kind != JObject:
    raise newException(ValueError, "Invalid trust store " & path & ": expected an object")
  result = initTable[string, Option[bool]]()
  for key, value in parsed:
    case value.kind
    of JBool:
      result[key] = some(value.getBool)
    of JNull:
      result[key] = none(bool)
    else:
      raise newException(ValueError,
        "Invalid trust store " & path & ": value for \"" & key & "\" must be true, false, or null")

proc readStore*(store: ProjectTrustStore): TrustFile =
  ## 读取 trust.json（不存在或空返回空表）。
  result = initTable[string, Option[bool]]()
  if not fileExists(store.trustPath):
    return
  let content = readFile(store.trustPath)
  if content.strip.len == 0:
    return
  result = parseTrustFile(content, store.trustPath)

proc writeStore*(store: ProjectTrustStore, data: TrustFile) =
  ## 写 trust.json（按 path 排序，格式对齐 pi JSON.stringify(sorted, null, 2)）。
  var j = newJObject()
  let keys = toSeq(data.keys).sorted()
  for k in keys:
    let v = data[k]
    if v.isSome:
      j[k] = %(v.get)
    else:
      j[k] = newJNull()
  createDir(parentDir(store.trustPath))
  writeFile(store.trustPath, j.pretty() & "\n")

proc setMany*(store: ProjectTrustStore, updates: seq[TrustUpdate]) =
  ## 批量应用更新（对齐 pi setMany）：decision=none 删除条目，否则写入。
  var data = store.readStore()
  for u in updates:
    let key = normalizeCwd(u.path)
    if u.decision.isSome:
      data[key] = u.decision
    else:
      if data.hasKey(key):
        data.del(key)
  store.writeStore(data)

proc get*(store: ProjectTrustStore, cwd: string): Option[bool] =
  ## 无文件或无条目返回 none。
  let nearest = findNearestTrustEntry(store.readStore(), cwd)
  if nearest.isSome:
    some(nearest.get.decision)
  else:
    none(bool)

proc getEntry*(store: ProjectTrustStore, cwd: string): Option[TrustStoreEntry] =
  findNearestTrustEntry(store.readStore(), cwd)

proc set*(store: ProjectTrustStore, cwd: string, decision: Option[bool]) =
  store.setMany(@[TrustUpdate(path: cwd, decision: decision)])

proc formatProjectTrustPrompt*(cwd: string): string =
  ## 信任提示文本（对齐 pi formatProjectTrustPrompt，配置目录名改为 .npi）。
  "Trust project folder?\n" & cwd & "\n\n" &
    "This allows npi to load " & ConfigDirName &
    " settings and resources, install missing project packages, and execute project extensions."

proc resolveProjectTrusted*(opts: ResolveTrustOptions): bool =
  ## 决策流（对齐 pi resolveProjectTrusted），按序短路。
  ## override → 资源检测 → store 记录 → default(always/never/ask) → UI → 无 UI false。
  if opts.trustOverride.isSome:
    return opts.trustOverride.get
  if not hasTrustRequiringProjectResources(opts.cwd):
    return true
  let record = opts.trustStore.get(opts.cwd)
  if record.isSome:
    return record.get
  case opts.defaultTrust
  of "always":
    return true
  of "never":
    return false
  else:
    discard  # ask
  if opts.uiSelect.isNil:
    return false
  let selected = opts.uiSelect(opts.cwd,
    getProjectTrustOptions(opts.cwd, includeSessionOnly = true))
  if selected.isSome:
    let opt = selected.get
    if opt.updates.len > 0:
      opts.trustStore.setMany(opt.updates)
    return opt.trusted
  # 未选中（取消）→ 不信任
  false
