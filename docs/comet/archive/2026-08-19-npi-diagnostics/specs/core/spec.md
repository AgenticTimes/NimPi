# NPI Diagnostics — Specification

## 目标
为 npi 实现资源诊断类型（对齐 pi diagnostics.ts）：ResourceCollision + ResourceDiagnostic。

## 范围
- `src/diagnostics.nim`：
  - `ResourceCollision`：resourceType/name/winnerPath/loserPath/winnerSource/loserSource
  - `ResourceDiagnostic`：type(warning/error/collision)/message/path/collision
  - 构造辅助：warning/error/collision
- 接入 skills.nim（可选）：诊断输出类型化

## 非目标
- 诊断收集器 —— 仅类型

## 验收
- [ ] ResourceCollision 字段
- [ ] ResourceDiagnostic warning/error/collision
- [ ] 构造辅助函数
- [ ] 单测覆盖
