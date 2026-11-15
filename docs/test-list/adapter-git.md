# adapter/git.lua

Repository roots of folders.

- [ ] When a folder is inside a git repository, the git adapter can return the repository root.
- [ ] When a folder is inside a git worktree, the git adapter can return the worktree's root.
- [ ] When a folder is outside any git repository, the git adapter can return no root.
- [ ] When the folder is on another machine, the git adapter can look up the root there through `hc exec --on`.
