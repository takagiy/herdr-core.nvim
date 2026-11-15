local project = assert(vim.env.HERDR_E2E_PROJECT)
vim.opt.runtimepath:append(project)
vim.o.lines, vim.o.columns = 40, 140
vim.o.mouse = "a"
vim.o.swapfile = false
---@type table
_G.e2e_app = require("herdr-core").setup({ auto_insert = false })
for key, action in pairs({
    ["<F5>"] = "new_tab",
    ["<F6>"] = "new_vertical",
    ["<F7>"] = "new_horizontal",
    ["<F8>"] = "focus_sidebar",
    ["<F9>"] = "toggle_sidebar"
}) do
    vim.keymap.set({ "n", "t" }, key, _G.e2e_app.actions[action])
end
