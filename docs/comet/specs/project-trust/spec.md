# 完整目标规格：npi project trust

对齐 pi-coding-agent 的 `core/project-trust.ts` 与 `core/trust-manager.ts`。归档后 `src/trust.nim` 的完整行为如下。

## 类型

```nim
type
  TrustDecision* = Option[bool]   ## nil = 无记录（未决策）
  TrustStoreEntry* = object
    path*: string
    decision*: bool
  TrustUpdate* = object
    path*: string
    decision*: Option[bool]       ## none 表示删除该路径条目
  TrustOption* = object
    label*: string
    trusted*: bool
    updates*: seq[TrustUpdate]
    savedPath*: string            ## 空 = 无持久化（session-only 选项）
  TrustFile* = Table[string, Option[bool]]  ## path -> true/false/nil
  ProjectTrustStore* = object
    trustPath*: string
  UiSelect* = proc(cwd: string, options: seq[TrustOption]): Option[TrustOption] {.closure.}
  ResolveTrustOptions* = object
    cwd*: string
    trustStore*: ProjectTrustStore
    trustOverride*: Option[bool]
    defaultTrust*: string         ## "ask" | "always" | "never"，默认 "ask"
    uiSelect*: Option[UiSelect]   ## none = 无 UI
```

## 资源常量

```nim
const TrustRequiringResources* = [
  "settings.json", "extensions", "skills", "prompts",
  "themes", "SYSTEM.md", "APPEND_SYSTEM.md",
]
```

## 纯逻辑函数

### findNearestTrustEntry

输入：TrustFile 数据、cwd。行为：从 cwd 规范化路径开始，沿目录向上逐级查找数据中的条目；遇到 `true`/`false` 立即返回该 `(path, decision)`；遇到 `nil` 继续向上；到达文件系统根仍未命中返回 nil。规范化使用 `expandFilename` 语义（解析符号链接与相对路径）。

### getProjectTrustParentPath

输入：cwd。行为：规范化后取 dirname；若父目录等于自身（文件系统根）返回空字符串，否则返回父路径。

### getProjectTrustOptions

输入：cwd，可选 includeSessionOnly。行为：固定顺序生成选项列表，label 与 pi 一致：

1. `Trust` — trusted=true，updates=[{path: cwd, decision: true}]，savedPath=cwd
2. `Trust parent folder (<parent>)` — 仅当存在父路径；trusted=true，updates=[{path: parent, decision: true}, {path: cwd, decision: nil}]，savedPath=parent
3. `Trust (this session only)` — 仅 includeSessionOnly；trusted=true，updates=[]（无持久化）
4. `Do not trust` — trusted=false，updates=[{path: cwd, decision: false}]，savedPath=cwd
5. `Do not trust (this session only)` — 仅 includeSessionOnly；trusted=false，updates=[]

### hasTrustRequiringProjectResources

输入：cwd。行为：返回 true 当且仅当 cwd 下存在需要信任门禁的项目资源，或 cwd 或其祖先存在 `.agents/skills`（用户级 `~/.agents/skills` 除外，它总是受信任并被跳过，即使 cwd 是 home）。

检测逻辑：

1. 规范化 cwd，用户 home 规范化。
2. 检查 `cwd/.npi/` 下是否含有资源常量列表中任一条目（存在即 true）。
3. 从 cwd 沿目录向上，检查每一级 `.agents/skills` 是否存在且不等于用户级 `~/.agents/skills`；命中即 true。
4. 到达根返回 false。

注意：npi 的配置目录名是 `.npi`（pi 是 `.pi`），通过常量 ConfigDirName = ".npi" 传入，函数不硬编码。

## 存储

### ProjectTrustStore

- 构造：`newProjectTrustStore(agentDir)` → trustPath = `agentDir/trust.json`
- `get(cwd)`: 读文件（无文件返回 nil），返回 findNearestTrustEntry 的 decision（无条目返回 nil）
- `getEntry(cwd)`: 同上但返回完整 (path, decision)
- `set(cwd, decision)`: setMany([{path, decision}])
- `setMany(updates)`: 读文件，逐条应用（decision=nil 删除该路径条目，否则写入），按 path 排序后写回，格式为 `JSON.stringify(sorted, null, 2) + "\n"`

读文件校验（对齐 pi readTrustFile）：

- 文件不存在 → 空表
- JSON 解析失败 → 抛错 `Failed to read trust store <path>: <message>`
- 顶层非对象 → 抛错 `Invalid trust store <path>: expected an object`
- 任一值非 true/false/null → 抛错 `Invalid trust store <path>: value for "<key>" must be true, false, or null`

写文件：目录自动创建，按 path 排序，仅保留 true/false/nil 值。

## 决策流 resolveProjectTrusted

输入：ResolveTrustOptions。返回 bool。步骤按序短路：

1. `trustOverride` 有值 → 直接返回。
2. `hasTrustRequiringProjectResources(cwd)` 为 false → 返回 true（无资源无需询问）。
3. store.get(cwd) 有记录（true/false）→ 返回记录。
4. `defaultTrust`：
   - "always" → true
   - "never" → false
   - "ask" → 继续
5. 无 UI（uiSelect 为 none）→ 返回 false。
6. 调用 uiSelect(cwd, getProjectTrustOptions(cwd, includeSessionOnly=true))；若用户选中选项：
   - 应用该选项的 updates 到 store（session-only 选项 updates 为空，不持久化）
   - 返回选项的 trusted
7. 未选中（取消）→ 返回 false。

## 接入

### src/npi.nim

- main 流程在解析 cwd 之后、加载 skills/templates 之前，执行 `resolveProjectTrusted`，结果存入 driver（AgentDriver 新增 `projectTrusted*: bool` 字段）。
- print 模式（-p）：uiSelect 传 none（无 UI）→ 按决策流默认 ask 无记录返回 false。
- TUI 模式：提供基于 illwill 的简单数字选择实现（1-5 对应选项，回车确认，q 取消），无复杂 select 组件。

### src/agent.nim / src/skills.nim / src/templates.nim

- `loadSkills(projectRoot)` 增加信任感知：不信任时跳过项目级 `.npi/skills` 子目录，仍加载用户级 `NPI_AGENT_DIR/skills`。签名改为 `loadSkills(projectRoot: string, trustProject: bool = true)`。
- `loadTemplates` 同理：不信任时跳过项目级 `.npi/prompts`。
- systemPrompt 的 skills 注入使用过滤后的结果。

## 测试（tests/test_core.nim 追加）

使用 `mkdtemp` 临时目录构造 fixtures（不触碰真实 `~/.npi`）：

- findNearestTrustEntry：无记录 → nil；当前目录命中；祖先命中；nil 条目继续向上
- getProjectTrustParentPath：普通目录 → 父路径；根 → 空
- getProjectTrustOptions：默认 4 项；includeSessionOnly 6 项；label/trusted/updates/savedPath 断言；无父路径目录（根）省略 Trust parent 项
- hasTrustRequiringProjectResources：空目录 false；含 `.npi/skills` true；含 `.npi/prompts` true；祖先 `.agents/skills` true；用户级 `~/.agents/skills` 忽略（用伪造 HOME 或构造相对判定）
- ProjectTrustStore：set/get 往返；setMany 合并；nil 删除；排序写回；非法 JSON 抛错；非法值抛错
- resolveProjectTrusted：override 短路；无资源 true；store 记录；always/never；ask+无UI false；ask+UI 选择 Trust → store 记录且返回 true；session-only 选项不持久化

## 非目标（明确不做）

- proper-lockfile 多进程锁（单进程 CLI）
- extensions project_trust 事件
- settings.json 文件接入
- 复杂 TUI select 组件
