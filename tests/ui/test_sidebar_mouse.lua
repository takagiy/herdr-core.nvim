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
    click(side, 3)
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
