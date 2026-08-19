# Outcome

对齐 pi-coding-agent 的 `core/system-prompt.ts`：新增 `src/systemprompt.nim`，实现系统提示词组装逻辑（`buildSystemPrompt`）——工具可见性过滤、guidelines 去重、prompt guidelines 注入、context 文件注入（`<project_context>`）、skills 注入、custom prompt 分支、当前工作目录标注；并接入 `src/npi.nim` 的 `systemPrompt`，替代硬编码字符串。

# Scope

- 新增 `src/systemprompt.nim`（对齐 pi `system-prompt.ts` 的纯字符串组装逻辑）
- 核心 API：`buildSystemPrompt(options)`，options 含 customPrompt/selectedTools/toolSnippets/promptGuidelines/appendSystemPrompt/cwd/contextFiles/skills
- 分支语义：customPrompt 提供时用自定义提示 + append + context + skills（有 read 工具时）+ cwd；否则用默认模板 + 工具列表 + guidelines 组装
- guidelines 去重（Set 语义）、promptGuidelines trim 后注入
- 接入 `src/npi.nim`：`systemPrompt` 改用 `buildSystemPrompt`（cwd + 当前工具列表 + skills）
- `tests/test_core.nim` 追加对应测试（8-12 个）

# Non-goals

- 不实现 pi 文档路径解析（getDocsPath/getExamplesPath/getReadmePath 是 pi 内部路径，npi 无对应）
- 不实现 pi 的完整默认提示文案（npi 保留自己的系统提示正文，仅对齐组装结构与分支逻辑）
- 不实现 toolSnippets 的完整外部注入（npi 工具行内建）
- 不改动 skills 注入格式（复用既有 formatSkillsForPrompt）

# Acceptance examples

- 无 customPrompt + 默认工具 → 输出含 "Available tools:"、全部工具行、guidelines 含 "Be concise in your responses"
- customPrompt 提供 → 输出以 customPrompt 开头，含 appendSection、context、cwd
- selectedTools 只含 bash → guidelines 含 "Use bash for file operations like ls, rg, find"（仅当无 grep/find/ls）
- promptGuidelines 重复项 → 去重只出现一次
- contextFiles 非空 → 输出含 `<project_context>` 与 `<project_instructions path="...">`
- skills 非空且有 read 工具 → 输出含 skills XML
- appendSystemPrompt 非空 → 附加在默认提示之后
- cwd 含反斜杠 → 替换为 "/"（Windows 路径归一）

# Constraints and invariants

- guidelines 顺序：工具组合判定（bash 且无 grep/find/ls 时）→ promptGuidelines → 固定项（Be concise / Show file paths clearly）
- 去重用 Set 语义（对齐 pi addGuideline + guidelinesSet）
- toolsList 仅列出有 toolSnippets 的可见工具；npi 侧内置 snippets
- 组装顺序（默认分支）：头部 + Available tools + Guidelines + 文档说明（npi 版）+ append + context + skills + cwd
- customPrompt 分支：customPrompt + append + context + skills（仅 hasRead）+ cwd
- 不修改既有 198 测试；新增测试全部通过

# Decisions

- D1: 新增单文件 `src/systemprompt.nim`（量级同 outputaccumulator.nim）
- D2: options 用 object 而非具名参数（对齐 pi options 对象语义，便于测试构造）
- D3: npi 默认工具集为 read/write/edit/bash/ls/grep/find，snippets 用 npi 现有工具描述行
- D4: 默认提示正文保留 npi 现有文本（"You are npi, a coding agent..."），仅对齐组装结构与分支
- D5: 文档说明段用 npi 简版（省略 pi 专属文档路径行，保留结构与占位）

# Open questions

- [blocking] CONFIRM: 请确认以下共享理解——(1) 新增 src/systemprompt.nim 对齐 pi system-prompt.ts 的 buildSystemPrompt 组装逻辑（customPrompt/默认双分支、工具可见性、guidelines 去重、context/skills/append/cwd 注入顺序）；(2) npi 默认提示正文保留现有文本，仅替换组装结构；(3) pi 文档路径段不实现（npi 无对应路径）；(4) 接入 npi.nim systemPrompt 与既有 skills 注入；(5) 验收 A1-A5 见 spec。

# Verification expectations

- `nimble test` 全绿（含新增 systemprompt 测试，约 10 个）
- 编译零 Error
- 手动验证：npi 启动 system prompt 含工具列表 + skills（信任门禁后），结构正确
