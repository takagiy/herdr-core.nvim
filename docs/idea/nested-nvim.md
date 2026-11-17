# 候補: ネストの防止は flatten.nvim などに任せ、herdr-core.nvim は `$NVIM` の宛先だけを用意する

## きっかけ

herdr のターミナルのシェルで `nvim` を起動すると、Neovim の中に Neovim がネストして、画面が崩れる。

Neovim の `:terminal` では、[flatten.nvim](https://github.com/willothy/flatten.nvim) などのプラグインがこれを防ぐ。内側の nvim が環境変数 `$NVIM` を読み、そのアドレスの Neovim にファイルを送る。

herdr のターミナルでは、この `$NVIM` が正しくない。シェルは Neovim ではなく hc の core の子プロセスなので、`$NVIM` は core を起動したときの値を受け継ぐ。2026-11-17 に確認したターミナル `t1m` では、`$NVIM` は 5:44 に起動した Neovim（PID 18072）を指していた。そのとき Neovim は 7 つ動いていた。

エージェントが編集しているファイルを隣に表示したい、というニーズは別に扱う。

## 案

ファイルを外側の Neovim で開く動作（開く場所、終了を待つかどうか、オプションの扱い）は、flatten.nvim などに任せる。herdr-core.nvim は、herdr のターミナルの `$NVIM` が、そのターミナルを表示している Neovim に届くようにする。

- `$NVIM` には、特定の Neovim ではなく固定のアドレスを入れる。Neovim を再起動しても、別の Neovim を開いても効き続ける。
- 宛先は、そのターミナルのウィンドウに最後にカーソルがあった Neovim。どの Neovim も表示していなければ接続できず、flatten.nvim は普通に nvim をネストして起動する。
- アドレスに届いた要求は、すべて宛先の Neovim に渡す。`nvim --server "$NVIM" --remote` など、flatten.nvim 以外のツールも、Neovim に直接つないだときと同じに動く。
- 効くのは、この機能を入れたあとに herdr-core.nvim が開いたターミナルと、その中でエージェントが `hc run` で起動した子ターミナル。PC の再起動後に hc が起動し直したターミナルでも効く。
- すでに動いているターミナル、Herdr アプリや `hc run` で直接起動したターミナル、Neovim の `:terminal` は対象外。環境変数はプロセスの起動時に決まり、あとから変えられない。
- 既定で有効にし、`setup()` の設定で無効にできる。無効のときは、新しいターミナルの `$NVIM` を空にする。エージェントから受け継いだ `CLAUDECODE` などを空にしているのと同じ扱い（[`inherited`](https://github.com/takagiy/herdr-core.nvim/blob/8ce0a61e7e16509a53f051856c43747bdce623fd/lua/herdr-core/adapter/hc.lua#L171-L176)）。設定の名前は未定。

## この案で諦めること

flatten.nvim に任せると、次の点は flatten.nvim の動作に従う。herdr-core.nvim で自前で作る案では、括弧内の動作にすると決めていた。

- `:cq` で `git commit` を取りやめられない。flatten.nvim の内側の nvim は、常に `:qa!` で終了コード 0 で終わる（[`maybe_block`](https://github.com/willothy/flatten.nvim/blob/d92ca41e9c330f45c1b854a80c89c8488a9d730c/lua/flatten/guest.lua#L10-L28)）。外側で打った `:cq` は、外側の Neovim 全体を終了させる。（自前の案: ターミナルに戻り、`nvim` コマンドは 0 以外の終了コードで終わる）
- `E37` で拒否された `:q` でも、内側の nvim の待機が終わる。flatten.nvim は `QuitPre` で待機の終了を伝えるが（[`notify_when_done`](https://github.com/willothy/flatten.nvim/blob/d92ca41e9c330f45c1b854a80c89c8488a9d730c/lua/flatten/core.lua#L40-L51)）、Neovim 0.11.7 では `:q` が拒否されたときにも `QuitPre` が起きる。（自前の案: 実際に閉じるまで待つ）
- 起動ごとのファイルのグループがない。（自前の案: 起動ごとに、ウィンドウ専用の引数リスト `:arglocal` を作る）

## 未決

- 本当にネストして起動したいときの指定方法（例: 環境変数 `HERDR_CORE_NVIM_NEST=1`）
- README で flatten.nvim をどう案内するか
