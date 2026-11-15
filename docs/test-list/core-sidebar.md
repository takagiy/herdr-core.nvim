# core/sidebar.lua

The rows the sidebar shows.

- [ ] When local terminals are in several spaces, the sidebar can list each space as a heading with its terminals under it.
- [ ] When terminals run on another machine, the sidebar can list that machine as a heading with its spaces under it.
- [ ] When a machine cannot be reached, the sidebar can mark its heading as disconnected and keep its rows.
- [ ] When a terminal is shown, the sidebar can show its status and name on the first line and its foreground program on the second.
- [ ] When a terminal has a `herdr-core-nvim.name` label, the sidebar can show that label as its name.
- [ ] When a terminal has no `herdr-core-nvim.name` label but an hc name, the sidebar can show the hc name.
- [ ] When a terminal has neither, the sidebar can show its address as its name.
- [ ] When the sidebar is first built, it can order spaces and terminals by their latest update, newest first.
- [ ] When terminals in a space are pinned, the sidebar can put them first in that space.
- [ ] When a status changes after the sidebar is built, the sidebar can keep the rows in place.
- [ ] When a terminal or space appears after the sidebar is built, the sidebar can put it at the top.
- [ ] When a terminal moves to another space, the sidebar can put it at the top of that space.
- [ ] When a space has blocked or done terminals, the sidebar can show their count on its heading.
- [ ] When the user folds a heading, the sidebar can hide its rows and keep its count.
- [ ] When the sidebar is collapsed, it can show only the number of terminals waiting for the user.
