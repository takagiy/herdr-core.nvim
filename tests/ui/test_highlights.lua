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

return T
