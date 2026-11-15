local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["defines default status highlight links"] = function ()
    -- Given no existing plugin highlights
    vim.api.nvim_set_hl(0, "HerdrCoreWorking", {})
    -- When highlights are initialized
    require("herdr-core.ui.highlights").setup()
    -- Then status text uses the editor's standard colors
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreWorking" }).link, "DiagnosticInfo")
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreBlocked" }).link, "DiagnosticWarn")
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreDone" }).link, "DiagnosticOk")
end

T["preserves user highlight definitions"] = function ()
    -- Given a user-defined status color
    vim.api.nvim_set_hl(0, "HerdrCoreWorking", { fg = 0x123456 })
    -- When plugin highlights are initialized again
    require("herdr-core.ui.highlights").setup()
    -- Then the user color remains
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreWorking" }).fg, 0x123456)
    vim.api.nvim_set_hl(0, "HerdrCoreWorking", {})
end

T["uses theme colors for active terminals and bold section headings"] = function ()
    -- Given the default sidebar styles without user overrides
    -- When the sidebar styles are initialized
    require("herdr-core.ui.highlights").setup()
    -- Then the active background follows CursorLine and headings use bold normal text
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreActive" }).link, "CursorLine")
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreHeader" }).bold, true)
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreSpace" }).bold, true)
end

T["gives labels bold text and spaces distinct theme backgrounds"] = function ()
    -- Given the editor's theme colors
    -- When sidebar highlights are initialized
    require("herdr-core.ui.highlights").setup()
    -- Then labels are bold and space backgrounds differ when selected
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreLabel" }).bold, true)
    local space = vim.api.nvim_get_hl(0, { name = "HerdrCoreSpace", link = false })
    local active = vim.api.nvim_get_hl(0, { name = "HerdrCoreSpaceActive", link = false })
    MiniTest.expect.equality(type(space.bg), "number")
    MiniTest.expect.equality(type(active.bg), "number")
    MiniTest.expect.equality(space.bg ~= active.bg, true)
end

return T
