# NPI Credentials — Specification

## 目标
为 npi 实现运行时 API key 覆盖（对齐 pi runtime-credentials.ts）：非持久凭据覆盖。

## 范围
- `src/credentials.nim`：
  - `RuntimeCredentials`：overrides Table（providerId → apiKey）
  - `setRuntimeApiKey(providerId, key)` / `removeRuntimeApiKey` / `hasRuntimeApiKey`
  - `read(providerId)`：覆盖优先，否则回退 base（env 查找）
  - `list()`：列出覆盖 + base
- 接入（可选）：CLI --api-key 用 setRuntimeApiKey 存覆盖

## 非目标
- 持久凭据存储 —— 运行时覆盖
- 完整 CredentialStore 接口 —— 核心方法

## 验收
- [ ] setRuntimeApiKey 覆盖
- [ ] read 覆盖优先
- [ ] read 回退 base
- [ ] remove/has
- [ ] list 合并
- [ ] 单测覆盖
