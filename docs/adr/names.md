# 名前は herdr-core.nvim とし、Lua では herdr-core、バッファーは herdr:// を使う

## 状況

GitHub で公開し、lazy.nvim などで入れられるようにする。herdr TUI 向けの Neovim プラグインがすでに 3 つあり（devxplay/herdr.nvim、ChmaraX/herdr-nvim、lmilojevicc/herdr-splits.nvim）、`hc.nvim` も使われている。Lua のモジュール名がほかのプラグインとぶつかると、同時に入れたときに壊れる。

## 決定

| 対象 | 名前 |
|---|---|
| リポジトリ | `herdr-core.nvim`。README の冒頭に非公式と書く |
| Lua モジュール | `require("herdr-core")` |
| ターミナルのバッファー | `herdr://<名前>`。名前がなければアドレス（`herdr://t1`）、ほかのマシンは `herdr://vps/t7` |
| ハイライトと autocmd のグループ | `HerdrCore` で始める（例: `HerdrCoreWorking`） |
| hc の doc | `herdr-core-nvim`。doc の名前はターミナル名と同じ規則（小文字の英字、数字、`-`、`_` で 1〜32 文字）で、`.` を使えない |
| 自分用の label | `herdr-core-nvim.` で始める（例: `herdr-core-nvim.name`）。Herdr のクライアントで共有する `herdr.` とは分ける |
| hc の API をそのまま呼ぶコマンド | 作る場合は `:Hc <サブコマンド>`。作るかは未定 |

## 結果

得たもの:

- herdr TUI 向けのプラグインと区別でき、同時に入れてもぶつからない。
- herdr-core の利用者が「herdr-core nvim」で探したときに見つかる。

失ったもの:

- 公式の名前をそのまま使うので、公式のプラグインに見えるおそれがある。README の非公式の表記で補う。

## 採らなかった案

- `hc.nvim` / `require("hc")`: 短いが、すでに使われている。
- `herdr.nvim` / `require("herdr")`: herdr TUI 向けと誤解される。`herdr` は devxplay/herdr.nvim のモジュール名と同じ。
- バッファー名 `hc://`: いったん決めたが、`herdr://` に変えた。
- 接頭辞 `Herdr`: herdr TUI 向けのプラグインと重なるおそれがある。
