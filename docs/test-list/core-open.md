# core/open.lua

Where a terminal opens.

- [x] When the chosen terminal is shown in a window, opening can ask to focus that window.
- [x] When the chosen terminal is not shown, opening can ask for a new tabpage that shows it.
- [x] When the user sets another way to open, opening can use it in place of the default.
- [x] When the user opens a new terminal from a terminal window, opening can ask for a shell in that terminal's folder.
- [x] When the user opens a new terminal from any other window, opening can ask for a shell in Neovim's current folder.
- [x] When the user opens a new terminal from a sidebar row, opening can ask for a shell in that row's space root.
- [x] When the user opens a new terminal, opening can ask for it in a new tabpage, a vertical split or a horizontal split, as requested.
- [x] When the user opens a new terminal, opening can ask to give it its own `herdr.tab` label and `herdr.seen=0`.
