# エージェントごとの差は Lua の integration の定義にまとめ、フックは nvim -l の共通スクリプトで動かす

## 状況

会話の再開には、各エージェントの設定にフックを入れる必要がある（[再起動後の復元](restore-after-reboot.md)）。入れ方はエージェントごとに違う。

- claude、codex、gemini などは、設定ファイル（JSON）にフックのコマンドを書く。codex は `config.toml` の `[features] hooks = true` も要る。
- pi、omp、opencode などは、拡張のファイル（JavaScript／TypeScript）を置く。
- フックが受け取る JSON で、会話 ID の項目名が違う（`session_id`、`sessionId`、`conversation_id`、`conversationId`）。grok は環境変数で受け取り、antigravity は標準出力に JSON を返す必要がある。
- codex のフックは、親の codex の会話 ID を `CODEX_THREAD_ID` で受け継ぐ。一番上の codex では空で、codex の中から起動した codex では親の ID が入る（`codex exec` で確かめた）。

Herdr TUI はこれらを Rust と、エージェントごとの sh／PowerShell のスクリプトで扱っている。

## 決定

- integration は、名前をキーにした Lua の表で定義する。組み込みの定義も同じ形で書き、`setup({ integrations = { ... } })` で渡した表を重ねる。項目を書けばその項目だけ置き換わり、`false` で無効にする。
- 1 つの定義は次の項目を持つ。
  - `directory()`: 設定フォルダーの絶対パス。エージェントが入っていなければ `nil`。`integrations.directory({ env, path })` は、環境変数が空でなければその値、なければ `path` を使うヘルパー。
  - `install`: 手順 `{ check(context), apply(context) }` のリスト。`check` は `installed`、`outdated`、`missing` のどれかを返し、何も書き込まない。`apply` は失敗したら `error` を投げる。全体の状態は、手順のうち一番悪いもの。
  - `resume_command(id)`: シェルに打ち込む 1 行。
  - `matches_program(program)`: 前面のプログラム `{ app, name, argv }` がこのエージェントなら `true`。`app` はエージェントが hc に報告した名前。`integrations.program({ 名前, ... })` は、デスクトップアプリと同じ見分け方で作るヘルパー。`app` を先に見て、なければ `node` などのインタープリターを飛ばしたスクリプト名か、プログラム名（`.exe` を除く）を比べる。見分け方そのものは `integrations.identify(program)` として公開する。
- `context` は `{ directory, hook_command(event, opts) }`。`hook_command` は `nvim -l <stdpath("data")>/herdr-core/session-hook.lua <名前> --event started|ended` に `opts` の引数を足して返す。イベントの名前は、Lua のキーワード `end` とぶつからないよう `started` と `ended` にする。スクリプトは、プラグインが起動のたびにこの場所へコピーする。
- スクリプトの引数で、エージェントごとの差を吸収する。
  - `--id <項目名>`: 会話 ID を探す項目。省略すると `session_id`、`sessionId`、`conversation_id`、`conversationId` の順。
  - `--id-env <環境変数>`: 空でなければ、JSON より先にその値を会話 ID にする。
  - `--parent-id-env <環境変数>`: 値があって会話 ID と違えば、何もしない。
  - `--reply <文字列>`: 終わるときに標準出力へ書く。
- 組み込みのヘルパーは 3 つ。
  - `hooks{ file, events = { started = ..., ended = ... }, script? }`: 設定ファイルの `hooks.<イベント名>` にコマンドを足す。`<スクリプト> <名前>` を含むコマンドを自分のものと見なし、まったく同じなら `installed`、違えば `outdated` として置き換える。`script` で自作のスクリプトに差し替えられる。
  - `file{ path, source }`: 拡張のファイルを置く。中身はテンプレートにして `hook_command` を埋め込む。中身が同じなら `installed`、違えば `outdated`。
  - `toml{ file, set }`: キーに値を書く。行単位で書き換える。
- 組み込みでは、Herdr TUI が会話の再開に対応しているエージェントのうち、letta と devin 以外に対応する。この 2 つは、利用者が `script` で自作のスクリプトを指定する。自作のスクリプトのために、2 つのラベル（`herdr-core-nvim.agent`、`.session`）の名前と値を公開する。

## 結果

得たもの:

- エージェントを足すのも、再開コマンドを変えるのも、`setup` の表に書くだけで済む。
- フックの処理は Lua のスクリプト 1 本で、Windows と Mac で同じものが動く。テストもプラグインのテストと一緒に書ける。
- 引数が変われば `outdated` になるので、古いフックが残らない。

失ったもの:

- フックの実行に `nvim` の起動（数十ミリ秒）がかかる。会話の開始と終了のときだけなので問題にしない。
- `NVIM_APPNAME` を変えるとスクリプトの場所が変わり、古いコマンドが自分のものと見なされずに残る。
- `toml` は TOML を完全には解析しないので、変わった書き方の設定ファイルでは失敗することがある。
- ラベルの名前と値の形が公開の API になり、変えにくくなる。

## 採らなかった案

- 定義を関数で受け取って書き換える。組み込みの定義の中身が、そのまま公開の API になる。
- 使う integration をリストで並べる。1 つ書くと、書かなかった組み込みが全部使われなくなる。
- 検出を、コマンドが PATH にあるかで判断する。検出もファイルとフォルダーにそろえる。
- 状態を、入れた記録と定義の `version` で判断する。`version` を上げるのが面倒。
- 状態の確かめ方を、手順と別に integration ごとに 1 つ持つ。組み込みのヘルパーが手順ごとに確かめる処理を持つことになり、結局同じになる。
- エージェントごとに sh と PowerShell のスクリプトを用意する（Herdr TUI と同じ）。同じ処理を 2 つの言語で持つことになる。
- 拡張から `hc label` を直接実行する。ラベルの扱いが Lua のスクリプトと拡張に散らばる。
- 自作のスクリプトには、会話 ID を取り出す部分だけを任せる。何でもできるほうを選んだ。
- 再開コマンドを配列で受け取り、プラグインがシェルに合わせて引用符を付ける。シェルの種類を判断する処理が要る。
- ほかのマシンにも、`hc file write --on` でフックを入れる。いまはほかのマシンをつないでいない。必要になったら、`context` にファイルを読み書きする関数を足す。
