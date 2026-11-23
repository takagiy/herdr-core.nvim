# core/sidebar.lua

The rows the sidebar shows.

- [x] When local terminals are in several spaces, the sidebar can list each space as a heading with its terminals under it.
- [x] When a terminal runs on another machine, the sidebar can leave it out.
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
- [x] When the sidebar is collapsed, it can show only the number of terminals waiting for the user.
- [x] When a terminal has a live parent, the sidebar can list it under its parent in the parent's space, one level deeper, with tree guides.
- [x] When a terminal's parent is gone, the sidebar can list it as a usual terminal in its own space.
- [x] When children wait for the user, the sidebar can count them on their parent and on the space heading.


- [x] プログラムはパスを除いた実行ファイル名を表示し、大小文字を問わず .exe を省く。
- [x] When a program was run through a link, such as claude pointing to a versioned file, the sidebar can show the name it was run by, from its argv.

- [x] When the terminals are listed, the sidebar can give each space as a section and each terminal as an item, with what their actions need in props.
- [x] When a resource has no parent, the sidebar can list what it notified at the top in the order of the resources: a section under a heading, an item without one.
- [x] When a resource's parent points at a level of another resource, the sidebar can list what it notified under each element of that level, after the element's own items.
- [x] When a row is made, it can carry its resource's name and keys, the element and the element above it; a section's row takes no keys.
- [x] When resources have monitors, the sidebar can say where they are wanted: once without an element for a resource at the top, once for each element of the level for one with a parent.
- [x] When an element has an id, the sidebar can keep it apart by the id wherever it is listed.
- [x] When a key is pressed on an item, the sidebar can ask for the function to be run with the item: the one given for the key, or the action its resource names for it.
- [x] When resources cannot be used, `problem` can say which one and why.
