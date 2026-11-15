-- Startup file for the test runner and the child Neovim processes it starts.
vim.opt.runtimepath:append(vim.fn.getcwd())

-- The version is in the folder name, so changing it fetches the new one.
-- Keep this path in sync with workspace.library in .emmyrc.json.
local version = "v0.18.0"
local mini_test = "deps/mini.test-" .. version
if vim.fn.isdirectory(mini_test) == 0 then
    vim.system({
        "git",
        "clone",
        "--quiet",
        "--depth",
        "1",
        "--branch",
        version,
        "https://github.com/nvim-mini/mini.test",
        mini_test
    }):wait()
end
vim.opt.runtimepath:append(mini_test)
require("mini.test").setup()
