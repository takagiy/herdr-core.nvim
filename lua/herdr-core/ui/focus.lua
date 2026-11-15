local M = {}

---@class HerdrCoreFocusSnapshot
---@field focused   boolean
---@field terminals string[]

---@param callback fun(value: HerdrCoreFocusSnapshot)
---@return fun()
function M.watch(callback)
    local focused = true
    local group = vim.api.nvim_create_augroup("HerdrCoreFocus", { clear = true })
    local function report()
        local terminals = {}
        local seen = {}
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            ---@type string?
            local address = vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address
            if address and not seen[address] then
                terminals[#terminals + 1] = address
                seen[address] = true
            end
        end
        callback({ focused = focused, terminals = terminals })
    end
    vim.api.nvim_create_autocmd({ "FocusGained", "FocusLost" }, {
        group = group,
        callback = function (event)
            focused = event.event == "FocusGained"
            report()
        end
    })
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "TabEnter", "BufWinEnter" }, {
        group = group,
        callback = report
    })
    report()
    return function () vim.api.nvim_del_augroup_by_id(group) end
end

return M
