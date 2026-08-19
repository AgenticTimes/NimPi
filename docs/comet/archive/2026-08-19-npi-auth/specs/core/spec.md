# NPI Auth — Specification

## 目标
为 npi 实现 auth.json 凭据持久存储（对齐 pi auth-storage.ts 的 FileAuthStorageBackend 核心语义）。

## 范围
- `src/authstorage.nim`：
  - `AuthStorage`：authPath（默认 NPI_AGENT_DIR/auth.json）
  - `readStoredCredential(providerId)`：读 JSON 取凭据（对齐 pi）
  - `setCredential(providerId, key)`：写（0o600 权限对齐 pi mode）
  - `deleteCredential(providerId)`：删
  - `listCredentials()`：列出
- 无文件锁（单进程 CLI，ponytail 注释）

## 非目标
- proper-lockfile 多进程锁 —— 单进程
- 完整 CredentialStore 接口 —— 核心方法
- provider auth 编排 —— ModelRuntime 职责

## 验收
- [ ] readStoredCredential 读取
- [ ] setCredential 写入 + 0o600
- [ ] deleteCredential 删除
- [ ] listCredentials 列出
- [ ] 无 auth.json 时返回空
- [ ] 单测覆盖
