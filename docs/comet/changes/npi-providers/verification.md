# NPI Providers — Verification Report

**Change**: npi-providers · **Phase**: verify · **Date**: 2026-08-18

## 背景
在 npi-core 基础上新增 Anthropic provider，支持 Claude 流式推理与工具调用，`--provider` 切换。

> 注：comet Runtime check 执行器在本环境无法 spawn 外进程，以下证据由 Agent 直接运行取证。

## 验收证据

| ID | Acceptance | 结果 | 证据 |
|----|------------|------|------|
| A1 | `--provider anthropic` 可切换，默认仍 openai | ✅ 通过 | `--help` 显示默认 openai；NPI_PROVIDER 生效 |
| A2 | Anthropic 文本流式解析 (text_delta) | ✅ 通过 | mock SSE 输出完整中文文本 |
| A3 | Anthropic `tool_use` 工具执行并回填 tool_result | ✅ 通过 | 第2轮请求体确认 assistant(tool_use/read)+user(tool_result/toolu_1) |
| A4 | mock Anthropic 端到端 2 轮 agent 循环 | ✅ 通过 | 输出 「已验证 tool_result 回填」 |
| A5 | 现有单测仍全绿 | ✅ 通过 | 9/9 单测通过 |

## 执行证据（命令）

```bash
# 编译 + 单测（9 项含 2 个 anthropic wire）
nim c -r ... tests/test_core.nim   # [OK] ×9
# mock Anthropic SSE 端到端
./npi -p "读文件" --provider anthropic --base-url http://127.0.0.1:8898 --api-key test
# → 第2轮请求：assistant[text, tool_use read] + user[tool_result toolu_1]
```

## 风险与已知限制
- Gemini/Mistral 多 provider 待后续 change
- Anthropic 仅 mock 验证，未接真实 API（无计费 key）
