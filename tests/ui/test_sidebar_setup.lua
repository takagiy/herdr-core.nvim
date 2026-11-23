local MiniTest = require("mini.test")
local T = MiniTest.new_set()

---@type HerdrCoreSidebarRow[]
local rows = {
    { kind = "section", id = "/app", waiting = 0, lines = { "app" } },
    { kind = "item", id = "t1", lines = { "build", "zsh" } },
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
    { kind = "setup_error", group = "integration", lines = { "! settings.json is not JSON" } },
    { kind = "setup_button", lines = { "" }, button = "Dismiss", action = "dismiss" }
}

---@param buffer integer
---@param group  string
---@return integer[] Lines (1-based) that carry the highlight group.
local function lines_with(buffer, group)
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true })) do
        if assert(mark[4]).hl_group == group then found[#found + 1] = mark[2] + 1 end
    end
    return found
end

T["draws the Setup panel above the toggle with buttons ending one column inside the border"] = function ()
    -- Given a sidebar 32 columns wide
    require("herdr-core.ui.highlights").setup()
    local sidebar = require("herdr-core.ui.sidebar").create()
    sidebar.show(32)
    -- When rows with a Setup panel are rendered
    sidebar.render(rows, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    local buttons = lines_with(sidebar.buffer, "HerdrCoreButton")
    sidebar.close()
    -- Then the box ends just above the toggle, its buttons end in one column and the long error wraps
    local count = #lines
    MiniTest.expect.equality(lines[count - 8], " ╭ Setup " .. string.rep("─", 21) .. "╮")
    local panel = {}
    for line = count - 7, count - 2 do
        panel[#panel + 1] = lines[line]
    end
    MiniTest.expect.equality(panel, {
        " │ Integration   Install all  │",
        " │ Supported agents detected. │",
        " │  claude           Install  │",
        " │  ! settings.json is not    │",
        " │  JSON                      │",
        " │                   Dismiss  │"
    })
    MiniTest.expect.equality(lines[count - 1], " ╰" .. string.rep("─", 28) .. "╯")
    MiniTest.expect.equality(#buttons, 5)
    MiniTest.expect.equality(vim.fn.strdisplaywidth(assert(lines[count - 8])), 31)
end

T["puts a Setup button that does not fit beside its name on the next line and wraps text"] = function ()
    -- Given a sidebar 24 columns wide
    require("herdr-core.ui.highlights").setup()
    local sidebar = require("herdr-core.ui.sidebar").create()
    sidebar.show(24)
    -- When rows with a Setup panel are rendered
    sidebar.render(rows, 0)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, -1, false)
    local buttons = lines_with(sidebar.buffer, "HerdrCoreButton")
    sidebar.close()
    -- Then Install all sits under its heading, the buttons end in one column and long text wraps
    local count = #lines
    local panel = {}
    for line = count - 10, count - 1 do
        panel[#panel + 1] = lines[line]
    end
    MiniTest.expect.equality(panel, {
        " ╭ Setup " .. string.rep("─", 13) .. "╮",
        " │ Integration        │",
        " │       Install all  │",
        " │ Supported agents   │",
        " │ detected.          │",
        " │  claude   Install  │",
        " │  ! settings.json is│",
        " │  not JSON          │",
        " │           Dismiss  │",
        " ╰" .. string.rep("─", 20) .. "╯"
    })
    MiniTest.expect.equality(vim.tbl_contains(buttons, count - 8), true)
end

T["moves onto Setup buttons and presses the one under the cursor"] = function ()
    -- Given a sidebar with a Setup panel, focused on the terminal row
    local pressed = {}
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row)
        pressed[#pressed + 1] = { action, row and row.action }
    end)
    local window = sidebar.show(32)
    sidebar.render(rows, 0)
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 5, 0 })
    -- When the user moves down twice and presses Enter
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("jj<CR>", true, false, true), "x", false)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = sidebar.buffer })
    local line = vim.api.nvim_win_get_cursor(window)[1]
    local active = lines_with(sidebar.buffer, "HerdrCoreButtonActive")
    sidebar.close()
    -- Then the cursor sits on the item button, which takes the active color and gets pressed
    MiniTest.expect.equality(pressed, { { "activate", "install" } })
    MiniTest.expect.equality(active, { line })
end

T["marks a collapsed sidebar when something needs setting up"] = function ()
    -- Given a collapsed sidebar
    local sidebar = require("herdr-core.ui.sidebar").create()
    sidebar.show(32)
    sidebar.toggle()
    -- When rows with a Setup panel are rendered
    sidebar.render(rows, 1)
    local lines = vim.api.nvim_buf_get_lines(sidebar.buffer, 0, 2, false)
    sidebar.close()
    -- Then the strip shows the count and a mark
    MiniTest.expect.equality(lines, { "1", "!" })
end

return T
