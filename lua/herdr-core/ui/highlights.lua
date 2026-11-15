local M = {}

function M.setup()
    for name, link in pairs({
        Working = "DiagnosticInfo",
        Blocked = "DiagnosticWarn",
        Done = "DiagnosticOk",
        Error = "DiagnosticError",
        Idle = "Comment",
        Space = "Directory",
        Machine = "Title"
    }) do
        vim.api.nvim_set_hl(0, "HerdrCore" .. name, { default = true, link = link })
    end
end

return M
