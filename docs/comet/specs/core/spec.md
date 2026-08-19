# NPI AuthGuidance — Specification

## 目标
对齐 pi auth-guidance.ts 的消息格式化（登录引导/无模型/无 API key），统一错误提示。

## 范围
- `src/authguidance.nim`：
  - `getProviderLoginHelp(docsPath)`：登录引导文本
  - `formatNoModelsAvailableMessage(docsPath)`：无模型可用
  - `formatNoModelSelectedMessage(docsPath)`：无模型选中
  - `formatNoApiKeyFoundMessage(provider, docsPath)`：无 API key（unknown provider 显示 "the selected model"）

## 非目标
- getDocsPath（config 依赖）—— 调用方传路径
- /login 命令实现 —— 后续

## 验收
- [ ] login help 含 providers/models 文档路径
- [ ] no models 消息
- [ ] no model selected 消息
- [ ] no api key（已知 provider）
- [ ] no api key（unknown → "the selected model"）
- [ ] 单测覆盖
