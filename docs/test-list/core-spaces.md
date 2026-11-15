# core/spaces.lua

Which space each terminal belongs to.

- [ ] When a terminal's folder changes, spaces can ask for the repository root of the new folder.
- [ ] When the folder is inside a git repository, spaces can put the terminal in the repository root's space.
- [ ] When the folder is outside any git repository, spaces can put the terminal in the folder's own space.
- [ ] When the space differs from the terminal's `herdr.space` label, spaces can ask to write the label.
- [ ] When the space matches the terminal's `herdr.space` label, spaces can leave the label as it is.
- [ ] When a terminal on another machine changes folder, spaces can ask for the repository root on that machine.
- [ ] When no terminal is left in a space, spaces can drop the space.
