## 资源清单：对齐 pi `pi-manifest.ts`。
## 解析 package.json 的 `pi` 字段（extensions/skills/prompts/themes）。

import std/[os, json, options]

type
  PiManifest* = object
    extensions*: seq[string]
    skills*: seq[string]
    prompts*: seq[string]
    themes*: seq[string]

const resourceFields = ["extensions", "skills", "prompts", "themes"]

proc emptyManifest*(): PiManifest =
  PiManifest(extensions: @[], skills: @[], prompts: @[], themes: @[])

proc readPiManifest*(packageJsonPath: string): Option[PiManifest] =
  ## 读 package.json 的 `pi` 资源字段；非法（无 pi/坏 JSON/非字符串数组）返回 none。
  if not fileExists(packageJsonPath):
    return none(PiManifest)
  var j: JsonNode
  try:
    j = parseJson(readFile(packageJsonPath))
  except JsonParsingError, IOError, OSError:
    return none(PiManifest)
  if j.kind != JObject:
    return none(PiManifest)
  let pi = j{"pi"}
  if pi.isNil or pi.kind != JObject:
    return none(PiManifest)
  result = some(emptyManifest())
  for field in resourceFields:
    let entries = pi{field}
    if entries.isNil or entries.kind != JArray:
      continue
    var items: seq[string] = @[]
    var allStrings = true
    for e in entries:
      if e.kind == JString:
        items.add e.str
      else:
        allStrings = false
        break
    if allStrings:
      case field
      of "extensions": result.get.extensions = items
      of "skills": result.get.skills = items
      of "prompts": result.get.prompts = items
      of "themes": result.get.themes = items
      else: discard