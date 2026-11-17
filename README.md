# herdr-core.nvim

A TUI client for [herdr-core](https://github.com/herdrdev/herdr-core), built on Neovim.

![The sidebar lists agent sessions by repository next to a Claude Code session and the file it is reading](docs/screenshot.png)

## Features

- A sidebar groups sessions into spaces by Git repository or working directory, automatically tracking `cd`.
- Shows each agent's status icon in the sidebar.
- Sends OS notifications when an agent needs you or finishes.
- Restores terminal layouts when Neovim restarts.
- Automatically resumes agent conversations after a reboot.
- Built-in integrations for Claude Code, Codex, Antigravity CLI, Copilot CLI, Cursor CLI, Droid, Grok, Kilo Code, Mastra Code, omp, opencode, pi, Qoder CLI and Qwen Code. You can [write your own](#custom-integrations).

## Usage

| Input | Action |
| --- | --- |
| `j`, `k` / `Up`, `Down` | Move selection |
| Select terminal session and press `Enter` / Click it | Open it |
| Select `New terminal` and press `Enter` / Click it | Start a terminal session in a space you pick |
| Select terminal session and press `n` | Start a terminal session in its space |
| Select terminal session and press `r` | Name it |
| Select terminal session and press `p` | Pin it |
| Select terminal session and press `u` | Mark it unread |
| Select `«` or `»` and press `Enter` / Click it | Toggle the sidebar |

## Requirements

- Neovim 0.11 or later
- `hc` on your PATH
- Git

## Installation and configuration

With lazy.nvim:

The plugin maps no global keys.

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
            -- Custom how notifications are sent.
            notify = function(name, status)
                ...
            end,
            -- Custom picker UI.
            picker = function(items, options, on_choice)
                ...
            end,
            -- Custom agent integrations. See Custom integrations below.
            integrations = {},
        })
        if not app.actions then return end
        vim.keymap.set("n", "<leader>ht", app.actions.new_tab)
        vim.keymap.set("n", "<leader>hv", app.actions.new_vertical)
        vim.keymap.set("n", "<leader>hs", app.actions.new_horizontal)
        vim.keymap.set("n", "<leader>hb", app.actions.toggle_sidebar)
        vim.keymap.set("n", "<leader>hf", app.actions.focus_sidebar)
    end,
}
```

### Statusline

If you use a statusline plugin, e.g. lualine, turn it off for the sidebar:

```lua
require("lualine").setup({
    options = {
        disabled_filetypes = { statusline = { "herdr-core" } },
    },
})
```

### Custom integrations

```lua
integrations = {
    -- Turns off a built-in integration.
    codex = false,
    -- Overrides part of a built-in integration.
    claude = {
        resume_command = function(id)
            return "claude --resume " .. id .. " --model opus"
        end,
    },
    -- Adds an agent.
    myagent = {
        -- Finds the agent's settings folder.
        -- Returns its path, or nil when the agent is not installed.
        directory = function()
            local path = vim.fs.normalize("~/.myagent")
            return vim.fn.isdirectory(path) == 1 and path or nil
        end,
        install = {
            {
                -- Checks the hooks are installed.
                -- Returns "installed", "outdated" or "missing".
                check = function(context)
                    local file = context.directory .. "/hooks.txt"
                    if vim.fn.filereadable(file) == 0 then return "missing" end
                    local wanted = { context.hook_command("started"), context.hook_command("ended") }
                    return vim.deep_equal(vim.fn.readfile(file), wanted) and "installed" or "outdated"
                end,
                -- Installs the hooks.
                apply = function(context)
                    local hooks = { context.hook_command("started"), context.hook_command("ended") }
                    vim.fn.writefile(hooks, context.directory .. "/hooks.txt")
                end,
            },
        },
        -- Builds the command that resumes a conversation.
        resume_command = function(id)
            return "myagent --resume " .. id
        end,
        -- Checks the terminal's program is this agent.
        matches_program = function(program)
            return program.name == "myagent" or (program.argv or {})[1] == "myagent"
        end,
    },
},
```

You can use these helpers to write an integration:

```lua
local integrations = require("herdr-core.integrations")

-- For directory: the folder named by the variable, or path when the variable is unset.
integrations.directory({ env = "MYAGENT_HOME", path = "~/.myagent" })
-- For install: sets or appends a value at a key in a JSON or JSONC settings file.
integrations.json({
    file = "hooks.json",
    events = { started = "SessionStart", ended = "SessionEnd" },
    append = { ["hooks.{{event}}"] = { type = "command", command = "{{command}}" } },
    set = { version = 1 },
})
-- For install: sets keys in a TOML settings file.
integrations.toml({ file = "config.toml", set = { ["features.hooks"] = true } })
-- For install: writes a file from a template, such as an extension the agent loads.
-- {{start_command}} and {{end_command}} become the hook commands.
integrations.template({ path = "extensions/herdr.js", source = vim.fn.expand("~/herdr-template.js") })
-- For matches_program: also recognizes programs run through node, npx and other interpreters.
integrations.program({ "myagent" })
```
