# NPI Exec — Specification

## 目标
为 npi 实现 execCommand（对齐 pi exec.ts）：执行命令返回分离的 stdout/stderr/code/killed，支持 timeout。

## 范围
- `src/exec.nim`：
  - `ExecOptions`：timeout、cwd
  - `ExecResult`：stdout、stderr、code、killed
  - `execCommand(command, args, cwd, opts)`：startProcess + 收集 stdout/stderr（分离管道）+ 超时终止（SIGTERM→5s 后 SIGKILL）
- 与 bashtimeout 区分：本模块返回分离流，bashtimeout 合并输出

## 非目标
- AbortSignal —— 仅 timeout
- 合并输出 —— bashtimeout 已有

## 验收
- [ ] stdout/stderr 分离
- [ ] code 返回
- [ ] 超时终止 + killed 标记
- [ ] SIGTERM 后 SIGKILL 升级
- [ ] 单测覆盖
