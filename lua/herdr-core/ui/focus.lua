local M = {}

---@class HerdrCoreFocusSnapshot
---@field focused   boolean
---@field terminals string[]
---@field front?    string   The terminal in front in the current tabpage.
---@field cwd       string   Neovim's global cwd.

---@param callback fun(value: HerdrCoreFocusSnapshot)
---@return fun()
function M.watch(callback)
    local focused = true
    local active, queued = true, false
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
        -- The terminal in front stays the one last shown while the cursor is in the sidebar.
        local current = vim.api.nvim_get_current_buf()
        if not vim.b[current].herdr_core_sidebar then
            vim.t.herdr_core_active_terminal = vim.b[current].herdr_core_address
        end
        callback({
            focused = focused,
            terminals = terminals,
            front = vim.t.herdr_core_active_terminal,
            cwd = vim.fn.getcwd(-1, -1)
        })
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
        callback = function ()
            if queued then return end
            queued = true
            vim.schedule(function ()
                queued = false
                if active then report() end
            end)
        end
    })
    report()
    return function ()
        active = false
        vim.api.nvim_del_augroup_by_id(group)
    end
end

return M
