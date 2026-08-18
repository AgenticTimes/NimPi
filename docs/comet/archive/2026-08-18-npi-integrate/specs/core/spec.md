# NPI Integrate — Specification

## 目标
把 pathutils/eventbus 两个已实现但未使用的模块接入实际路径，消除孤岛。

## 范围
- `read` 工具：用 `resolveReadPath` 解析路径（~ 展开/macOS 变体）
- `Agent`：增加 `eventBus` 字段；runTool 执行后 emit `tool:executed` 事件（channel 含工具名）
- npi.nim：创建 agent 时挂载 eventBus

## 非目标
- 事件消费者 —— 仅提供事件通知能力
- 其它工具路径解析 —— 后续

## 验收
- [ ] read 用 resolveReadPath（~ 可读）
- [ ] agent 执行工具 emit 事件
- [ ] eventBus 可订阅工具事件
- [ ] 现有单测仍全绿
- [ ] 集成单测覆盖
