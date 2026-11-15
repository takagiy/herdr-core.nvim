local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["reports focus gained and lost"] = function ()
    -- Given a focus listener
    local focus = require("herdr-core.ui.focus")
    local reports = {}
    local stop = focus.watch(function (value) reports[#reports + 1] = value.focused end)
    -- When Neovim loses and regains focus
    vim.api.nvim_exec_autocmds("FocusLost", {})
    vim.api.nvim_exec_autocmds("FocusGained", {})
    stop()
    -- Then both transitions are reported in order
    MiniTest.expect.equality(reports, { true, false, true })
end

T["reports visible terminals when buffers change"] = function ()
    -- Given a buffer carrying a terminal address and a focus listener
    local focus = require("herdr-core.ui.focus")
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "t1"
    local original = vim.api.nvim_get_current_buf()
    local reports = {}
    local stop = focus.watch(function (value) reports[#reports + 1] = value.terminals end)
    -- When that terminal is displayed in the current window
    vim.api.nvim_set_current_buf(buffer)
    vim.wait(100, function () return #reports > 1 end)
    stop()
    vim.api.nvim_set_current_buf(original)
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the visible address is reported
    MiniTest.expect.equality(reports[#reports], { "t1" })
end

T["does not report temporary tabs visited during layout restoration"] = function ()
    -- Given a file window and a listener
    local reports = {}
    local original = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.b[buffer].herdr_core_address = "hidden"
    local stop = require("herdr-core.ui.focus").watch(function (value)
        for _, address in ipairs(value.terminals) do
            reports[#reports + 1] = address
        end
    end)
    -- When a layout pass visits another tab and returns before control reaches the user
    vim.cmd.tabnew()
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_set_current_win(original)
    vim.wait(20, function () return false end)
    stop()
    vim.cmd.tabonly()
    vim.api.nvim_buf_delete(buffer, { force = true })
    -- Then the hidden terminal was never reported as being watched
    MiniTest.expect.equality(reports, {})
end

return T
