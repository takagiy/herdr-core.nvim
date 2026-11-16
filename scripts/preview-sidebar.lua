-- Prints the sidebar with its real highlights as 24-bit ANSI colors.
-- Usage: nvim --clean --headless -l scripts/preview-sidebar.lua [light|dark] [colorscheme]
local scheme = arg[2]
---@type 'light' | 'dark'
local background = arg[1] == "dark" and "dark" or "light"
local root = vim.fn.fnamemodify(assert(debug.getinfo(1, "S")).source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, path in ipairs(vim.fn.glob(vim.fn.stdpath("data") .. "/lazy/*", false, true)) do
    vim.opt.rtp:append(path)
end
vim.o.background = background
if scheme == "onedark" then
    -- onedark picks its light or dark palette from its own style, not from background.
    vim.cmd.lua(string.format("require('onedark').setup({ style = '%s' }); require('onedark').load()", background))
elseif scheme then
    vim.cmd.colorscheme(scheme)
end
vim.o.termguicolors = true
vim.o.lines, vim.o.columns = 30, 100

require("herdr-core.ui.highlights").setup()
local sidebar = require("herdr-core.ui.sidebar").create()
local window = sidebar.show(32)
local rows = {
    { kind = "space", root = "/herdr-core.nvim", waiting = 1, lines = {} },
    { kind = "terminal", address = "t1", status = "working", lines = { "fix-login", "claude" } },
    { kind = "terminal", address = "t3", status = "blocked", lines = { "review", "codex" } },
    { kind = "space", root = "/dotnvim", lines = {} },
    { kind = "terminal", address = "t5", lines = { "t5", "zsh" } },
    {
        kind = "setup_heading",
        group = "integration",
        lines = { "Integration" },
        button = "Install all",
        action = "install_all"
    },
    { kind = "setup_text", group = "integration", lines = { "Supported agents detected." } },
    {
        kind = "setup_item",
        group = "integration",
        name = "claude",
        lines = { "claude" },
        button = "Install",
        action = "install"
    },
    {
        kind = "setup_item",
        group = "integration",
        name = "codex",
        lines = { "codex" },
        button = "Update",
        action = "install"
    },
    { kind = "setup_button", lines = { "" }, button = "Dismiss", action = "dismiss" }
}

---@param name string
---@return { fg: integer?, bg: integer?, bold: boolean?, reverse: boolean? }
local function color(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false })
end

---@param value integer
---@return string
local function rgb(value)
    return string.format("%d;%d;%d", math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
end

-- The sidebar as lines of styled cells, from its text and extmarks.
---@return string[]
local function capture()
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    local normal = color("Normal")
    local base = {
        fg = normal.fg or (background == "dark" and 0xd0d0d0 or 0x303030),
        bg = normal.bg or (background == "dark" and 0x202020 or 0xfafafa)
    }
    local marks = vim.api.nvim_buf_get_extmarks(sidebar.buffer, -1, 0, -1, { details = true })
    table.sort(marks, function (a, b) return (assert(a[4]).priority or 4096) < (assert(b[4]).priority or 4096) end)
    local width = vim.api.nvim_win_get_width(window)
    local out = {}
    for index, text in ipairs(lines) do
        local row = index - 1
        local cells = {}
        local starts = vim.str_utf_pos(text)
        for position, start in ipairs(starts) do
            local finish = (starts[position + 1] or #text + 1) - 1
            cells[#cells + 1] = { text = text:sub(start, finish), from = start - 1, style = vim.deepcopy(base) }
        end
        while vim.fn.strdisplaywidth(text) + (#cells - #starts) < width do
            cells[#cells + 1] = { text = " ", from = math.huge, style = vim.deepcopy(base) }
        end
        for _, mark in ipairs(marks) do
            local details = assert(mark[4])
            local first, last = mark[2], details.end_row or mark[2]
            if details.hl_group and row >= first and row <= last then
                local from = row == first and mark[3] or 0
                local to = (row == last and details.end_col) or math.huge
                if row == last and details.end_col == 0 and last > first then to = -1 end
                local group = color(details.hl_group)
                if group.reverse then
                    -- Reverse swaps the colors under it, like a block cursor.
                    group = { fg = group.bg or base.bg, bg = group.fg or base.fg, bold = group.bold }
                end
                for _, cell in ipairs(cells) do
                    local inside = cell.from >= from and cell.from < to
                    if cell.from == math.huge then
                        inside = details.hl_eol == true and row < (details.end_col and last or last + 1)
                    end
                    if inside then
                        cell.style.fg = group.fg or cell.style.fg
                        cell.style.bg = group.bg or cell.style.bg
                        if group.bold then cell.style.bold = true end
                    end
                end
            end
        end
        local parts = {}
        for _, cell in ipairs(cells) do
            parts[#parts + 1] = string.format(
                "\27[%s38;2;%sm\27[48;2;%sm%s", cell.style.bold and "1;" or "22;", rgb(cell.style.fg),
                rgb(cell.style.bg), cell.text
            )
        end
        out[#out + 1] = table.concat(parts) .. "\27[0m"
    end
    return out
end

-- The terminal t1 is in front, as if its window had focus.
local terminal = vim.api.nvim_create_buf(false, true)
vim.b[terminal].herdr_core_address = "t1"
vim.cmd.wincmd("l")
local editor = vim.api.nvim_get_current_win()

local variants = { { "herdr-core.nvim (" .. background .. ")" } }
local gap = "    "
vim.o.lines = 22
for _, variant in ipairs(variants) do
    vim.api.nvim_set_current_win(editor)
    vim.api.nvim_set_current_buf(terminal)
    sidebar.render(rows, 1)
    local outside = capture()
    -- Then the cursor moves into the sidebar, onto the review terminal.
    vim.api.nvim_set_current_win(window)
    for line, text in ipairs(vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)) do
        if text:find("review", 1, true) then vim.api.nvim_win_set_cursor(window, { line, 0 }) end
    end
    sidebar.render(rows, 1)
    local inside = capture()
    io.write("\n" .. variant[1] .. "\n")
    io.write(string.format("%-32s%s%s\n", "cursor outside the sidebar", gap, "cursor on review"))
    for index = 1, math.max(#outside, #inside) do
        io.write((outside[index] or string.rep(" ", 32)) .. gap .. (inside[index] or "") .. "\n")
    end
end
vim.cmd("qa!")
