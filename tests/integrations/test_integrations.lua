local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local integrations = require("herdr-core.integrations")

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
    local make = integrations.hooks({
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
    MiniTest.expect.equality(table.concat(vim.fn.readfile(file), "\n"):find('"env": {}', 1, true) ~= nil, true)
end

T["replaces its own hooks when their arguments change"] = function ()
    -- Given hooks installed without the parent check
    local directory = folder()
    local events = { started = "SessionStart", ended = "SessionEnd" }
    local plain = integrations.hooks({ file = "hooks.json", events = events })
    plain("codex").apply(context(directory, "codex"))
    local checked = integrations.hooks({ file = "hooks.json", events = events, parent_id_env = "CODEX_THREAD_ID" })
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

T["refuses a settings file that is not JSON"] = function ()
    -- Given a broken settings file
    local directory = folder()
    vim.fn.writefile({ "{ broken" }, directory .. "/settings.json")
    local make = integrations.hooks({ file = "settings.json", events = { started = "SessionStart" } })
    local step = make("claude")
    -- When the step is checked
    local ok, err = pcall(step.check, context(directory))
    -- Then it fails with the file name
    MiniTest.expect.equality({ ok, tostring(err) }, { false, "settings.json is not JSON" })
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
            install = { integrations.hooks({ file = "settings.json", events = { started = "SessionStart" } }) }
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
