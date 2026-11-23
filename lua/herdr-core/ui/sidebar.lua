local M = {}

local symbols = { working = "◐", blocked = "●", error = "✗", done = "✓", idle = "○" }

---@param text  string
---@param width integer
---@return string
local function fit(text, width)
    local shown = vim.fn.strcharpart(text, 0, width)
    while vim.fn.strdisplaywidth(shown) > width do
        shown = vim.fn.strcharpart(shown, 0, vim.fn.strchars(shown) - 1)
    end
    return shown .. string.rep(" ", width - vim.fn.strdisplaywidth(shown))
end

-- Breaks text at spaces into lines no wider than width, each starting with indent; fit cuts a word that is wider.
---@param indent string
---@param text   string
---@param width  integer
---@return string[]
local function wrap(indent, text, width)
    local lines, line = {}, indent
    for word in text:gmatch("%S+") do
        local longer = line == indent and indent .. word or line .. " " .. word
        if line ~= indent and vim.fn.strdisplaywidth(longer) > width then
            lines[#lines + 1] = line
            longer = indent .. word
        end
        line = longer
    end
    lines[#lines + 1] = line
    return lines
end

---@class HerdrCoreSetupLine
---@field text          string
---@field row?          HerdrCoreSidebarRow
---@field group?        string
---@field button_start? integer             Byte column where the button starts.
---@field button_end?   integer

-- The Setup panel as boxed lines, each knowing its row and where its button is.
---@param rows  HerdrCoreSidebarRow[]
---@param width integer
---@return HerdrCoreSetupLine[]
local function setup_box(rows, width)
    if #rows == 0 then return {} end
    -- Wide enough for the longest button, Install all, with a column on each side.
    local inner = math.max(15, width - 4)
    local lines = { { text = " ╭ Setup " .. string.rep("─", inner - 7) .. "╮", group = "HerdrCoreMuted" } }
    for _, row in ipairs(rows) do
        local indent = (row.kind == "setup_item" or row.kind == "setup_error") and "  " or " "
        local label = indent .. (row.lines[1] or "")
        if row.button then
            -- Buttons end one column inside the border; one that does not fit beside its name goes on the next line.
            local button = " " .. row.button .. " "
            local start = inner - 1 - vim.fn.strdisplaywidth(button)
            local beside = vim.fn.strdisplaywidth(label) + 1 <= start
            if not beside then
                lines[#lines + 1] = {
                    text = " │" .. fit(label, inner) .. "│",
                    row = row,
                    group = row.kind == "setup_heading" and "HerdrCoreHeader" or nil
                }
            end
            local before = " │" .. fit(beside and label or "", start)
            lines[#lines + 1] = {
                text = before .. button .. " │",
                row = row,
                group = beside and row.kind == "setup_heading" and "HerdrCoreHeader" or nil,
                button_start = #before,
                button_end = #before + #button
            }
        else
            for _, text in ipairs(wrap(indent, row.lines[1] or "", inner)) do
                lines[#lines + 1] = {
                    text = " │" .. fit(text, inner) .. "│",
                    row = row,
                    group = row.kind == "setup_heading" and "HerdrCoreHeader" or "HerdrCoreMuted"
                }
            end
        end
    end
    lines[#lines + 1] = { text = " ╰" .. string.rep("─", inner) .. "╯", group = "HerdrCoreMuted" }
    return lines
end

---@class HerdrCoreSidebarView
---@field buffer integer
---@field render fun(rows: HerdrCoreSidebarRow[], waiting: integer?)
---@field show   fun(width: integer?): integer
---@field close  fun()
---@field toggle fun()

---@param on_action? fun(action: string, row: HerdrCoreSidebarRow?, value: string?)
---@return HerdrCoreSidebarView
function M.create(on_action)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_sidebar = true
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].filetype = "herdr-core"
    local namespace = vim.api.nvim_create_namespace("HerdrCoreSidebar" .. buffer)
    ---@type table<integer, HerdrCoreSidebarRow>
    local by_line = {}
    ---@type integer[]
    local positions = {}
    local width, shown, collapsed, footer = 24, false, false, 0
    ---@type HerdrCoreSidebarRow[], integer
    local last_rows, last_waiting = {}, 0
    ---@type fun(rows: HerdrCoreSidebarRow[], waiting: integer?)
    local render
    local function toggle()
        collapsed = not collapsed
        for _, window in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(window) == buffer then
                vim.api.nvim_win_set_width(window, collapsed and 3 or width)
            end
        end
        render(last_rows, last_waiting)
    end
    ---@param line integer
    ---@param line integer
    local function activate(line)
        if line == footer then
            toggle()
            return
        end
        local row = by_line[line]
        -- Headings have no button to press.
        if not row or not on_action or row.kind == "section" then return end
        if row.kind == "new_terminal" then
            on_action("new_terminal", row)
            return
        end
        if row.kind:find("^setup_") and not row.action then return end
        on_action("activate", row)
    end
    ---@param direction integer
    local function move(direction)
        if #positions == 0 then return end
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local index = 0
        for item, start in ipairs(positions) do
            if start <= line then index = item end
        end
        index = math.max(1, math.min(#positions, index + direction * vim.v.count1))
        vim.api.nvim_win_set_cursor(0, { assert(positions[index]), 0 })
    end
    -- What a key does on a row that does not take it, by the key's code.
    ---@type table<string, fun()?>
    local plain = {}
    for key, direction in pairs({ j = 1, ["<Down>"] = 1, k = -1, ["<Up>"] = -1 }) do
        plain[vim.api.nvim_replace_termcodes(key, true, false, true)] = function () move(direction) end
    end
    plain[vim.api.nvim_replace_termcodes("<CR>", true, false, true)] = function ()
        activate(vim.api.nvim_win_get_cursor(0)[1])
    end
    ---@type table<string, boolean>
    local mapped = {}
    -- Maps a key once. On a row that takes the key it is reported; elsewhere it does what it did.
    ---@param key string
    local function map(key)
        local code = vim.api.nvim_replace_termcodes(key, true, false, true)
        if mapped[code] then return end
        mapped[code] = true
        vim.keymap.set("n", key, function ()
            local row = by_line[vim.api.nvim_win_get_cursor(0)[1]]
            for taken in pairs(row and row.keys or {}) do
                if vim.api.nvim_replace_termcodes(taken, true, false, true) == code then
                    if on_action then on_action("key", row, taken) end
                    return
                end
            end
            local otherwise = plain[code]
            if otherwise then otherwise() end
        end, { buffer = buffer }
        )
    end
    for _, key in ipairs({ "j", "<Down>", "k", "<Up>", "<CR>" }) do
        map(key)
    end
    ---@type table<string, boolean>
    local clicks = {}
    for _, key in ipairs({ "<LeftRelease>", "<2-LeftRelease>", "<3-LeftRelease>", "<4-LeftRelease>" }) do
        clicks[vim.api.nvim_replace_termcodes(key, true, false, true)] = true
    end
    local right = vim.api.nvim_replace_termcodes("<RightMouse>", true, false, true)
    local right_release = vim.api.nvim_replace_termcodes("<RightRelease>", true, false, true)
    -- Opens the menu of the item on a line, with the cursor moved to the item.
    ---@param window integer
    ---@param line   integer
    local function offer(window, line)
        local row = by_line[line]
        local menu = row and row.menu or {}
        if not row or not on_action or #menu == 0 then return end
        while by_line[line - 1] == row do
            line = line - 1
        end
        vim.api.nvim_win_set_cursor(window, { line, 0 })
        require("herdr-core.ui.prompt").menu(row.lines[1] or "", menu, function (index)
            local choice = index and menu[index]
            if choice then on_action("action", row, choice.action) end
        end)
    end
    -- Observe native clicks so focus can move both into and out of the sidebar. Acting on the release lets a
    -- window opened by the action, such as the place picker, keep the focus the click would otherwise take back.
    vim.on_key(function (key)
        if not clicks[key] and key ~= right and key ~= right_release then return end
        local mouse = vim.fn.getmousepos()
        if mouse.winid == 0 or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
        -- The right button opens the item's menu here; dropping the key keeps Neovim's popup menu away.
        if key == right_release then return "" end
        vim.schedule(function ()
            if not vim.api.nvim_win_is_valid(mouse.winid) or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
            if key == right then
                offer(mouse.winid, mouse.line)
            else
                activate(mouse.line)
            end
        end)
        if key == right then return "" end
    end, namespace)
    ---@param requested? integer
    ---@return integer
    local function show(requested)
        width, shown = requested or width, true
        local current = collapsed and 3 or width
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == buffer then
                vim.api.nvim_win_set_width(window, current)
                return window
            end
        end
        local window = vim.api.nvim_open_win(buffer, false, { split = "left", win = -1, width = current })
        vim.wo[window].number, vim.wo[window].relativenumber = false, false
        vim.wo[window].cursorline, vim.wo[window].cursorcolumn = false, false
        vim.wo[window].foldcolumn, vim.wo[window].colorcolumn = "0", ""
        vim.wo[window].fillchars = "eob: "
        vim.wo[window].winhighlight = "NormalNC:Normal,StatusLine:Normal,StatusLineNC:Normal"
        vim.wo[window].statusline = " "
        vim.wo[window].signcolumn, vim.wo[window].wrap, vim.wo[window].winfixwidth = "no", false, true
        return window
    end
    local group = vim.api.nvim_create_augroup("HerdrCoreSidebar" .. buffer, { clear = true })
    -- Wait until :tabnew has put its own buffer in the new window, which at TabEnter still shows the current buffer.
    vim.api.nvim_create_autocmd("TabEnter", {
        group = group,
        callback = function () vim.schedule(function () if shown then show() end end) end
    })
    local queued = false
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TabEnter" }, {
        group = group,
        callback = function ()
            if queued then return end
            queued = true
            vim.schedule(function ()
                queued = false
                if vim.api.nvim_buf_is_valid(buffer) then render(last_rows, last_waiting) end
            end)
        end
    })
    -- Redraw so the Setup button under the cursor takes the active color.
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = buffer,
        callback = function () render(last_rows, last_waiting) end
    })
    -- A trackpad also scrolls sideways, and the window under the pointer scrolls wherever the cursor is: go back to
    -- the left edge, since every row starts there.
    vim.api.nvim_create_autocmd("WinScrolled", {
        group = group,
        callback = function ()
            for id in pairs(vim.v.event) do
                local window = tonumber(id)
                if window and vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buffer then
                    vim.api.nvim_win_call(window, function ()
                        if vim.fn.winsaveview().leftcol ~= 0 then vim.fn.winrestview({ leftcol = 0 }) end
                    end)
                end
            end
        end
    })
    -- Redraw so the toggle stays on the bottom line when the window height changes.
    vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
        group = group,
        callback = function () render(last_rows, last_waiting) end
    })
    ---@param rows     HerdrCoreSidebarRow[]
    ---@param waiting? integer
    function render(rows, waiting)
        last_rows, last_waiting = rows, waiting or 0
        local lines = { collapsed and tostring(last_waiting) or "  HERDR" }
        -- The row under the cursor is selected only while the cursor is in the sidebar.
        local cursor = vim.api.nvim_get_current_buf() == buffer and vim.api.nvim_win_get_cursor(0)[1] or nil
        -- Whether the rows last drawn at the top were items without a heading.
        local flat = false
        ---@type { row: integer, group: string, start_col: integer?, end_col: integer?, priority: integer? } []
        local marks = { { row = 0, group = collapsed and "HerdrCoreMuted" or "HerdrCoreHeader" } }
        ---@type { line: integer, start_col: integer, end_col: integer } []
        local buttons = {}
        -- The mark of the space heading each terminal row sits under, by the row's first line.
        ---@type table<integer, integer>
        local space_of = {}
        local space_mark = 0
        by_line = {}
        positions = {}
        local setup_rows = vim.tbl_filter(function (row) return row.kind:find("^setup_") ~= nil end, rows)
        if collapsed and #setup_rows > 0 then
            lines[#lines + 1] = "!"
            marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreBlocked" }
        end
        if not collapsed then
            local button = " New terminal "
            lines[#lines + 1] = " " .. button
            by_line[#lines] = { kind = "new_terminal", lines = {} }
            positions[#positions + 1] = #lines
            buttons[#buttons + 1] = { line = #lines, start_col = 1, end_col = 1 + #button }
        end
        for _, row in ipairs(collapsed and {} or rows) do
            if row.kind:find("^setup_") then goto continue end
            -- A blank line sets a section apart, and items at the top apart from the section before them.
            if (row.kind == "section" or (row.top and not flat)) and #lines > 1 then lines[#lines + 1] = "" end
            if row.kind == "section" then
                flat = false
            elseif row.top then
                flat, space_mark = true, 0
            end
            local start = #lines + 1
            local keys = row.keys or {}
            for key in pairs(keys) do
                if key ~= "use" then map(key) end
            end
            if row.kind == "section" then
                local count = (row.waiting or 0) > 0 and "  · " .. row.waiting or ""
                lines[#lines + 1] = "  " .. (row.lines[1] or "") .. count
                marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreSpace" }
                space_mark = #marks
            elseif row.kind == "item" and row.guide then
                -- A deeper item takes one line under its parent: guide, status, label, then the detail dimmed.
                local guide = "    " .. row.guide
                local head = guide .. (symbols[row.status] or " ") .. " "
                local name = row.lines[1] or ""
                local status = row.status or "idle"
                lines[#lines + 1] = head .. name .. "  " .. (row.lines[2] or "")
                vim.list_extend(marks, {
                    { row = #lines - 1, group = "HerdrCoreProgram", start_col = 4, end_col = #guide },
                    {
                        row = #lines - 1,
                        group = "HerdrCore" .. status:sub(1, 1):upper() .. status:sub(2),
                        start_col = #guide,
                        end_col = #head
                    },
                    { row = #lines - 1, group = "HerdrCoreLabel", start_col = #head, end_col = #head + #name },
                    { row = #lines - 1, group = "HerdrCoreProgram", start_col = #head + #name + 2 }
                })
                space_of[start] = space_mark
            elseif row.kind == "item" then
                local count = (row.waiting or 0) > 0 and "  · " .. row.waiting or ""
                lines[#lines + 1] = "  " .. (symbols[row.status] or " ") .. " " .. (row.lines[1] or "") .. count
                marks[#marks + 1] = {
                    row = #lines - 1,
                    group = "HerdrCoreLabel",
                    start_col = #("  " .. (symbols[row.status] or " ") .. " ")
                }
                local status = row.status or "idle"
                marks[#marks + 1] = {
                    row = #lines - 1,
                    group = "HerdrCore" .. status:sub(1, 1):upper() .. status:sub(2),
                    end_col = #("  " .. (symbols[row.status] or " ") .. " ")
                }
                -- An item without a detail takes the one line.
                if row.lines[2] then
                    lines[#lines + 1] = "    " .. row.lines[2]
                    marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreProgram" }
                end
                space_of[start] = space_mark
            end
            -- j and k stop on the items that take keys.
            if row.kind == "item" and next(keys) ~= nil then
                positions[#positions + 1] = start
            end
            for line = start, #lines do
                by_line[line] = row
            end
            ::continue::
        end
        -- The toggle sits on the window's bottom line, below the rows.
        local height, footer_width = 0, collapsed and 3 or width
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == buffer then
                height = vim.api.nvim_win_get_height(window)
                footer_width = vim.api.nvim_win_get_width(window)
            end
        end
        local box = collapsed and {} or setup_box(setup_rows, footer_width)
        while #lines < height - 1 - #box do
            lines[#lines + 1] = ""
        end
        if #box > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
        for _, entry in ipairs(box) do
            lines[#lines + 1] = entry.text
            local line = #lines
            if entry.group then
                marks[#marks + 1] = { row = line - 1, group = entry.group }
            end
            if entry.row then by_line[line] = entry.row end
            if entry.button_start then
                positions[#positions + 1] = line
                buttons[#buttons + 1] = { line = line, start_col = entry.button_start, end_col = entry.button_end }
            end
        end
        local toggle_button = collapsed and " » " or " « "
        lines[#lines + 1] = string.rep(" ", math.max(0, footer_width - 3)) .. toggle_button
        footer = #lines
        positions[#positions + 1] = footer
        buttons[#buttons + 1] = { line = footer, start_col = #lines[footer] - #toggle_button, end_col = #lines[footer] }
        -- The lines of the row that holds `line`.
        ---@param line integer
        ---@return { first: integer, last: integer }
        local function extent(line)
            local row, first, last = by_line[line], line, line
            while row and by_line[first - 1] == row do
                first = first - 1
            end
            while row and by_line[last + 1] == row do
                last = last + 1
            end
            return { first = first, last = last }
        end
        -- The highlighted items, and the accent on the headings of the sections holding them.
        ---@type { [1]: { first: integer, last: integer }, [2]: string, [3]: integer } []
        local ranges = {}
        for line, row in pairs(by_line) do
            local owner = space_of[line]
            if row.kind == "item" and row.highlighted and owner then
                ranges[#ranges + 1] = { extent(line), "HerdrCoreActive", 90 }
                if owner > 0 then assert(marks[owner]).group = "HerdrCoreSpaceActive" end
            end
        end
        ---@type { first: integer, last: integer }?
        local selected
        if cursor and (by_line[cursor] or cursor == footer) then selected = extent(cursor) end
        local on_button = false
        for _, button in ipairs(buttons) do
            local chosen = selected and button.line >= selected.first and button.line <= selected.last
            on_button = on_button or chosen == true
            marks[#marks + 1] = {
                row = button.line - 1,
                group = chosen and "HerdrCoreButtonActive" or "HerdrCoreButton",
                start_col = button.start_col,
                end_col = button.end_col,
                priority = 5000
            }
        end
        vim.bo[buffer].modifiable = true
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
        -- Gray marks the highlighted items, the accent the row under the cursor, which wins on the same row.
        -- On a row with a button, the button alone shows the selection.
        if selected and not on_button then
            ranges[#ranges + 1] = { selected, "HerdrCoreSelected", 95 }
        end
        for _, range in ipairs(ranges) do
            vim.api.nvim_buf_set_extmark(buffer, namespace, range[1].first - 1, 0, {
                end_row = range[1].last,
                hl_group = range[2],
                hl_eol = true,
                priority = range[3]
            })
        end
        for _, mark in ipairs(marks) do
            vim.api.nvim_buf_set_extmark(buffer, namespace, mark.row, mark.start_col or 0, {
                end_row = mark.end_col and mark.row or mark.row + 1,
                end_col = mark.end_col,
                hl_group = mark.group,
                hl_eol = not mark.end_col,
                priority = mark.priority
            })
        end
        vim.bo[buffer].modifiable = false
    end
    local function close()
        shown = false
        vim.on_key(nil, namespace)
        vim.api.nvim_del_augroup_by_id(group)
        for _, window in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(window) == buffer then vim.api.nvim_win_close(window, true) end
        end
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
    return { buffer = buffer, render = render, show = show, close = close, toggle = toggle }
end

return M
