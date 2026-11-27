# ui/focus.lua

What the user is looking at.

- [x] When Neovim gains or loses focus, the change can be reported.
- [x] When windows, buffers or tabpages change, the terminals shown on screen can be reported.
- [x] When a terminal's buffer is entered, the watcher can report it as the one in front, and keep reporting it while the cursor is in the sidebar.
- [x] When layout restoration temporarily visits hidden tabs, focus can report only the final visible terminals.
- [x] When the focus is reported, the watcher can report Neovim's global cwd with it.
