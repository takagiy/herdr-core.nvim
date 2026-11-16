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
    local tint = accent.fg or foreground
    -- Mixed from the theme, so a dark theme gets the same roles in dark colors.
    -- Faint text stays readable on every row background, unlike the theme comment color.
    local faint = blend(background, foreground, 0.8)
    for name, colors in pairs({
        Program = { fg = faint },
        Idle = { fg = faint },
        Muted = { fg = faint },
        -- The terminal in front: a light lift.
        Active = { bg = blend(background, foreground, 0.08) },
        Space = { bold = true, fg = foreground, bg = blend(background, foreground, 0.06) },
        -- The space holding the terminal in front: inverted, the strongest mark.
        SpaceActive = { bold = true, fg = background, bg = blend(background, foreground, 0.85) },
        -- The row under the cursor: a pale wash of the accent.
        Selected = { fg = foreground, bg = blend(background, tint, 0.2) },
        Button = { fg = foreground, bg = blend(background, foreground, 0.14) },
        ButtonActive = { fg = foreground, bg = blend(background, tint, 0.35) }
    }) do
        colors.default = true
        vim.api.nvim_set_hl(0, "HerdrCore" .. name, colors)
    end
end

return M
