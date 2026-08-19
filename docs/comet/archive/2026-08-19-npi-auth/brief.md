# NPI Auth — Brief

为 npi 实现 auth.json 凭据存储精简版：凭据文件读写（0o600 权限）+ readStoredCredential + setCredential/deleteCredential。衔接 credentials 运行时覆盖层。对齐 pi auth-storage.ts 核心。
