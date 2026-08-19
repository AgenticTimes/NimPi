# NPI Timings — Specification

## 目标
为 npi 实现启动/阶段性能计时（对齐 pi timings.ts）：环境变量开关、分段间隔计时、分组输出。

## 范围
- `src/timings.nim`：
  - `TimingNamespace`：timings 列表 + lastTime
  - `resetTimings(namespace)`、`time(label, namespace)` 间隔计时、`printTimings()`
  - 开关：NPI_TIMING=1（对齐 pi PI_TIMING）
  - 未启用时全部 no-op
- 接入：main 里 reset/time 标记关键阶段（可选）

## 非目标
- 完整 profiling —— 简单间隔计时

## 验收
- [ ] 未启用时 no-op
- [ ] reset 初始化
- [ ] time 记录间隔
- [ ] print 分组输出
- [ ] 单测覆盖
