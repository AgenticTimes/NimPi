# Outcome

对齐 pi-coding-agent 的 project trust 机制：新增 `src/trust.nim`，实现项目信任判定（`resolveProjectTrusted`）、信任选项生成（`getProjectTrustOptions`）、最近信任条目查找（`findNearestTrustEntry`）、信任资源检测（`hasTrustRequiringProjectResources`）与 trust.json 存储（`ProjectTrustStore`），并接入 npi 启动流程：不信任时跳过项目级 `.npi/skills` / `.npi/prompts` 加载，用户级目录始终受信任。

# Scope

- 新增 `src/trust.nim`（对齐 pi `trust-manager.ts` + `project-trust.ts` 的纯逻辑与轻量 JSON 存储）
- 接入 `src/npi.nim` 启动流程与 `src/agent.nim` 的 skills 加载路径：信任判定结果控制项目级资源加载
- `tests/test_core.nim` 追加对应测试（fixtures 用临时目录构造，不污染真实 home）
- 决策流完整对齐 pi：override → 资源检测 → store 记录 → default(ask/always/never) → UI 回调 → 无 UI 返回 false
- trust.json 位置：`NPI_AGENT_DIR/trust.json`（默认 `~/.npi/trust.json`），格式对齐 pi（排序 JSON）

# Non-goals

- 不实现 proper-lockfile 等价的多进程文件锁（npi 是单进程 CLI，`ponytail:` 注释说明）
- 不实现 extensions `project_trust` 事件（npi 无扩展系统）
- 不做 TUI 的复杂 select 组件（illwill 简单数字选择即可）
- 不接入 settings.json 文件读取（npi settings 目前仅结构 + 默认值，非本 change 范围）
- 不实现 pi 的 UI 提示文本（formatProjectTrustPrompt）以外的任何视觉组件

# Acceptance examples

- 有 `.npi/skills/` 的目录 → `hasTrustRequiringProjectResources` 返回 true，启动时触发信任判定
- 目录及其祖先均无 `.npi` 资源、无 `.agents/skills` → 返回 false，跳过询问直接信任
- `~/.npi/trust.json` 中已有该目录记录 → 直接使用记录，不询问
- print 模式（无 UI）+ default=ask + 无记录 → 返回 false（不信任，项目级 skills/prompts 不加载）
- TUI 模式询问，用户选 "Trust" → 记录到 trust.json，加载项目级资源

# Constraints and invariants

- 纯逻辑函数对齐 pi 同名函数语义：`findNearestTrustEntry`（沿目录向上找最近条目）、`getProjectTrustParentPath`（父目录，根返回空）、`getProjectTrustOptions`（选项列表顺序与 label 对齐 pi）
- 资源常量列表对齐 pi 完整列表：settings.json / extensions / skills / prompts / themes / SYSTEM.md / APPEND_SYSTEM.md
- 用户级目录（`NPI_AGENT_DIR/skills`）始终受信任，不受门禁影响（对齐 pi 忽略 `~/.agents/skills`）
- 无 UI（print / REPL stdin 非 TTY）时行为对齐 pi：default=ask 且无记录 → false
- trust.json 读写失败（非法 JSON / 非法值类型）抛错，错误消息含路径
- 不修改既有 164 测试；新增测试全部通过

# Decisions

- D1: 新增单文件 `src/trust.nim`，不做子目录拆分（模块量级与 credentials.nim 相当）
- D2: 资源常量保留 pi 完整 7 项列表（即使 npi 当前只实际加载 skills/prompts，保持未来兼容）
- D3: 文件锁省略（单进程 CLI 无需 proper-lockfile；`ponytail:` 注释标注升级路径）
- D4: `resolveProjectTrusted` 的 UI 通过 proc 回调注入（`uiSelect`），TUI 提供实现，print 模式传 nil → 无 UI 语义
- D5: trust.json 使用 `NPI_AGENT_DIR`（默认 `~/.npi`），与既有 skills/prompts 用户级目录一致
- D6: 接入点放在 `src/npi.nim` 启动早期（解析 cwd 之后），结果传入 skills/templates 加载路径

# Open questions

- [blocking] CONFIRM: 请确认以下共享理解——(1) 新增 src/trust.nim 对齐 pi project-trust + trust-manager 的纯逻辑与 JSON 存储；(2) 接入启动流程，不信任时跳过项目级 .npi/skills 与 .npi/prompts 加载（用户级 ~/.npi 不受影响）；(3) print 模式（无 UI）默认 ask 且无记录时返回不信任——这是对齐 pi 的行为，意味着 -p 模式下项目级 skills 不再自动注入，可用 NPI_TRUST=always 或 trust.json 记录恢复；(4) 省略多进程文件锁；(5) 验收 A1-A5 见 spec。

# Verification expectations

- `nim c -r --path:$(dirname $(ls ~/.nimble/pkgs2/illwill-*/ 2>/dev/null | head -1)) tests/test_core.nim` 全绿（含新增 trust 测试）
- `nimble test` 全绿
- 手动验证：含 `.npi/skills` 的项目在 TUI 下询问并记录；print 模式返回不信任
