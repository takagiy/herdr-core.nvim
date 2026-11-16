# herdr-core.nvim

A TUI client for [herdr-core](https://github.com/herdrdev/herdr-core), built on Neovim.

## Requirements

- Neovim 0.11 or later
- `hc` on your PATH
- Git

## Usage

The sidebar groups terminal sessions into spaces by Git repository root, or by working directory outside a repository.

- Press `j`/`k` or `Up`/`Down` to move between items.
- On a space's row, press `n` or click `+` to start a terminal session there.
- On a terminal session's row, press Enter or click to open it.
- On a terminal session's row, press `r` to name it, `p` to pin it, or `u` to mark it unread.
- Click `«` at the bottom right to collapse the sidebar, or `»` to expand it.

Closing a terminal window leaves its session running in herdr-core. Terminal layouts are restored when Neovim restarts and synchronized between Neovim instances.

## Restoring after a reboot

Terminals opened from the plugin come back after a reboot as shells in the same place. Agent conversations come back too, once the agent's integration is installed: when Claude Code or Codex is set up on this machine, the sidebar shows a Setup panel to install it.

The integration adds a hook to the agent's settings (`~/.claude/settings.json`, or `~/.codex/hooks.json` and `config.toml`). The hook labels its hc terminal with `herdr-core-nvim.agent` (the integration's name) and `herdr-core-nvim.session` (the conversation id), and clears both when the conversation ends. When Neovim starts and finds those labels on a terminal whose agent no longer runs, it types the integration's resume command there.

To change a built-in integration or add one, pass `integrations` to `setup`. Fields you give replace the built-in ones; `false` turns one off.

```lua
local integrations = require("herdr-core.integrations")
require("herdr-core").setup({
    integrations = {
        claude = { resume_command = function(id) return "claude --resume " .. id .. " --model opus" end },
        codex = false,
        mycli = {
            directory = integrations.directory({ env = "MYCLI_HOME", path = "~/.mycli" }),
            install = {
                integrations.hooks({ file = "settings.json", events = { started = "SessionStart", ended = "SessionEnd" } }),
            },
            resume_command = function(id) return "mycli --resume " .. id end,
            matches_program = integrations.program({ "mycli" }),
        },
    },
})
```

See [docs/adr/integrations.md](docs/adr/integrations.md) for the helpers and the hook script's arguments.

## Installation

With lazy.nvim:

The plugin maps no global keys. This example uses the default sidebar settings.

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

Notifications use your OS notification service by default.
