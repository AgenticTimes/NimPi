# Outcome

对齐 pi-coding-agent 的 `core/tools/edit-diff.ts` 核心编辑语义：新增 `src/editdiff.nim`，实现模糊匹配编辑（`fuzzyFindText`：精确优先 → 模糊回退）、Unicode 模糊规范化（`normalizeForFuzzyMatch`：行尾 trim + 智能引号/破折号/特殊空格归一）、批量编辑应用（`applyEditsToNormalizedContent`：空 oldText / not found / duplicate / overlap / no change 五类错误语义 + 逆序应用）、行尾处理（detectLineEnding / normalizeToLF / restoreLineEndings）；并接入 `src/agent.nim` 的 edit 工具，替换简化版 find→replace。

# Scope

- 新增 `src/editdiff.nim`（对齐 pi `edit-diff.ts` 的纯逻辑：normalize/fuzzyFind/countOccurrences/applyEdits/错误消息）
- 错误消息精确对齐 pi 文本（单编辑与多编辑变体）
- 行尾检测与 LF 归一/恢复
- 接入 `src/agent.nim` 的 edit 工具：fuzzy 匹配 + 完整错误语义
- `tests/test_core.nim` 追加对应测试（14-18 个）

# Non-goals

- 不实现 unified patch 生成（generateUnifiedPatch/generateDiffString 依赖 jsdiff 库，npi 无对应依赖，且 npi 编辑无需展示 patch）
- 不实现 NFKC 完整 Unicode 规范化（仅实现 pi 用到的字符替换集：智能引号/破折号/特殊空格）
- 不实现 BOM 处理（stripBom 属读取层，npi read 工具已内联处理）
- 不实现 applyReplacementsPreservingUnchangedLines 的行级叠加（npi 编辑直接在模糊空间应用，见 D4）

# Acceptance examples

- 精确匹配：content 含 oldText → found，usedFuzzyMatch=false，index 精确
- 模糊匹配：oldText 带行尾空格差异 → found，usedFuzzyMatch=true
- 智能引号：oldText 用 U+201C/U+201D，content 用 ASCII 引号 → 模糊命中
- 无匹配 → found=false
- 单编辑 applyEdits：oldText 不存在 → 抛 "Could not find the exact text in <path>..."
- oldText 出现 2 次 → 抛 "Found 2 occurrences of the text in <path>..."
- oldText 为空 → 抛 "oldText must not be empty in <path>."
- 替换结果与原文相同 → 抛 "No changes made to <path>..."
- 两编辑重叠 → 抛 overlap 错误
- CRLF 内容：oldText 用 LF → normalize 后命中，结果行尾保持 CRLF

# Constraints and invariants

- `normalizeForFuzzyMatch` 字符替换集与 pi 完全一致：行尾 trim → 智能单引号(2018/2019/201A/201B)→'、智能双引号(201C/201D/201E/201F)→"、破折号(2010-2015/2212)→-、特殊空格(00A0/2002-200A/202F/205F/3000)→空格
- `fuzzyFindText` 返回 contentForReplacement：精确 → 原文；模糊 → 规范化文本
- `applyEditsToNormalizedContent` 错误优先级：空 oldText 先行 → not found → duplicate → overlap → no change
- 逆序应用保持偏移稳定（对齐 pi matchedEdits 按 index 排序后逆序）
- 错误消息文本逐字对齐 pi（含单编辑/多编辑变体）
- 不修改既有 209 测试；新增测试全部通过

# Decisions

- D1: 新增单文件 `src/editdiff.nim`（量级同 systemprompt.nim）
- D2: NFKC 仅实现 pi 字符替换集（非目标注明），U+00A0 等按序替换
- D3: `applyEdits` 支持单编辑与多编辑（seq[Edit]），错误消息按 totalEdits 分变体
- D4: 模糊匹配时直接在规范化空间应用替换并返回规范化结果（简化：不做行级叠加回原文；与 pi 的差异仅影响模糊编辑时未改动行的行尾字节，见 known_limits）
- D5: 接入 edit 工具：oldText/newText 参数 → normalizeToLF → applyEditsToNormalizedContent → 结果写入；错误转为工具错误消息
- D6: 行尾检测用于结果写入：内容以 CRLF 为主时恢复 CRLF

# Open questions

- [blocking] CONFIRM: 请确认以下共享理解——(1) 新增 src/editdiff.nim 对齐 pi edit-diff.ts 编辑语义（normalizeForFuzzyMatch 字符集、fuzzyFindText 精确→模糊、applyEdits 五类错误、行尾处理）；(2) 接入 edit 工具替换简化 find→replace，错误消息对齐 pi 文本；(3) 非目标：unified patch（jsdiff 依赖）、NFKC 完整规范、BOM、行级叠加；(4) 模糊编辑时结果在规范化空间返回（行尾字节差异见 known_limits）；(5) 验收 A1-A6 见 spec。

# Verification expectations

- `nimble test` 全绿（含新增 editdiff 测试，约 15 个）
- 编译零 Error
- 手动验证：edit 工具模糊匹配命中、错误消息正确（不存在的文本/重复文本）
