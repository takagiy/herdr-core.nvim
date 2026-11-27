# 型注釈付きの Lua で書き、型検査とフォーマットに EmmyLua の toolchain を使う

## 状況

静的型付けで書きたい。プラグインは、lazy.nvim でそのまま入れられる Lua として公開する。開発は Windows で行う。

Neovim は、自分の API の型注釈を同梱している。EmmyLua の toolchain（[emmylua-analyzer-rust](https://github.com/EmmyLuaLs/emmylua-analyzer-rust)）は、この注釈を読む型検査、フォーマッター、言語サーバーを、各 OS 向けのビルド済みのバイナリで配っている。

## 決定

- LuaJIT 向けの普通の Lua に、型注釈を付けて書く。
- 型検査は `emmylua_check` で、警告も失敗にする。設定はできるだけ厳しくする。
- フォーマットは `luafmt` で行う。

## 結果

得たもの:

- 生成されたファイルがなく、書いた Lua がそのまま公開される。エラーのスタックトレースも、書いた行を指す。
- Neovim の API の型を、Neovim 自身の注釈で検査できる。
- 型検査、フォーマット、エディタの補完が、1 つの toolchain と設定で揃う。

失ったもの:

- 型は段階的で、すべては検査されない。`any` を禁止する診断はない。
- 型検査に Neovim の runtime が要る。
- `luafmt` は StyLua より新しく、使っている人が少ない。

## 採らなかった案

- TypeScriptToLua: 型は最も厳しいが、Neovim の型定義が古いまま止まっていて、自分で保守することになる。生成された Lua をリポジトリに入れる必要がある。
- Teal: Neovim の型定義が不完全で、nil をどの型にも許す。
- Luau（darklua で Lua 5.1 に変換）: Neovim の型定義がなく、使っているプラグインも見つからなかった。
- `lua-language-server --check`: 問題があったときに 0 以外で終わるかを確かめられなかった。
- StyLua: 型検査とは別の道具と設定になる。
