# core/terminals.lua

The terminals the core reports, as the plugin keeps them.

- [ ] When the terminal list arrives at startup, the registry can hold each terminal's address, name, labels, status, turn, foreground program and folder, and update times.
- [ ] When a terminal starts, the registry can add it.
- [ ] When a terminal's foreground changes, the registry can record its new program and folder.
- [ ] When a terminal's status changes, the registry can record the new status and when it changed.
- [ ] When a terminal's labels change, the registry can replace them with the reported set.
- [ ] When a terminal's program ends, the registry can drop the terminal.
- [ ] When the user names a terminal, the registry can ask to write the name as its `herdr-core-nvim.name` label.
- [ ] When the user clears a terminal's name, the registry can ask to remove its `herdr-core-nvim.name` label.
- [ ] When the user pins a terminal, the registry can ask to write `herdr.pinned=1` on it.
- [ ] When the user unpins a terminal, the registry can ask to remove its `herdr.pinned` label.
