local M = {}

---@param current  string
---@param callback fun(value: string?)
function M.name(current, callback)
    vim.ui.input({ prompt = "Terminal name: ", default = current }, callback)
end

return M
