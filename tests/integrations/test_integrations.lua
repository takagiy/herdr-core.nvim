local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local integrations = require("herdr-core.integrations")
local claude_hooks = {
    ["hooks.{{event}}"] = { hooks = { { type = "command", command = "{{command}}", timeout = 10 } } }
}

---@return string
local function folder()
    local path = vim.fn.tempname()
    vim.fn.mkdir(path, "p")
    return vim.fs.normalize(path)
end

---@param directory string
---@param name?     string
---@return HerdrCoreIntegrationContext
local function context(directory, name)
    return {
        directory = directory,
        hook_command = function (event, options) return integrations.hook_command(name or "claude", event, options) end
    }
end

---@param path string
---@return table
local function json(path)
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

T["finds the agent folder from its variable or its default path"] = function ()
    -- Given an existing folder named by a variable, and a default path that does not exist
    local existing = folder()
    vim.env.HERDR_TEST_AGENT_HOME = existing
    -- When both directories are resolved
    local from_env = integrations.directory({ env = "HERDR_TEST_AGENT_HOME", path = "~/none" })()
    vim.env.HERDR_TEST_AGENT_HOME = nil
    local missing = integrations.directory({ env = "HERDR_TEST_AGENT_HOME", path = existing .. "/none" })()
    -- Then the variable wins and a missing folder means the agent is not here
    MiniTest.expect.equality({ from_env, missing }, { existing, nil })
end

T["builds the hook command with the script arguments"] = function ()
    -- Given an integration that needs a parent check and a JSON reply
    -- When its start command is built
    local command = integrations.hook_command(
        "agy", "started", { parent_id_env = "X_ID", reply = "{}", id = { "cid" } }
    )
    -- Then the script gets every option, with the reply quoted for the shell
    MiniTest.expect.equality(
        command,
        "nvim -l " .. integrations.script() .. ' agy --event started --id cid --parent-id-env X_ID --reply "{}"'
    )
end

T["installs hooks beside the user's own settings"] = function ()
    -- Given a settings file with another hook and other settings
    local directory = folder()
    local file = directory .. "/settings.json"
    vim.fn.writefile({
        '{"model":"opus","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo mine"}]}]},"env":{}}'
    }, file)
    local make = integrations.json({
        append = claude_hooks,
        file = "settings.json",
        events = {
            started = "SessionStart",
            ended = "SessionEnd"
        }
    })
    local step = make("claude")
    -- When the step is checked, applied and checked again
    local before = step.check(context(directory))
    step.apply(context(directory))
    local after = step.check(context(directory))
    -- Then it goes from missing to installed and keeps the user's hook and settings
    local settings = json(file)
    MiniTest.expect.equality({ before, after }, { "missing", "installed" })
    MiniTest.expect.equality(settings.model, "opus")
    MiniTest.expect.equality(settings.hooks.SessionStart[1].hooks[1].command, "echo mine")
    MiniTest.expect.equality(
        settings.hooks.SessionEnd[1].hooks[1].command, integrations.hook_command("claude", "ended")
    )
    MiniTest.expect.equality(table.concat(vim.fn.readfile(file), "\n"):find('"env":{}', 1, true) ~= nil, true)
end

T["replaces its own hooks when their arguments change"] = function ()
    -- Given hooks installed without the parent check
    local directory = folder()
    local events = { started = "SessionStart", ended = "SessionEnd" }
    local plain = integrations.json({ file = "hooks.json", events = events, append = claude_hooks })
    plain("codex").apply(context(directory, "codex"))
    local checked = integrations.json({
        file = "hooks.json",
        events = events,
        append = claude_hooks,
        parent_id_env = "CODEX_THREAD_ID"
    })
    local step = checked("codex")
    -- When the definition now asks for the parent check
    local before = step.check(context(directory, "codex"))
    step.apply(context(directory, "codex"))
    -- Then the old commands count as outdated and are replaced, not duplicated
    ---@type { hooks: { command: string } [] } []
    local start = json(directory .. "/hooks.json").hooks.SessionStart
    MiniTest.expect.equality(before, "outdated")
    MiniTest.expect.equality(#start, 1)
    MiniTest.expect.equality(
        assert(assert(start[1]).hooks[1]).command:find("--parent-id-env CODEX_THREAD_ID", 1, true) ~= nil, true
    )
end

T["writes hooks in each agent's own layout"] = function ()
    -- Given agents that list hooks flat at the top level, flat under another key, or in groups with extra fields
    local layouts = {
        { append = { ["{{event}}"] = { type = "command", command = "{{command}}", timeout = 10000 } } },
        { append = { ["herdr.{{event}}"] = { powershell = "{{command}}" } } },
        {
            append = {
                ["hooks.{{event}}"] = {
                    matcher = "*",
                    hooks = {
                        {
                            type = "command",
                            command = "{{command}}",
                            timeout = 10
                        }
                    }
                }
            },
            set = { version = 1 }
        }
    }
    local results = {}
    for index, layout in ipairs(layouts) do
        local directory = folder()
        local options = vim.tbl_extend("force", layout, { file = "nested/hooks.json", events = { started = "Start" } })
        local step = integrations.json(
            options --[[@as HerdrCoreJsonOptions]]
        )("claude")
        -- When each is applied
        step.apply(context(directory))
        results[index] = { step.check(context(directory)), json(directory .. "/nested/hooks.json") }
    end
    -- Then each file holds the command in that layout and reads back as installed
    local command = integrations.hook_command("claude", "started")
    MiniTest.expect.equality(results, {
        { "installed", { Start = { { type = "command", timeout = 10000, command = command } } } },
        { "installed", { herdr = { Start = { { powershell = command } } } } },
        {
            "installed",
            {
                version = 1,
                hooks = {
                    Start = { { matcher = "*", hooks = { { type = "command", timeout = 10, command = command } } } }
                }
            }
        }
    })
end

T["replaces its own entry when its other fields change"] = function ()
    -- Given a hook installed with one timeout
    local directory = folder()
    ---@param timeout integer
    ---@return HerdrCoreIntegrationStep
    local function step(timeout)
        return integrations.json({
            file = "settings.json",
            events = { started = "SessionStart" },
            append = {
                ["hooks.{{event}}"] = {
                    hooks = {
                        {
                            type = "command",
                            command = "{{command}}",
                            timeout = timeout
                        }
                    }
                }
            }
        })("claude")
    end
    step(10).apply(context(directory))
    -- When the definition asks for another timeout
    local before = step(30).check(context(directory))
    step(30).apply(context(directory))
    -- Then the old entry counts as outdated and is replaced, not duplicated
    ---@type { hooks: { timeout: integer } [] } []
    local start = json(directory .. "/settings.json").hooks.SessionStart
    MiniTest.expect.equality({ before, #start, assert(assert(start[1]).hooks[1]).timeout }, { "outdated", 1, 30 })
end

T["refuses a settings file that is not JSON"] = function ()
    -- Given a broken settings file
    local directory = folder()
    vim.fn.writefile({ "{ broken" }, directory .. "/settings.json")
    local make = integrations.json({
        file = "settings.json",
        events = { started = "SessionStart" },
        append = claude_hooks
    })
    local step = make("claude")
    -- When the step is checked
    local ok, err = pcall(step.check, context(directory))
    -- Then it fails with the file name
    MiniTest.expect.equality({ ok, tostring(err) }, { false, "settings.json is not JSON" })
end

T["places an extension file with the hook commands filled in"] = function ()
    -- Given a template that names both hook commands, and an agent folder without the extension
    local template = vim.fn.tempname()
    vim.fn.writefile({ "const started = {{start_command}};", "const ended = {{end_command}};" }, template)
    local step = integrations.template({ path = "plugins/herdr.ts", source = template })
    local directory = folder()
    local target = directory .. "/plugins/herdr.ts"
    -- When it is checked, applied, edited by hand and checked again
    local before = step.check(context(directory))
    step.apply(context(directory))
    local after = step.check(context(directory))
    local written = vim.fn.readfile(target)
    vim.fn.writefile({ "edited" }, target)
    local edited = step.check(context(directory))
    -- Then it writes each command as a string literal and tells a changed file from its own
    local started = vim.json.encode(integrations.hook_command("claude", "started"))
    local ended = vim.json.encode(integrations.hook_command("claude", "ended"))
    MiniTest.expect.equality(
        { before, after, edited, written },
        { "missing", "installed", "outdated", { "const started = " .. started .. ";", "const ended = " .. ended .. ";" } }
    )
end

T["adds a value to the first file that exists unless one lists it"] = function ()
    -- Given a commented file, one without the key, none, the value in the second file, and only the second file
    local step = integrations.json({ file = { "tui.jsonc", "tui.json" }, append = { plugin = "./x.js" } })("opencode")
    local commented = {
        "{", "  // mine", '  "plugin": [', '    "a", // first', "  ],",
        '  "theme": "x\\\\", "url": "http://a", /* "plugin": [] */', "}"
    }
    local cases = {
        { ["tui.jsonc"] = commented }, { ["tui.jsonc"] = { '{ "theme": "x" }' } }, {},
        { ["tui.json"] = { '{ "plugin": ["./x.js"] }' } }, { ["tui.json"] = { '{ "plugin": [] }' } }
    }
    local results = {}
    for index, files in ipairs(cases) do
        local directory = folder()
        for file, lines in pairs(files) do
            vim.fn.writefile(lines, directory .. "/" .. file)
        end
        -- When each is checked and applied
        local before = step.check(context(directory))
        step.apply(context(directory))
        local written = {}
        for _, file in ipairs({ "tui.jsonc", "tui.json" }) do
            local path = directory .. "/" .. file
            if vim.fn.filereadable(path) == 1 then written[file] = vim.fn.readfile(path) end
        end
        results[index] = { before, step.check(context(directory)), written }
    end
    -- Then the value joins the first file that exists once, around the user's comments, and a listed value stays alone
    local added = vim.list_extend(vim.list_slice(commented, 1, 4), { '    "./x.js",' })
    MiniTest.expect.equality(results, {
        { "missing", "installed", { ["tui.jsonc"] = vim.list_extend(added, vim.list_slice(commented, 5)) } },
        { "missing", "installed", { ["tui.jsonc"] = { '{ "theme": "x", "plugin": ["./x.js"] }' } } },
        { "missing", "installed", { ["tui.jsonc"] = { "{", '  "plugin": [', '    "./x.js"', "  ]", "}" } } },
        { "installed", "installed", { ["tui.json"] = { '{ "plugin": ["./x.js"] }' } } },
        { "missing", "installed", { ["tui.json"] = { '{ "plugin": ["./x.js"] }' } } }
    })
end

T["edits a settings file in place, changing only its own entries and set values"] = function ()
    -- Given a commented file with trailing commas and a strict one, each holding an old entry of this integration
    local command = vim.json.encode(integrations.hook_command("claude", "started"))
    local old = '{ "hooks": [{ "type": "command", "command": ' .. command .. ', "timeout": 5 }] }'
    local theirs = '{ "hooks": [{ "type": "command", "command": "echo mine" }] }'
    local step = integrations.json({
        append = claude_hooks,
        file = "settings.json",
        events = { started = "SessionStart" },
        set = { version = 1 }
    })("claude")
    ---@param entry   string
    ---@param version integer
    ---@return string[]
    local function commented(entry, version)
        return {
            "{", "  // my settings", '  "model": "opus",', '  "hooks": {', '    "SessionStart": [',
            "      " .. theirs .. ", // mine", "      " .. entry .. ",", "    ],", "  },",
            '  "version": ' .. version .. ",", "}"
        }
    end
    local loose, strict = folder(), folder()
    vim.fn.writefile(commented(old, 0), loose .. "/settings.json")
    vim.fn.writefile({ '{"hooks": {"SessionStart": [' .. theirs .. ", " .. old .. "]}}" }, strict .. "/settings.json")
    -- When the step is checked and applied to each
    local before = { step.check(context(loose)), step.check(context(strict)) }
    step.apply(context(loose))
    step.apply(context(strict))
    -- Then only the old entry and the set value change, and the strict file gets no trailing comma
    local entry = '{"hooks": [{"command": ' .. command .. ', "timeout": 10, "type": "command"}]}'
    MiniTest.expect.equality(before, { "outdated", "outdated" })
    MiniTest.expect.equality(vim.fn.readfile(loose .. "/settings.json"), commented(entry, 1))
    MiniTest.expect.equality(
        vim.fn.readfile(strict .. "/settings.json"),
        { '{"hooks": {"SessionStart": [' .. theirs .. ", " .. entry .. ']}, "version": 1}' }
    )
    MiniTest.expect.equality({ step.check(context(loose)), step.check(context(strict)) }, { "installed", "installed" })
end

T["waits for opencode 2 to migrate the old settings before writing cli.json"] = function ()
    -- Given an opencode folder with only the old tui.json
    local directory = folder()
    vim.fn.writefile({ "{}" }, directory .. "/tui.json")
    local opencode = integrations.resolve().opencode
    opencode.directory = function () return directory end
    -- When the integration is installed
    local status, err = integrations.install("opencode", opencode)
    -- Then cli.json is not created, so opencode 2 can still migrate, and the old TUI file that exists lists the plugin
    MiniTest.expect.equality({ status, err }, { "installed", nil })
    MiniTest.expect.equality(vim.fn.filereadable(directory .. "/cli.json"), 0)
    MiniTest.expect.equality(json(directory .. "/tui.json").plugin, { "./herdr-core-nvim.js" })
end

T["sets TOML keys in their table"] = function ()
    -- Given a config without the key, one with the table, and one with another value
    local step = integrations.toml({ file = "config.toml", set = { ["features.hooks"] = true } })
    local cases = { { 'model = "o3"' }, { "[features]", "other = 1" }, { "[features]", "hooks = false" } }
    local results = {}
    for index, lines in ipairs(cases) do
        local directory = folder()
        vim.fn.writefile(lines, directory .. "/config.toml")
        -- When each is checked and applied
        local before = step.check(context(directory))
        step.apply(context(directory))
        results[index] = { before, step.check(context(directory)), vim.fn.readfile(directory .. "/config.toml") }
    end
    -- Then each ends with the key set once, in the right table
    MiniTest.expect.equality(results, {
        { "missing", "installed", { 'model = "o3"', "", "[features]", "hooks = true" } },
        { "missing", "installed", { "[features]", "hooks = true", "other = 1" } },
        { "outdated", "installed", { "[features]", "hooks = true" } }
    })
end

T["names programs the way the desktop app does"] = function ()
    -- Given programs as hc reports them
    local cases = {
        { app = "Claude-Code", name = "node", argv = { "node", "cli.js" } },
        { name = "codex.exe", argv = { "C:\\bin\\codex.exe", "resume" } },
        { name = "node", argv = { "node", "--no-warnings", "/opt/gemini/gemini.js" } },
        { name = "npx", argv = { "npx", "-y", "@anthropic-ai/claude-code" } }, { name = "zsh" }
    }
    -- When each is identified
    local names = vim.tbl_map(integrations.identify, cases)
    -- Then the agent's report wins, then the script an interpreter runs, then the program without .exe
    MiniTest.expect.equality(names, { "claude-code", "codex", "gemini", "claude-code", "zsh" })
    local claude = integrations.program({ "claude", "claude-code" })
    MiniTest.expect.equality({ claude(cases[4]), claude(cases[2]) }, { true, false })
end

T["installs every built-in integration into an empty agent folder"] = function ()
    -- Given each built-in pointed at an empty folder
    local results = {}
    for name, definition in pairs(integrations.resolve()) do
        local directory = folder()
        definition.directory = function () return directory end
        -- When it is installed
        local status, err = integrations.install(name, definition)
        results[name] = err or status
    end
    -- Then every one reports installed
    for name in pairs(results) do
        MiniTest.expect.equality({ name, results[name] }, { name, "installed" })
    end
end

T["merges the user's definitions over the built-in ones"] = function ()
    -- Given a changed resume command, a new agent and a built-in turned off
    local mine = { directory = function () return nil end, install = {}, resume_command = function () return "" end }
    -- When the definitions are resolved
    local resolved = integrations.resolve({
        claude = { resume_command = function (id) return "claude -r " .. id end },
        mycli = mine,
        codex = false
    })
    -- Then only the named field changes, the new one joins and the disabled one is gone
    MiniTest.expect.equality(resolved.claude.resume_command("x"), "claude -r x")
    MiniTest.expect.equality(resolved.claude.directory, integrations.builtin.claude.directory)
    MiniTest.expect.equality({ resolved.mycli.label, resolved.codex }, { "mycli", nil })
end

T["reports, installs and explains an integration"] = function ()
    -- Given one agent that is installed here, one that is not, and one whose step cannot work
    local directory = folder()
    local here = integrations.resolve({
        tool = {
            directory = function () return directory end,
            install = {
                integrations.json({
                    file = "settings.json",
                    events = { started = "SessionStart" },
                    append = claude_hooks
                })
            }
        }
    }).tool
    local absent = { directory = function () return nil end, install = {} }
    local stuck = {
        directory = function () return directory end,
        install = { { check = function () return "missing" end, apply = function () end } }
    }
    -- When they are checked and installed
    local before = integrations.status("tool", here)
    local installed = integrations.install("tool", here)
    local missing = integrations.status(
        "absent",
        absent --[[@as HerdrCoreIntegration]]
    )
    local status, err = integrations.install(
        "stuck",
        stuck --[[@as HerdrCoreIntegration]]
    )
    -- Then each result says what happened
    MiniTest.expect.equality({ before, installed, missing }, { "missing", "installed", nil })
    MiniTest.expect.equality({ status, err }, { "missing", "still missing after install" })
end

return T
