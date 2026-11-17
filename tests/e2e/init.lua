local project = assert(vim.env.HERDR_E2E_PROJECT)
vim.opt.runtimepath:append(project)
vim.o.lines, vim.o.columns = 40, 140
vim.o.mouse = "a"
vim.o.swapfile = false
---@type table
_G.e2e_app = require("herdr-core").setup({
    auto_insert = false,
    integrations = {
        -- The dummy agent. Its resume types an echo, so a case can find it on the shell's screen.
        e2e = {
            directory = function () return nil end,
            install = {},
            resume_command = function (id) return "echo resumed-" .. id end,
            matches_program = require("herdr-core.integrations").program({ "dummy-agent" })
        }
    }
})
for key, action in pairs({
    ["<F5>"] = "new_tab",
    ["<F6>"] = "new_vertical",
    ["<F7>"] = "new_horizontal",
    ["<F8>"] = "focus_sidebar",
    ["<F9>"] = "toggle_sidebar"
}) do
    vim.keymap.set({ "n", "t" }, key, _G.e2e_app.actions[action])
end
