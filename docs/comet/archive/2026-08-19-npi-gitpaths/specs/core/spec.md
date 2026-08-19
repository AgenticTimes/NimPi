# NPI GitPaths — Specification

## 目标
对齐 pi findGitPaths：从 cwd 向上查找 git 仓库根，支持普通 .git 目录与 worktree gitdir 文件（gitdir:/commondir 指针）。

## 范围
- `src/gitpaths.nim`：
  - `GitPaths`（repoDir/commonGitDir/headPath）
  - `findGitPaths(cwd): Option[GitPaths]`：
    - 向上遍历，找 .git（目录或文件）
    - .git 文件 → `gitdir: <path>` 指针，HEAD 在 gitDir，解析 commondir（存在则指向 common）
    - .git 目录 → HEAD 在其下
    - 无 HEAD → none
    - 到根仍无 → none

## 非目标
- branch 解析（git symbolic-ref 调用）—— 后续/调用方
- WSL/Windows 环境检测 —— 平台特定

## 验收
- [ ] .git 目录场景（普通仓库）
- [ ] .git 文件场景（worktree gitdir 指针）
- [ ] commondir 解析
- [ ] 无 HEAD 返回 none
- [ ] 向上查找（子目录开始）
- [ ] 无 .git 返回 none
- [ ] 单测覆盖
