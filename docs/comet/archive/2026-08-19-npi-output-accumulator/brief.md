# Outcome

对齐 pi-coding-agent 的 `core/tools/output-accumulator.ts`：新增 `src/outputaccumulator.nim`，实现流式输出累积器（`OutputAccumulator`）——有界内存 tail 快照、行/字节统计、UTF-8 流式解码边界处理、超限时全文保存到临时文件，并接入 npi 工具执行流程（bash 工具输出走 accumulator，超限时返回全文路径）。

# Scope

- 新增 `src/outputaccumulator.nim`（对齐 pi `output-accumulator.ts` 的纯逻辑 + 轻量临时文件 IO）
- 核心 API：`newOutputAccumulator` / `append` / `finish` / `snapshot` / `getLastLineBytes` / `closeTempFile`
- UTF-8 多字节字符跨 chunk 边界的流式解码（对齐 pi TextDecoder stream 语义，Nim 端用字节级判定）
- 临时文件：仅当输出超限（行/字节）时创建，`/tmp/npi-output-<hex>.log`，格式对齐 pi（prefix-id.log）
- 接入 `src/agent.nim` 的 bash 工具分支：输出经 accumulator 处理，超限时工具结果附全文路径提示
- `tests/test_core.nim` 追加对应测试（临时目录/随机前缀，不污染真实 /tmp 长时文件）

# Non-goals

- 不实现 Node Buffer/WriteStream 异步流（Nim 用同步文件 API，语义等价）
- 不实现 TextDecoder 的 BOM 处理等完整解码器行为（Nim string 已是 UTF-8，仅需跨 chunk 边界恢复）
- 不改变既有 bash 截断显示语义（tail 内容与 truncateTail 一致），仅新增超限时全文保存
- 不接入非 bash 工具（read/grep/find 输出均为内存级，无累积价值）

# Acceptance examples

- 追加 3 个 chunk（"ab"、"c"、"def"）→ finish → snapshot.content == "abcdef"，totalLines == 1（无换行 → hasOpenLine=true，对齐 pi），truncated == false
- 追加 1 行超过 maxBytes 的内容 → snapshot.truncated == true，truncatedBy == "bytes"
- 追加 5 行但 maxLines=2 → snapshot.content 只含最后 2 行，truncatedBy == "lines"
- 追加含多字节字符（如中文/emoji）且字符恰被拆在两个 chunk 边界 → 解码后内容正确
- 超限 + persistIfTruncated=true → fullOutputPath 存在且包含完整输出
- 追加到已 finish 的 accumulator → 抛错

# Constraints and invariants

- `append` 在 finished 后调用必须抛错（对齐 pi "Cannot append to a finished output accumulator"）
- tail 内存有界：tailBytes 超过 maxRollingBytes*2（即 maxBytes*4）时裁剪，裁剪点避免切分 UTF-8 字符
- `snapshot` 的 truncation 字段与 npi `truncate.nim` 的 `TruncationResult` 字段一一对应（复用 truncateTail）
- 行统计语义对齐 pi：completedLines + hasOpenLine；`getLastLineBytes` 返回当前未完成行字节数
- 临时文件仅在超限或显式 persistIfTruncated 时创建；未超限时 fullOutputPath 为 none
- 不修改既有 186 测试；新增测试全部通过

# Decisions

- D1: 新增单文件 `src/outputaccumulator.nim`（量级同 trust.nim）
- D2: UTF-8 跨 chunk 边界用"保存尾部未完成序列字节 + 恢复解码"实现，Nim 字节判定（0xC0/0x80 掩码）对齐 pi trimTail
- D3: 临时文件路径 `getTempDir() / (prefix & "-" & randomHex & ".log")`，randomHex 用 std/random 生成 8 字节 hex
- D4: 接入点选 bash 工具：`execBashWithTimeout` 输出 → accumulator（append + finish + snapshot(persistIfTruncated=true)），截断语义不变，超限时结果尾部附 `[full output: <path>]`
- D5: maxLines/maxBytes 默认对齐 pi：`DEFAULT_MAX_LINES=2000`、`DEFAULT_MAX_BYTES=50*1024`；可经 options 覆盖（bash 工具用默认值）

# Open questions

- [blocking] CONFIRM: 请确认以下共享理解——(1) 新增 src/outputaccumulator.nim 对齐 pi output-accumulator.ts（append/finish/snapshot/getLastLineBytes/closeTempFile + UTF-8 流边界 + 超限临时文件）；(2) 接入 bash 工具：输出经 accumulator，超限时工具结果附全文路径 `[full output: /tmp/npi-output-<hex>.log]`，tail 显示语义不变；(3) 未超限时无临时文件、无路径提示；(4) 非 bash 工具不接入；(5) 验收 A1-A6 见 spec。

# Verification expectations

- `nimble test` 全绿（含新增 outputaccumulator 测试，约 12-15 个）
- 编译零 Error
- 手动验证：长输出 bash 工具（如 `seq 1 10000`）结果含全文路径提示；短输出无提示
