local M = {}

local symbols = { working = "◐", blocked = "●", error = "✗", done = "✓", idle = "○" }

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
    ---@type table<integer, integer>
    local plus = {}
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
    ---@param line    integer
    ---@param column? integer
    local function activate(line, column)
        if line == footer then
            toggle()
            return
        end
        local action = column and plus[line] == column and "new_terminal" or "activate"
        if on_action then on_action(action, by_line[line]) end
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
    for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>" }) do
        clicks[vim.api.nvim_replace_termcodes(key, true, false, true)] = true
    end
    -- Observe native clicks so focus can move both into and out of the sidebar.
    vim.on_key(function (key)
        if not clicks[key] then return end
        local mouse = vim.fn.getmousepos()
        if mouse.winid == 0 or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
        vim.schedule(function ()
            if not vim.api.nvim_win_is_valid(mouse.winid) or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
            activate(mouse.line, mouse.column)
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
        local active = vim.t.herdr_core_active_terminal
        ---@type { first: integer, last: integer }?
        local selected
        ---@type { row: integer, group: string, start_col: integer?, end_col: integer? } []
        local marks = { { row = 0, group = collapsed and "HerdrCoreMuted" or "HerdrCoreHeader" } }
        local space_mark = 0
        by_line = {}
        plus = {}
        positions = {}
        for _, row in ipairs(collapsed and {} or rows) do
            if row.kind == "space" and #lines > 1 then lines[#lines + 1] = "" end
            local start = #lines + 1
            if row.kind == "space" then
                local count = (row.waiting or 0) > 0 and "  · " .. row.waiting or ""
                lines[#lines + 1] = "  " .. (row.folded and "▸" or "▾")
                    .. " " .. vim.fs.basename(row.root or "")
                    .. count .. "  +"
                -- getmousepos().column is a byte position, not a screen column.
                plus[#lines] = #lines[#lines]
                marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreSpace" }
                space_mark = #marks
            elseif row.kind == "machine" then
                space_mark = 0
                lines[#lines + 1] = (row.machine or "") .. (row.connected == false and " (disconnected)" or "")
                marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreMachine" }
            elseif row.kind == "terminal" then
                lines[#lines + 1] = "  " .. (symbols[row.status] or " ") .. " " .. (row.lines[1] or "")
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
                if active and row.address == active then
                    selected = { first = start - 1, last = #lines }
                    if space_mark > 0 then assert(marks[space_mark]).group = "HerdrCoreSpaceActive" end
                end
            end
            if #lines >= start then positions[#positions + 1] = start end
            for line = start, #lines do
                by_line[line] = row
            end
        end
        -- The toggle sits on the window's bottom line, below the rows.
        local height = 0
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == buffer then height = vim.api.nvim_win_get_height(window) end
        end
        while #lines < height - 1 do
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = collapsed and "»" or "«"
        marks[#marks + 1] = { row = #lines - 1, group = "HerdrCoreMuted" }
        footer = #lines
        positions[#positions + 1] = footer
        vim.bo[buffer].modifiable = true
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
        if not collapsed and last_waiting > 0 then
            vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 0, {
                virt_text = { { last_waiting .. " waiting  ", "HerdrCoreBlocked" } },
                virt_text_pos = "right_align"
            })
        end
        if selected then
            vim.api.nvim_buf_set_extmark(buffer, namespace, selected.first, 0, {
                end_row = selected.last,
                hl_group = "HerdrCoreActive",
                hl_eol = true,
                priority = 90
            })
        end
        for _, mark in ipairs(marks) do
            vim.api.nvim_buf_set_extmark(buffer, namespace, mark.row, mark.start_col or 0, {
                end_row = mark.end_col and mark.row or mark.row + 1,
                end_col = mark.end_col,
                hl_group = mark.group,
                hl_eol = not mark.end_col
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
