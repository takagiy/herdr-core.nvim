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
    local namespace = vim.api.nvim_create_namespace("HerdrCoreSidebar")
    ---@type table<integer, HerdrCoreSidebarRow>
    local by_line = {}
    ---@type table<integer, integer>
    local plus = {}
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
    vim.keymap.set(
        "n", bound.activate, function () activate(assert(vim.api.nvim_win_get_cursor(0)[1])) end, { buffer = buffer }
    )
    local function click()
        local mouse = vim.fn.getmousepos()
        if mouse.winid == 0 or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
        vim.api.nvim_set_current_win(mouse.winid)
        vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
        activate(mouse.line, mouse.column)
    end
    -- Quick repeated clicks arrive as multi-clicks; each one still acts like a click.
    for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>" }) do
        vim.keymap.set("n", key, click, { buffer = buffer })
    end
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
        vim.wo[window].signcolumn, vim.wo[window].wrap, vim.wo[window].winfixwidth = "no", false, true
        return window
    end
    local group = vim.api.nvim_create_augroup("HerdrCoreSidebar" .. buffer, { clear = true })
    -- Wait until :tabnew has put its own buffer in the new window, which at TabEnter still shows the current buffer.
    vim.api.nvim_create_autocmd("TabEnter", {
        group = group,
        callback = function () vim.schedule(function () if shown then show() end end) end
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
        local lines = { collapsed and tostring(last_waiting) or "Waiting: " .. last_waiting }
        local marks = {}
        by_line = {}
        plus = {}
        for _, row in ipairs(collapsed and {} or rows) do
            local start = #lines + 1
            if row.kind == "space" then
                lines[#lines + 1] = (row.root or "") .. "  [" .. (row.waiting or 0) .. "]  +"
                plus[#lines] = vim.fn.strdisplaywidth(lines[#lines])
                marks[#marks + 1] = { #lines - 1, "HerdrCoreSpace" }
            elseif row.kind == "machine" then
                lines[#lines + 1] = (row.machine or "") .. (row.connected == false and " (disconnected)" or "")
                marks[#marks + 1] = { #lines - 1, "HerdrCoreMachine" }
            elseif row.kind == "terminal" then
                lines[#lines + 1] = "  " .. (symbols[row.status] or " ") .. " " .. (row.lines[1] or "")
                local status = row.status or "idle"
                marks[#marks + 1] = { #lines - 1, "HerdrCore" .. status:sub(1, 1):upper() .. status:sub(2) }
                lines[#lines + 1] = "    " .. (row.lines[2] or "")
            end
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
        lines[#lines + 1] = collapsed and "»" or "« Collapse"
        footer = #lines
        vim.bo[buffer].modifiable = true
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
        for _, mark in ipairs(marks) do
            vim.api.nvim_buf_set_extmark(buffer, namespace, mark[1], 0, {
                end_row = mark[1] + 1,
                hl_group = mark[2],
                hl_eol = true
            })
        end
        vim.bo[buffer].modifiable = false
    end
    local function close()
        shown = false
        vim.api.nvim_del_augroup_by_id(group)
        for _, window in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(window) == buffer then vim.api.nvim_win_close(window, true) end
        end
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
    return { buffer = buffer, render = render, show = show, close = close, toggle = toggle }
end

return M
