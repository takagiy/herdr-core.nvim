local M = {}

---@class HerdrCoreTerminalIdentity
---@field address  string
---@field name?    string
---@field machine? string

---@param terminal HerdrCoreTerminalIdentity
---@return string
function M.name(terminal)
    local name = terminal.name or terminal.address:match("([^/]+)$") or terminal.address
    return "herdr://" .. (terminal.machine and terminal.machine .. "/" or "") .. name
end

---@param terminal  HerdrCoreTerminalIdentity
---@param command   string[]
---@param existing? integer
---@return integer
function M.buffer(terminal, command, existing)
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.b[buffer].herdr_core_address == terminal.address then return buffer end
    end
    local buffer = existing or vim.api.nvim_create_buf(true, false)
    vim.b[buffer].herdr_core_address = terminal.address
    local ok, failure = pcall(function ()
        vim.api.nvim_buf_call(buffer, function ()
            local job = vim.fn.jobstart(command, { term = true })
            if job <= 0 then error("Could not start terminal attach process") end
        end)
        vim.api.nvim_buf_set_name(buffer, M.name(terminal))
    end)
    if not ok then
        vim.api.nvim_buf_delete(buffer, { force = true })
        error(failure)
    end
    vim.bo[buffer].bufhidden = "hide"
    return buffer
end

---@param on_read      fun(uri: string, buffer: integer)
---@param auto_insert? boolean
---@return fun()
function M.setup(on_read, auto_insert)
    local active = true
    local group = vim.api.nvim_create_augroup("HerdrCoreTerminal", { clear = true })
    vim.api.nvim_create_autocmd("BufReadCmd", {
        group = group,
        pattern = "herdr://*",
        callback = function (event) on_read(event.match, event.buf) end
    })
    if auto_insert ~= false then
        vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
            group = group,
            callback = function (event)
                if vim.b[event.buf].herdr_core_address and vim.bo[event.buf].buftype == "terminal" then
                    vim.schedule(function ()
                        if active and vim.api.nvim_get_current_buf() == event.buf then vim.cmd.startinsert() end
                    end)
                end
            end
        })
    end
    return function ()
        active = false
        vim.api.nvim_del_augroup_by_id(group)
    end
end

return M
