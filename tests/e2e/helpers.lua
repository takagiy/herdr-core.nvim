local MiniTest = require("mini.test")
local M = {}
local project = vim.fn.getcwd()

---@param predicate   fun(): boolean
---@param description string
function M.wait(predicate, description)
    assert(vim.wait(10000, predicate, 20), "Timed out: " .. description)
end

---@return table
function M.new()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local env = vim.fn.environ()
    env.HC_SESSION = "nvim-e2e-" .. vim.fn.getpid() .. "-" .. vim.fn.fnamemodify(root, ":t")
    env.HERDR_E2E_PROJECT = project
    env.NVIM_APPNAME = "herdr-core-e2e"
    for _, key in ipairs({ "HC_SOCKET", "HC_TERMINAL_ID", "HC_TERMINAL_SOCKET", "HC_SCOPE" }) do
        env[key] = nil
    end
    for _, kind in ipairs({ "STATE", "CONFIG", "DATA", "CACHE" }) do
        local path = root .. "/" .. kind:lower()
        vim.fn.mkdir(path, "p")
        env["XDG_" .. kind .. "_HOME"] = path
    end
    if vim.fn.has("win32") == 0 then
        env.XDG_RUNTIME_DIR = root .. "/runtime"
        vim.fn.mkdir(env.XDG_RUNTIME_DIR, "p")
        assert(vim.fn.setfperm(env.XDG_RUNTIME_DIR, "rwx------") == 1)
    end
    local children = {}
    local closed = false
    local session = { root = root, env = env, wait = M.wait }
    ---@param args string[]
    ---@return table
    function session.hc(args)
        local argv = { "hc" }
        vim.list_extend(argv, args)
        local result = vim.system(argv, { env = env, clear_env = true, text = true, timeout = 15000 }):wait()
        assert(result.code == 0, vim.inspect(argv) .. ": " .. (result.stderr or ""))
        return vim.json.decode(result.stdout or "{}", { luanil = { object = true, array = true } })
    end
    ---@param folder? string
    ---@param name?   string
    ---@return string
    function session.spawn(folder, name)
        local result = session.hc({
            "run",
            "--bg",
            "--json",
            "--cwd",
            folder or root,
            "--name",
            name or "agent",
            "--",
            vim.fn.exepath("node"),
            project .. "/tests/e2e/dummy-agent.mjs"
        })
        return assert(result.address) --[[@as string]]
    end
    ---@param file? string
    ---@return MiniTest.child
    function session.editor(file)
        local child = MiniTest.new_child_neovim()
        children[#children + 1] = child
        local saved = vim.fn.environ()
        for key in pairs(saved) do
            if env[key] == nil then vim.env[key] = nil end
        end
        for key, value in pairs(env) do
            vim.env[key] = value
        end
        local args = { "-u", project .. "/tests/e2e/init.lua" }
        if file then args[#args + 1] = file end
        local ok, err = pcall(function () child.start(args) end)
        for key in pairs(env) do
            if saved[key] == nil then vim.env[key] = nil end
        end
        for key, value in pairs(saved) do
            vim.env[key] = value
        end
        assert(ok, err)
        M.wait(
            function () return child.lua_get("e2e_app.state ~= nil and e2e_app.state().layout.version ~= nil") end,
            "plugin startup"
        )
        return child
    end
    ---@param child MiniTest.child
    function session.normal(child)
        child.type_keys("<C-\\><C-n>")
    end
    ---@param child MiniTest.child
    ---@return string
    function session.text(child)
        return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    end
    ---@param child MiniTest.child
    ---@param text  string
    function session.input(child, text)
        session.normal(child)
        child.type_keys("i", text .. "<CR>")
    end
    ---@param child MiniTest.child
    ---@param text  string
    ---@return integer
    function session.row(child, text)
        session.normal(child)
        child.type_keys("<F8>")
        ---@type integer?
        local found
        M.wait(function ()
            for index, line in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
                if line:find(text, 1, true) then
                    found = index
                    return true
                end
            end
            return false
        end, "sidebar row " .. text)
        return assert(found)
    end
    ---@param child   MiniTest.child
    ---@param address string
    function session.choose(child, address)
        local record = session.hc({ "get", "--json", address })
        local row = session.row(child, record.labels["herdr-core-nvim.name"] or record.name or address)
        child.type_keys(tostring(row) .. "G<CR>")
        M.wait(function () return child.lua_get("vim.b.herdr_core_address") == address end, "open " .. address)
    end
    function session.close()
        if closed then return end
        closed = true
        local artifacts = vim.env.HERDR_E2E_ARTIFACTS or (project .. "/artifacts/e2e")
        vim.fn.mkdir(artifacts, "p")
        for index, child in ipairs(children) do
            if child.is_running() then
                local ok, snapshot = pcall(
                    child.lua_get,
                    [[{ messages = vim.fn.execute('messages'),
                    buffers = vim.tbl_map(function(b) return {name=vim.api.nvim_buf_get_name(b),
                    lines=vim.api.nvim_buf_get_lines(b,0,-1,false)} end, vim.api.nvim_list_bufs()) }]]
                )
                if ok then
                    vim.fn.writefile(
                        vim.split(vim.inspect(snapshot), "\n"),
                        artifacts .. "/" .. env.HC_SESSION .. "-" .. index .. ".log"
                    )
                end
            end
        end
        for _, child in ipairs(children) do
            pcall(child.stop)
        end
        local terminals = session.hc({ "ls", "--json", "--all" }).terminals or {}
        for _, terminal in ipairs(terminals) do
            if terminal.state == "live" then pcall(session.hc, { "kill", "--json", terminal.address }) end
        end
        session.hc({ "server", "stop", "--json" })
    end
    return session
end

return M
