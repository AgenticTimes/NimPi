## Skills：对齐 pi `skills.ts` 的 Agent Skills 支持。
## 递归发现 SKILL.md、解析 frontmatter（YAML 子集）、XML 格式注入 system prompt。

import std/[os, strutils, tables]

type
  Skill* = object
    name*: string
    description*: string
    filePath*: string
    baseDir*: string
    disableModelInvocation*: bool

  SkillDiagnostic* = object
    isError*: bool
    message*: string
    path*: string

  LoadSkillsResult* = object
    skills*: seq[Skill]
    diagnostics*: seq[SkillDiagnostic]

const
  SkillFile = "SKILL.md"
  ## Agent Skills XML 模板（对齐 agentskills.io 标准）
  SkillsPromptHeader = """<available_skills>
The following skills provide specialized instructions for specific tasks.
Use the read tool to load a skill's file when the task matches its description.
When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands."""

proc xmlEscape(s: string): string =
  ## XML 转义（对齐 pi escapeXml）
  result = s
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
    .replace("\"", "&quot;")
    .replace("'", "&apos;")

proc parseFrontmatter(content: string): tuple[frontmatter: Table[string, string], ok: bool] =
  ## 解析 SKILL.md 开头的 YAML frontmatter（--- 围栏内的 key: value 简单形式）。
  ## 返回 (键值表, 是否成功)。
  result.ok = false
  result.frontmatter = initTable[string, string]()
  if not content.startsWith("---\n"):
    return
  let endIdx = content.find("\n---", 4)
  if endIdx < 0:
    return
  let body = content[4 ..< endIdx]
  for line in body.splitLines():
    let l = line.strip
    if l.len == 0 or l.startsWith("#"):
      continue
    let colon = l.find(':')
    if colon <= 0:
      continue
    let key = l[0 ..< colon].strip
    var val = l[colon+1 .. ^1].strip
    # 去掉引号
    if val.len >= 2 and ((val[0] == '"' and val[^1] == '"') or
                         (val[0] == '\'' and val[^1] == '\'')):
      val = val[1 .. ^2]
    result.frontmatter[key] = val
  result.ok = true

proc validateName(name: string): seq[string] =
  ## 校验 skill 名（Agent Skills spec：小写、字母数字+连字符下划线，长度 1-64）。
  if name.len == 0:
    return @["skill name is empty"]
  if name.len > 64:
    return @["skill name is too long (max 64 chars): " & name]
  if not name.allCharsInSet(Letters + Digits + {'-', '_'}):
    return @["skill name must be lowercase alphanumeric with dashes/underscores: " & name]
  result = @[]

proc loadSkillFromFile(filePath: string): tuple[skill: Skill, diag: SkillDiagnostic] =
  ## 解析单个 SKILL.md，返回 skill（无效时报诊断）。
  let isDeclared = extractFilename(filePath) == SkillFile
  var content: string
  try:
    content = readFile(filePath)
  except CatchableError as e:
    return (Skill(), SkillDiagnostic(isError: true,
      message: "failed to read skill file: " & e.msg, path: filePath))
  let (fm, ok) = parseFrontmatter(content)
  if not ok:
    if isDeclared:
      return (Skill(), SkillDiagnostic(isError: true,
        message: "failed to parse skill file (missing frontmatter)", path: filePath))
    return (Skill(), SkillDiagnostic(isError: false, message: "", path: filePath))
  let description = fm.getOrDefault("description", "").strip
  if not isDeclared and description.len == 0:
    return (Skill(), SkillDiagnostic(isError: false, message: "", path: filePath))
  let skillDir = parentDir(filePath)
  let name = fm.getOrDefault("name", extractFilename(skillDir)).strip
  let dm = fm.getOrDefault("disable-model-invocation", "").strip
  result.skill = Skill(
    name: name,
    description: description,
    filePath: filePath,
    baseDir: skillDir,
    disableModelInvocation: dm.toLowerAscii in ["true", "yes", "1"])
  if description.len == 0:
    result.diag = SkillDiagnostic(isError: true,
      message: "skill description is missing or empty", path: filePath)
  else:
    result.diag = SkillDiagnostic(isError: false, message: "", path: filePath)

proc loadSkillsFromDir*(dir: string): LoadSkillsResult =
  ## 递归发现 SKILL.md：目录含 SKILL.md 视为 skill root，不再深入子目录。
  if not dirExists(dir):
    return LoadSkillsResult()
  # 本目录自身若含 SKILL.md，视为一个 skill root（加载后不再深入）
  let ownSkill = dir / SkillFile
  if fileExists(ownSkill):
    let (s, d) = loadSkillFromFile(ownSkill)
    if d.isError:
      result.diagnostics.add d
    elif s.name.len > 0 and s.description.len > 0:
      result.skills.add s
    return
  for kind, path in walkDir(dir):
    if kind == pcDir:
      # 子目录：含 SKILL.md 则递归处理（其自身即 root），否则递归深入
      let subRes = loadSkillsFromDir(path)
      result.skills.add subRes.skills
      result.diagnostics.add subRes.diagnostics

proc loadSkills*(projectRoot: string, trustProject = true): LoadSkillsResult =
  ## 加载项目级 .npi/skills/ 与用户级 NPI_AGENT_DIR/skills（默认 ~/.npi/skills）。
  ## trustProject=false（项目未信任）时跳过项目级目录，仍加载用户级。
  result = LoadSkillsResult()
  let userDir = getEnv("NPI_AGENT_DIR", getHomeDir() / ".npi")
  let userSkills = userDir / "skills"
  var dirs: seq[string] = @[]
  if trustProject:
    dirs.add projectRoot / ".npi" / "skills"
  dirs.add userSkills
  for d in dirs:
    let r = loadSkillsFromDir(d)
    result.skills.add r.skills
    result.diagnostics.add r.diagnostics

proc formatSkillsForPrompt*(skills: seq[Skill]): string =
  ## 按 Agent Skills 标准 XML 格式组合可注入 system prompt 的文本。
  ## disable-model-invocation=true 的 skill 不注入。
  var visible: seq[Skill] = @[]
  for s in skills:
    if not s.disableModelInvocation:
      visible.add s
  if visible.len == 0:
    return ""
  var sb = SkillsPromptHeader & "\n"
  for s in visible:
    sb.add "<skill name=\"" & s.name.xmlEscape() & "\">\n"
    sb.add "  <description>" & s.description.xmlEscape() & "</description>\n"
    sb.add "</skill>\n"
  sb.add "</available_skills>\n"
  result = sb