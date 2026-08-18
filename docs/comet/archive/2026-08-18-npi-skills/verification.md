---
generated_from_state_version: 8
---

# Verification

## Current result

- Result: **Passed**
- Assurance: **skill-coordinated**
- Goal cycle: 1
- Iteration: 1
- Verifier attempt: 1
- Completed: 2026-08-18T00:49:28.610Z
- Summary: NPI Skills 验收全过：comet Runtime 用 brew nim 实跑单测 16 OK，mock 抓取 system prompt 确认 XML skills 段注入正确，disabled 排除。

## Acceptance

| ID | Result | Source | Criterion | Reason |
| --- | --- | --- | --- | --- |
| A1 | passed | specs/core/spec.md | 为 npi 实现 pi 的 Agent Skills 支持：从 skills 目录递归发现 SKILL.md，解析 frontmatter（name/description/disable-model-invocation），按 Agent Skills 标准 XML 格式注入 system prompt。 | 实现 pi Agent Skills 支持：发现+frontmatter+XML 注入 system prompt |
| A2 | passed | specs/core/spec.md | `src/skills.nim`：递归发现 SKILL.md（目录含 SKILL.md 即视为 skill root 不再深入）、YAML frontmatter 解析（name/description/disable-model-invocation）、name 校验 | src/skills.nim：递归发现/解析/校验 |
| A3 | passed | specs/core/spec.md | 加载源：项目级 `.npi/skills/` 与用户级（`NPI_AGENT_DIR`/默认 `~/.npi/skills`） | 项目级 .npi/skills 与用户级 NPI_AGENT_DIR/skills 双源加载 |
| A4 | passed | specs/core/spec.md | XML 格式注入 system prompt（对齐 agentskills.io 标准）；`disable-model-invocation=true` 的 skill 不注入 | XML 格式注入对齐 agentskills.io |
| A5 | passed | specs/core/spec.md | 校验失败仅警告不阻断 | disable-model-invocation=true 不注入 |
| A6 | passed | specs/core/spec.md | [ ] 递归找到 SKILL.md（含嵌套子目录），目录含 SKILL.md 不再深入子目录 | 校验失败仅警告不阻断 |
| A7 | passed | specs/core/spec.md | [ ] YAML frontmatter name/description 正确解析（name 缺省用目录名） | 递归发现 SKILL.md 含嵌套，目录含 SKILL.md 不深入 |
| A8 | passed | specs/core/spec.md | [ ] XML 格式注入 system prompt 正确（对齐 agentskills.io） | frontmatter name/description 解析正确（name 缺省用目录名） |
| A9 | passed | specs/core/spec.md | [ ] disable-model-invocation=true 的 skill 从 prompt 排除 | XML 注入正确（单测验证） |
| A10 | passed | specs/core/spec.md | [ ] 缺失/损坏 frontmatter 仅警告不报错 | disabled skill 从 prompt 排除 |
| A11 | passed | specs/core/spec.md | [ ] 单测覆盖以上逻辑 | 单测全绿（brew nim comet check 实跑 16 项） |

## Checks

| Check | Command | Working directory | Status | Exit | Duration |
| --- | --- | --- | --- | ---: | ---: |
| NPI Skills 单测 (brew nim) | c -r --hints:off --path:/Users/meetai/.nimble/pkgs2/illwill-0.4.1-9c58351502f89a16caf031cbd1992ad3fdfd3c67 -o:/tmp/npi_skills_vt tests/test_core.nim | . | passed | 0 | 2099 ms |

## Blockers

_None._

## Risks and skipped work

- /skill:name 显式调用待后续 change
- 平台目录枚举（.claude/.cursor 等）待后续 change

## Previous iterations

| Goal cycle | Iteration | Attempt | Outcome | Unresolved | Summary | Completed |
| ---: | ---: | ---: | --- | --- | --- | --- |
| 1 | 1 | 1 | pass | — | NPI Skills 验收全过：comet Runtime 用 brew nim 实跑单测 16 OK，mock 抓取 system prompt 确认 XML skills 段注入正确，disabled 排除。 | 2026-08-18T00:49:28.610Z |

## Conclusion

NPI Skills 验收全过：comet Runtime 用 brew nim 实跑单测 16 OK，mock 抓取 system prompt 确认 XML skills 段注入正确，disabled 排除。
