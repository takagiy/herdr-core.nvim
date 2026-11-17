# core/attention.lua

Which terminals wait for the user, and when to tell the user.

- [x] When a terminal is blocked or in error, attention can count it as waiting for the user.
- [x] When a terminal has a live parent, attention can show its finished turn as idle and its error as blocked, so only a blocked child waits for the user.
- [x] When a child finishes a turn, attention can skip the notification, and still notify when it is blocked.
- [x] When a terminal's turn is newer than its `herdr.seen` label, attention can mark it done.
- [x] When a terminal's `herdr.seen` label is at its turn, attention can mark it idle.
- [x] When Neovim is focused and shows a terminal, attention can ask to raise its `herdr.seen` label to its turn, once per turn.
- [x] When Neovim shows a terminal that has no `herdr.seen` label, attention can ask to write the label at its turn.
- [x] When Neovim is not focused, attention can leave `herdr.seen` labels as they are.
- [x] When the user marks a terminal unread, attention can ask to write its `herdr.seen` label one below its turn.
- [x] When the user marks a terminal unread at turn 0, attention can leave it as it is.
- [x] When a terminal becomes blocked or done and is not shown in a focused Neovim, attention can ask to notify the user.
- [x] When a terminal becomes blocked or done while shown in a focused Neovim, attention can skip the notification.
- [x] When a terminal starts working, attention can skip the notification.
- [x] When a terminal is working with an earlier unread turn, attention can keep its working status instead of marking it done.

- [x] When the same state is reported again, attention can avoid repeating its notification, including a separate turn event after blocked status.
- [x] When another client has already marked a turn seen, attention can avoid rewriting or lowering its seen label.
