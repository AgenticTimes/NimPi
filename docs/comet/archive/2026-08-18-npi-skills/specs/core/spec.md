# NPI Skills — Specification

## 目标
为 npi 实现 pi 的 Agent Skills 支持：从 skills 目录递归发现 SKILL.md，解析 frontmatter（name/description/disable-model-invocation），按 Agent Skills 标准 XML 格式注入 system prompt。

## 范围
- `src/skills.nim`：递归发现 SKILL.md（目录含 SKILL.md 即视为 skill root 不再深入）、YAML frontmatter 解析（name/description/disable-model-invocation）、name 校验
- 加载源：项目级 `.npi/skills/` 与用户级（`NPI_AGENT_DIR`/默认 `~/.npi/skills`）
- XML 格式注入 system prompt（对齐 agentskills.io 标准）；`disable-model-invocation=true` 的 skill 不注入
- 校验失败仅警告不阻断

## 非目标
- `/skill:name` 显式命令调用 —— 后续 change
- 平台目录枚举（.claude/.cursor 等各家）—— 后续 change
- 技能市场/安装器 —— 后续 change

## 验收
- [ ] 递归找到 SKILL.md（含嵌套子目录），目录含 SKILL.md 不再深入子目录
- [ ] YAML frontmatter name/description 正确解析（name 缺省用目录名）
- [ ] XML 格式注入 system prompt 正确（对齐 agentskills.io）
- [ ] disable-model-invocation=true 的 skill 从 prompt 排除
- [ ] 缺失/损坏 frontmatter 仅警告不报错
- [ ] 单测覆盖以上逻辑
