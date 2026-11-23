local M = {}

---@param current  string
---@param callback fun(value: string?)
function M.name(current, callback)
    vim.ui.input({ prompt = "Terminal name: ", default = current }, callback)
end

---@class HerdrCoreChoice
---@field label string
---@field path  string

-- A floating window that lists lines; the row under the cursor is selected, as in the sidebar. Enter and a
-- click choose a line; q, Esc, a click outside and leaving the window choose none.
---@param lines     string[]
---@param config    table               The window's place and title, over a rounded border.
---@param on_choice fun(line: integer?) Called once.
---@return integer buffer
---@return fun(line: integer?) finish Closes the window with a line chosen, or none.
local function list(lines, config, on_choice)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable, vim.bo[buffer].bufhidden = false, "wipe"
    local window = vim.api.nvim_open_win(
        buffer, true,
        vim.tbl_extend("force", { height = math.max(1, #lines), style = "minimal", border = "rounded" }, config)
    )
    vim.wo[window].cursorline, vim.wo[window].wrap = true, false
    vim.wo[window].winhighlight = "NormalFloat:Normal,FloatBorder:HerdrCoreMuted,CursorLine:HerdrCoreSelected"
    local done = false
    ---@param line integer?
    local function finish(line)
        if done then return end
        done = true
        if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
        on_choice(line)
    end
    vim.keymap.set("n", "<CR>", function () finish(vim.api.nvim_win_get_cursor(window)[1]) end, {
        buffer = buffer
    })
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function () finish(nil) end, { buffer = buffer })
    end
    vim.keymap.set("n", "<LeftRelease>", function ()
        local mouse = vim.fn.getmousepos()
        finish(mouse.winid == window and mouse.line or nil)
    end, { buffer = buffer }
    )
    -- Moving to another window closes it, as a cancel.
    vim.api.nvim_create_autocmd("WinLeave", { buffer = buffer, once = true, callback = function () finish(nil) end })
    return buffer, finish
end

-- Takes the arguments of vim.ui.select, so that vim.ui.select can stand in for it.
-- A floating window centered in the editor.
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
    list(lines, {
        relative = "editor",
        row = math.max(0, math.floor((vim.o.lines - math.max(1, #lines)) / 2) - 1),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        width = width,
        title = title ~= "" and " " .. title .. " " or nil,
        title_pos = title ~= "" and "center" or nil
    }, function (line) on_choice(line and items[line] or nil) end
    )
end

local namespace = vim.api.nvim_create_namespace("herdr-core-menu")

-- A menu at the mouse pointer: each choice on a line, with the keys that run it at the right. Enter runs the
-- choice under the cursor, and a choice's key runs it from any line.
---@param title     string
---@param choices   { label: string, keys: string[] } []
---@param on_choice fun(index: integer?)                 Called once, with nil when the menu closes without a choice.
function M.menu(title, choices, on_choice)
    local hints, labels, keys = {}, 0, 0
    for index, choice in ipairs(choices) do
        hints[index] = table.concat(choice.keys, " ")
        labels = math.max(labels, vim.fn.strdisplaywidth(choice.label))
        keys = math.max(keys, vim.fn.strdisplaywidth(hints[index]))
    end
    -- A column on each side, and two between the labels and the keys.
    local width = math.max(labels + (keys > 0 and keys + 2 or 0) + 2, vim.fn.strdisplaywidth(title) + 4)
    local lines = {}
    for index, choice in ipairs(choices) do
        local gap = width - 2 - vim.fn.strdisplaywidth(choice.label) - vim.fn.strdisplaywidth(hints[index])
        lines[index] = " " .. choice.label .. string.rep(" ", gap) .. hints[index] .. " "
    end
    local buffer, finish = list(lines, {
        relative = "mouse",
        row = 1,
        col = 0,
        width = width,
        title = " " .. title .. " ",
        title_pos = "left"
    }, function (line) on_choice(line and choices[line] and line or nil) end
    )
    for index, choice in ipairs(choices) do
        if hints[index] ~= "" then
            vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1, #lines[index] - 1 - #hints[index], {
                end_col = #lines[index] - 1,
                hl_group = "HerdrCoreMuted"
            })
        end
        -- Set after q and Esc, so a choice that takes one of them keeps it.
        for _, key in ipairs(choice.keys) do
            vim.keymap.set("n", key, function () finish(index) end, { buffer = buffer, nowait = true })
        end
    end
end

return M
