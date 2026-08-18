# NPI EventBus — Specification

## 目标
为 npi 实现轻量事件总线（对齐 pi event-bus.ts）：通道发布/订阅、handler 错误隔离、清空。

## 范围
- `src/eventbus.nim`：
  - `EventBus`：`on(channel, handler)` 返回取消函数、`emit(channel, data)`、`clear()`
  - handler 异常隔离（emit 不因单个 handler 崩溃中断）
  - 数据用 string（简单 payload）或 JsonNode
- 接入：agent 循环工具调用时 emit（可选）

## 非目标
- 异步 handler —— 同步即可
- 多进程总线 —— 进程内

## 验收
- [ ] on/emit 通道订阅发布
- [ ] 返回取消函数可取消订阅
- [ ] handler 异常不中断其它 handler
- [ ] clear 清空所有
- [ ] 单测覆盖
