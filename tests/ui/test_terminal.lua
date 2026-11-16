local MiniTest = require("mini.test")
local T = MiniTest.new_set()

-- When a terminal is shown, its buffer can be named `herdr://<name>`, or `herdr://<address>` when it has no name.
T["names a local terminal buffer by name or address"] = function ()
    -- Given named and unnamed local terminals
    local terminal = require("herdr-core.ui.terminal")
    -- When their buffer names are requested
    local named = terminal.name({ address = "t1", name = "build" })
    local unnamed = terminal.name({ address = "t2" })
    -- Then both use the herdr URI scheme
    MiniTest.expect.equality(named, "herdr://build")
    MiniTest.expect.equality(unnamed, "herdr://t2")
end

-- When a terminal on another machine is shown, its buffer can be named `herdr://<machine>/<name or address>`.
T["qualifies remote buffer names with their machine"] = function ()
    -- Given named and unnamed terminals on a remote machine
    local terminal = require("herdr-core.ui.terminal")
    -- When their buffer names are requested
    local named = terminal.name({ address = "server/t1", machine = "server", name = "build" })
    local unnamed = terminal.name({ address = "server/t2", machine = "server" })
    -- Then they cannot collide with local names
    MiniTest.expect.equality(named, "herdr://server/build")
    MiniTest.expect.equality(unnamed, "herdr://server/t2")
end

-- When a `herdr://` buffer is opened, the buffer can run `hc attach` for that terminal.
T["opens a real terminal buffer with the supplied attach command"] = function ()
    -- Given an attach command represented by a short-lived Neovim process
    local terminal = require("herdr-core.ui.terminal")
    -- When a terminal buffer is requested
    local buffer = terminal.buffer({ address = "t1", name = "build" }, { vim.v.progpath, "--version" })
    local name = vim.api.nvim_buf_get_name(buffer)
    local kind = vim.bo[buffer].buftype
    local address = vim.b[buffer].herdr_core_address
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then it has the URI, terminal type and stable address
    MiniTest.expect.equality(name, "herdr://build")
    MiniTest.expect.equality(kind, "terminal")
    MiniTest.expect.equality(address, "t1")
end

T["reports a herdr URI when its buffer is opened"] = function ()
    -- Given a URI read handler
    local terminal = require("herdr-core.ui.terminal")
    ---@type string?
    local requested
    local original = vim.api.nvim_get_current_buf()
    local stop = terminal.setup(function (uri) requested = uri end, false)
    -- When the user opens a terminal URI
    vim.cmd.edit("herdr://probe")
    local buffer = vim.api.nvim_get_current_buf()
    stop()
    vim.api.nvim_set_current_buf(original)
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the app can resolve and attach it
    MiniTest.expect.equality(requested, "herdr://probe")
end

-- When the cursor enters a terminal window, the window can switch to terminal mode.
T["enters terminal mode when a terminal window is entered"] = function ()
    -- Given automatic terminal mode and a terminal buffer
    local terminal = require("herdr-core.ui.terminal")
    local original = vim.api.nvim_get_current_buf()
    local startinsert = vim.cmd.startinsert
    local entered = false
    vim.cmd.startinsert = function () entered = true end
    local stop = terminal.setup(function () end, true)
    local buffer = terminal.buffer({ address = "auto" }, { vim.v.progpath, "--version" })
    -- When the terminal becomes the current buffer
    vim.api.nvim_set_current_buf(buffer)
    vim.wait(1000, function () return entered end)
    stop()
    vim.cmd.startinsert = startinsert
    vim.api.nvim_set_current_buf(original)
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the UI requests terminal input mode
    MiniTest.expect.equality(entered, true)
end

-- When the user turns automatic terminal mode off, the window can stay in normal mode on entry.
T["does not enter terminal mode when automatic entry is disabled"] = function ()
    -- Given automatic entry disabled after a listener was previously active
    local terminal = require("herdr-core.ui.terminal")
    local original = vim.api.nvim_get_current_buf()
    local startinsert = vim.cmd.startinsert
    local entered = false
    vim.cmd.startinsert = function () entered = true end
    local stop = terminal.setup(function () end, true)
    local buffer = terminal.buffer({ address = "manual" }, { vim.v.progpath, "--version" })
    vim.api.nvim_set_current_buf(buffer)
    stop()
    local stop_manual = terminal.setup(function () end, false)
    -- When previously queued callbacks are processed
    vim.wait(10, function () return entered end)
    stop_manual()
    vim.cmd.startinsert = startinsert
    vim.api.nvim_set_current_buf(original)
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the new disabled setting is respected
    MiniTest.expect.equality(entered, false)
end

T["does not leave a buffer behind when attach cannot start"] = function ()
    -- Given an attach command that does not exist
    local before = vim.api.nvim_list_bufs()
    -- When creating its terminal buffer fails
    local ok = pcall(
        require("herdr-core.ui.terminal").buffer, { address = "missing" }, { "herdr-core-nvim-missing-executable" }
    )
    -- Then the failure is reported without leaving an unusable terminal buffer
    MiniTest.expect.equality(ok, false)
    MiniTest.expect.equality(vim.api.nvim_list_bufs(), before)
end

T["attaches inside the existing URI read buffer"] = function ()
    -- Given the named buffer Neovim created before BufReadCmd
    local existing = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(existing, "herdr://existing")
    -- When the URI handler attaches using that buffer
    local terminal = require("herdr-core.ui.terminal")
    local attached = terminal.buffer({ address = "existing" }, { vim.v.progpath, "--version" }, existing)
    -- Then it reuses the buffer without creating a duplicate URI
    MiniTest.expect.equality(attached, existing)
    MiniTest.expect.equality(vim.bo[attached].buftype, "terminal")
    vim.api.nvim_buf_delete(attached, { force = true })
end

-- When a terminal is opened again while its attach is still running, the plugin can reuse that buffer.
T["reuses a buffer whose attach is still running"] = function ()
    -- Given a terminal buffer whose attach process keeps running
    local terminal = require("herdr-core.ui.terminal")
    local running = { vim.v.progpath, "--headless", "--clean", "+sleep 2", "+qa!" }
    local first = terminal.buffer({ address = "running" }, running)
    -- When the same terminal is opened again
    local second = terminal.buffer({ address = "running" }, running)
    vim.api.nvim_buf_delete(first, { force = true })
    -- Then the same buffer is returned
    MiniTest.expect.equality(second, first)
end

-- When a terminal is opened again after its attach exited, the plugin can start a new attach in the windows that showed it.
T["replaces a buffer whose attach exited"] = function ()
    -- Given a terminal buffer shown in the current window whose attach process has exited
    local terminal = require("herdr-core.ui.terminal")
    local original = vim.api.nvim_get_current_buf()
    local exited = terminal.buffer({ address = "exited" }, { vim.v.progpath, "--version" })
    vim.api.nvim_set_current_buf(exited)
    local window = vim.api.nvim_get_current_win()
    vim.fn.jobwait({ vim.b[exited].terminal_job_id }, 5000)
    -- When the same terminal is opened again
    local replaced = terminal.buffer(
        { address = "exited" }, { vim.v.progpath, "--headless", "--clean", "+sleep 2", "+qa!" }
    )
    local shown, old_exists = vim.api.nvim_win_get_buf(window), vim.api.nvim_buf_is_valid(exited)
    local running = vim.fn.jobwait({ vim.b[replaced].terminal_job_id }, 0)[1] == -1
    local name = vim.api.nvim_buf_get_name(replaced)
    vim.api.nvim_set_current_buf(original)
    vim.api.nvim_buf_delete(replaced, { force = true })
    -- Then a new running attach takes the old buffer's place, name and window
    MiniTest.expect.equality(replaced ~= exited, true)
    MiniTest.expect.equality({ shown, old_exists, running, name }, { replaced, false, true, "herdr://exited" })
end

return T
