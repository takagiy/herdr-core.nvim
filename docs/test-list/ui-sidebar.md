# ui/sidebar.lua

The sidebar window.

- [x] When given rows, the sidebar can draw headings, two-line terminal rows and counts with `HerdrCore` highlights.
- [x] When a space heading is drawn, the sidebar can show the folder's name instead of its full path.
- [x] When the user switches tabpages, the sidebar can stay on the same side and width.
- [x] When a new tabpage is opened from the sidebar window, the sidebar can appear in it beside the new window.
- [x] When the user presses Enter or clicks on a terminal row, the sidebar can report that terminal as chosen.
- [x] space 見出しで Enter を押したりクリックしたりしても、開閉せずアクションを発行しない。
- [x] When a terminal is working, blocked, done or idle, the sidebar can show a different symbol for each.
- [x] When an item's resource takes a key, the sidebar can report that key for the item, and do nothing on other rows.
- [x] When the user clicks `«` at the bottom, the sidebar can collapse to a strip 2 to 3 columns wide.
- [x] When the sidebar is collapsed, it can show the waiting count at the top and `»` at the bottom.
- [x] When the user clicks `»`, the sidebar can expand again.
- [x] When an item's resource takes no key, `j`/`k` can skip the item.
- [x] When a heading is drawn for a resource, the sidebar can show its name; an item without a detail can take one line.
- [x] When the user clicks the same place again quickly, the sidebar can treat the second click like the first.

- [x] j/k と上下キーは、2行のターミナルを1項目として移動する。
- [x] 状態色は記号だけに使い、名前は通常色の太字、プログラムは薄い色で表示する。
- [x] 折りたたみボタンは « だけを表示する。

- [x] 現在操作しているターミナルの2行全幅に背景を付け、サイドバーへの移動中も保持する。
- [x] ヘッダーとプロジェクト見出しの太字、プロジェクト間の余白で階層を表示する。

- [x] 別ウィンドウからの1回のクリックで、サイドバーの項目を操作する。
- [x] サイドバーの外をクリックすると、標準のマウス操作でそのウィンドウに移動する。
- [x] 既存のグローバルマウスマッピングを残したまま、項目の操作を1回だけ実行する。
- [x] サイドバーを閉じると、マウス入力の監視を解除する。

- [x] 選択中のterminalが属するspaceの見出しを、通常と異なる全幅の背景色で表示する。

- [x] When an item's resource takes a key that moves the cursor, the sidebar can report the key instead of moving.

- [x] 下端のトグルを右端に表示し、リサイズ・折りたたみ後も表示されたボタンをクリックして開閉できる。
- [x] When rows include a Setup panel, the sidebar can draw it in a box above the toggle with its buttons ending one column inside the border.
- [x] When a Setup button does not fit beside its name, the sidebar can put it on the next line, ending in the same column.
- [x] When a Setup text line is wider than the box, the sidebar can wrap it at spaces.
- [x] When the sidebar is shown without a width, it can open 24 columns wide.
- [x] When the user moves with `j`/`k`, the sidebar can stop on Setup buttons, color the one under the cursor and press it with Enter.
- [x] When the sidebar is collapsed and something needs setting up, the sidebar can show `!` under the count.
- [x] When the sidebar is drawn, it can show a New terminal button under the header and report it when pressed with Enter or a click.
- [x] When items are marked as highlighted, the sidebar can give each a full-width background over all its lines.
- [x] When items at the top follow a section's rows, the sidebar can set them apart with a blank line and leave the section's heading without the accent.
- [x] When the user moves with `j`/`k`, the sidebar can skip space headings, which have no button.
- [x] When the cursor is in the sidebar, the sidebar can give the row under it the selection background and its button the accent, while the terminal in front keeps its gray.
- [x] When the sidebar draws the New terminal button, the toggle and Setup buttons, it can give them all the same button background.
- [x] When the user clicks New terminal, the sidebar can act after the mouse button is released, so the picker it opens keeps the focus.
- [x] When the cursor is on a button's row, the sidebar can give only the button the accent and leave the rest of the row plain.
- [x] When a row is a child, the sidebar can draw it on one line with its guide, status, name and dimmed program, and show a parent's waiting count after its name.
- [x] When a trackpad scrolls the sidebar sideways, the sidebar can return to its left edge, wherever the cursor is.
- [x] When an item with a menu is right-clicked, the sidebar can open the menu in place of Neovim's popup menu, with the cursor on the item, and report the action chosen in it.
- [x] When a row without a menu is right-clicked, the sidebar can open nothing.
