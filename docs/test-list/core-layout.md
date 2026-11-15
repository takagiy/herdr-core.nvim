# core/layout.lua

The tabpages, splits and terminals that every Neovim shares.

- [ ] When Neovim starts and the core holds a saved layout, layout can ask to show its tabpages, splits and terminals.
- [ ] When Neovim starts and the core holds no layout, layout can start with no terminal windows.
- [ ] When the arrangement of terminal windows changes, layout can ask to save it with the version it last read.
- [ ] When a tabpage holds file windows, layout can save the tabpage without them.
- [ ] When another Neovim saves a newer layout, layout can ask to show it.
- [ ] When saving is refused because another Neovim saved first, layout can take the newer layout and apply its own change to it again.
- [ ] When a terminal in the layout ends, layout can remove its windows and any tabpage left without windows.
- [ ] When a terminal window is closed, layout can save the layout without asking to stop the terminal.
