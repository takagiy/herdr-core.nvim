local M = {}

local symbols = { working = "◐", blocked = "●", error = "✗", done = "✓", idle = "○" }

-- Labels on the left of the Setup panel take this many columns, the last one a gap; buttons start after them.
local label_width = 13

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
    local inner = math.max(label_width + 2, width - 4)
    local lines = { { text = " ╭ Setup " .. string.rep("─", inner - 7) .. "╮", group = "HerdrCoreMuted" } }
    for _, row in ipairs(rows) do
        local indent = (row.kind == "setup_item" or row.kind == "setup_error") and "  " or " "
        local left = indent .. (row.lines[1] or "")
        local line = { row = row }
        if row.button then
            left = fit(left, label_width - 1) .. " "
            local button = " " .. row.button .. " "
            line.text = " │" .. left .. fit(button, inner - label_width) .. "│"
            line.button_start = #(" │" .. left)
            line.button_end = line.button_start + #button
            line.group = row.kind == "setup_heading" and "HerdrCoreHeader" or nil
        else
            line.text = " │" .. fit(left, inner) .. "│"
            line.group = row.kind == "setup_heading" and "HerdrCoreHeader" or "HerdrCoreMuted"
        end
        lines[#lines + 1] = line
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

---@class HerdrCoreSidebarKeys
---@field activate?     string
---@field new_terminal? string
---@field rename?       string
---@field pin?          string
---@field unread?       string

---@param on_action? fun(action: string, row: HerdrCoreSidebarRow?, value: string?)
---@param keys?      HerdrCoreSidebarKeys
---@return HerdrCoreSidebarView
function M.create(on_action, keys)
    ---@type table<string, string>
    local bound = vim.tbl_extend(
        "force", { activate = "<CR>", new_terminal = "n", rename = "r", pin = "p", unread = "u" }, keys or {}
    )
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_sidebar = true
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].filetype = "herdr-core"
    local namespace = vim.api.nvim_create_namespace("HerdrCoreSidebar" .. buffer)
    ---@type table<integer, HerdrCoreSidebarRow>
    local by_line = {}
    ---@type integer[]
    local positions = {}
    local width, shown, collapsed, footer = 32, false, false, 0
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
        -- Space headings have no button to press.
        if not row or not on_action or row.kind == "space" then return end
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
    for _, key in ipairs({ "j", "<Down>" }) do
        vim.keymap.set("n", key, function () move(1) end, { buffer = buffer })
    end
    for _, key in ipairs({ "k", "<Up>" }) do
        vim.keymap.set("n", key, function () move(-1) end, { buffer = buffer })
    end
    vim.keymap.set(
        "n", bound.activate, function () activate(assert(vim.api.nvim_win_get_cursor(0)[1])) end, { buffer = buffer }
    )
    ---@type table<string, boolean>
    local clicks = {}
    for _, key in ipairs({ "<LeftRelease>", "<2-LeftRelease>", "<3-LeftRelease>", "<4-LeftRelease>" }) do
        clicks[vim.api.nvim_replace_termcodes(key, true, false, true)] = true
    end
    -- Observe native clicks so focus can move both into and out of the sidebar. Acting on the release lets a
    -- window opened by the action, such as the place picker, keep the focus the click would otherwise take back.
    vim.on_key(function (key)
        if not clicks[key] then return end
        local mouse = vim.fn.getmousepos()
        if mouse.winid == 0 or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
        vim.schedule(function ()
            if not vim.api.nvim_win_is_valid(mouse.winid) or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
            activate(mouse.line)
        end)
    end, namespace)
    vim.keymap.set("n", bound.new_terminal, function ()
        if on_action then on_action("new_terminal", by_line[assert(vim.api.nvim_win_get_cursor(0)[1])]) end
    end, { buffer = buffer }
    )
    vim.keymap.set("n", bound.rename, function ()
        local row = by_line[assert(vim.api.nvim_win_get_cursor(0)[1])]
        if not row or row.kind ~= "terminal" then return end
        require("herdr-core.ui.prompt").name(row.lines[1] or "", function (name)
            if name ~= nil and on_action then on_action("rename", row, name) end
        end)
    end, { buffer = buffer }
    )
    for _, action in ipairs({ "pin", "unread" }) do
        vim.keymap.set("n", bound[action], function ()
            local row = by_line[assert(vim.api.nvim_win_get_cursor(0)[1])]
            if row and row.kind == "terminal" and on_action then on_action(action, row) end
        end, { buffer = buffer }
        )
    end
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
        local current = vim.api.nvim_get_current_buf()
        if current ~= buffer then vim.t.herdr_core_active_terminal = vim.b[current].herdr_core_address end
        -- The row under the cursor is selected only while the cursor is in the sidebar.
        local cursor = current == buffer and vim.api.nvim_win_get_cursor(0)[1] or nil
        local active = vim.t.herdr_core_active_terminal
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
            if row.kind == "space" and #lines > 1 then lines[#lines + 1] = "" end
            local start = #lines + 1
            if row.kind == "space" then
                local count = (row.waiting or 0) > 0 and "  · " .. row.waiting or ""
                lines[#lines + 1] = "  " .. vim.fs.basename(row.root or "") .. count
                marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreSpace" }
                space_mark = #marks
            elseif row.kind == "machine" then
                space_mark = 0
                lines[#lines + 1] = (row.machine or "") .. (row.connected == false and " (disconnected)" or "")
                marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreMachine" }
            elseif row.kind == "terminal" and row.guide then
                -- A child takes one line under its parent's name: guide, status, name, then the program dimmed.
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
            elseif row.kind == "terminal" then
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
                lines[#lines + 1] = "    " .. (row.lines[2] or "")
                marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreProgram" }
                space_of[start] = space_mark
            end
            -- j and k stop on rows that do something; a space heading only labels its terminals.
            if #lines >= start and row.kind ~= "space" then positions[#positions + 1] = start end
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
        ---@type { first: integer, last: integer }?
        local front
        for line, row in pairs(by_line) do
            if active and row.kind == "terminal" and row.address == active and space_of[line] then
                front = { first = line, last = line + 1 }
            end
        end
        ---@type { first: integer, last: integer }?
        local selected
        if cursor and (by_line[cursor] or cursor == footer) then
            local row, first, last = by_line[cursor], cursor, cursor
            while row and by_line[first - 1] == row do
                first = first - 1
            end
            while row and by_line[last + 1] == row do
                last = last + 1
            end
            selected = { first = first, last = last }
        end
        -- The space holding the terminal in front takes the accent.
        local owner = front and space_of[front.first]
        if owner and owner > 0 then assert(marks[owner]).group = "HerdrCoreSpaceActive" end
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
        -- Gray marks the terminal in front, the accent the row under the cursor, which wins on the same row.
        -- On a row with a button, the button alone shows the selection.
        local row = not on_button and selected or nil
        for _, range in ipairs({ { front, "HerdrCoreActive", 90 }, { row, "HerdrCoreSelected", 95 } }) do
            if range[1] then
                vim.api.nvim_buf_set_extmark(buffer, namespace, range[1].first - 1, 0, {
                    end_row = range[1].last,
                    hl_group = range[2],
                    hl_eol = true,
                    priority = range[3]
                })
            end
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
