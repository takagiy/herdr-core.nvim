# adapter/git.lua

Repository roots of folders.

- [x] When a folder is inside a git repository, the git adapter can return the repository root.
- [x] When a folder is inside a git worktree, the git adapter can return the worktree's root.
- [x] When a folder is outside any git repository, the git adapter can return no root.
- [x] When the folder is on another machine, the git adapter can look up the root there through `hc exec --on`.

- [x] When git or hc cannot be started, the git adapter can return no root without crashing the client.
