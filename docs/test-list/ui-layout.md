# ui/layout.lua

Tabpages and windows in Neovim.

- [x] When asked to show a layout, Neovim can get its tabpages and splits with each window showing its terminal.
- [x] When asked to show a new layout, Neovim can keep the current tabpage and window focused if they still exist.
- [x] When asked to show a new layout, Neovim can keep the file windows that were open.
- [x] When the user splits, closes or moves a terminal window or tabpage, the change can be reported as the arrangement of terminal windows.
- [x] When the arrangement is reported, the sidebar and file windows can be left out of it.
- [x] When a window that showed a file shows a terminal again after the layout was shown, each terminal window can keep its own id.
