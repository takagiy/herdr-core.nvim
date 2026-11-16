local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["reads terminal windows while omitting file and sidebar windows"] = function ()
    -- Given a tab containing a terminal next to a file buffer
    local original = vim.api.nvim_get_current_win()
    vim.cmd.vsplit()
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "t1"
    vim.api.nvim_win_set_buf(window, buffer)
    -- When the current layout is read
    local value = require("herdr-core.ui.layout").read()
    vim.api.nvim_win_close(window, true)
    vim.api.nvim_set_current_win(original)
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then only the terminal appears in the shared tree
    MiniTest.expect.equality(#value.tabs, 1)
    MiniTest.expect.equality(assert(value.tabs[1]).root.kind, "terminal")
    MiniTest.expect.equality(assert(value.tabs[1]).root.terminal, "t1")
end

T["shows tabpages and nested splits with their terminal buffers"] = function ()
    -- Given a saved tab with side-by-side terminals and one below them
    local layout = require("herdr-core.ui.layout")
    local buffers = {}
    local value = {
        tabs = {
            {
                id = "restored",
                root = {
                    kind = "split",
                    id = "split-split-w1",
                    axis = "column",
                    children = {
                        {
                            kind = "split",
                            id = "split-w1",
                            axis = "row",
                            children = {
                                { kind = "terminal", id = "w1", terminal = "t1" },
                                { kind = "terminal", id = "w2", terminal = "t2" }
                            }
                        },
                        { kind = "terminal", id = "w3", terminal = "t3" }
                    }
                }
            }
        }
    }
    local original = vim.api.nvim_get_current_tabpage()
    -- When that layout is shown
    layout.show(value, function (address)
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.b[buffer].herdr_core_address = address
        buffers[#buffers + 1] = buffer
        return buffer
    end)
    local actual = layout.read()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if tab ~= original then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd.tabclose()
        end
    end
    for _, buffer in ipairs(buffers) do
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
    -- Then the same split directions and terminal order are restored
    MiniTest.expect.equality(actual, value)
end

T["keeps the existing window focused while restoring another tab"] = function ()
    -- Given a currently focused file window
    local layout = require("herdr-core.ui.layout")
    local original = vim.api.nvim_get_current_win()
    local tab = vim.api.nvim_get_current_tabpage()
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "focus"
    -- When a terminal tab is restored
    layout.show({
        tabs = { { id = "focus-tab", root = { kind = "terminal", id = "focus-window", terminal = "focus" } } }
    },
        function ()
            return buffer
        end)
    local focused = vim.api.nvim_get_current_win()
    for _, other in ipairs(vim.api.nvim_list_tabpages()) do
        if other ~= tab then
            vim.api.nvim_set_current_tabpage(other)
            vim.cmd.tabclose()
        end
    end
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the original file window remains focused
    MiniTest.expect.equality(focused, original)
end

T["keeps file windows when adding a terminal to their tab"] = function ()
    -- Given an existing managed tab with a local file window
    local layout = require("herdr-core.ui.layout")
    local window = vim.api.nvim_get_current_win()
    local file = vim.api.nvim_win_get_buf(window)
    local tab = vim.api.nvim_get_current_tabpage()
    local old_id = vim.t[tab].herdr_core_id
    vim.t[tab].herdr_core_id = "mixed"
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "mixed-terminal"
    -- When a terminal is restored into this tab
    layout.show({
        tabs = {
            {
                id = "mixed",
                root = { kind = "terminal", id = "mixed-window", terminal = "mixed-terminal" }
            }
        }
    },
        function ()
            return buffer
        end)
    local kept = vim.api.nvim_win_get_buf(window) == file
    for _, other in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if other ~= window then vim.api.nvim_win_close(other, true) end
    end
    vim.api.nvim_win_set_buf(window, file)
    vim.t[tab].herdr_core_id = old_id
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the local file window still shows its original buffer
    MiniTest.expect.equality(kept, true)
end

T["removes terminal-only tabs that disappear from the shared layout"] = function ()
    -- Given a restored terminal tab alongside a local file tab
    local layout = require("herdr-core.ui.layout")
    local file_tab = vim.api.nvim_get_current_tabpage()
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "removed"
    layout.show({
        tabs = {
            {
                id = "removed-tab",
                root = { kind = "terminal", id = "removed-window", terminal = "removed" }
            }
        }
    },
        function ()
            return buffer
        end)
    -- When that terminal tab is removed remotely
    layout.show({ tabs = {} }, function () error("No terminal needs attaching") end)
    local tabs = vim.api.nvim_list_tabpages()
    local survived = vim.api.nvim_buf_is_valid(buffer)
    for _, tab in ipairs(tabs) do
        if tab ~= file_tab then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd.tabclose()
        end
    end
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then only the file tab remains while the terminal buffer survives
    MiniTest.expect.equality(tabs, { file_tab })
    MiniTest.expect.equality(survived, true)
end

T["does not reuse a former terminal window now showing a file"] = function ()
    -- Given a file window retaining an old terminal window id
    local layout = require("herdr-core.ui.layout")
    local window = vim.api.nvim_get_current_win()
    local file = vim.api.nvim_get_current_buf()
    local tab = vim.api.nvim_get_current_tabpage()
    local tab_id, window_id = vim.t[tab].herdr_core_id, vim.w[window].herdr_core_id
    vim.t[tab].herdr_core_id = "reused-tab"
    vim.w[window].herdr_core_id = "old-terminal"
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "returned"
    -- When the former terminal is restored
    layout.show({
        tabs = { { id = "reused-tab", root = { kind = "terminal", id = "old-terminal", terminal = "returned" } } }
    },
        function ()
            return buffer
        end)
    local kept = vim.api.nvim_win_get_buf(window) == file
    for _, other in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if other ~= window then vim.api.nvim_win_close(other, true) end
    end
    vim.api.nvim_win_set_buf(window, file)
    vim.t[tab].herdr_core_id, vim.w[window].herdr_core_id = tab_id, window_id
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the file keeps its own window
    MiniTest.expect.equality(kept, true)
end

T["reports a locally changed terminal arrangement"] = function ()
    -- Given a layout listener and a terminal buffer
    local layout = require("herdr-core.ui.layout")
    local original = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "local"
    ---@type HerdrCoreLayoutValue?
    local reported
    local stop = layout.watch(function (value) reported = value end)
    -- When the user opens a split showing the terminal
    vim.cmd.vsplit()
    local window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(window, buffer)
    vim.wait(1000, function () return reported ~= nil end)
    stop()
    vim.api.nvim_win_close(window, true)
    vim.api.nvim_set_current_win(original)
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the terminal arrangement is reported
    MiniTest.expect.equality(assert(assert(reported).tabs[1]).root.terminal, "local")
end

T["does not report restoration as a local edit"] = function ()
    -- Given an active layout listener
    local layout = require("herdr-core.ui.layout")
    local original = vim.api.nvim_get_current_tabpage()
    local reports = 0
    local stop = layout.watch(function () reports = reports + 1 end)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "restoring"
    -- When a remote layout is shown and queued UI events are processed
    layout.show({
        tabs = { { id = "no-echo", root = { kind = "terminal", id = "no-echo-window", terminal = "restoring" } } }
    },
        function ()
            return buffer
        end)
    vim.wait(10, function () return reports > 0 end)
    stop()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if tab ~= original then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd.tabclose()
        end
    end
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then restoring does not create a local change event
    MiniTest.expect.equality(reports, 0)
end

T["updates the order of existing terminal tabs"] = function ()
    -- Given two previously restored terminal tabs
    local layout = require("herdr-core.ui.layout")
    local original = vim.api.nvim_get_current_tabpage()
    local buffers = {}
    local first = { id = "first", root = { kind = "terminal", id = "first-window", terminal = "first" } }
    local second = { id = "second", root = { kind = "terminal", id = "second-window", terminal = "second" } }
    ---@param address string
    ---@return integer
    local function buffer_for(address)
        if not buffers[address] then
            local buffer = vim.api.nvim_create_buf(false, true)
            vim.b[buffer].herdr_core_address = address
            buffers[address] = buffer
        end
        return buffers[address]
    end
    layout.show({ tabs = { first, second } }, buffer_for)
    -- When another editor reverses their order
    layout.show({ tabs = { second, first } }, buffer_for)
    local actual = layout.read()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if tab ~= original then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd.tabclose()
        end
    end
    for _, buffer in pairs(buffers) do
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
    -- Then existing tabs follow the shared order
    MiniTest.expect.equality(actual.tabs, { second, first })
end

T["gives each terminal window its own id after a file window shows a terminal again"] = function ()
    -- Given a shown terminal window that the user switched to a file
    local layout = require("herdr-core.ui.layout")
    local original = vim.api.nvim_get_current_tabpage()
    local buffers = {}
    ---@param address string
    ---@return integer
    local function buffer_for(address)
        if not buffers[address] then
            local buffer = vim.api.nvim_create_buf(false, true)
            vim.b[buffer].herdr_core_address = address
            buffers[address] = buffer
        end
        return buffers[address]
    end
    local value = { tabs = { { id = "tab", root = { kind = "terminal", id = "window", terminal = "t1" } } } }
    layout.show(value, buffer_for)
    local window = assert(vim.fn.win_findbuf(buffer_for("t1"))[1])
    local file = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(window, file)
    -- When the layout is shown again and the file window then shows another terminal
    layout.show(value, buffer_for)
    vim.api.nvim_win_set_buf(window, buffer_for("t2"))
    local actual = layout.read()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if tab ~= original then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd.tabclose()
        end
    end
    for _, buffer in pairs(buffers) do
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
    vim.api.nvim_buf_delete(file, { force = true })
    -- Then the two terminal windows have different ids
    local children = assert(assert(actual.tabs[1]).root.children)
    MiniTest.expect.no_equality(assert(children[1]).id, assert(children[2]).id)
end

return T
