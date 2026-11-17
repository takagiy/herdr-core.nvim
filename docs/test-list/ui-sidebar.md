# ui/sidebar.lua

The sidebar window.

- [x] When given rows, the sidebar can draw headings, two-line terminal rows and counts with `HerdrCore` highlights.
- [x] When a space heading is drawn, the sidebar can show the folder's name instead of its full path.
- [x] When the user switches tabpages, the sidebar can stay on the same side and width.
- [x] When a new tabpage is opened from the sidebar window, the sidebar can appear in it beside the new window.
- [x] When the user presses Enter or clicks on a terminal row, the sidebar can report that terminal as chosen.
- [x] space 見出しで Enter を押したりクリックしたりしても、開閉せずアクションを発行しない。
- [x] When the user presses `n` on a row, the sidebar can report a new terminal for that row's space.
- [x] When a terminal is working, blocked, done or idle, the sidebar can show a different symbol for each.
- [x] When the user presses the rename key, the sidebar can ask for a name and report it for that terminal.
- [x] When the user presses the pin or unread key, the sidebar can report it for that terminal.
- [x] When the user clicks `«` at the bottom, the sidebar can collapse to a strip 2 to 3 columns wide.
- [x] When the sidebar is collapsed, it can show the waiting count at the top and `»` at the bottom.
- [x] When the user clicks `»`, the sidebar can expand again.
- [x] When the user sets other sidebar keys, the sidebar can use them in place of the defaults.
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

- [x] ユーザーが移動キーにアクションを割り当てた場合、移動より指定したアクションを優先する。

- [x] 下端のトグルを右端に表示し、リサイズ・折りたたみ後も表示されたボタンをクリックして開閉できる。
- [x] When rows include a Setup panel, the sidebar can draw it in a box above the toggle with its buttons in one column.
- [x] When the user moves with `j`/`k`, the sidebar can stop on Setup buttons, color the one under the cursor and press it with Enter.
- [x] When the sidebar is collapsed and something needs setting up, the sidebar can show `!` under the count.
- [x] When the sidebar is drawn, it can show a New terminal button under the header and report it when pressed with Enter or a click.
- [x] When the user moves with `j`/`k`, the sidebar can skip space headings, which have no button.
- [x] When the cursor is in the sidebar, the sidebar can give the row under it the selection background and its button the accent, while the terminal in front keeps its gray.
- [x] When the sidebar draws the New terminal button, the toggle and Setup buttons, it can give them all the same button background.
- [x] When the user clicks New terminal, the sidebar can act after the mouse button is released, so the picker it opens keeps the focus.
- [x] When the cursor is on a button's row, the sidebar can give only the button the accent and leave the rest of the row plain.
- [x] When a row is a child, the sidebar can draw it on one line with its guide, status, name and dimmed program, and show a parent's waiting count after its name.
