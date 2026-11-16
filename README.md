# herdr-core.nvim

A TUI client for [herdr-core](https://github.com/herdrdev/herdr-core), built on Neovim.

## Features

- A sidebar groups sessions into spaces by Git repository or working directory, and shows each agent's status icon.
- Sends OS notifications when an agent needs you or finishes.
- Restores terminal layouts when Neovim restarts.
- Automatically resumes agent conversations after a reboot.

## Usage

- Press `j`/`k` or `Up`/`Down` to move between items, and Enter or click to use one.
- Use New terminal to start a terminal session in the Neovim folder, your home folder or a space.
- On a space's or terminal session's row, press `n` to start a terminal session in that space.
- On a terminal session's row, press Enter or click to open it, `r` to name it, `p` to pin it, or `u` to mark it unread.
- Click `«` at the bottom right to collapse the sidebar, or `»` to expand it.

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
        vim.keymap.set({ "n", "t" }, "<leader>ht", app.actions.new_tab)
        vim.keymap.set({ "n", "t" }, "<leader>hv", app.actions.new_vertical)
        vim.keymap.set({ "n", "t" }, "<leader>hs", app.actions.new_horizontal)
        vim.keymap.set({ "n", "t" }, "<leader>hb", app.actions.toggle_sidebar)
        vim.keymap.set({ "n", "t" }, "<leader>hf", app.actions.focus_sidebar)
    end,
}
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
-- For install: adds the hooks to a JSON settings file, in this shape:
-- { "hooks": { "<event>": [{ "hooks": [{ "type": "command", "command": "<hook command>" }] }] } }
integrations.hooks({ file = "settings.json", events = { started = "SessionStart", ended = "SessionEnd" } })
-- For install: sets keys in a TOML settings file.
integrations.toml({ file = "config.toml", set = { ["features.hooks"] = true } })
-- For matches_program: also recognizes programs run through node, npx and other interpreters.
integrations.program({ "myagent" })
```
