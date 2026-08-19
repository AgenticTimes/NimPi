## 模糊匹配：对齐 pi `tui/fuzzy.ts`。
## fzf 风格——query 所有字符按序出现（不必连续），低分更优。

import std/[strutils, algorithm]

type
  FuzzyMatch* = object
    matches*: bool
    score*: float

proc isWordBoundary(text: string, i: int): bool =
  ## 词边界：行首或前一个字符是分隔符。
  i == 0 or text[i - 1] in {' ', '\t', '-', '_', '.', '/', ':'}

proc matchQuery(queryLower, textLower: string): FuzzyMatch =
  ## 核心评分：顺序子序列，连续奖励、间隙惩罚、词边界奖励、位置轻微惩罚。
  result = FuzzyMatch(matches: true, score: 0.0)
  if queryLower.len == 0:
    return
  if queryLower.len > textLower.len:
    return FuzzyMatch(matches: false, score: 0.0)
  var queryIndex = 0
  var score = 0.0
  var lastMatchIndex = -1
  var consecutiveMatches = 0
  for i in 0 ..< textLower.len:
    if queryIndex >= queryLower.len:
      break
    if textLower[i] == queryLower[queryIndex]:
      # 连续匹配奖励
      if lastMatchIndex == i - 1:
        consecutiveMatches += 1
        score -= float(consecutiveMatches * 5)
      else:
        consecutiveMatches = 0
        # 间隙惩罚
        if lastMatchIndex >= 0:
          score += float((i - lastMatchIndex - 1) * 2)
      # 词边界奖励
      if isWordBoundary(textLower, i):
        score -= 10
      # 靠后轻微惩罚
      score += float(i) * 0.1
      lastMatchIndex = i
      queryIndex += 1
  if queryIndex < queryLower.len:
    return FuzzyMatch(matches: false, score: 0.0)
  if queryLower == textLower:
    score -= 100
  result = FuzzyMatch(matches: true, score: score)

proc swappedVariant(queryLower: string): string =
  ## 字母数字交换变体："abc123" → "123abc"，反之亦然。
  var letters = ""
  var digits = ""
  for c in queryLower:
    if c in {'0' .. '9'}:
      digits.add c
    elif c in {'a' .. 'z'}:
      letters.add c
    else:
      return ""  # 只处理纯字母数字组合
  if letters.len > 0 and digits.len > 0 and letters.len + digits.len == queryLower.len:
    # 保留原顺序前缀逻辑：检测原始是 letters 在前还是 digits 在前
    let first = queryLower[0]
    if first in {'0' .. '9'}:
      return letters & digits
    else:
      return digits & letters
  ""

proc fuzzyMatch*(query, text: string): FuzzyMatch =
  ## 匹配 query 是否按序出现在 text 中；低分更优。
  let queryLower = query.toLowerAscii()
  let textLower = text.toLowerAscii()
  let primary = matchQuery(queryLower, textLower)
  if primary.matches:
    return primary
  let swapped = swappedVariant(queryLower)
  if swapped.len == 0:
    return primary
  let swappedMatch = matchQuery(swapped, textLower)
  if not swappedMatch.matches:
    return primary
  FuzzyMatch(matches: true, score: swappedMatch.score + 5)

proc fuzzyFilter*[T](items: openArray[T], query: string, getText: proc(x: T): string): seq[T] =
  ## 按模糊匹配质量过滤排序（最优在前）。空白/slash 分隔 token，全 token 匹配才保留。
  if query.strip().len == 0:
    for it in items:
      result.add it
    return
  var tokens: seq[string]
  for t in query.strip().split({' ', '\t', '/'}):
    if t.len > 0:
      tokens.add t
  if tokens.len == 0:
    for it in items:
      result.add it
    return
  var scored: seq[(float, T)]
  for item in items:
    let text = getText(item)
    var totalScore = 0.0
    var allMatch = true
    for token in tokens:
      let m = fuzzyMatch(token, text)
      if m.matches:
        totalScore += m.score
      else:
        allMatch = false
        break
    if allMatch:
      scored.add (totalScore, item)
  scored.sort(proc(a, b: (float, T)): int =
    cmp(a[0], b[0]))
  for (_, item) in scored:
    result.add item