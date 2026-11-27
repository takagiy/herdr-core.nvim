# テストは mini.test で書き、core・adapter・ui のすべての層に使う

## 状況

テストの対象は、層によって性質が違う。core はテーブルの入出力、adapter は偽の `hc` との変換、ui はヘッドレスの Neovim でのバッファー、キー、マウス、描画を確かめる。開発は Windows で行う。

## 決定

- テストは [mini.test](https://github.com/nvim-mini/mini.test) で書き、3 つの層すべてに使う。
- ui のテストは、子の Neovim を RPC で操作する。

## 結果

得たもの:

- 1 つの仕組みで、3 つの層をテストできる。
- ui のテストは本物の Neovim で動く。子の Neovim で失敗しても、テストを動かしている側は止まらない。
- luarocks も C コンパイラも要らない。

失ったもの:

- テストを動かすのに Neovim が要る。core のテストも、Neovim の中で動く。

## 採らなかった案

- plenary.nvim のテスト: 保守を終えて、近くアーカイブすると書かれている。
- vusted: アーカイブされている。
- busted を `nvim -l` や nlua で動かす: luarocks が要り、Windows では C コンパイラも要る。画面を確かめる手段がない。
- lewis6991/nvim-test: luarocks が要る。
