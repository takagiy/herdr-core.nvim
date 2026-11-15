local MiniTest = require("mini.test")
local T = MiniTest.new_set()

-- When given rows, the sidebar can draw headings, two-line terminal rows and counts with `HerdrCore` highlights.
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
    }, 2)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    local marks = vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })
    sidebar.close()
    -- Then the terminal name and program occupy separate lines
    MiniTest.expect.equality(
        { lines[1], lines[2], lines[3], lines[4] }, { "Waiting: 2", "/app  [2]  +", "  ◐ build", "    claude" }
    )
    MiniTest.expect.equality(#marks > 0, true)
    MiniTest.expect.equality(lines[#lines], "« Collapse")
end

-- When the user switches tabpages, the sidebar can stay on the same side and width.
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

-- When the user presses Enter or clicks on a terminal row, the sidebar can report that terminal as chosen.
T["reports a terminal chosen with Enter or a mouse click"] = function ()
    -- Given a sidebar containing a terminal row
    local chosen = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        chosen[#chosen + 1] = { action, row and row.address }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "terminal", address = "t1", lines = { "build", "claude" } } }, 0)
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

-- When the user presses Enter or clicks on a heading, the sidebar can report the heading as folded or unfolded.
T["reports heading activation so the app can toggle its fold"] = function ()
    -- Given a space heading with its stable id
    local chosen = {}
    local row = { kind = "space", id = "space1", root = "/app", lines = {} }
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, selected)
        chosen[#chosen + 1] = { action, selected and selected.id }
    end)
    local window = sidebar.show()
    sidebar.render({ row }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When the heading is activated twice
    vim.fn.maparg("<CR>", "n", false, true).callback()
    vim.fn.maparg("<CR>", "n", false, true).callback()
    sidebar.close()
    -- Then both gestures identify the same heading for folding or unfolding
    MiniTest.expect.equality(chosen, { { "activate", "space1" }, { "activate", "space1" } })
end

-- When the user presses `n` on a row or clicks a heading's `+`, the sidebar can report a new terminal for that row's space.
T["reports new terminal requests from n and the heading plus button"] = function ()
    -- Given a space heading
    local requests = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        requests[#requests + 1] = { action, row and row.root }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "space", root = "/app", lines = {} } }, 0)
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

-- When a terminal is working, blocked, done or idle, the sidebar can show a different symbol for each.
T["shows a different symbol for each status"] = function ()
    -- Given terminals in every status, and one that reports none
    local sidebar = require("herdr-core.ui.sidebar").create()
    local rows = {}
    for index, status in ipairs({ "working", "blocked", "done", "idle", "error", false }) do
        rows[index] = {
            kind = "terminal",
            address = "t" .. index,
            status = status or nil,
            lines = { "t" .. index, "" }
        }
    end
    -- When they are rendered
    sidebar.render(rows, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    sidebar.close()
    -- Then each status has its own symbol and no status shows none
    local symbols = {}
    for index = 1, 6 do
        symbols[index] = assert(lines[index * 2]):match("^%s*(.-)%s*t%d$")
    end
    MiniTest.expect.equality(#vim.fn.uniq(vim.fn.sort(vim.deepcopy(symbols))), 6)
    MiniTest.expect.equality(symbols[6], "")
end

-- When the user presses the rename key, the sidebar can ask for a name and report it for that terminal.
T["asks for a name with r and reports it for the terminal"] = function ()
    -- Given a terminal row and a user who types a name, then cancels, then clears it
    local answers = { "fix-login", nil, "" }
    local asked = 0
    local input = vim.ui.input
    ---@param opts       table?
    ---@param on_confirm fun(input: string?)
    vim.ui.input = function (opts, on_confirm)
        asked = asked + 1
        MiniTest.expect.equality(assert(opts).default, "t1")
        on_confirm(answers[asked])
    end
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row, value)
        reported[#reported + 1] = { action, row and row.address, value }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "terminal", address = "t1", lines = { "t1", "pwsh" } } }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When r is pressed three times
    for _ = 1, 3 do
        vim.fn.maparg("r", "n", false, true).callback()
    end
    vim.ui.input = input
    sidebar.close()
    -- Then the typed name and the cleared name are reported, and the cancel reports nothing
    MiniTest.expect.equality(reported, { { "rename", "t1", "fix-login" }, { "rename", "t1", "" } })
end

-- When the user presses the pin or unread key, the sidebar can report it for that terminal.
T["reports pin with p and unread with u for the terminal"] = function ()
    -- Given a terminal row under a heading
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        reported[#reported + 1] = { action, row and row.address }
    end)
    local window = sidebar.show()
    sidebar.render({
        { kind = "space", root = "/app", lines = {} },
        { kind = "terminal", address = "t1", lines = { "t1", "pwsh" } }
    }, 0)
    vim.api.nvim_set_current_win(window)
    -- When p and u are pressed on the terminal, and p on the heading
    vim.api.nvim_win_set_cursor(window, { 4, 0 })
    vim.fn.maparg("p", "n", false, true).callback()
    vim.fn.maparg("u", "n", false, true).callback()
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    vim.fn.maparg("p", "n", false, true).callback()
    sidebar.close()
    -- Then only the terminal row reports them
    MiniTest.expect.equality(reported, { { "pin", "t1" }, { "unread", "t1" } })
end

---@param window integer
---@param line   integer
local function click(window, line)
    vim.api.nvim_set_current_win(window)
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = line, column = 1 } end
    vim.fn.maparg("<LeftMouse>", "n", false, true).callback()
    vim.fn.getmousepos = getmousepos
end

-- When the user clicks `«` at the bottom, the sidebar can collapse to a strip 2 to 3 columns wide.
T["collapses to a narrow strip when the bottom button is clicked"] = function ()
    -- Given a shown sidebar with a terminal waiting for the user
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show(30)
    sidebar.render({ { kind = "terminal", address = "t1", status = "blocked", lines = { "t1", "claude" } } }, 1)
    local bottom = vim.api.nvim_buf_line_count(sidebar.buffer)
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(sidebar.buffer, bottom - 1, bottom, false)[1], "« Collapse")
    -- When the button on the bottom line is clicked
    click(window, bottom)
    local width = vim.api.nvim_win_get_width(window)
    sidebar.close()
    -- Then the sidebar becomes a strip 2 to 3 columns wide
    MiniTest.expect.equality(width >= 2 and width <= 3, true)
end

-- When the sidebar is collapsed, it can show the waiting count at the top and `»` at the bottom.
T["shows the waiting count at the top and the expand button at the bottom when collapsed"] = function ()
    -- Given a collapsed sidebar with two terminals waiting
    local lines = vim.o.lines
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show(30)
    sidebar.render({ { kind = "terminal", address = "t1", status = "blocked", lines = { "t1", "claude" } } }, 2)
    click(window, vim.api.nvim_buf_line_count(sidebar.buffer))
    -- When Neovim becomes taller
    vim.o.lines = lines + 6
    vim.api.nvim_exec_autocmds("VimResized", {})
    local height = vim.api.nvim_win_get_height(window)
    local shown = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    sidebar.close()
    vim.o.lines = lines
    -- Then the count stays on the top line and the button on the window's bottom line
    MiniTest.expect.equality(shown[1], "2")
    MiniTest.expect.equality(#shown, height)
    MiniTest.expect.equality(shown[#shown], "»")
end

-- When the user clicks `»`, the sidebar can expand again.
T["expands to its width and rows when the expand button is clicked"] = function ()
    -- Given a sidebar collapsed from a width of 30
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show(30)
    sidebar.render({ { kind = "terminal", address = "t1", status = "blocked", lines = { "t1", "claude" } } }, 1)
    click(window, vim.api.nvim_buf_line_count(sidebar.buffer))
    -- When the button on the bottom line is clicked
    click(window, vim.api.nvim_buf_line_count(sidebar.buffer))
    local width = vim.api.nvim_win_get_width(window)
    local shown = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, 3, false)
    sidebar.close()
    -- Then the width and the terminal rows come back
    MiniTest.expect.equality(width, 30)
    MiniTest.expect.equality(shown[2], "  ● t1")
end

-- When the user sets other sidebar keys, the sidebar can use them in place of the defaults.
T["uses the keys the user sets in place of the defaults"] = function ()
    -- Given sidebar keys set by the user
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        reported[#reported + 1] = { action, row and row.address }
    end, { activate = "o", new_terminal = "a", rename = "R", pin = "P", unread = "U" })
    local window = sidebar.show()
    sidebar.render({ { kind = "terminal", address = "t1", lines = { "t1", "pwsh" } } }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When the user's keys are pressed
    for _, key in ipairs({ "o", "a", "P", "U" }) do
        vim.fn.maparg(key, "n", false, true).callback()
    end
    local defaults = {}
    for _, key in ipairs({ "<CR>", "n", "r", "p", "u" }) do
        defaults[#defaults + 1] = vim.fn.maparg(key, "n", false, true).callback ~= nil
    end
    sidebar.close()
    -- Then they report their actions, and the default keys are left unmapped
    MiniTest.expect.equality(
        reported, { { "activate", "t1" }, { "new_terminal", "t1" }, { "pin", "t1" }, { "unread", "t1" } }
    )
    MiniTest.expect.equality(defaults, { false, false, false, false, false })
end

return T
