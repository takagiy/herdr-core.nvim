# core/state.lua

The core's single entry point.

- [x] When a terminal starts, `update` can store it and request its repository root.
- [x] When a terminal ends, `update` can remove it from terminals, spaces and layout and return the layout effects.
- [x] When a foreground folder changes, `update` can store the foreground data and request the root on the terminal's machine.
- [x] When the initial terminal list arrives, `update` can store it and request every terminal's repository root.
- [x] When status, labels, turn, name or pin events arrive, `update` can return the terminal state and requested effects.
- [x] When a repository root result arrives for the current folder, `update` can update its space.
- [x] When a repository root result arrives for an old folder or ended terminal, `update` can ignore it.
- [x] When layout events arrive, `update` can return the layout state and effects.
- [x] When an event's type is unknown, `update` can return the state unchanged with no effects.
- [x] When Neovim gains focus or shows other terminals, `update` can ask to mark each shown terminal as seen.
- [x] When a terminal becomes blocked or done while nobody looks at it, `update` can ask to notify the user.
- [x] When the user chooses a terminal, `update` can ask to focus its window or to show it, as the opening policy decides.
- [x] When the user activates a machine heading, `update` can fold or unfold it.
- [x] When the user asks for a new terminal, `update` can ask for a shell where the opening policy decides.
- [x] When the user marks a terminal unread, `update` can ask to lower its `herdr.seen` label.
- [x] When the state changes, `view` can return the sidebar rows and the number of terminals waiting, keeping their order.
- [x] When a foreground program changes without the folder changing, `update` can skip looking up the repository root again.
- [x] When a sidebar action is requested, `update` can return the corresponding UI effect.
- [x] When a machine heading is folded, `view` can still count that machine's terminals waiting for the user.
- [x] When a saved layout names terminals that finished while no Neovim was running, `update` can restore it without them and save the result.
- [x] When a saved layout loads before the terminal list, `update` can keep every terminal in it.
- [x] When a later layout names a terminal whose start event has not arrived yet, `update` can keep that terminal.
