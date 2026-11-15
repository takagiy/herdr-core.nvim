# herdr-core.nvim

A TUI client for [herdr-core](https://github.com/herdrdev/herdr-core), built on Neovim.

## Requirements

- Neovim 0.11 or later
- `hc` on your PATH
- Git

## Usage

The sidebar lists terminal sessions in herdr-core, grouped by working directory.

- On a project's row, press Enter or click to fold or unfold it.
- On a project's row, press `n` or click `+` to start a terminal session there.
- On a terminal session's row, press Enter or click to open it.
- On a terminal session's row, press `r` to name it, `p` to pin it, or `u` to mark it unread.
- At the bottom of the sidebar, click `«` to toggle it.

## Installation

With lazy.nvim:

The plugin maps no keys by itself. The `setup({ ... })` below shows defaults.

```lua
{
    "takagiy/herdr-core.nvim",
    lazy = false,
    config = function()
        local app = require("herdr-core").setup({
            -- Enter terminal mode when the cursor moves into a terminal window.
            auto_insert = true,
            -- Width of the sidebar.
            sidebar_width = 32,
            -- Keys inside the sidebar.
            sidebar_keys = {
                activate = "<CR>",
                new_terminal = "n",
                rename = "r",
                pin = "p",
                unread = "u",
            },
            -- Called as notify(name, status) when a terminal needs you.
            notify = function(name, status)
                ...
            end,
        })
        if not app.actions then return end
        vim.keymap.set({ "n", "t" }, "<leader>ht", app.actions.new_tab)
        vim.keymap.set({ "n", "t" }, "<leader>hv", app.actions.new_vertical)
        vim.keymap.set({ "n", "t" }, "<leader>hs", app.actions.new_horizontal)
        vim.keymap.set({ "n", "t" }, "<leader>hb", app.actions.toggle_sidebar)
        vim.keymap.set({ "n", "t" }, "<leader>hf", app.actions.focus_sidebar)
    end,
}
```
