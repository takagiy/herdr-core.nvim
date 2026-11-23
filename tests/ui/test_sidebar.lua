local MiniTest = require("mini.test")
local on_key = vim.on_key
---@type fun(key: string, typed: string)?
local mouse_listener
local T = MiniTest.new_set({
    hooks = {
        pre_case = function ()
            mouse_listener = nil
            ---@param fn?        fun(key: string, typed: string): string?
            ---@param namespace? integer
            ---@param options?   table
            ---@return integer
            vim.on_key = function (fn, namespace, options)
                if fn then mouse_listener = fn end
                return on_key(fn, namespace, options)
            end
        end,
        post_case = function () vim.on_key = on_key end
    }
})

---@param key? string
local function press_mouse(key)
    local raw = vim.api.nvim_replace_termcodes(key or "<LeftRelease>", true, false, true)
    assert(mouse_listener)(raw, raw)
    local done = false
    vim.schedule(function () done = true end)
    assert(vim.wait(1000, function () return done end))
end

-- When given rows, the sidebar can draw headings, two-line terminal rows and counts with `HerdrCore` highlights.
T["draws headings counts and two-line terminals with highlights"] = function ()
    -- Given core rows for a space and one terminal
    require("herdr-core.ui.highlights").setup()
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When the rows are rendered
    sidebar.render({
        { kind = "section", id = "/app", waiting = 2, lines = { "app" } },
        {
            kind = "item",
            id = "t1",
            status = "working",
            lines = { "build", "claude" }
        }
    }, 2)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    local marks = vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })
    sidebar.close()
    -- Then the terminal name and program occupy separate lines
    MiniTest.expect.equality(
        { lines[1], lines[2], lines[3], lines[4], lines[5], lines[6] },
        { "  HERDR", "  New terminal ", "", "  app  · 2", "  ◐ build", "    claude" }
    )
    MiniTest.expect.equality(#marks > 0, true)
    local badge
    for _, mark in ipairs(marks) do
        local details = assert(mark[4])
        if details.virt_text_pos == "right_align" then badge = details.virt_text end
    end
    -- The space heading carries the count, so the header shows no total.
    MiniTest.expect.equality(badge, nil)
    MiniTest.expect.equality(lines[#lines], string.rep(" ", 21) .. " « ")
end

T["opens 24 columns wide when shown without a width"] = function ()
    -- Given a sidebar
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When it is shown without a width
    local window = sidebar.show()
    local width = vim.api.nvim_win_get_width(window)
    sidebar.close()
    -- Then its window is 24 columns wide
    MiniTest.expect.equality(width, 24)
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
    vim.wait(1000, function ()
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == sidebar.buffer then second = window end
        end
        return second ~= nil
    end)
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
        chosen[#chosen + 1] = { action, row and row.id }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "item", id = "t1", lines = { "build", "claude" } } }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 3, 0 })
    -- When Enter is pressed and the second terminal line is clicked
    vim.fn.maparg("<CR>", "n", false, true).callback()
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = 4, column = 5 } end
    press_mouse()
    vim.fn.getmousepos = getmousepos
    sidebar.close()
    -- Then both gestures choose the same terminal
    MiniTest.expect.equality(chosen, { { "activate", "t1" }, { "activate", "t1" } })
end

T["ignores Enter and clicks on space headings"] = function ()
    -- Given a space heading above a terminal
    local chosen = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action)
        chosen[#chosen + 1] = action
    end)
    local window = sidebar.show()
    sidebar.render({
        { kind = "section", id = "/app", lines = { "app" } },
        { kind = "item", id = "t1", lines = { "review", "claude" } }
    }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 4, 0 })
    -- When Enter is pressed and the heading is clicked
    vim.cmd("normal " .. vim.api.nvim_replace_termcodes("<CR>", true, false, true))
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = 4, column = 1 } end
    press_mouse()
    vim.fn.getmousepos = getmousepos
    local heading = vim.api.nvim_buf_get_lines(sidebar.buffer, 3, 4, false)[1]
    sidebar.close()
    -- Then no action is emitted and no fold arrow is shown
    MiniTest.expect.equality(chosen, {})
    MiniTest.expect.equality(heading, "  app")
end

-- When a terminal is working, blocked, done or idle, the sidebar can show a different symbol for each.
T["shows a different symbol for each status"] = function ()
    -- Given terminals in every status, and one that reports none
    local sidebar = require("herdr-core.ui.sidebar").create()
    local rows = {}
    for index, status in ipairs({ "working", "blocked", "done", "idle", "error", false }) do
        rows[index] = { kind = "item", id = "t" .. index, status = status or nil, lines = { "t" .. index, "" } }
    end
    -- When they are rendered
    sidebar.render(rows, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    sidebar.close()
    -- Then each status has its own symbol and no status shows none
    local symbols = {}
    for index = 1, 6 do
        symbols[index] = assert(lines[index * 2 + 1]):match("^%s*(.-)%s*t%d$")
    end
    MiniTest.expect.equality(#vim.fn.uniq(vim.fn.sort(vim.deepcopy(symbols))), 6)
    MiniTest.expect.equality(symbols[6], "")
end

-- When an item's resource takes a key, the sidebar can report that key for the item, and do nothing on other rows.
T["reports a key the item's resource takes, and nothing on other rows"] = function ()
    -- Given an item whose resource takes p and u, under a heading without a resource
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row, value)
        reported[#reported + 1] = { action, row and row.id, value }
    end)
    local window = sidebar.show()
    sidebar.render({
        { kind = "section", id = "/app", lines = { "app" } },
        { kind = "item", id = "t1", lines = { "t1", "pwsh" }, keys = { p = "pin", u = "unread" } }
    }, 0)
    vim.api.nvim_set_current_win(window)
    -- When p and u are pressed on the item, and p on the heading
    vim.api.nvim_win_set_cursor(window, { 5, 0 })
    vim.fn.maparg("p", "n", false, true).callback()
    vim.fn.maparg("u", "n", false, true).callback()
    vim.api.nvim_win_set_cursor(window, { 4, 0 })
    vim.fn.maparg("p", "n", false, true).callback()
    sidebar.close()
    -- Then only the item reports them, each with its key
    MiniTest.expect.equality(reported, { { "key", "t1", "p" }, { "key", "t1", "u" } })
end

---@param window integer
---@param line   integer
local function click(window, line)
    vim.api.nvim_set_current_win(window)
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = line, column = 1 } end
    press_mouse()
    vim.fn.getmousepos = getmousepos
end

-- When the user clicks `«` at the bottom, the sidebar can collapse to a strip 2 to 3 columns wide.
T["collapses to a narrow strip when the bottom button is clicked"] = function ()
    -- Given a shown sidebar with a terminal waiting for the user
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show(30)
    sidebar.render({ { kind = "item", id = "t1", status = "blocked", lines = { "t1", "claude" } } }, 1)
    local bottom = vim.api.nvim_buf_line_count(sidebar.buffer)
    MiniTest.expect.equality(
        vim.api.nvim_buf_get_lines(sidebar.buffer, bottom - 1, bottom, false)[1], string.rep(" ", 27) .. " « "
    )
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
    sidebar.render({ { kind = "item", id = "t1", status = "blocked", lines = { "t1", "claude" } } }, 2)
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
    MiniTest.expect.equality(shown[#shown], " » ")
end

-- When the user clicks `»`, the sidebar can expand again.
T["expands to its width and rows when the expand button is clicked"] = function ()
    -- Given a sidebar collapsed from a width of 30
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show(30)
    sidebar.render({ { kind = "item", id = "t1", status = "blocked", lines = { "t1", "claude" } } }, 1)
    click(window, vim.api.nvim_buf_line_count(sidebar.buffer))
    -- When the button on the bottom line is clicked
    click(window, vim.api.nvim_buf_line_count(sidebar.buffer))
    local width = vim.api.nvim_win_get_width(window)
    local shown = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, 3, false)
    sidebar.close()
    -- Then the width and the terminal rows come back
    MiniTest.expect.equality(width, 30)
    MiniTest.expect.equality(shown[3], "  ● t1")
end

-- When an item's resource takes a key that moves the cursor, the sidebar can report the key instead of moving.
T["lets a resource's keys take the keys that move the cursor"] = function ()
    -- Given an item whose resource takes the keys that move the cursor
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, _, value)
        reported[#reported + 1] = { action, value }
    end)
    local window = sidebar.show()
    sidebar.render({
        {
            kind = "item",
            id = "t1",
            lines = { "review", "claude" },
            keys = { j = "a", ["<Down>"] = "b", k = "c", ["<Up>"] = "d" }
        }
    }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 3, 0 })
    -- When the keys are pressed through their actual mappings
    vim.cmd("normal j")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Down>k<Up>", true, false, true), "xt", false)
    local line = vim.api.nvim_win_get_cursor(window)[1]
    sidebar.close()
    -- Then each key is reported for the item and the cursor stays
    MiniTest.expect.equality(reported, { { "key", "j" }, { "key", "<Down>" }, { "key", "k" }, { "key", "<Up>" } })
    MiniTest.expect.equality(line, 3)
end

-- When an item's resource takes no key, `j`/`k` can skip the item.
T["skips items whose resource takes no key"] = function ()
    -- Given an item without keys between two items that take Enter
    local keyed = { use = "open" }
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show()
    sidebar.render({
        { kind = "item", lines = { "first" }, keys = keyed },
        { kind = "item", lines = { "plain" } },
        { kind = "item", lines = { "second" }, keys = keyed }
    }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 3, 0 })
    -- When j is pressed on the first item
    vim.fn.maparg("j", "n", false, true).callback()
    local line = vim.api.nvim_win_get_cursor(window)[1]
    sidebar.close()
    -- Then the cursor lands on the second item that takes a key
    MiniTest.expect.equality(line, 5)
end

-- When a heading is drawn for a resource, the sidebar can show its name; an item without a detail can take one line.
T["heads a resource's items with its name and draws an item without a detail on one line"] = function ()
    -- Given a resource's heading, an item with a label alone and one with a detail
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When they are rendered
    sidebar.render({
        { kind = "section", lines = { "Tasks" } },
        { kind = "item", status = "working", lines = { "T12" } },
        { kind = "item", lines = { "T13", "fix login" } }
    }, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 3, 7, false)
    sidebar.close()
    -- Then the heading shows the name, the first item one line, and the second its detail below
    MiniTest.expect.equality(lines, { "  Tasks", "  ◐ T12", "    T13", "    fix login" })
end

-- When a new tabpage is opened from the sidebar window, the sidebar can appear in it beside the new window.
T["appears in a tab opened from the sidebar window"] = function ()
    -- Given the cursor in a shown sidebar
    local sidebar = require("herdr-core.ui.sidebar").create()
    local original = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_win(sidebar.show(24))
    -- When a new tab is opened from there
    vim.cmd.tabnew()
    vim.wait(100)
    local shown = 0
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == sidebar.buffer then shown = shown + 1 end
    end
    local windows = #vim.api.nvim_tabpage_list_wins(0)
    sidebar.close()
    vim.cmd.tabclose()
    vim.api.nvim_set_current_tabpage(original)
    -- Then the new tab has the sidebar next to its own window
    MiniTest.expect.equality({ shown, windows }, { 1, 2 })
end

-- When the user clicks the same place again quickly, the sidebar can treat the second click like the first.
T["treats a quick second click like the first"] = function ()
    -- Given a terminal that the user has just clicked
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        reported[#reported + 1] = { action, row and row.id }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "item", id = "t1", lines = { "review", "claude" } } }, 0)
    vim.api.nvim_set_current_win(window)
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = 3, column = 1 } end
    press_mouse()
    -- When the second click arrives as a double click
    press_mouse("<2-LeftRelease>")
    vim.fn.getmousepos = getmousepos
    sidebar.close()
    -- Then both clicks activate the terminal
    MiniTest.expect.equality(reported, { { "activate", "t1" }, { "activate", "t1" } })
end

T["moves between sidebar items instead of display lines"] = function ()
    -- Given two-line terminals under project headings
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show()
    sidebar.render({
        { kind = "section", id = "/app", lines = { "app" } },
        { kind = "item", id = "t1", lines = { "first", "claude" }, keys = { use = "open" } },
        { kind = "item", id = "t2", lines = { "second", "codex" }, keys = { use = "open" } },
        { kind = "section", id = "/other", lines = { "other" } }
    }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 5, 0 })
    local positions = {}
    -- When moving down and up with Vim keys and arrow keys
    for _, key in ipairs({ "j", "<Down>", "<Up>", "k" }) do
        local mapping = vim.fn.maparg(key, "n", false, true)
        if mapping.callback then
            mapping.callback()
        else
            vim.cmd("normal! " .. (key == "<Down>" and "j" or key == "<Up>" and "k" or key))
        end
        positions[#positions + 1] = vim.api.nvim_win_get_cursor(window)[1]
    end
    vim.cmd("normal 2j")
    local counted = vim.api.nvim_win_get_cursor(window)[1]
    vim.api.nvim_win_set_cursor(window, { 6, 0 })
    vim.fn.maparg("k", "n", false, true).callback()
    local from_program = vim.api.nvim_win_get_cursor(window)[1]
    vim.cmd("normal 99j")
    local bottom = vim.api.nvim_win_get_cursor(window)[1]
    local footer = vim.api.nvim_buf_line_count(sidebar.buffer)
    vim.cmd("normal 99k")
    local top = vim.api.nvim_win_get_cursor(window)[1]
    sidebar.close()
    -- Then each key moves to the next or previous item with an action, skipping space headings; counts clamp at the ends
    MiniTest.expect.equality(positions, { 7, footer, 7, 5 })
    MiniTest.expect.equality({ counted, from_program, bottom, top }, { footer, 2, footer, 2 })
end

T["draws a child on one line under its parent's waiting count"] = function ()
    -- Given a lead with one waiting child, and that child
    require("herdr-core.ui.highlights").setup()
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When they are rendered
    sidebar.render({
        { kind = "item", id = "t1", status = "working", waiting = 1, lines = { "lead", "claude" } },
        { kind = "item", id = "t2", status = "blocked", guide = "└ ", lines = { "review", "claude" } }
    }, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 2, 5, false)
    local dimmed = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, { 4, 0 }, { 4, -1 }, { details = true })) do
        if assert(mark[4]).hl_group == "HerdrCoreProgram" then dimmed[#dimmed + 1] = mark[3] end
    end
    sidebar.close()
    -- Then the lead shows the count, and the child takes one line with its guide and program dimmed
    MiniTest.expect.equality(lines, { "  ◐ lead  · 1", "    claude", "    └ ● review  claude" })
    table.sort(dimmed)
    MiniTest.expect.equality(dimmed, { #"    ", #"    └ ● review  " })
end

T["dims the program but keeps the terminal name in normal text"] = function ()
    -- Given an idle terminal with a name and program
    require("herdr-core.ui.highlights").setup()
    local sidebar = require("herdr-core.ui.sidebar").create()
    sidebar.render({ { kind = "item", id = "t1", status = "idle", lines = { "review", "claude" } } }, 0)
    -- When its highlight ranges are inspected
    local marks = vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })
    local status_end, program
    for _, mark in ipairs(marks) do
        local details = assert(mark[4])
        if details.hl_group == "HerdrCoreIdle" then
            status_end = { details.end_row, details.end_col }
        end
        if details.hl_group == "HerdrCoreProgram" then program = mark[2] end
    end
    sidebar.close()
    -- Then status color stops before the name and the program uses Comment
    MiniTest.expect.equality(status_end, { 2, #("  ○ ") })
    MiniTest.expect.equality(program, 3)
end

-- When items at the top follow a section's rows, the sidebar can set them apart with a blank line and leave the section's heading without the accent.
T["sets items at the top apart from the section before them"] = function ()
    -- Given a section with an item, followed by two items at the top, the first highlighted
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When they are rendered
    sidebar.render({
        { kind = "section", id = "/app", lines = { "app" } },
        { kind = "item", id = "t1", lines = { "review" } },
        { kind = "item", id = "a", lines = { "note" }, top = true, highlighted = true },
        { kind = "item", id = "b", lines = { "todo" }, top = true }
    }, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 2, 8, false)
    local accents = 0
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })) do
        if assert(mark[4]).hl_group == "HerdrCoreSpaceActive" then accents = accents + 1 end
    end
    sidebar.close()
    -- Then one blank line comes before the items at the top, none between them, and the heading is not accented
    MiniTest.expect.equality(lines, { "", "  app", "    review", "", "    note", "    todo" })
    MiniTest.expect.equality(accents, 0)
end

-- When items are marked as highlighted, the sidebar can give each a full-width background over all its lines.
T["gives highlighted items a background over all their lines"] = function ()
    -- Given a highlighted two-line item, a highlighted child on one line, and an item that is not highlighted
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When they are rendered
    sidebar.render({
        { kind = "item", id = "t1", lines = { "review", "claude" }, highlighted = true },
        { kind = "item", id = "t2", lines = { "child", "codex" }, guide = "└ ", highlighted = true },
        { kind = "item", id = "t3", lines = { "build", "codex" } }
    }, 0)
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })) do
        local details = assert(mark[4])
        if details.hl_group == "HerdrCoreActive" then
            found[#found + 1] = { mark[2], details.end_row, details.hl_eol }
        end
    end
    sidebar.close()
    -- Then the two-line item has it on both lines, and the child on its one line
    table.sort(found, function (a, b) return a[1] < b[1] end)
    MiniTest.expect.equality(found, { { 2, 4, true }, { 4, 5, true } })
end

T["emphasizes labels and the space owning the selected terminal"] = function ()
    -- Given two spaces and a highlighted terminal in the second space
    local sidebar = require("herdr-core.ui.sidebar").create()
    -- When both spaces are rendered
    sidebar.render({
        { kind = "section", id = "/one", lines = { "one" } },
        { kind = "item", id = "t1", lines = { "first", "claude" } },
        { kind = "section", id = "/two", lines = { "two" } },
        { kind = "item", id = "t2", lines = { "second", "codex" }, highlighted = true }
    }, 0)
    local spaces, labels = {}, {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })) do
        local details = assert(mark[4])
        if details.hl_group == "HerdrCoreSpace" or details.hl_group == "HerdrCoreSpaceActive" then
            spaces[#spaces + 1] = { mark[2], details.hl_group, details.hl_eol }
        elseif details.hl_group == "HerdrCoreLabel" then
            labels[#labels + 1] = { mark[2], mark[3] }
        end
    end
    sidebar.close()
    -- Then only the owning heading is selected, and both labels have their own style
    MiniTest.expect.equality(spaces, { { 3, "HerdrCoreSpace", true }, { 7, "HerdrCoreSpaceActive", true } })
    MiniTest.expect.equality(labels, { { 4, #("    ") }, { 8, #("    ") } })
end

---@param buffer integer
---@param group  string
---@return integer[][] The 0-based start and end rows of each mark with that group.
local function ranges(buffer, group)
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true })) do
        local details = assert(mark[4])
        if details.hl_group == group then
            found[#found + 1] = { mark[2], details.end_row }
        end
    end
    return found
end

T["reports the New terminal button pressed with Enter"] = function ()
    -- Given the cursor on the New terminal button under the header
    local reported = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        reported[#reported + 1] = { action, row and row.kind }
    end)
    local window = sidebar.show()
    sidebar.render({ { kind = "item", id = "t1", lines = { "review", "claude" } } }, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    -- When Enter is pressed
    vim.fn.maparg("<CR>", "n", false, true).callback()
    sidebar.close()
    -- Then a new terminal is asked for, with no space chosen yet
    MiniTest.expect.equality(reported, { { "new_terminal", "new_terminal" } })
end

T["selects the row under the cursor beside the terminal in front"] = function ()
    -- Given t1 highlighted and two terminal rows
    local sidebar = require("herdr-core.ui.sidebar").create()
    local window = sidebar.show()
    local rows = {
        { kind = "item", id = "t1", lines = { "review", "claude" }, highlighted = true },
        { kind = "item", id = "t2", lines = { "build", "codex" } }
    }
    sidebar.render(rows, 0)
    local outside = ranges(sidebar.buffer, "HerdrCoreSelected")
    -- When the cursor moves into the sidebar onto t2, then onto New terminal
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 5, 0 })
    sidebar.render(rows, 0)
    local on_t2 = { ranges(sidebar.buffer, "HerdrCoreSelected"), ranges(sidebar.buffer, "HerdrCoreActive") }
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    sidebar.render(rows, 0)
    local on_button = { ranges(sidebar.buffer, "HerdrCoreButtonActive"), ranges(sidebar.buffer, "HerdrCoreSelected") }
    sidebar.close()
    -- Then only the cursor row is selected, t1 keeps its gray, and on a button row only the button takes the accent
    MiniTest.expect.equality(outside, {})
    MiniTest.expect.equality(on_t2, { { { 4, 6 } }, { { 2, 4 } } })
    MiniTest.expect.equality(on_button, { { { 1, 1 } }, {} })
end

T["gives every button the same background"] = function ()
    -- Given a sidebar with a space and a terminal
    local sidebar = require("herdr-core.ui.sidebar").create()
    sidebar.show()
    -- When it is drawn
    sidebar.render({
        { kind = "section", id = "/app", lines = { "app" } },
        { kind = "item", id = "t1", lines = { "review", "claude" } }
    }, 0)
    local buttons = ranges(sidebar.buffer, "HerdrCoreButton")
    local footer = vim.api.nvim_buf_line_count(sidebar.buffer) - 1
    sidebar.close()
    -- Then New terminal and the toggle are buttons, and the space heading has none
    MiniTest.expect.equality(buttons, { { 1, 1 }, { footer, footer } })
end

return T
