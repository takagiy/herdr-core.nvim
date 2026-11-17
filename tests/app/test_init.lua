local MiniTest = require("mini.test")
local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
    hooks = {
        pre_case = function () child.restart({ "-u", "scripts/minimal_init.lua" }) end,
        post_once = child.stop
    }
})

local fake = [[
    vim.fn.executable = function () return 1 end
    requests = {}
    package.loaded['herdr-core.adapter.git'] = { root = function (_, _, callback) callback('/app') end }
    package.loaded['herdr-core.adapter.hc'] = {
        watch = function (callback)
            requests.watch = true
            callback({ type = 'terminals_listed', terminals = {
                { address = 't1', labels = { ['herdr.space'] = '/app' },
                  folder = '/app', turn = 0, created_ms = 1 }
            } })
            callback({ type = 'layout_loaded', version = 1, value = { tabs = {
                { id = 'tab1', root = { kind = 'terminal', id = 'w1', terminal = 't1' } }
            } } })
            return function () requests.stopped = true end
        end,
        attach = function () return { vim.v.progpath, '--version' } end,
        label = function (_, _, _, callback) callback(nil) end,
        save_layout = function (value, version, callback)
            requests.saved = value
            callback({ type = 'layout_loaded', value = value, version = version + 1 })
        end
    }
]]

T["starts the stream and restores the saved terminal layout with a sidebar"] = function ()
    -- Given a core with one running terminal and a saved layout
    child.lua(fake)
    -- When setup runs
    child.lua([[require('herdr-core').setup({ auto_insert = false })]])
    child.lua([[vim.wait(1000, function () return #require('herdr-core.ui.layout').read().tabs == 1 end)]])
    -- Then the stream is followed, the layout is shown, and the sidebar is open
    MiniTest.expect.equality(child.lua_get("requests.watch"), true)
    MiniTest.expect.equality(child.lua_get("require('herdr-core.ui.layout').read().tabs[1].root.terminal"), "t1")
    MiniTest.expect.equality(
        child.lua_get(
            [[(function ()
        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.b[vim.api.nvim_win_get_buf(w)].herdr_core_sidebar then return true end
        end
        return false
    end)()]]
        ), true
    )
end

T["does not install global key mappings by default"] = function ()
    -- Given existing global normal and terminal mappings
    child.lua(fake)
    child.lua("before_maps = { vim.api.nvim_get_keymap('n'), vim.api.nvim_get_keymap('t') }")
    -- When setup runs without key settings
    child.lua([[require('herdr-core').setup({ auto_insert = false })]])
    -- Then global mappings remain untouched
    MiniTest.expect.equality(
        child.lua_get("vim.deep_equal(before_maps, { vim.api.nvim_get_keymap('n'), vim.api.nvim_get_keymap('t') })"),
        true
    )
end

T["restores while keeping an existing file window"] = function ()
    -- Given Neovim editing a file before setup
    child.lua(fake)
    child.lua([[vim.api.nvim_buf_set_name(0, 'notes.txt'); file_buffer = vim.api.nvim_get_current_buf()]])
    -- When setup restores terminals
    child.lua([[require('herdr-core').setup({ auto_insert = false })]])
    child.lua([[vim.wait(1000, function () return #require('herdr-core.ui.layout').read().tabs == 1 end)]])
    -- Then the file remains open alongside the restored layout
    MiniTest.expect.equality(child.lua_get("#vim.fn.win_findbuf(file_buffer) > 0"), true)
    MiniTest.expect.equality(child.lua_get("#require('herdr-core.ui.layout').read().tabs"), 1)
end

T["leaves Neovim untouched when hc is missing"] = function ()
    -- Given no hc executable
    child.lua(
        [[vim.fn.executable = function () return 0 end; messages = {}
        vim.notify = function (message) messages[#messages + 1] = message end]]
    )
    local before = child.lua_get("#vim.api.nvim_list_wins()")
    -- When setup runs
    child.lua("require('herdr-core').setup()")
    -- Then no windows are created and the user gets the reason
    MiniTest.expect.equality(child.lua_get("#vim.api.nvim_list_wins()"), before)
    MiniTest.expect.equality(child.lua_get("#messages"), 1)
end

T["does not save local windows before the initial layout arrives"] = function ()
    -- Given a connection whose initial layout has not arrived yet
    child.lua(fake)
    child.lua(
        [[package.loaded['herdr-core.adapter.hc'].watch = function (callback)
        stream = callback
        return function () end
    end]]
    )
    child.lua([[require('herdr-core').setup({ auto_insert = false })]])
    -- When a local terminal window appears before restoration
    child.lua(
        [[vim.b.herdr_core_address = 't1'; vim.api.nvim_exec_autocmds('BufWinEnter', {})
        vim.wait(30, function () return requests.saved ~= nil end)]]
    )
    -- Then the stored layout has not been replaced
    MiniTest.expect.equality(child.lua_get("requests.saved == nil"), true)
end

T["can stop twice and set up again"] = function ()
    -- Given a running plugin that has been stopped
    child.lua(fake)
    child.lua([[app = require('herdr-core').setup({ auto_insert = false }); app.stop()]])
    -- When cleanup repeats before setup is called again
    local ok = child.lua_get(
        [[(function ()
        return pcall(function () app.stop(); require('herdr-core').setup({ auto_insert = false }) end)
    end)()]]
    )
    -- Then cleanup is harmless and the next setup can start
    MiniTest.expect.equality(ok, true)
end

T["opens the requested shell after hc returns its address"] = function ()
    -- Given a running plugin and an hc run response
    child.lua(fake)
    child.lua(
        [[package.loaded['herdr-core.adapter.hc'].run = function (options, callback)
        requests.run = options
        callback('t2')
    end]]
    )
    child.lua(
        [[app = require('herdr-core').setup({ auto_insert = false })
        vim.wait(1000, function () return #require('herdr-core.ui.layout').read().tabs == 1 end)
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.b[vim.api.nvim_win_get_buf(w)].herdr_core_address == 't1' then vim.api.nvim_set_current_win(w); break end
        end]]
    )
    -- When the user asks for a new tab
    child.lua(
        [[app.actions.new_tab(); vim.wait(1000, function ()
        return vim.b.herdr_core_address == 't2'
    end)]]
    )
    -- Then a shell is requested in the current terminal's folder and displayed
    MiniTest.expect.equality(child.lua_get("requests.run.folder"), "/app")
    MiniTest.expect.equality(child.lua_get("vim.b.herdr_core_address"), "t2")
end

T["saves window changes after the initial layout has loaded"] = function ()
    -- Given a restored layout received through the event subscription
    child.lua(fake)
    child.lua(
        [[require('herdr-core').setup({ auto_insert = false })
        vim.wait(1000, function () return #require('herdr-core.ui.layout').read().tabs == 1 end)
        requests.saved = nil]]
    )
    -- When the user adds a terminal window
    child.lua(
        [[for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.b[vim.api.nvim_win_get_buf(w)].herdr_core_address == 't1' then vim.api.nvim_set_current_win(w); break end
    end
    vim.cmd.vsplit()
    vim.wait(1000, function () return requests.saved ~= nil end)]]
    )
    -- Then the changed arrangement is saved
    MiniTest.expect.equality(child.lua_get("requests.saved ~= nil"), true)
end

local tool = [[{
    claude = false,
    codex = false,
    tool = {
        directory = function () return vim.fn.stdpath('cache') end,
        install = { { check = function () return 'missing' end, apply = function () end } },
        resume_command = function (id) return 'tool --resume ' .. id end,
        matches_program = function (program) return program.name == 'tool' end
    }
}]]

T["resumes a conversation left in a terminal whose agent is gone"] = function ()
    -- Given a terminal whose hook left a tool conversation and that now shows a shell
    child.lua(fake)
    child.lua(
        [[
        local hc = package.loaded['herdr-core.adapter.hc']
        local watch = hc.watch
        hc.watch = function (callback)
            return watch(function (event)
                if event.type == 'terminals_listed' then
                    event.terminals[1].labels['herdr-core-nvim.agent'] = 'tool'
                    event.terminals[1].labels['herdr-core-nvim.session'] = 'abc'
                    event.terminals[1].program = 'zsh'
                end
                callback(event)
            end)
        end
        requests.typed = {}
        hc.labels = function (address, labels, callback) requests.cleared = { address, labels }; callback(nil) end
        hc.send = function (address, text, callback) table.insert(requests.typed, { address, text }); callback(nil) end
    ]]
    )
    -- When setup runs with that integration
    child.lua("require('herdr-core').setup({ auto_insert = false, integrations = " .. tool .. " })")
    child.lua([[vim.wait(1000, function () return #requests.typed > 0 end)]])
    -- Then the labels are cleared first and the resume command is typed once
    MiniTest.expect.equality(child.lua_get("requests.cleared"), {
        "t1",
        { ["herdr-core-nvim.agent"] = "", ["herdr-core-nvim.session"] = "", ["herdr-core-nvim.pid"] = "" }
    })
    MiniTest.expect.equality(child.lua_get("requests.typed"), { { "t1", "tool --resume abc" } })
end

T["shows the Setup panel for an integration that needs it"] = function ()
    -- Given an integration whose agent is installed but whose hook is not
    child.lua(fake)
    -- When setup runs
    child.lua("require('herdr-core').setup({ auto_insert = false, integrations = " .. tool .. " })")
    child.lua(
        [[vim.wait(1000, function ()
        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
            if vim.b[buffer].herdr_core_sidebar then
                return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n'):find('tool', 1, true) ~= nil
            end
        end
    end)]]
    )
    -- Then the sidebar offers to install it
    local text = child.lua_get(
        [[(function ()
        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
            if vim.b[buffer].herdr_core_sidebar then
                return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
            end
        end
    end)()]]
    )
    MiniTest.expect.equality(text:find("Setup", 1, true) ~= nil, true)
    MiniTest.expect.equality(text:find("tool%s+Install") ~= nil, true)
end

-- Presses the sidebar's New terminal button with Enter.
local press_new_terminal = [[
    vim.wait(1000, function () return #require('herdr-core.ui.layout').read().tabs == 1 end)
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.b[vim.api.nvim_win_get_buf(w)].herdr_core_sidebar then vim.api.nvim_set_current_win(w) end
    end
    for line, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if text:find('New terminal', 1, true) then vim.api.nvim_win_set_cursor(0, { line, 0 }) end
    end
    vim.fn.maparg('<CR>', 'n', false, true).callback()
]]

T["offers the Neovim folder, home and this machine's spaces for a new terminal"] = function ()
    -- Given a terminal in the /app space, a picker that takes the last place, and an hc run response
    child.lua(fake)
    child.lua(
        [[
        package.loaded['herdr-core.adapter.hc'].run = function (options, callback)
            requests.run = options
            callback('t2')
        end
    ]]
    )
    child.lua(
        [[require('herdr-core').setup({ auto_insert = false, picker = function (items, options, on_choice)
        requests.places = vim.tbl_map(function (item) return item.path end, items)
        requests.labels = vim.tbl_map(function (item) return item.label end, items)
        requests.prompt = options.prompt
        on_choice(items[#items])
    end })]]
    )
    -- When the user presses New terminal
    child.lua(press_new_terminal)
    child.lua([[vim.wait(1000, function () return requests.run ~= nil end)]])
    -- Then the places are the Neovim folder, home and the space, each once, and the shell starts in the chosen one
    local expected = child.lua_get(
        [[(function ()
        local places = {}
        for _, path in ipairs({ vim.fn.getcwd(), vim.fn.expand('~'), '/app' }) do
            path = vim.fs.normalize(path)
            if not vim.tbl_contains(places, path) then places[#places + 1] = path end
        end
        return places
    end)()]]
    )
    MiniTest.expect.equality(child.lua_get("requests.places"), expected)
    -- Each place shows as its path, shortened under home
    local shown = child.lua_get(
        "vim.tbl_map(function (path) return vim.fn.fnamemodify(path, ':~') end, ...)", { expected }
    )
    MiniTest.expect.equality(child.lua_get("requests.labels"), shown)
    MiniTest.expect.equality(child.lua_get("requests.prompt"), "New terminal")
    MiniTest.expect.equality(child.lua_get("requests.run.folder"), "/app")
end

T["starts nothing when the picker returns no place"] = function ()
    -- Given a picker that is closed without a choice
    child.lua(fake)
    child.lua([[package.loaded['herdr-core.adapter.hc'].run = function () requests.run = true end]])
    child.lua(
        [[require('herdr-core').setup({ auto_insert = false, picker = function (_, _, on_choice)
        requests.asked = true
        on_choice(nil)
    end })]]
    )
    -- When the user presses New terminal
    child.lua(press_new_terminal)
    -- Then no shell is started
    MiniTest.expect.equality(child.lua_get("requests.asked"), true)
    MiniTest.expect.equality(child.lua_get("requests.run"), vim.NIL)
end

return T
