## Git 路径查找：对齐 pi footer-data-provider.ts 的 `findGitPaths`。
## 从 cwd 向上找 git 仓库根，支持普通 .git 目录与 worktree gitdir 指针文件。

import std/[os, options, strutils]

type
  GitPaths* = object
    repoDir*: string
    commonGitDir*: string
    headPath*: string

proc resolveGitDir(gitPath: string): Option[tuple[commonGitDir, headPath: string]] =
  ## 处理单个 .git 路径：目录 → 直接用；文件 → 解析 `gitdir: <path>` 指针 + commondir。
  if dirExists(gitPath):
    let headPath = gitPath / "HEAD"
    if fileExists(headPath):
      return some((commonGitDir: gitPath, headPath: headPath))
    return none(tuple[commonGitDir, headPath: string])
  if fileExists(gitPath):
    try:
      let content = readFile(gitPath).strip()
      if content.startsWith("gitdir: "):
        let gitDir = absolutePath(content["gitdir: ".len .. ^1].strip(), parentDir(gitPath))
        let headPath = gitDir / "HEAD"
        if fileExists(headPath):
          let commonDirPath = gitDir / "commondir"
          let commonGitDir =
            if fileExists(commonDirPath):
              absolutePath(readFile(commonDirPath).strip(), gitDir)
            else:
              gitDir
          return some((commonGitDir: commonGitDir, headPath: headPath))
    except IOError, OSError:
      discard
  none(tuple[commonGitDir, headPath: string])

proc findGitPaths*(cwd: string): Option[GitPaths] =
  ## 从 cwd 向上查找 git 仓库根；无则 none（对齐 pi findGitPaths）。
  var dir = cwd
  while true:
    let gitPath = dir / ".git"
    let resolved = resolveGitDir(gitPath)
    if resolved.isSome:
      return some(GitPaths(repoDir: dir,
                           commonGitDir: resolved.get.commonGitDir,
                           headPath: resolved.get.headPath))
    let parent = parentDir(dir)
    # Nim parentDir("/") 返回空串，须显式终止（pi dirname 返回 self）
    if parent == dir or parent.len == 0:
      return none(GitPaths)
    dir = parent