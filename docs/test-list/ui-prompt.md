# ui/prompt.lua

Asking the user for input.

- [x] When the user enters a name, the prompt can return it.
- [x] When the user cancels, the prompt can report that nothing changes.
- [x] When the user enters an empty name, the prompt can report that the name is cleared.
- [x] When asked to choose, `choose` can list the items in a floating window centered in the editor, with the row under the cursor selected.
- [x] When the user presses Enter or clicks an item, `choose` can return that item.
- [x] When the user presses Esc or `q`, or leaves the window, `choose` can return nil.
- [x] When an item is wider than the editor, `choose` can shorten it from the left with `…`, so every item keeps one row.
- [x] When a menu opens, it can list each choice on a line with its keys at the right, under its title, at the mouse pointer.
- [x] When a menu is open, the user can run the choice under the cursor with Enter, any choice with its key or a click, and none with q.
- [x] When a choice takes a key that closes the menu, the menu can run the choice with that key instead of closing without one.
