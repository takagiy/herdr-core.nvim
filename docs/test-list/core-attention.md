# core/attention.lua

Which terminals wait for the user, and when to tell the user.

- [ ] When a terminal is blocked or in error, attention can count it as waiting for the user.
- [ ] When a terminal's turn is newer than its `herdr.seen` label, attention can mark it done.
- [ ] When a terminal's `herdr.seen` label is at its turn, attention can mark it idle.
- [ ] When Neovim is focused and shows a terminal, attention can ask to raise its `herdr.seen` label to its turn, once per turn.
- [ ] When Neovim shows a terminal that has no `herdr.seen` label, attention can ask to write the label at its turn.
- [ ] When Neovim is not focused, attention can leave `herdr.seen` labels as they are.
- [ ] When the user marks a terminal unread, attention can ask to write its `herdr.seen` label one below its turn.
- [ ] When the user marks a terminal unread at turn 0, attention can leave it as it is.
- [ ] When a terminal becomes blocked or done and is not shown in a focused Neovim, attention can ask to notify the user.
- [ ] When a terminal becomes blocked or done while shown in a focused Neovim, attention can skip the notification.
- [ ] When a terminal starts working, attention can skip the notification.
