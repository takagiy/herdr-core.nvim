# app/actions.lua

Actions the user maps to keys.

- [x] When the user calls the action for a new terminal in a tabpage, vertical split or horizontal split, the action can pass the matching event to the core.
- [x] When the user calls the action to toggle or focus the sidebar, the action can pass the matching event to the core.
- [x] When `setup` runs without key settings, the plugin can leave global keys unmapped.
