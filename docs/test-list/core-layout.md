# core/layout.lua

The tabpages, splits and terminals that every Neovim shares.

- [x] When Neovim starts and the core holds a saved layout, layout can ask to show its tabpages, splits and terminals.
- [x] When Neovim starts and the core holds no layout, layout can start with no terminal windows.
- [x] When the arrangement of terminal windows changes, layout can ask to save it with the version it last read.
- [x] When a tabpage holds file windows, layout can save the tabpage without them.
- [x] When another Neovim saves a newer layout, layout can ask to show it.
- [x] When saving is refused because another Neovim saved first, layout can take the newer layout and apply its own change to it again.
- [x] When a terminal in the layout ends, layout can remove its windows and any tabpage left without windows.
- [x] When a terminal window is closed, layout can save the layout without asking to stop the terminal.

- [x] When a version conflict affects an existing tab, layout can retain its local edit.
- [x] When a version conflict follows a local tab deletion, layout can keep that tab closed.
- [x] When a remote editor deletes an unchanged tab, layout can keep it deleted while saving a different local tab.
- [x] When an older layout notification arrives, layout can ignore it.
- [x] When the window arrangement is unchanged, layout can avoid saving it again.
- [x] When its saved value arrives with a newer version, layout can accept the version without rebuilding its windows.

- [x] When another editor's layout arrives while local changes are pending, layout can merge them without dropping the local changes.

- [x] When a terminal absent from the layout ends, layout can leave its windows and shared data unchanged.
- [x] When a conflict response is older than the current layout version, layout can ignore it.
