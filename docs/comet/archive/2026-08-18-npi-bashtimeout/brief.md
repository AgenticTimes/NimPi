# NPI BashTimeout — Brief

为 npi 实现 bash 超时与进程树终止：startProcess + poll 轮询 + 超时 kill（含子进程），替换 execCmdEx 无超时实现。对齐 pi bash-executor 的 timeout 语义。
