# NPI TUI Palette — Specification

## 目标
给 npi TUI 加命令面板：`/` 前缀激活 palette 模式，fuzzy 过滤命令，↑/↓ 选择，Enter 确认选中。

## 范围
- `src/tui.nim` 扩展：
  - `Tui` 加 `commands*: seq[string]`、`paletteMode*: bool`、`paletteIndex*: int`
  - `setCommands(tui, cmds)`：设置可用命令
  - `/` 输入进入 palette（paletteQuery = input[1..]）
  - palette 模式渲染：fuzzy 过滤命令列表，当前选择高亮，状态行显示"命令面板"
  - ↑/↓ 在 palette 列表中移动选择
  - Enter：palette 模式选中命令（输入框显示 `/命令`），退出 palette
  - Esc（evQuit 之外）：退出 palette 清空输入？→ 退出 palette 保留输入
  - `paletteMatches(tui): seq[string]`：当前 fuzzy 匹配结果（供测试/消费）
- 单测：fuzzy 过滤、选择移动、Enter 确认、Esc 退出

## 非目标
- 完整命令执行链路（slash 模块已有，agent 循环消费）—— 调用方对接
- TUI 重构

## 验收
- [ ] setCommands 生效
- [ ] / 进入 palette 模式
- [ ] palette 渲染 fuzzy 过滤列表
- [ ] ↑/↓ 选择移动
- [ ] Enter 确认选中
- [ ] Esc 退出 palette
- [ ] 现有单测全绿
