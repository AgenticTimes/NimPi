## 来源信息：对齐 pi `source-info.ts`。
## SourceInfo 数据 + 工厂函数（source/scope/origin/baseDir）。

type
  SourceScope* = enum
    scopeUser = "user", scopeProject = "project", scopeTemporary = "temporary"

  SourceOrigin* = enum
    originPackage = "package", originTopLevel = "top-level"

  SourceInfo* = object
    path*: string
    source*: string
    scope*: SourceScope
    origin*: SourceOrigin
    baseDir*: string

proc createSourceInfo*(path, source: string, scope: SourceScope,
                       origin: SourceOrigin, baseDir = ""): SourceInfo =
  ## 完整构造 SourceInfo（对齐 createSourceInfo）。
  SourceInfo(path: path, source: source, scope: scope,
             origin: origin, baseDir: baseDir)

proc createSyntheticSourceInfo*(path, source: string, scope = scopeTemporary,
                                origin = originTopLevel, baseDir = ""): SourceInfo =
  ## 合成 SourceInfo（对齐 createSyntheticSourceInfo：默认 temporary/top-level）。
  SourceInfo(path: path, source: source, scope: scope,
             origin: origin, baseDir: baseDir)