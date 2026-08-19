## auth.json 凭据存储：对齐 pi `auth-storage.ts` 核心语义。
## AuthStorage：凭据文件读写（0o600 权限）+ readStoredCredential/set/delete/list。

import std/[os, json, tables, strutils]

type
  AuthStorage* = object
    authPath*: string

proc defaultAuthPath*(): string =
  let dir = getEnv("NPI_AGENT_DIR", getHomeDir() / ".npi")
  dir / "auth.json"

proc newAuthStorage*(authPath: string = ""): AuthStorage =
  AuthStorage(authPath: if authPath.len > 0: authPath else: defaultAuthPath())

proc readAuthData(path: string): JsonNode =
  ## 读 auth.json（不存在/空返回空对象）。
  if not fileExists(path):
    return newJObject()
  let content = readFile(path)
  if content.strip.len == 0:
    return newJObject()
  try:
    let j = parseJson(content)
    if j.kind == JObject: return j
    return newJObject()
  except CatchableError:
    return newJObject()

proc writeAuthData(path: string, data: JsonNode) =
  ## 写 auth.json（0o600 权限对齐 pi）。
  createDir(parentDir(path))
  writeFile(path, $data & "\n")
  # 0o600 权限（仅 owner 可读写）
  try:
    setFilePermissions(path, {fpUserRead, fpUserWrite})
  except CatchableError:
    discard

proc readStoredCredential*(store: AuthStorage, providerId: string): string =
  ## 读 provider 凭据（对齐 pi readStoredCredential，返回 api key）。
  let data = readAuthData(store.authPath)
  let entry = data{providerId}
  if entry.isNil: return ""
  entry{"key"}.getStr(entry.getStr(""))

proc setCredential*(store: AuthStorage, providerId: string, apiKey: string) =
  ## 写 provider 凭据（对齐 pi AuthStorage 写入语义）。
  var data = readAuthData(store.authPath)
  data[providerId] = %*{"type": "api_key", "key": apiKey}
  writeAuthData(store.authPath, data)

proc deleteCredential*(store: AuthStorage, providerId: string) =
  ## 删 provider 凭据。
  var data = readAuthData(store.authPath)
  if data.hasKey(providerId):
    data.delete(providerId)
    writeAuthData(store.authPath, data)

proc listCredentials*(store: AuthStorage): seq[string] =
  ## 列出有凭据的 providerId。
  let data = readAuthData(store.authPath)
  for k, v in data:
    if v.kind == JObject and v.hasKey("key"):
      result.add k