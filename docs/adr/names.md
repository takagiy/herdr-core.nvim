# 名前は herdr-core.nvim とし、Lua では herdr-core、hc に書くものは herdr-core-nvim を使う

## 状況

herdr TUI 向けの Neovim プラグインがすでにあり（devxplay/herdr.nvim など）、`hc.nvim` も使われている。Lua のモジュール名がほかのプラグインとぶつかると、同時に入れたときに壊れる。

Herdr のクライアント（デスクトップアプリ、スマートフォンアプリ）は、`herdr.` で始まる label で状態を共有している。

## 決定

- リポジトリは `herdr-core.nvim`、Lua のモジュールは `herdr-core`、ターミナルのバッファーは `herdr://`。
- このプラグインだけが使う label は `herdr-core-nvim.` で始める。Herdr のクライアントと共有する `herdr.` とは分ける。
- hc の doc の名前は `herdr-core-nvim`。doc の名前には `.` を使えない。

## 結果

得たもの:

- herdr TUI 向けのプラグインと同時に入れても、ぶつからない。
- Herdr のクライアントが、このプラグインの label を自分のものと取り違えない。

失ったもの:

- 公式の名前をそのまま使うので、公式のプラグインに見えるおそれがある。README の非公式の表記で補う。

## 採らなかった案

- `hc.nvim` / `require("hc")`: すでに使われている。
- `herdr.nvim` / `require("herdr")`: herdr TUI 向けと誤解され、devxplay/herdr.nvim のモジュール名とぶつかる。
