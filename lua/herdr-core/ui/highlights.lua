local M = {}

---@param background integer
---@param foreground integer
---@param amount     number
---@return integer
local function blend(background, foreground, amount)
    local color = 0
    for _, shift in ipairs({ 16, 8, 0 }) do
        local base = math.floor(background / 2 ^ shift) % 256
        local tint = math.floor(foreground / 2 ^ shift) % 256
        color = math.floor(color + math.floor(base + (tint - base) * amount + 0.5) * 2 ^ shift)
    end
    return color
end

function M.setup()
    for name, link in pairs({
        Working = "DiagnosticInfo",
        Blocked = "DiagnosticWarn",
        Done = "DiagnosticOk",
        Error = "DiagnosticError",
        Idle = "Comment",
        Program = "Comment",
        Active = "CursorLine",
        Muted = "Comment",
        Machine = "Title"
    }) do
        vim.api.nvim_set_hl(0, "HerdrCore" .. name, { default = true, link = link })
    end
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("HerdrCoreHighlights", { clear = true }),
        callback = M.setup
    })
    for _, name in ipairs({ "Header", "Label" }) do
        vim.api.nvim_set_hl(0, "HerdrCore" .. name, { default = true, bold = true })
    end
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local accent = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false })
    local dark = vim.o.background == "dark"
    local background = normal.bg or (dark and 0x202020 or 0xfafafa)
    local foreground = normal.fg or (dark and 0xd0d0d0 or 0x303030)
    vim.api.nvim_set_hl(0, "HerdrCoreSpace", {
        default = true,
        bold = true,
        fg = foreground,
        bg = blend(background, foreground, 0.06)
    })
    vim.api.nvim_set_hl(0, "HerdrCoreSpaceActive", {
        default = true,
        bold = true,
        fg = foreground,
        bg = blend(background, accent.fg or foreground, 0.18)
    })
end

return M
