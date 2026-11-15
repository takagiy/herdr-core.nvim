# core/spaces.lua

Which space each terminal belongs to.

- [x] When a terminal's folder changes, spaces can ask for the repository root of the new folder.
- [x] When the folder is inside a git repository, spaces can put the terminal in the repository root's space.
- [x] When the folder is outside any git repository, spaces can put the terminal in the folder's own space.
- [x] When the space differs from the terminal's `herdr.space` label, spaces can ask to write the label.
- [x] When the space matches the terminal's `herdr.space` label, spaces can leave the label as it is.
- [x] When a terminal on another machine changes folder, spaces can ask for the repository root on that machine.
- [x] When no terminal is left in a space, spaces can drop the space.
