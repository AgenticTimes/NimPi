# NPI Templates — Specification

## 目标
为 npi 实现 prompt 模板：用户输入 `/模板名 参数` 时展开为模板内容（含占位符替换），支持默认参数与切片。

## 范围
- `src/templates.nim`：
  - `parseCommandArgs(str)` bash 风格解析（支持双引号/单引号）
  - `substituteArgs(content, args)` 占位符替换：`$1` `$@`/`$ARGUMENTS` `${@:N}` `${@:N:L}` `${N:-default}`（对齐 pi 正则语义）
  - `PromptTemplate` 类型（name/description/content/filePath）
  - `loadTemplatesFromDir`：递归发现 `.md`，解析 frontmatter(name/description) + body
  - `expandPromptTemplate(text, templates)`：以 `/name` 开头且命中模板则展开，否则原样返回
- 加载源：用户级 `~/.npi/prompts/` + 项目级 `.npi/prompts/`
- 与 slash 系统衔接：TUI/REPL 输入 `/name ...` 若是模板则展开为对话(而非命令)

## 非目标
- promptPaths 显式文件参数 —— 后续
- includeDefaults 内置模板 —— 后续
- 更多占位符变体 —— 后续

## 验收
- [ ] parseCommandArgs 处理空格/引号
- [ ] substituteArgs：$1、$@、${@:N}、${@:N:L}、${N:-default}
- [ ] 模板从 frontmatter+body 加载
- [ ] expandPromptTemplate 命中展开、未命中原样
- [ ] 单测覆盖参数解析/替换/展开
