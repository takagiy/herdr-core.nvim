local MiniTest = require("mini.test")
local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
    hooks = {
        pre_case = function ()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            child.lua(
                [[
            vim.o.mouse = 'a'
            vim.o.mousemodel = 'extend'
            actions = {}
            editor = vim.api.nvim_get_current_win()
            sidebar = require('herdr-core.ui.sidebar').create(function(action, row)
                actions[#actions + 1] = { action, row and (row.address or row.root) }
                if select_terminal then vim.api.nvim_set_current_win(editor) end
            end)
            side = sidebar.show(32)
            sidebar.render({ { kind='terminal', address='t1', lines={'review','claude'} } }, 0)
            vim.api.nvim_set_current_win(editor)
        ]]
            )
        end,
        post_once = child.stop
    }
})

---@param window  integer
---@param line    integer
---@param column? integer
local function click(window, line, column)
    local pos = child.fn.screenpos(window, line, column or 1)
    assert(pos.row > 0 and pos.col > 0)
    child.api.nvim_input_mouse("left", "press", "", 0, pos.row - 1, pos.col - 1)
    child.lua("vim.cmd.redraw()")
    child.api.nvim_input_mouse("left", "release", "", 0, pos.row - 1, pos.col - 1)
    child.lua("vim.cmd.redraw()")
end

T["activates a sidebar item with one click from another window"] = function ()
    -- Given the cursor in the editor rather than the sidebar
    local side = child.lua_get("side")
    -- When clicking the terminal once
    click(side, 2)
    local actions = child.lua_get("actions")
    -- Then the same click both focuses the sidebar and activates the terminal
    MiniTest.expect.equality(child.api.nvim_get_current_win(), side)
    MiniTest.expect.equality(actions, { { "activate", "t1" } })
end

T["lets a click leave the sidebar"] = function ()
    -- Given the cursor in the sidebar
    child.api.nvim_set_current_win(child.lua_get("side"))
    local editor = child.lua_get("editor")
    -- When clicking the editor window
    click(editor, 1)
    -- Then the cursor leaves the sidebar without triggering a sidebar action
    MiniTest.expect.equality(child.api.nvim_get_current_win(), editor)
    MiniTest.expect.equality(child.lua_get("actions"), {})
end

T["keeps terminal focus after one click with an existing global mouse mapping"] = function ()
    -- Given the user's global click mapping and activation moving into a terminal window
    child.lua(
        [[
        select_terminal = true
        vim.keymap.set('n', '<LeftMouse>', '<LeftMouse><Cmd>lua hover_called = true<CR>')
    ]]
    )
    -- When clicking the terminal from the editor once
    click(child.lua_get("side"), 2)
    -- Then the native mapping still runs and activation happens exactly once
    MiniTest.expect.equality(child.lua_get("actions"), { { "activate", "t1" } })
    MiniTest.expect.equality(child.lua_get("hover_called"), true)
    MiniTest.expect.equality(child.api.nvim_get_current_win(), child.lua_get("editor"))
end

T["stops observing mouse input when the sidebar closes"] = function ()
    -- Given a live sidebar with a registered key listener
    local before = child.lua_get("vim.on_key()")
    -- When the sidebar closes
    child.lua("sidebar.close()")
    -- Then its listener is removed
    MiniTest.expect.equality(child.lua_get("vim.on_key()"), before - 1)
end

local plus = MiniTest.new_set({ parametrize = { { "/app", 0 }, { "/app", 2 }, { "/日本語", 1 } } })
T["plus button"] = plus

---@param root    string
---@param waiting integer
plus["starts a terminal at the visible plus after Unicode text"] = function (root, waiting)
    -- Given a heading with a Unicode fold marker, optional count, and project name
    child.lua("sidebar.render({ { kind='space', root=..., waiting=select(2, ...), lines={} } }, 0)", { root, waiting })
    local buffer = child.lua_get("sidebar.buffer")
    local heading = assert(child.api.nvim_buf_get_lines(buffer, 1, 2, false)[1])
    -- When clicking the actual displayed plus from the editor window
    click(child.lua_get("side"), 2, #heading)
    -- Then it requests a terminal instead of toggling the project's fold
    MiniTest.expect.equality(child.lua_get("actions"), { { "new_terminal", root } })
end

return T
