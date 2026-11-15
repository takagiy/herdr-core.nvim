local M = {}

---@param folder   string
---@param machine  string?
---@param callback fun(root: string?)
function M.root(folder, machine, callback)
    local command = { "git", "-C", folder, "rev-parse", "--show-toplevel" }
    if machine then
        command = { "hc", "exec", "--on", machine, "--", "git", "-C", folder, "rev-parse", "--show-toplevel" }
    end
    local ok = pcall(vim.system, command, { text = true }, function (result)
        if result.code ~= 0 then
            callback(nil)
            return
        end
        callback((result.stdout or ""):gsub("[\r\n]+$", ""))
    end)
    if not ok then callback(nil) end
end

return M
