# 完整目标规格：npi edit diff

对齐 pi-coding-agent 的 `core/tools/edit-diff.ts` 核心编辑语义。归档后 `src/editdiff.nim` 的完整行为如下。

## 类型

```nim
type
  Edit* = object
    oldText*: string
    newText*: string

  FuzzyMatchResult* = object
    found*: bool
    index*: int               ## 匹配起点（精确：原文偏移；模糊：规范化文本偏移）
    matchLength*: int
    usedFuzzyMatch*: bool
    contentForReplacement*: string  ## 精确：原文；模糊：规范化文本

  AppliedEditsResult* = object
    baseContent*: string
    newContent*: string

  LineEnding* = enum
    leCrLf, leLf
```

## 行尾处理

- `detectLineEnding*(content: string): LineEnding` — 内容含 "\r\n" 返回 leCrLf，否则 leLf
- `normalizeToLF*(text: string): string` — 把 "\r\n" 替换为 "\n"
- `restoreLineEndings*(text: string, ending: LineEnding): string` — leCrLf 时把 "\n" 替换为 "\r\n"，leLf 原样

## normalizeForFuzzyMatch

对齐 pi 的字符替换集（顺序）：
1. 每行行尾 trim（`\n` 分行，每行 trimEnd）
2. 智能单引号 U+2018 U+2019 U+201A U+201B → `'`
3. 智能双引号 U+201C U+201D U+201E U+201F → `"`
4. 破折号 U+2010 U+2011 U+2012 U+2013 U+2014 U+2015 U+2212 → `-`
5. 特殊空格 U+00A0 U+2002 U+2003 U+2004 U+2005 U+2006 U+2007 U+2008 U+2009 U+200A U+202F U+205F U+3000 → ` `

Nim 实现：直接对 UTF-8 字节序列做替换（用 rune 迭代或字节模式替换）。替换在规范化文本上顺序执行，结果与 pi 一致。

## fuzzyFindText

输入：content, oldText。行为：
1. 精确匹配：content.indexOf(oldText) ≠ -1 → {found: true, index: 精确偏移, matchLength: oldText.len, usedFuzzyMatch: false, contentForReplacement: content}
2. 模糊匹配：fuzzyContent = normalizeForFuzzyMatch(content)，fuzzyOldText = normalizeForFuzzyMatch(oldText)；fuzzyContent.indexOf(fuzzyOldText) ≠ -1 → {found: true, index: 模糊偏移, matchLength: fuzzyOldText.len, usedFuzzyMatch: true, contentForReplacement: fuzzyContent}
3. 均无 → {found: false, index: -1, matchLength: 0, usedFuzzyMatch: false, contentForReplacement: content}

## countOccurrences

`normalizeForFuzzyMatch(content).split(normalizeForFuzzyMatch(oldText)).len - 1`。

## applyEditsToNormalizedContent

输入：normalizedContent（LF 已归一）, edits: seq[Edit], path: string。行为：

1. normalizedEdits = edits 每项 normalizeToLF
2. 逐项检查 oldText 为空 → 抛 getEmptyOldTextError(path, i, edits.len)
3. 对 normalizedContent 逐 edit 调 fuzzyFindText 求初始匹配；任一 usedFuzzyMatch → replacementBaseContent = normalizeForFuzzyMatch(normalizedContent)，否则 = normalizedContent
4. 对 replacementBaseContent 逐 edit：fuzzyFindText 不 found → 抛 getNotFoundError；countOccurrences > 1 → 抛 getDuplicateError
5. matchedEdits 按 matchIndex 升序排序；相邻项重叠（prev.index + prev.len > curr.index）→ 抛 overlap 错误
6. 在 replacementBaseContent 上按 matchIndex 逆序替换（保持偏移稳定）
7. baseContent == newContent → 抛 getNoChangeError
8. 返回 {baseContent: normalizedContent, newContent}

## 错误消息（逐字对齐 pi）

- 单编辑 not found: `Could not find the exact text in <path>. The old text must match exactly including all whitespace and newlines.`
- 多编辑 not found: `Could not find edits[<i>] in <path>. The oldText must match exactly including all whitespace and newlines.`
- 单编辑 duplicate: `Found <n> occurrences of the text in <path>. The text must be unique. Please provide more context to make it unique.`
- 多编辑 duplicate: `Found <n> occurrences of edits[<i>] in <path>. Each oldText must be unique. Please provide more context to make it unique.`
- 单编辑 empty: `oldText must not be empty in <path>.`
- 多编辑 empty: `edits[<i>].oldText must not be empty in <path>.`
- 单编辑 no change: `No changes made to <path>. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected.`
- 多编辑 no change: `No changes made to <path>. The replacements produced identical content.`
- overlap: `edits[<prev>] and edits[<curr>] overlap in <path>. Merge them into one edit or target disjoint regions.`

## 接入：agent.nim edit 工具

现有 `of "edit"` 分支（find oldText → 替换）替换为：

```nim
of "edit":
  let oldText = args{"oldText"}.getStr("")
  let newText = args{"newText"}.getStr("")
  if oldText.len == 0 or newText.len == 0:
    return ("", name, "error: edit requires oldText and newText", true)
  try:
    var content = readFile(path)
    let ending = detectLineEnding(content)
    let normalized = normalizeToLF(content)
    let res = applyEditsToNormalizedContent(normalized, @[Edit(oldText: oldText, newText: newText)], path)
    var out = res.newContent
    if ending == leCrLf:
      out = restoreLineEndings(out, leCrLf)
    writeFile(path, out)
    return ("", name, "edited " & path, false)
  except ValueError as e:
    return ("", name, "error: " & e.msg, true)
  except CatchableError as e:
    return ("", name, "error: " & e.msg, true)
```

错误消息直接透传（对齐 pi 文本）。readFile 的读取错误沿用现有分支的 except CatchableError 处理。

## 测试（tests/test_core.nim 追加）

- normalizeForFuzzyMatch：行尾 trim、智能引号、破折号、特殊空格逐一断言
- fuzzyFindText 精确：found/usedFuzzyMatch=false/index 正确
- fuzzyFindText 模糊（行尾空格差异）：found/usedFuzzyMatch=true
- fuzzyFindText 模糊（智能引号差异）：命中
- fuzzyFindText 无匹配：found=false
- countOccurrences：0/1/2 次
- applyEdits 单编辑成功：替换正确
- applyEdits 多编辑逆序：两处不重叠替换都生效
- 空 oldText → 抛错（消息对齐）
- not found → 抛错（消息对齐，单编辑变体）
- duplicate（2 次出现）→ 抛错（消息含 occurrences）
- overlap 两编辑 → 抛错
- no change（newText == oldText）→ 抛错
- CRLF：normalizeToLF/restoreLineEndings 往返
- 多编辑 not found → edits[1] 变体消息

## 非目标（明确不做）

- unified patch 生成（jsdiff 依赖）
- NFKC 完整规范化（仅字符替换集）
- BOM 处理
- applyReplacementsPreservingUnchangedLines 行级叠加（模糊编辑时结果在规范化空间返回，未改动行的行尾字节可能变化）
