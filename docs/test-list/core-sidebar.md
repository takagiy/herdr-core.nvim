# core/sidebar.lua

The rows the sidebar shows.

- [x] When local terminals are in several spaces, the sidebar can list each space as a heading with its terminals under it.
- [x] When terminals run on another machine, the sidebar can list that machine as a heading with its spaces under it.
- [x] When a machine cannot be reached, the sidebar can mark its heading as disconnected and keep its rows.
- [x] When a terminal is shown, the sidebar can show its status and name on the first line and its foreground program on the second.
- [x] When a terminal has a `herdr-core-nvim.name` label, the sidebar can show that label as its name.
- [x] When a terminal has no `herdr-core-nvim.name` label but an hc name, the sidebar can show the hc name.
- [x] When a terminal has neither, the sidebar can show its address as its name.
- [x] When the sidebar is first built, it can order spaces and terminals by their latest update, newest first.
- [x] When terminals in a space are pinned, the sidebar can put them first in that space.
- [x] When a status changes after the sidebar is built, the sidebar can keep the rows in place.
- [x] When a terminal or space appears after the sidebar is built, the sidebar can put it at the top.
- [x] When a terminal moves to another space, the sidebar can put it at the top of that space.
- [x] When a space has blocked or done terminals, the sidebar can show their count on its heading.
- [x] When the user folds a heading, the sidebar can hide its rows and keep its count.
- [x] When the sidebar is collapsed, it can show only the number of terminals waiting for the user.

- [x] When a remote machine heading is folded, the sidebar can hide its projects without losing the total waiting count.
