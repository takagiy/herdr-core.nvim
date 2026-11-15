# core/terminals.lua

The terminals the core reports, as the plugin keeps them.

- [x] When the terminal list arrives at startup, the registry can hold each terminal's address, name, labels, status, turn, foreground program and folder, and update times.
- [x] When a terminal starts, the registry can add it.
- [x] When a terminal's foreground changes, the registry can record its new program and folder.
- [x] When a terminal's status changes, the registry can record the new status and when it changed.
- [x] When a terminal's labels change, the registry can replace them with the reported set.
- [x] When a terminal's program ends, the registry can drop the terminal.
- [x] When the user names a terminal, the registry can ask to write the name as its `herdr-core-nvim.name` label.
- [x] When the user clears a terminal's name, the registry can ask to remove its `herdr-core-nvim.name` label.
- [x] When the user pins a terminal, the registry can ask to write `herdr.pinned=1` on it.
- [x] When the user unpins a terminal, the registry can ask to remove its `herdr.pinned` label.

- [x] When a turn change arrives separately from status, the registry can record it without changing other terminal facts.
