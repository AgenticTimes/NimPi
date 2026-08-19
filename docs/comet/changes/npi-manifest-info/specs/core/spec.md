# NPI ManifestInfo — Specification

## 目标
对齐 pi-manifest（资源清单解析）与 source-info（来源信息数据），补齐 core 纯逻辑模块。

## 范围
- `src/manifest.nim`：
  - `PiManifest`（extensions/skills/prompts/themes）
  - `readPiManifest(packageJsonPath): Option[PiManifest]`：解析 package.json 的 `pi` 字段，非法返回 none
- `src/sourceinfo.nim`：
  - `SourceScope`（user/project/temporary）、`SourceOrigin`（package/top-level）
  - `SourceInfo`（path/source/scope/origin/baseDir）
  - `createSourceInfo(path, source, scope, origin, baseDir)`
  - `createSyntheticSourceInfo(path, source, scope=临时, origin=top-level)`

## 非目标
- package-manager（PathMetadata 来源）—— 边界，SourceInfo 字段直接传参
- 接入 skills/加载链路 —— 后续

## 验收
- [ ] readPiManifest 解析 pi 字段
- [ ] 无 pi 字段返回 none
- [ ] 非法 JSON 返回 none
- [ ] 非字符串数组忽略
- [ ] SourceInfo 默认值
- [ ] synthetic 默认 scope/origin
- [ ] 单测覆盖
