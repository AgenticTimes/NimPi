## 模糊匹配编辑：对齐 pi `core/tools/edit-diff.ts` 核心编辑语义。
## normalizeForFuzzyMatch 字符集 / fuzzyFindText 精确→模糊 / applyEdits 五类错误 / 行尾处理。

import std/[strutils, algorithm]

type
  Edit* = object
    oldText*: string
    newText*: string

  FuzzyMatchResult* = object
    found*: bool
    index*: int                 ## 精确：原文偏移；模糊：规范化文本偏移
    matchLength*: int
    usedFuzzyMatch*: bool
    contentForReplacement*: string

  AppliedEditsResult* = object
    baseContent*: string
    newContent*: string

  LineEnding* = enum
    leCrLf, leLf

  MatchedEdit = object
    editIndex: int
    matchIndex: int
    matchLength: int
    newText: string

proc detectLineEnding*(content: string): LineEnding =
  ## 内容含 "\r\n" → leCrLf，否则 leLf。
  if "\r\n" in content: leCrLf else: leLf

proc normalizeToLF*(text: string): string =
  ## 把 "\r\n" 替换为 "\n"。
  result = text.replace("\r\n", "\n")

proc restoreLineEndings*(text: string, ending: LineEnding): string =
  ## leCrLf 时把 "\n" 替换为 "\r\n"，leLf 原样。
  if ending == leCrLf:
    result = text.replace("\n", "\r\n")
  else:
    result = text

proc trimEnd(s: string): string =
  ## 行尾空白 trim。
  var i = s.len
  while i > 0 and s[i-1].isSpaceAscii:
    dec i
  if i == s.len: s else: s[0 ..< i]

proc normalizeForFuzzyMatch*(text: string): string =
  ## 对齐 pi 字符替换集：行尾 trim → 智能引号 → 破折号 → 特殊空格。
  # 1. 行尾 trim
  var lines: seq[string] = @[]
  for line in text.split("\n"):
    lines.add trimEnd(line)
  result = lines.join("\n")
  # 2. 智能单引号 → '
  result = result.replace("\u2018", "'").replace("\u2019", "'")
    .replace("\u201A", "'").replace("\u201B", "'")
  # 3. 智能双引号 → "
  result = result.replace("\u201C", "\"").replace("\u201D", "\"")
    .replace("\u201E", "\"").replace("\u201F", "\"")
  # 4. 破折号 → -
  result = result.replace("\u2010", "-").replace("\u2011", "-")
    .replace("\u2012", "-").replace("\u2013", "-")
    .replace("\u2014", "-").replace("\u2015", "-")
    .replace("\u2212", "-")
  # 5. 特殊空格 → 空格
  result = result.replace("\u00A0", " ").replace("\u2002", " ")
    .replace("\u2003", " ").replace("\u2004", " ")
    .replace("\u2005", " ").replace("\u2006", " ")
    .replace("\u2007", " ").replace("\u2008", " ")
    .replace("\u2009", " ").replace("\u200A", " ")
    .replace("\u202F", " ").replace("\u205F", " ")
    .replace("\u3000", " ")

proc fuzzyFindText*(content: string, oldText: string): FuzzyMatchResult =
  ## 精确优先 → 模糊回退（对齐 pi fuzzyFindText）。
  let exactIndex = content.find(oldText)
  if exactIndex >= 0:
    return FuzzyMatchResult(found: true, index: exactIndex,
      matchLength: oldText.len, usedFuzzyMatch: false,
      contentForReplacement: content)
  let fuzzyContent = normalizeForFuzzyMatch(content)
  let fuzzyOldText = normalizeForFuzzyMatch(oldText)
  let fuzzyIndex = fuzzyContent.find(fuzzyOldText)
  if fuzzyIndex < 0:
    return FuzzyMatchResult(found: false, index: -1, matchLength: 0,
      usedFuzzyMatch: false, contentForReplacement: content)
  FuzzyMatchResult(found: true, index: fuzzyIndex,
    matchLength: fuzzyOldText.len, usedFuzzyMatch: true,
    contentForReplacement: fuzzyContent)

proc countOccurrences*(content: string, oldText: string): int =
  ## 规范化空间的出现次数（对齐 pi countOccurrences）。
  let fuzzyContent = normalizeForFuzzyMatch(content)
  let fuzzyOldText = normalizeForFuzzyMatch(oldText)
  result = fuzzyContent.split(fuzzyOldText).len - 1

proc emptyOldTextError*(path: string, editIndex: int, totalEdits: int): string =
  if totalEdits == 1:
    "oldText must not be empty in " & path & "."
  else:
    "edits[" & $editIndex & "].oldText must not be empty in " & path & "."

proc notFoundError*(path: string, editIndex: int, totalEdits: int): string =
  if totalEdits == 1:
    "Could not find the exact text in " & path &
      ". The old text must match exactly including all whitespace and newlines."
  else:
    "Could not find edits[" & $editIndex & "] in " & path &
      ". The oldText must match exactly including all whitespace and newlines."

proc duplicateError*(path: string, editIndex: int, totalEdits: int, occurrences: int): string =
  if totalEdits == 1:
    "Found " & $occurrences & " occurrences of the text in " & path &
      ". The text must be unique. Please provide more context to make it unique."
  else:
    "Found " & $occurrences & " occurrences of edits[" & $editIndex & "] in " & path &
      ". Each oldText must be unique. Please provide more context to make it unique."

proc noChangeError*(path: string, totalEdits: int): string =
  if totalEdits == 1:
    "No changes made to " & path &
      ". The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
  else:
    "No changes made to " & path & ". The replacements produced identical content."

proc overlapError*(path: string, prev: int, curr: int): string =
  "edits[" & $prev & "] and edits[" & $curr & "] overlap in " & path &
    ". Merge them into one edit or target disjoint regions."

proc applyEditsToNormalizedContent*(normalizedContent: string, edits: seq[Edit], path: string): AppliedEditsResult =
  ## 批量编辑应用（对齐 pi applyEditsToNormalizedContent）：
  ## 空 oldText → not found → duplicate → overlap → no change，逆序应用保持偏移稳定。
  # 1. normalizedEdits
  var normalizedEdits: seq[Edit] = @[]
  for e in edits:
    normalizedEdits.add Edit(oldText: normalizeToLF(e.oldText), newText: normalizeToLF(e.newText))
  # 2. 空 oldText 先行校验
  for i in 0 ..< normalizedEdits.len:
    if normalizedEdits[i].oldText.len == 0:
      raise newException(ValueError, emptyOldTextError(path, i, normalizedEdits.len))
  # 3. 初始匹配判定是否用模糊空间
  var usedFuzzyMatch = false
  for i in 0 ..< normalizedEdits.len:
    let m = fuzzyFindText(normalizedContent, normalizedEdits[i].oldText)
    if m.usedFuzzyMatch:
      usedFuzzyMatch = true
      break
  let replacementBase =
    if usedFuzzyMatch: normalizeForFuzzyMatch(normalizedContent)
    else: normalizedContent
  # 4. 逐 edit 匹配 + 唯一性
  var matched: seq[MatchedEdit] = @[]
  for i in 0 ..< normalizedEdits.len:
    let m = fuzzyFindText(replacementBase, normalizedEdits[i].oldText)
    if not m.found:
      raise newException(ValueError, notFoundError(path, i, normalizedEdits.len))
    let occ = countOccurrences(replacementBase, normalizedEdits[i].oldText)
    if occ > 1:
      raise newException(ValueError, duplicateError(path, i, normalizedEdits.len, occ))
    matched.add MatchedEdit(editIndex: i, matchIndex: m.index,
      matchLength: m.matchLength, newText: normalizedEdits[i].newText)
  # 5. 按 matchIndex 升序排序 + 重叠检测
  matched.sort(proc(a, b: MatchedEdit): int = cmp(a.matchIndex, b.matchIndex))
  for i in 1 ..< matched.len:
    let prev = matched[i-1]
    let curr = matched[i]
    if prev.matchIndex + prev.matchLength > curr.matchIndex:
      raise newException(ValueError, overlapError(path, prev.editIndex, curr.editIndex))
  # 6. 逆序应用（偏移稳定）
  var buf = replacementBase
  for i in countdown(matched.len - 1, 0):
    let m = matched[i]
    buf = buf[0 ..< m.matchIndex] & m.newText &
      buf[m.matchIndex + m.matchLength .. ^1]
  # 7. no change 检测
  if replacementBase == buf:
    raise newException(ValueError, noChangeError(path, normalizedEdits.len))
  result = AppliedEditsResult(baseContent: normalizedContent, newContent: buf)
