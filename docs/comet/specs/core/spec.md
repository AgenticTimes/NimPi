# NPI FinalIntegrate — Specification

## 目标
把 attribution/configvalue/timings/diagnostics 接入实际路径，消除 0-ref 孤岛。

## 范围
- `llm.nim`：`ClientOptions` 增加 `attributionEnabled`/`extraHeaders`；请求头合并 attribution 归属 header（provider/baseUrl 判定）
- `npi.nim` main：NPI_TIMING 启用时 reset/time 标记关键阶段
- `skills.nim`：诊断类型改为 ResourceDiagnostic（可选，最小）
- exec 保持独立模块（bashtimeout 已覆盖 bash 工具）

## 非目标
- 大重构 —— 最小接入

## 验收
- [ ] llm 请求头含 attribution header
- [ ] main 计时接入
- [ ] skills 诊断类型化
- [ ] 现有单测全绿
- [ ] 集成单测
