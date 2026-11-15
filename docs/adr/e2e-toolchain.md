# E2E は mini.test と実際の端末プロセスを使い、状態変化も同じプロセスから発生させる

## 状況

[実際の hc を通す E2E の決定](e2e-with-real-hc.md) を実装するため、Neovim の操作、状態変化、環境分離、Linux CI の通知を動かす技術を決める。既存の mini.test と Neovim の機能を使い、同じ目的の実行基盤やテスト用プログラムを増やさない。

## 決定

### テストの実行と操作

テストの実行と操作には既存の Lua、EmmyLua、mini.test を使う。Neovim と mini.test の版はプロジェクトの指定に従う。dummy agent に限り Node.js を使い、テストフレームワークは追加しない。

- E2E は `tests/e2e/` に置く。mini.test の `collect.find_files` で収集対象を明示し、`mise run test` では除外、`mise run test-e2e` では E2E だけを実行する。初期化と結果出力は共通にする。
- `MiniTest.new_child_neovim()` で独立した Neovim を起動し、RPC で操作する。キーは `child.type_keys()`、マウスは `nvim_input_mouse()` を使い、mapping の関数を直接呼んで操作の代わりにしない。
- `hc attach` は製品コードと同じ terminal buffer の `jobstart(..., { term = true })` で起動する。headless の Neovim でも、端末ジョブには疑似端末を使える。別の TUI ラッパーや端末エミュレーターは追加しない。
- 合否は画面や buffer の文字、現在の window、配置、実際の `hc get/ls --json` と保存データで確認する。固定時間の sleep ではなく、制限時間付きで期待する状態を待つ。
- 実装の最初に、実際の attach を通した入力と出力を確認する。`--observe` やプロセスの起動成功だけを、対話的な attach の成功とは扱わない。

根拠: [mini.test の子 Neovim と収集設定](https://nvim-mini.org/mini.nvim/doc/mini-test.html)、[Neovim の jobstart](https://neovim.io/doc/user/builtin/#jobstart())、[hc attach の端末確認](https://github.com/herdrdev/herdr-core/blob/c84d6e76156a6c2aac1da20efbe800f10acfe897/crates/herdr-core/src/attach.rs#L158)。

### Node.js で共通の dummy agent を書く

herdr の terminal 内で harness の代わりに動く、認証不要の dummy agent を Node.js で書く。標準 API だけを使う単一の JavaScript スクリプトとし、npm パッケージ、TypeScript のビルド、別のテスト用ランタイムは追加しない。Node.js は開発・E2E 用の依存として mise で管理し、プラグインの利用者には要求しない。

attach を通して入力を送り、その入力に応じて文字列の出力と OSC 7501 の状態報告を行わせる。`working`、`blocked`、`done` を順に報告し、その都度 hc とプラグインの結果を確かめる。入力・出力と状態変化はこの1つの dummy agent にまとめ、同じ目的の Bash や Python の実装は持たない。

これは hc が公開する Program Status Protocol を実際のプロセスから出力する方式であり、状態変更 RPC や偽のイベント生成器は追加しない。既定シェルを新規起動する製品の利用経路自体は、実際のシェルで検証する。

調査した上流の `fake_tui.py` は `termios` と `tty` に依存し、そのままでは Windows で使えない。両 OS で使える配布済みの `hc-lab` も確認できなかったため、既存ツールの移植は選ばない。

根拠: [Program Status Protocol の公式説明](https://herdr.dev/core/)、[状態の受信処理](https://github.com/herdrdev/herdr-core/blob/c84d6e76156a6c2aac1da20efbe800f10acfe897/crates/herdr-core/src/status.rs)。

### hc と作業環境を分離する

実行ごとに一意な `HC_SESSION` と一時ディレクトリを作る。`XDG_STATE_HOME`、`XDG_CONFIG_HOME`、`XDG_DATA_HOME`、`XDG_CACHE_HOME`、`NVIM_APPNAME` を専用の値にし、Linux では短い専用パスの `XDG_RUNTIME_DIR` を作って権限を `0700` にする。同期テストの2つの Neovim は、この環境を共有する。

親セッションの接続先や所属を引き継がないよう、`HC_SOCKET`、`HC_TERMINAL_ID`、`HC_TERMINAL_SOCKET`、`HC_SCOPE` を取り除く。終了処理は作成した専用プロセスだけを対象とする。通常の hc を更新・再起動してテストの準備に使わない。

根拠: [hc のパス解決](https://github.com/herdrdev/herdr-core/blob/c84d6e76156a6c2aac1da20efbe800f10acfe897/crates/herdr-core/src/paths.rs#L15)、[セキュリティと保存先](https://github.com/herdrdev/herdr-core/blob/master/docs/security.md)。

### Linux の通知には実際の通知サービスを使う

GitHub Actions の Linux runner に `dbus`、`xvfb`、`xauth`、`dunst`、`libnotify-bin` を用意する。`dbus-run-session` で専用のバス、`xvfb-run` で仮想画面を起動し、その中で dunst と E2E を動かす。デスクトップ環境や window manager は導入しない。

プラグインの既定の `notify-send` を実行し、その終了結果を確認する。dunst の `--print` による受信ログも失敗調査に保存する。通知コマンドや通知サービスを mock に置き換えない。実際のデスクトップで通知が見えたことの保証は対象外とする。

根拠: [dbus-run-session の分離](https://dbus.freedesktop.org/doc/dbus-run-session.1.html)、[dunst の設定と受信ログ](https://dunst-project.org/documentation/dunst/)。

### hc の取得と失敗調査

CI は [公式 latest.json](https://releases.herdr.dev/core/latest.json) を実行開始時に一度取得し、対象 OS の配布物と SHA-256 を解決する。検証してから専用ディレクトリに展開し、そのバイナリを使う。版とチェックサムを記録し、同じ実行の途中では更新しない。Windows では同梱の ConPTY も保持する。

GitHub Actions の `schedule` と `workflow_dispatch` を使い、記録した版・画面・ログは artifact に保存する。通常のテスト結果とは分ける。動作確認済み版での比較と任意の trace の範囲は、先の ADR に従う。

画面には `child.get_screenshot()` を使い、文字と属性の記録として保存する。任意の trace を追加する場合も、この画面取得と操作内容・時刻の記録を使い、動画用の別基盤は導入しない。

## 結果

得たもの:

- 通常テストと同じ言語・実行基盤で、実際の Neovim、hc、プログラムを通せる。
- 1つの JavaScript スクリプトで入出力と状態報告を記述でき、コンパイルや npm パッケージが不要になる。
- 普段の環境から分離し、Linux CI でも実際の通知コマンドを実行できる。

失ったもの:

- E2E 用に Node.js と dummy agent の保守が必要になる。Linux CI には通知用の追加パッケージも必要になる。
- 実際の agent の認証・モデル応答・独自の hook は検証しない。検証するのは公開プロトコルからプラグインまでの経路になる。
- この選定はソースと文書に基づく。Linux の attach 入出力と通知構成の一連の実行は、最初の実装で成立を確かめる必要がある。

## 採らなかった案

- 別のテストフレームワークや Python 製の画面操作基盤。既存の mini.test と RPC で必要な操作を行える。
- Neovim 全体を別の TUI や疑似端末で包む。まず製品と同じ terminal buffer を使い、端末要件をそこで満たす。
- Bash で dummy agent を書く。短い出力だけなら十分だが、入力に応じた状態変化を増やす際の読み書きと OS 間の差を避けるため採らない。
- Python で dummy agent を書く。実現可能だが、利用者が好む Node.js に統一し、ランタイムを増やさない。
- Unix 専用の dummy agent を Windows 向けに移植する。Node.js の標準 API と公開プロトコルで必要な経路を記述する。
- 通知コマンドを成功だけ返すスクリプトに差し替える。実際の通知機構まで通す要件を満たさない。
