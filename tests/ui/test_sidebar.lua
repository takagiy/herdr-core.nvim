local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["draws headings counts and two-line terminals with highlights"] = function ()
    -- Given core rows for a space and one terminal
    require("herdr-core.ui.highlights").setup()
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When the rows are rendered
    sidebar.render({
        { kind = "space", root = "/app", waiting = 2, lines = {} },
        {
            kind = "terminal",
            address = "t1",
            status = "working",
            lines = { "build", "claude" }
        }
    }, false, 2)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    local marks = vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })
    sidebar.close()
    -- Then the terminal name and program occupy separate lines
    MiniTest.expect.equality(
        { lines[1], lines[2], lines[3], lines[4] }, { "Waiting: 2", "/app  [2]  +", "  ● build", "    claude" }
    )
    MiniTest.expect.equality(#marks > 0, true)
    MiniTest.expect.equality(lines[#lines], "« Collapse")
end

T["keeps a sidebar on the left with the same width across tabs"] = function ()
    -- Given a sidebar shown at a chosen width
    local sidebar = require("herdr-core.ui.sidebar").create()
    local original = vim.api.nvim_get_current_tabpage()
    local first = sidebar.show(24)
    -- When a new tab is entered
    vim.cmd.tabnew()
    local second
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == sidebar.buffer then second = window end
    end
    local first_width = vim.api.nvim_win_get_width(first)
    local second_width = second and vim.api.nvim_win_get_width(second)
    sidebar.close()
    vim.cmd.tabclose()
    vim.api.nvim_set_current_tabpage(original)
    -- Then both tabs have a sidebar of that width
    MiniTest.expect.equality(first_width, 24)
    MiniTest.expect.equality(second_width, 24)
end

T["reports a terminal chosen with Enter or a mouse click"] = function ()
    -- Given a sidebar containing a terminal row
    local chosen = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        chosen[#chosen + 1] = { action, row and row.address }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "terminal", address = "t1", lines = { "build", "claude" } } }, false, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When Enter is pressed and the second terminal line is clicked
    vim.fn.maparg("<CR>", "n", false, true).callback()
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = 3, column = 5 } end
    vim.fn.maparg("<LeftMouse>", "n", false, true).callback()
    vim.fn.getmousepos = getmousepos
    sidebar.close()
    -- Then both gestures choose the same terminal
    MiniTest.expect.equality(chosen, { { "activate", "t1" }, { "activate", "t1" } })
end

T["reports heading activation so the app can toggle its fold"] = function ()
    -- Given a space heading with its stable id
    local chosen = {}
    local row = { kind = "space", id = "space1", root = "/app", lines = {} }
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, selected)
        chosen[#chosen + 1] = { action, selected and selected.id }
    end)
    local window = sidebar.show()
    sidebar.render({ row }, false, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When the heading is activated twice
    vim.fn.maparg("<CR>", "n", false, true).callback()
    vim.fn.maparg("<CR>", "n", false, true).callback()
    sidebar.close()
    -- Then both gestures identify the same heading for folding or unfolding
    MiniTest.expect.equality(chosen, { { "activate", "space1" }, { "activate", "space1" } })
end

T["reports new terminal requests from n and the heading plus button"] = function ()
    -- Given a space heading
    local requests = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        requests[#requests + 1] = { action, row and row.root }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "space", root = "/app", lines = {} } }, false, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When n is pressed and the heading's plus is clicked
    local keyboard = vim.fn.maparg("n", "n", false, true).callback
    if keyboard then keyboard() end
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = 2, column = 12 } end
    vim.fn.maparg("<LeftMouse>", "n", false, true).callback()
    vim.fn.getmousepos = getmousepos
    sidebar.close()
    -- Then both request a shell in the selected space
    MiniTest.expect.equality(requests, { { "new_terminal", "/app" }, { "new_terminal", "/app" } })
end

return T
