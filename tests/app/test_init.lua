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

return T
