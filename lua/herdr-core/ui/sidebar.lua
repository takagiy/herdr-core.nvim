local M = {}

---@class HerdrCoreSidebarView
---@field buffer integer
---@field render fun(rows: HerdrCoreSidebarRow[], collapsed: boolean?, waiting: integer?)
---@field show   fun(width: integer?): integer
---@field close  fun()

---@param on_action? fun(action: string, row: HerdrCoreSidebarRow?)
---@return HerdrCoreSidebarView
function M.create(on_action)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_sidebar = true
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].filetype = "herdr-core"
    local namespace = vim.api.nvim_create_namespace("HerdrCoreSidebar")
    ---@type table<integer, HerdrCoreSidebarRow>
    local by_line = {}
    ---@type table<integer, integer>
    local plus = {}
    ---@param line    integer
    ---@param column? integer
    local function activate(line, column)
        local action = column and plus[line] == column and "new_terminal" or "activate"
        if on_action then on_action(action, by_line[line]) end
    end
    vim.keymap.set(
        "n", "<CR>", function () activate(assert(vim.api.nvim_win_get_cursor(0)[1])) end, { buffer = buffer }
    )
    vim.keymap.set("n", "<LeftMouse>", function ()
        local mouse = vim.fn.getmousepos()
        if mouse.winid == 0 or vim.api.nvim_win_get_buf(mouse.winid) ~= buffer then return end
        vim.api.nvim_set_current_win(mouse.winid)
        vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
        activate(mouse.line, mouse.column)
    end, { buffer = buffer }
    )
    vim.keymap.set("n", "n", function ()
        if on_action then on_action("new_terminal", by_line[assert(vim.api.nvim_win_get_cursor(0)[1])]) end
    end, { buffer = buffer }
    )
    local width, shown = 32, false
    ---@param requested? integer
    ---@return integer
    local function show(requested)
        width, shown = requested or width, true
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == buffer then
                vim.api.nvim_win_set_width(window, width)
                return window
            end
        end
        local window = vim.api.nvim_open_win(buffer, false, { split = "left", win = -1, width = width })
        vim.wo[window].number, vim.wo[window].relativenumber = false, false
        vim.wo[window].signcolumn, vim.wo[window].wrap, vim.wo[window].winfixwidth = "no", false, true
        return window
    end
    local group = vim.api.nvim_create_augroup("HerdrCoreSidebar" .. buffer, { clear = true })
    vim.api.nvim_create_autocmd("TabEnter", { group = group, callback = function () if shown then show() end end })
    ---@param rows        HerdrCoreSidebarRow[]
    ---@param _collapsed? boolean
    ---@param waiting?    integer
    local function render(rows, _collapsed, waiting)
        local lines = { "Waiting: " .. (waiting or 0) }
        local marks = {}
        by_line = {}
        plus = {}
        for _, row in ipairs(rows) do
            local start = #lines + 1
            if row.kind == "space" then
                lines[#lines + 1] = (row.root or "") .. "  [" .. (row.waiting or 0) .. "]  +"
                plus[#lines] = vim.fn.strdisplaywidth(lines[#lines])
                marks[#marks + 1] = { #lines - 1, "HerdrCoreSpace" }
            elseif row.kind == "machine" then
                lines[#lines + 1] = (row.machine or "") .. (row.connected == false and " (disconnected)" or "")
                marks[#marks + 1] = { #lines - 1, "HerdrCoreMachine" }
            elseif row.kind == "terminal" then
                lines[#lines + 1] = "  ● " .. (row.lines[1] or "")
                local status = row.status or "idle"
                marks[#marks + 1] = { #lines - 1, "HerdrCore" .. status:sub(1, 1):upper() .. status:sub(2) }
                lines[#lines + 1] = "    " .. (row.lines[2] or "")
            end
            for line = start, #lines do
                by_line[line] = row
            end
        end
        lines[#lines + 1] = "« Collapse"
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
    return { buffer = buffer, render = render, show = show, close = close }
end

return M
