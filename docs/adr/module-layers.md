# core・adapter・ui を app がつなぐ 4 層に分け、core は state と event から新しい state と effect を返す

## 状況

判断（スペースの決め方、配置の同期、done の扱い、サイドバーの並び）を、Neovim と hc なしでテストしたい。Neovim の画面の操作と hc の呼び出しは、判断と混ぜたくない。

## 決定

- 4 つの層に分ける。

  | 層 | 役割 | 知ってよいもの |
  |---|---|---|
  | `core/` | 状態と判断 | 自分の state、event、effect の形だけ |
  | `adapter/` | 外部とのやりとり（hc、git、OS の通知）。判断はしない | hc などの外部 API |
  | `ui/` | Neovim の画面と操作。判断はしない | Neovim の API |
  | `app/` | 層をつなぐ | すべての層 |

- core は、state と event を受け取り、新しい state と effect の一覧を返す。入出力はしない。event と effect は、ただの Lua のテーブルにする。
  - event の例: `{ type = "foreground", terminal = "t1", cwd = "…", program = "claude" }`
  - effect の例: `{ type = "set_label", terminal = "t1", key = "herdr.space", value = "…" }`
- 外部の情報が要る判断は、core が「調べて」という effect を出し、結果を event で受け取る（例: cwd の repo root）。
- adapter は、hc の JSON を core の event の形に変換する。core は hc の形を知らない。
- ui は、Neovim のタブページとウィンドウを読んで core の配置の形にし、core が決めた配置を実際のウィンドウに反映する。キーとクリックは「どの行で何をしたか」の event にする。
- app は、adapter と ui からの event を core に渡し、返ってきた effect を adapter と ui に振り分けて実行する。

各層のファイル:

| 層 | ファイル | 中身 |
|---|---|---|
| core | `state.lua` | state の形と `update` |
| | `terminals.lua` | ターミナルの一覧（アドレス、名前、label、状態、turn、前面のプログラムと cwd、更新時刻） |
| | `spaces.lua` | repo root からスペースを決め、変わったら `herdr.space` を書く effect を出す |
| | `layout.lua` | 共有する配置の木、ファイルのウィンドウを除く処理、ほかの Neovim の変更の取り込み、doc の版 |
| | `attention.lua` | done と未読の判定、`herdr.seen` を書くか、通知するか |
| | `sidebar.lua` | サイドバーの行の一覧（木、並び順、ピン留め、待っている数、折りたたみ） |
| | `open.lua` | 開き方。差し替えられる形にする |
| adapter | `hc.lua` | `hc` の呼び出し（run、ls、label、doc.get / doc.set）と `hc events` の受信 |
| | `git.lua` | パスから repo root を求める |
| | `notifier.lua` | OS の通知。利用者が差し替えられる |
| ui | `terminal.lua` | `herdr://` のバッファーと `hc attach`、`BufReadCmd`、自動のターミナルモード |
| | `layout.lua` | Neovim の配置の読み取りと反映 |
| | `sidebar.lua` | 行の描画、キーとクリック、折りたたんだ帯 |
| | `focus.lua` | Neovim が前面にあるか、どのターミナルが表示されているか |
| | `prompt.lua` | 名前の入力など |
| | `highlights.lua` | `HerdrCore` のハイライトグループ |
| app | `init.lua` | `setup(config)`。層を組み立てて起動する |
| | `actions.lua` | 利用者がキーに割り当てるアクション。ui の event として core に渡す |
| | `loop.lua` | event を core に渡し、effect を振り分けて実行する |

## 結果

得たもの:

- 判断はすべて core にあり、テーブルを渡して返ってきたテーブルを確かめるだけでテストできる。
- adapter は偽の `hc` で、ui はヘッドレスの Neovim で、それぞれ変換と描画だけを確かめればよい。
- hc の API が変わっても、直すのは adapter だけで済む。

失ったもの:

- 外部の情報が要る判断は、effect と event の往復になり、直接呼ぶより手順が増える。
- event と effect の種類を、層の間の取り決めとして保つ必要がある。

## 採らなかった案

- 3 層（core、adapter、ui）だけにする。core は外部を知らず、ui と adapter は判断をしないので、event を core に渡して effect を実行する役の置き場がない。
- core が adapter や ui の関数を直接呼ぶ（関数を注入する）。core のテストに偽の関数が要り、呼んだ順番も確かめる必要が出る。
