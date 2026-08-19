## 认证引导消息：对齐 pi `auth-guidance.ts`。
## 登录引导 + 无模型/无 API key 错误提示格式化。

import std/[strutils, os]

const unknownProvider = "unknown"

proc getProviderLoginHelp*(docsPath: string): string =
  ## 登录引导：/login 提示 + providers/models 文档路径。
  result = "Use /login to log into a provider via OAuth or API key. See:"
  if docsPath.len > 0:
    result &= "\n  " & docsPath.joinPath("providers.md") &
              "\n  " & docsPath.joinPath("models.md")

proc formatNoModelsAvailableMessage*(docsPath: string): string =
  "No models available. " & getProviderLoginHelp(docsPath)

proc formatNoModelSelectedMessage*(docsPath: string): string =
  "No model selected.\n\n" & getProviderLoginHelp(docsPath) &
    "\n\nThen use /model to select a model."

proc formatNoApiKeyFoundMessage*(provider: string, docsPath: string): string =
  ## unknown provider 显示 "the selected model"。
  let providerDisplay = if provider == unknownProvider: "the selected model" else: provider
  "No API key found for " & providerDisplay & ".\n\n" & getProviderLoginHelp(docsPath)