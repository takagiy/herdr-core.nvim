# 型注釈付きの Lua で書き、型検査とフォーマットに EmmyLua の toolchain を使う

## 状況

静的型付けで書きたい。プラグインは、lazy.nvim でそのまま入れられる Lua として公開する。開発は Windows で行い、CI は Linux と macOS でも動かす。

Neovim は、自分の API の型注釈を `runtime/lua/vim/_meta` に同梱している。EmmyLua の toolchain（[emmylua-analyzer-rust](https://github.com/EmmyLuaLs/emmylua-analyzer-rust)）は、この注釈を読む型検査（`emmylua_check`）、フォーマッター（`luafmt`）、言語サーバー（`emmylua_ls`）を、Windows を含む各 OS 向けのビルド済みのバイナリで配っている。

## 決定

- LuaJIT 向けの普通の Lua に、`---@class` や `---@param` の型注釈を付けて書く。
- 型検査は `emmylua_check --warnings-as-errors .` で行い、CI で警告も失敗にする。エディタでは `emmylua_ls` が同じ設定を読む。
- 設定（`.emmyrc.json`）は、できるだけ厳しくする。
  - 引数か戻り値のある関数は、すべての引数に `@param`、返すすべての値に `@return` が要る（`incomplete-signature-doc` をエラーにする）。グローバル関数は、引数がなくても注釈が要る（`missing-global-doc` をエラーにする）。
  - 既定ではヒントの診断（`unused`、`unreachable-code`、`deprecated`、`redefined-local`、`duplicate-require`）もエラーにする。
  - `strict` の `requirePath`、`typeCall`、`arrayIndex` を有効にし、`docBaseConstMatchBaseType` を無効にする。
  - Neovim API の型は `workspace.library` の `{env:VIMRUNTIME}/lua` から読む。
- フォーマットは `luafmt` で行う。設定（`.luafmt.toml`）をリポジトリに入れ、CI で `luafmt . --check` を動かす。
- 道具は GitHub Releases のビルド済みのバイナリを使い、版を固定する（決めた時点の最新は 0.25.1）。

## 結果

得たもの:

- 生成されたファイルがなく、書いた Lua がそのまま公開される。エラーのスタックトレースも、書いた行を指す。
- Neovim 0.11 の API の型を、Neovim 自身の注釈で検査できる。
- 型検査、フォーマット、エディタの補完が、1 つの toolchain と設定で揃う。

失ったもの:

- 型は段階的で、すべては検査されない。ローカル変数は推論に任せ、`@param x any` や明示的な型変換は通る。`any` を禁止する診断はない。
- CI で Neovim を入れ、`VIMRUNTIME` を設定する必要がある。
- `luafmt` は、Neovim のプラグインで広く使われている StyLua より新しく、使っている人が少ない。
- `vim._meta` がこの厳しい設定で問題を出さないかは、まだ試していない。

## 採らなかった案

- TypeScriptToLua: 型は最も厳しいが、Neovim の型定義が 2021〜2023 年で止まっていて、自分で保守することになる。生成された Lua をリポジトリに入れる必要があり、開発に Node が要る。
- Teal: Neovim の型定義が不完全で、nil をどの型にも許す。
- Luau（darklua で Lua 5.1 に変換）: Neovim の型定義がなく、使っているプラグインも見つからなかった。
- `lua-language-server --check`: 問題があったときに 0 以外で終わるかを確かめられなかった。
- StyLua: 広く使われているが、型検査とは別の道具と設定になる。
