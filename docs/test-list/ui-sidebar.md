# ui/sidebar.lua

The sidebar window.

- [x] When given rows, the sidebar can draw headings, two-line terminal rows and counts with `HerdrCore` highlights.
- [x] When a space heading is drawn, the sidebar can show the folder's name instead of its full path, so that `+` stays in view.
- [x] When the user switches tabpages, the sidebar can stay on the same side and width.
- [x] When a new tabpage is opened from the sidebar window, the sidebar can appear in it beside the new window.
- [x] When the user presses Enter or clicks on a terminal row, the sidebar can report that terminal as chosen.
- [x] When the user presses Enter or clicks on a heading, the sidebar can report the heading as folded or unfolded.
- [x] When the user presses `n` on a row or clicks a heading's `+`, the sidebar can report a new terminal for that row's space.
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
- [x] ヘッダーとプロジェクト見出しの太字、開閉記号、プロジェクト間の余白で階層を表示する。

- [x] 別ウィンドウからの1回のクリックで、サイドバーの項目を操作する。
- [x] サイドバーの外をクリックすると、標準のマウス操作でそのウィンドウに移動する。
- [x] 既存のグローバルマウスマッピングを残したまま、項目の操作を1回だけ実行する。
- [x] サイドバーを閉じると、マウス入力の監視を解除する。
- [x] 開閉記号・待機件数・日本語を含む見出しでも、表示された + をクリックしてターミナルを起動する。

- [x] 選択中のterminalが属するspaceの見出しを、通常と異なる全幅の背景色で表示する。

- [x] ユーザーが移動キーにアクションを割り当てた場合、移動より指定したアクションを優先する。
