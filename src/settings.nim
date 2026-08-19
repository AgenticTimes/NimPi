## Settings：对齐 pi `settings-manager.ts` 的 Settings 结构（精简版）。
## 核心配置结构 + 默认值 + deepMerge（逐字段递归合并）。

type
  SettingsCompaction* = object
    enabled*: bool            ## 默认 true
    reserveTokens*: int       ## 默认 16384
    keepRecentTokens*: int    ## 默认 20000

  BranchSummarySettings* = object
    reserveTokens*: int       ## 默认 16384
    skipPrompt*: bool

  ProviderRetrySettings* = object
    timeoutMs*: int
    maxRetries*: int
    maxRetryDelayMs*: int

  RetrySettings* = object
    enabled*: bool            ## 默认 true
    maxRetries*: int          ## 默认 3
    baseDelayMs*: int         ## 默认 2000
    provider*: ProviderRetrySettings

  TerminalSettings* = object
    showImages*: bool         ## 默认 true
    imageWidthCells*: int     ## 默认 60
    clearOnShrink*: bool
    showTerminalProgress*: bool

  MarkdownSettings* = object
    codeBlockIndent*: string  ## 默认 "  "
    mermaid*: string          ## off|final|streaming，默认 streaming

  WarningSettings* = object
    anthropicExtraUsage*: bool

  Settings* = object
    defaultProvider*: string
    defaultModel*: string
    compaction*: SettingsCompaction
    branchSummary*: BranchSummarySettings
    retry*: RetrySettings
    terminal*: TerminalSettings
    markdown*: MarkdownSettings
    warnings*: WarningSettings
    showCacheMissNotices*: bool
    quietStartup*: bool
    enableInstallTelemetry*: bool

proc defaultCompaction*(): SettingsCompaction =
  SettingsCompaction(enabled: true, reserveTokens: 16384, keepRecentTokens: 20000)

proc defaultRetrySettings*(): RetrySettings =
  RetrySettings(enabled: true, maxRetries: 3, baseDelayMs: 2000)

proc defaultTerminalSettings*(): TerminalSettings =
  TerminalSettings(showImages: true, imageWidthCells: 60)

proc defaultMarkdownSettings*(): MarkdownSettings =
  MarkdownSettings(codeBlockIndent: "  ", mermaid: "streaming")

proc defaultSettings*(): Settings =
  Settings(compaction: defaultCompaction(),
           branchSummary: BranchSummarySettings(reserveTokens: 16384),
           retry: defaultRetrySettings(),
           terminal: defaultTerminalSettings(),
           markdown: defaultMarkdownSettings(),
           warnings: WarningSettings(anthropicExtraUsage: true),
           enableInstallTelemetry: true)

proc mergeSettings*(base: Settings, overrides: Settings): Settings =
  ## 合并设置：overrides 非零字段覆盖 base（对齐 pi deepMergeSettings）。
  result = base
  if overrides.defaultProvider.len > 0: result.defaultProvider = overrides.defaultProvider
  if overrides.defaultModel.len > 0: result.defaultModel = overrides.defaultModel
  # compaction 嵌套合并
  let co = overrides.compaction
  if co.enabled != base.compaction.enabled: result.compaction.enabled = co.enabled
  if co.reserveTokens != 0: result.compaction.reserveTokens = co.reserveTokens
  if co.keepRecentTokens != 0: result.compaction.keepRecentTokens = co.keepRecentTokens
  # retry 嵌套合并
  let ro = overrides.retry
  if ro.enabled != base.retry.enabled: result.retry.enabled = ro.enabled
  if ro.maxRetries != 0: result.retry.maxRetries = ro.maxRetries
  if ro.baseDelayMs != 0: result.retry.baseDelayMs = ro.baseDelayMs
  if ro.provider.timeoutMs != 0: result.retry.provider.timeoutMs = ro.provider.timeoutMs
  # 布尔覆盖（用显式 has 判断：true 或 false 都覆盖）
  if overrides.showCacheMissNotices: result.showCacheMissNotices = true
  if overrides.quietStartup: result.quietStartup = true
  if not overrides.enableInstallTelemetry and overrides.enableInstallTelemetry != base.enableInstallTelemetry:
    result.enableInstallTelemetry = false