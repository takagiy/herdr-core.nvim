local MiniTest = require("mini.test")
local T = MiniTest.new_set()

---@param env    table
---@param extra? string[]
---@return vim.SystemCompleted
local function run(env, extra)
    local argv = { vim.v.progpath, "--headless", "--noplugin", "-u", "NONE" }
    vim.list_extend(argv, extra or {})
    vim.list_extend(argv, { "-c", "lua dofile('scripts/test.lua')" })
    return vim.system(argv, { env = env, clear_env = true, text = true, timeout = 30000 }):wait()
end

-- When hc is not on the PATH, `mise run test` can run only the ordinary tests.
T["runs ordinary tests without hc and excludes E2E"] = function ()
    -- Given: the real development PATH with the hc installation directory removed
    local env = vim.fn.environ()
    local separator = vim.fn.has("win32") == 1 and ";" or ":"
    local directory = vim.fs.dirname(vim.fn.exepath("hc"))
    local paths = vim.split(env.PATH, separator, { plain = true })
    env.PATH = table.concat(vim.tbl_filter(function (path)
            return vim.fs.normalize(path):lower() ~= vim.fs.normalize(directory):lower()
        end, paths), separator)
    env.HERDR_TEST_GROUP = nil
    -- When: the actual ordinary runner is launched
    local result = run(env, { "--cmd", "lua assert(vim.fn.executable('hc') == 0, 'hc still on PATH')" })
    -- Then: no hc dependency and no recursive E2E collection are required
    MiniTest.expect.equality(result.code, 0)
    MiniTest.expect.equality((result.stdout .. result.stderr):find("Fails (0)", 1, true) ~= nil, true)
    MiniTest.expect.equality((result.stdout .. result.stderr):find("test_environment.lua", 1, true), nil)
end

-- When `mise run test-e2e` runs, it can run only the E2E cases and fail when none are collected.
T["collects only E2E cases and fails when there are none"] = function ()
    -- Given: a tree where only an ordinary test file can be found
    local env = vim.fn.environ()
    env.HERDR_TEST_GROUP = "e2e"
    local only_ordinary = "lua vim.fn.globpath = function () return { 'tests/core/test_state.lua' } end"
    -- When: the E2E runner is launched
    local result = run(env, { "--cmd", only_ordinary })
    -- Then: the ordinary file is left out, and finding no E2E case is a failure
    MiniTest.expect.equality(result.code ~= 0, true)
    MiniTest.expect.equality((result.stdout .. result.stderr):find("No E2E cases collected", 1, true) ~= nil, true)
end

-- When E2E runs next to another hc session, it can leave that session's terminals, settings and saved layout unchanged.
T["isolates terminal labels and configuration from another core"] = function ()
    -- Given: another dedicated core with its own terminal and configuration
    local H = dofile("tests/e2e/helpers.lua")
    local first = H.new()
    ---@type table?
    local second
    local ok, err = pcall(function ()
        local address = first.spawn(nil, "control")
        first.hc({ "label", "--json", address, "control=untouched" })
        local config = first.env.XDG_CONFIG_HOME .. "/herdr-core"
        vim.fn.mkdir(config, "p")
        vim.fn.writefile({ "notes = false" }, config .. "/config.toml")
        local previous = vim.env.HC_SESSION
        vim.env.HC_SESSION = first.env.HC_SESSION
        -- When: another E2E environment is created despite the inherited session
        second = H.new()
        vim.env.HC_SESSION = previous
        local own = second.spawn(nil, "control")
        second.hc({ "label", "--json", own, "control=changed" })
        -- Then: labels, terminal directories, and configuration remain independent
        MiniTest.expect.equality(first.hc({ "get", "--json", address }).labels.control, "untouched")
        MiniTest.expect.equality(second.hc({ "get", "--json", own }).labels.control, "changed")
        MiniTest.expect.equality(first.root ~= second.root, true)
        MiniTest.expect.equality(vim.fn.readfile(config .. "/config.toml"), { "notes = false" })
    end)
    if second then second.close() end
    first.close()
    assert(ok, err)
end

-- When E2E ends by success, failure or timeout, it can stop only the processes it started.
T["cleans only its own processes after success or failure"] = function ()
    -- Given: real processes in two independent dedicated cores
    local H = dofile("tests/e2e/helpers.lua")
    local control, own = H.new(), H.new()
    local ok, err = pcall(function ()
        local address = control.spawn(nil, "control")
        local program = own.spawn(nil, "owned")
        local pid = own.hc({ "get", "--json", program }).pid
        assert(type(pid) == "number", "Terminal PID missing: " .. vim.inspect(own.hc({ "get", "--json", program })))
        -- When: an assertion fails and the same teardown used by the suite runs
        local passed = pcall(function () error("intentional failure before teardown") end)
        MiniTest.expect.equality(passed, false)
        own.close()
        -- Then: the other program survives and this program no longer runs
        MiniTest.expect.equality(control.hc({ "get", "--json", address }).state, "live")
        local uv = vim.uv --[[@as table]]
        MiniTest.expect.equality(uv.kill(pid, 0) == nil, true)
    end)
    control.close()
    assert(ok, err)
end

-- When Neovim, hc or Node.js is missing, E2E can fail with the missing executable instead of skipping.
T["fails instead of skipping when an E2E executable is missing"] = function ()
    -- Given: a PATH without hc or Node.js and an actual absolute Neovim executable
    local env = vim.fn.environ()
    env.PATH = ""
    env.HERDR_TEST_GROUP = "e2e"
    -- When: the E2E runner starts
    local result = run(env)
    -- Then: it fails with the missing prerequisite rather than reporting skipped tests
    MiniTest.expect.equality(result.code ~= 0, true)
    MiniTest.expect.equality((result.stdout .. result.stderr):find("Missing E2E executable: hc", 1, true) ~= nil, true)
end

return T
