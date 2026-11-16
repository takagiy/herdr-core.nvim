local M = {}

---@param current  string
---@param callback fun(value: string?)
function M.name(current, callback)
    vim.ui.input({ prompt = "Terminal name: ", default = current }, callback)
end

---@class HerdrCoreChoice
---@field label string
---@field path  string

-- Takes the arguments of vim.ui.select, so that vim.ui.select can stand in for it.
-- A floating window centered in the editor; the row under the cursor is selected, as in the sidebar.
---@param items     HerdrCoreChoice[]
---@param options   { prompt?: string }
---@param on_choice fun(item: HerdrCoreChoice?) Called once, with nil when the window closes without a choice.
function M.choose(items, options, on_choice)
    local title = options.prompt or ""
    local width = vim.fn.strdisplaywidth(title) + 4
    for _, item in ipairs(items) do
        width = math.max(width, vim.fn.strdisplaywidth(item.label) + 2)
    end
    -- The border takes a column on each side.
    width = math.min(width, math.max(1, vim.o.columns - 2))
    local lines = {}
    for _, item in ipairs(items) do
        local label = item.label
        -- A path tells folders apart by its end, so a long one loses its start.
        while vim.fn.strdisplaywidth(label) > width - 2 and vim.fn.strchars(label) > 1 do
            label = "…" .. vim.fn.strcharpart(label, 2)
        end
        lines[#lines + 1] = " " .. label .. " "
    end
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable, vim.bo[buffer].bufhidden = false, "wipe"
    local height = math.max(1, #lines)
    local window = vim.api.nvim_open_win(buffer, true, {
        relative = "editor",
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = title ~= "" and " " .. title .. " " or nil,
        title_pos = title ~= "" and "center" or nil
    })
    vim.wo[window].cursorline, vim.wo[window].wrap = true, false
    vim.wo[window].winhighlight = "NormalFloat:Normal,FloatBorder:HerdrCoreMuted,CursorLine:HerdrCoreSelected"
    local done = false
    ---@param item HerdrCoreChoice?
    local function finish(item)
        if done then return end
        done = true
        if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
        on_choice(item)
    end
    ---@param line integer
    local function pick(line)
        finish(items[line])
    end
    vim.keymap.set("n", "<CR>", function () pick(assert(vim.api.nvim_win_get_cursor(window)[1])) end, {
        buffer = buffer
    })
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function () finish(nil) end, { buffer = buffer })
    end
    vim.keymap.set("n", "<LeftRelease>", function ()
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= window then return finish(nil) end
        pick(mouse.line)
    end, { buffer = buffer }
    )
    -- Moving to another window closes it, as a cancel.
    vim.api.nvim_create_autocmd("WinLeave", { buffer = buffer, once = true, callback = function () finish(nil) end })
end

return M
