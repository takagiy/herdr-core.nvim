local MiniTest = require("mini.test")
local H = dofile("tests/e2e/helpers.lua")
local eq = MiniTest.expect.equality
---@type table
local session
local T = MiniTest.new_set({
    hooks = {
        pre_case = function () session = H.new() end,
        post_case = function () session.close() end
    }
})

-- A kept shell that the real hook labelled as if the dummy agent had started conversation s-1 in it.
---@return string address
local function labelled_shell()
    local shell = vim.fn.has("win32") == 1 and "cmd.exe" or "sh"
    local started = session.hc({ "run", "--bg", "--keep", "--json", "--cwd", session.root, "--", shell })
    local address = assert(started.address) --[[@as string]]
    local pid = assert(session.hc({ "get", "--json", address }).pid) --[[@as integer]]
    local env = vim.deepcopy(session.env) --[[@as table<string, string>]]
    env.HC_TERMINAL_ID = address
    local hook = session.env.HERDR_E2E_PROJECT .. "/assets/session-hook.lua"
    local argv = { vim.v.progpath, "-l", hook, "e2e", "--event", "started" }
    local options = { env = env, clear_env = true, stdin = '{"session_id":"s-1"}', text = true, timeout = 15000 }
    local result = vim.system(argv, options):wait()
    assert(result.code == 0, result.stderr)
    eq(session.hc({ "get", "--json", address }).labels["herdr-core-nvim.pid"], tostring(pid))
    return address
end

---@param address string
---@return string
local function screen(address)
    return session.hc({ "read", "--json", address }).text or ""
end

-- When hc restarts a kept terminal whose conversation was cut off, a new Neovim can type the resume command into it.
T["resumes the conversation in a terminal hc restarted"] = function ()
    -- Given: a labelled shell that hc replaced after its process was killed, as after a reboot
    local address = labelled_shell()
    local pid = session.hc({ "get", "--json", address }).pid
    local uv = vim.uv --[[@as table]]
    uv.kill(pid, "sigkill")
    session.wait(function ()
        local record = session.hc({ "get", "--json", address })
        return record.state == "live" and record.pid ~= nil and record.pid ~= pid
    end, "hc restarts the shell")
    -- When: Neovim starts
    session.editor()
    -- Then: the resume command reaches the new shell, and the labels are cleared so it is typed only once
    session.wait(function () return screen(address):find("resumed-s-1", 1, true) ~= nil end, "resume command")
    eq(session.hc({ "get", "--json", address }).labels["herdr-core-nvim.session"] or "", "")
end

-- When the user quit the agent and its shell still runs, a new Neovim can leave the terminal alone.
T["leaves a terminal whose agent the user quit"] = function ()
    -- Given: a labelled shell still on the process the hook recorded
    local address = labelled_shell()
    -- When: Neovim starts and has checked the terminals
    local child = session.editor()
    session.wait(function () return child.lua_get("e2e_app.state().listed == true") end, "terminal list")
    -- Then: nothing is typed, and the labels stay for a later restart
    eq(child.lua_get(("e2e_app.state().resuming[%q] == nil"):format(address)), true)
    eq(session.hc({ "get", "--json", address }).labels["herdr-core-nvim.session"], "s-1")
    eq(screen(address):find("resumed", 1, true), nil)
end

return T
