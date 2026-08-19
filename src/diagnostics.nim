## 资源诊断：对齐 pi `diagnostics.ts`。
## ResourceCollision + ResourceDiagnostic 类型 + 构造辅助。

import std/strutils

type
  ResourceType* = enum
    rtExtension, rtSkill, rtPrompt, rtTheme

  ResourceCollision* = object
    resourceType*: ResourceType
    name*: string
    winnerPath*: string
    loserPath*: string
    winnerSource*: string
    loserSource*: string

  DiagnosticKind* = enum
    dkWarning, dkError, dkCollision

  ResourceDiagnostic* = object
    kind*: DiagnosticKind
    message*: string
    path*: string
    collision*: ResourceCollision

proc resourceTypeName*(t: ResourceType): string =
  case t
  of rtExtension: "extension"
  of rtSkill: "skill"
  of rtPrompt: "prompt"
  of rtTheme: "theme"

proc warning*(message: string, path: string = ""): ResourceDiagnostic =
  ResourceDiagnostic(kind: dkWarning, message: message, path: path)

proc error*(message: string, path: string = ""): ResourceDiagnostic =
  ResourceDiagnostic(kind: dkError, message: message, path: path)

proc makeCollision*(c: ResourceCollision): ResourceDiagnostic =
  ResourceDiagnostic(kind: dkCollision,
    message: "资源冲突: " & resourceTypeName(c.resourceType) & " '" & c.name &
             "' 由 " & c.winnerPath & " 胜出（冲突方: " & c.loserPath & "）",
    collision: c)

proc describe*(d: ResourceDiagnostic): string =
  ## 人类可读描述。
  case d.kind
  of dkWarning: "⚠ " & d.message
  of dkError: "✗ " & d.message
  of dkCollision: "⚡ " & d.message