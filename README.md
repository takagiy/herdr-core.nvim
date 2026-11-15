# herdr-core.nvim

herdr-core (`hc`) の非公式 Neovim クライアントです。ターミナルの表示、プロジェクト別のサイドバー、配置の保存・同期を提供します。

## 設定

Neovim 0.11 以降と、PATH 上の `hc`、Git が必要です。lazy.nvim の例です。

```lua
{
    "takagiy/herdr-core.nvim",
    lazy = false,
    config = function()
        local app = require("herdr-core").setup()
        if not app.actions then return end
        vim.keymap.set({ "n", "t" }, "<leader>ht", app.actions.new_tab)
        vim.keymap.set({ "n", "t" }, "<leader>hv", app.actions.new_vertical)
        vim.keymap.set({ "n", "t" }, "<leader>hs", app.actions.new_horizontal)
        vim.keymap.set({ "n", "t" }, "<leader>hb", app.actions.toggle_sidebar)
        vim.keymap.set({ "n", "t" }, "<leader>hf", app.actions.focus_sidebar)
    end,
}
```

グローバルキーは自動では設定しません。`setup()` は `actions`、状態を返す `state()`、購読とUIを終了する `stop()` を返します。ウィンドウを閉じても、hc 内のプログラムは動き続けます。

サイドバーでは Enter またはクリックで開き、見出しなら折りたたみます。`n` または見出しの `+` でシェルを起動し、`r` で名前の変更、`p` でピン留め、`u` で未読に戻します。下端のボタンでサイドバー全体を折りたためます。

`setup({ auto_insert = false, sidebar_width = 28 })` のように設定します。`sidebar_keys` で `activate`、`new_terminal`、`rename`、`pin`、`unread` のキーを変更できます。`notify = function(name, status) ... end` で通知方法を差し替えられます。

## 開発

```sh
mise install
mise run test
mise run check
mise run fmt-check
```

`mise run fmt` で整形します。mini.test は初回に取得します。

対話画面での attach、OS 通知の表示、リモート接続は統合テストでは未検証です。
