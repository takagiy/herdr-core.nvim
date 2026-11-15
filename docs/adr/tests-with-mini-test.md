# テストは mini.test で書き、core・adapter・ui のすべての層に使う

## 状況

テストの対象は、層によって性質が違う。

- core: テーブルを渡して、返ってきたテーブルを確かめる。
- adapter: 偽の `hc` を相手に、呼び出しと変換を確かめる。
- ui: ヘッドレスの Neovim で、ターミナルのバッファー、キー入力、マウスのクリック、サイドバーの描画を確かめる。

開発は Windows で行い、CI は Linux と macOS でも動かす。

## 決定

- テストは [mini.test](https://github.com/nvim-mini/mini.test) で書き、3 つの層すべてに使う。
- テストファイルは Lua で書く。型検査の設定は、テストにも同じものを使う。
- ui のテストは、子の Neovim（`MiniTest.new_child_neovim()`）を RPC で操作する。キーは `child.type_keys()` で送り、描画は `expect.reference_screenshot()` で保存済みの画面と比べる。
- テストは `nvim --headless` から `MiniTest.run()` で動かし、`mise run test` から呼ぶ。mini.test は版を固定して取得する。

## 結果

得たもの:

- 1 つの仕組みで、3 つの層をテストできる。
- ui のテストは本物の Neovim で動くので、ターミナルのバッファーや画面がそのまま確かめられる。子の Neovim で失敗しても、テストを動かしている側は止まらない。
- luarocks も C コンパイラも要らない。Windows 対応が README に書かれている。

失ったもの:

- テストを動かすのに Neovim が要る。core のテストも、Neovim の中で動く。
- 子の Neovim が固まると、そのテストは止まる。
- ターミナルのバッファーとマウスのクリック（`nvim_input_mouse`）を Windows でテストできるかは、まだ試していない。

## 採らなかった案

- plenary.nvim のテスト: README に、保守を終えて近くアーカイブすると書かれている。
- vusted: アーカイブされている。
- busted を `nvim -l` や nlua で動かす: luarocks が要り、Windows では C コンパイラも要る。画面を確かめる手段がない。
- lewis6991/nvim-test: Neovim 本体のテストと同じ画面の確かめ方ができるが、luarocks が要る。mini.test の画面の比較で足りなかったときに考える。
