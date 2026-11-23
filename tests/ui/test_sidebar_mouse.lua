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
            sidebar = require('herdr-core.ui.sidebar').create(function(action, row, value)
                actions[#actions + 1] = { action, row and row.id, value }
                if select_terminal then vim.api.nvim_set_current_win(editor) end
            end)
            side = sidebar.show(32)
            sidebar.render({ { kind='item', id='t1', lines={'review','claude'} } }, 0)
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
    click(side, 3)
    local actions = child.lua_get("actions")
    -- Then the same click both focuses the sidebar and activates the terminal
    MiniTest.expect.equality(child.api.nvim_get_current_win(), side)
    MiniTest.expect.equality(actions, { { "activate", "t1" } })
end

-- When an item with a menu is right-clicked, the sidebar can open the menu in place of Neovim's popup menu, with the cursor on the item, and report the action chosen in it.
-- When a row without a menu is right-clicked, the sidebar can open nothing.
T["opens an item's menu on a right click and reports the chosen action"] = function ()
    -- Given Neovim's popup menu on the right button, and an item without a menu
    child.lua([[vim.o.mousemodel = 'popup_setpos']])
    local side = child.lua_get("side")
    ---@param line integer
    local function right_click(line)
        local pos = child.fn.screenpos(side, line, 1)
        child.api.nvim_input_mouse("right", "press", "", 0, pos.row - 1, pos.col - 1)
        child.lua("vim.cmd.redraw()")
        child.api.nvim_input_mouse("right", "release", "", 0, pos.row - 1, pos.col - 1)
        child.lua("vim.cmd.redraw()")
    end
    -- When the item is right-clicked, then again once it has a menu, and r is pressed in the menu
    right_click(3)
    child.lua([[vim.wait(100, function () return false end)]])
    local without = child.lua_get("{ vim.api.nvim_win_get_config(0).relative, vim.fn.pumvisible() }")
    child.lua(
        [[sidebar.render({ {
            kind = 'item', id = 't1', lines = { 'review', 'claude' },
            menu = {
                { action = 'open', label = 'open', keys = {} }, { action = 'rename', label = 'rename', keys = { 'r' } }
            }
        } }, 0)]]
    )
    right_click(4)
    child.lua([[vim.wait(1000, function () return vim.api.nvim_win_get_config(0).relative ~= '' end)]])
    local opened = child.lua_get(
        [[{
            vim.api.nvim_win_get_config(0).relative ~= '', vim.fn.pumvisible(),
            vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.api.nvim_win_get_cursor(side)[1]
        }]]
    )
    child.type_keys("r")
    -- Then nothing opened without a menu; with one it opened at the pointer in place of the popup menu, the cursor went to the item's first line, and rename is reported
    MiniTest.expect.equality(without, { "", 0 })
    MiniTest.expect.equality(opened, { true, 0, { " open      ", " rename  r " }, 3 })
    MiniTest.expect.equality(child.lua_get("actions"), { { "action", "t1", "rename" } })
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
    click(child.lua_get("side"), 3)
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

T["presses New terminal with one click from another window"] = function ()
    -- Given the cursor in the editor
    -- When the New terminal button under the header is clicked
    click(child.lua_get("side"), 2, 3)
    -- Then it is reported without a space, for the plugin to ask where
    MiniTest.expect.equality(child.lua_get("actions"), { { "new_terminal" } })
end

T["keeps the picker open after a click on New terminal"] = function ()
    -- Given New terminal opening the place picker
    child.lua(
        [[
        sidebar.close()
        sidebar = require('herdr-core.ui.sidebar').create(function (action)
            if action ~= 'new_terminal' then return end
            require('herdr-core.ui.prompt').choose({ { label = '~', path = '~' } }, {}, function (item)
                picked = item or false
            end)
        end)
        side = sidebar.show(32)
        sidebar.render({}, 0)
        vim.api.nvim_set_current_win(editor)
    ]]
    )
    -- When New terminal is clicked from the editor
    click(child.lua_get("side"), 2, 3)
    -- Then the picker is still open and focused, with nothing chosen yet
    MiniTest.expect.equality(child.lua_get("picked"), vim.NIL)
    MiniTest.expect.equality(child.lua_get("vim.api.nvim_win_get_config(0).relative"), "editor")
end

T["keeps the sidebar at its left edge when scrolled sideways"] = function ()
    -- Given a terminal name wider than the sidebar, and the cursor in the editor
    child.lua(
        [[
        sidebar.render({ { kind = 'item', id = 't1', lines = { string.rep('long', 20), 'claude' } } }, 0)
        vim.api.nvim_set_current_win(editor)
    ]]
    )
    local side = child.lua_get("side")
    local pos = child.fn.screenpos(side, 3, 1)
    -- When a trackpad scrolls right over the sidebar
    child.api.nvim_input_mouse("wheel", "right", "", 0, pos.row - 1, pos.col - 1)
    child.lua("vim.cmd.redraw()")
    -- Then the sidebar still shows its left edge
    local leftcol = child.lua_get(
        "vim.api.nvim_win_call(..., function () return vim.fn.winsaveview().leftcol end)", { side }
    )
    MiniTest.expect.equality(leftcol, 0)
end

T["keeps the footer toggle at the right edge when resized and collapsed"] = function ()
    -- Given a sidebar resized from its configured width
    local side = child.lua_get("side")
    child.api.nvim_win_set_width(side, 24)
    child.lua("vim.api.nvim_exec_autocmds('WinResized', {})")
    local buffer = child.lua_get("sidebar.buffer")
    local function footer()
        local line = child.api.nvim_buf_line_count(buffer)
        local text = assert(child.api.nvim_buf_get_lines(buffer, line - 1, line, false)[1])
        return line, text
    end
    local line, text = footer()
    -- When inspecting and clicking the visible toggle at the right edge
    MiniTest.expect.equality(child.fn.strdisplaywidth(text), 24)
    MiniTest.expect.equality(text, string.rep(" ", 21) .. " « ")
    click(side, line, #text - 1)
    local narrow_line, narrow_text = footer()
    -- Then the collapsed toggle is also right-aligned and can expand again
    MiniTest.expect.equality(child.api.nvim_win_get_width(side), 3)
    MiniTest.expect.equality(narrow_text, " » ")
    click(side, narrow_line, #narrow_text - 1)
    MiniTest.expect.equality(child.api.nvim_win_get_width(side), 32)
end

return T
