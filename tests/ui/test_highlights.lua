local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["defines default status highlight links"] = function ()
    -- Given no existing plugin highlights
    vim.api.nvim_set_hl(0, "HerdrCoreWorking", {})
    -- When highlights are initialized
    require("herdr-core.ui.highlights").setup()
    -- Then status text uses the editor's standard colors
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreWorking" }).link, "DiagnosticInfo")
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreBlocked" }).link, "DiagnosticWarn")
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreDone" }).link, "DiagnosticOk")
end

T["preserves user highlight definitions"] = function ()
    -- Given a user-defined status color
    vim.api.nvim_set_hl(0, "HerdrCoreWorking", { fg = 0x123456 })
    -- When plugin highlights are initialized again
    require("herdr-core.ui.highlights").setup()
    -- Then the user color remains
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreWorking" }).fg, 0x123456)
    vim.api.nvim_set_hl(0, "HerdrCoreWorking", {})
end

-- WCAG contrast ratio of two 0xRRGGBB colors.
---@param a integer
---@param b integer
---@return number
local function contrast(a, b)
    ---@param color integer
    ---@return number
    local function luminance(color)
        local total = 0.0
        local weights = { 0.2126, 0.7152, 0.0722 }
        for index, shift in ipairs({ 16, 8, 0 }) do
            local channel = (math.floor(color / 2 ^ shift) % 256) / 255
            channel = channel <= 0.03928 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
            total = total + assert(weights[index]) * channel
        end
        return total
    end
    local high, low = math.max(luminance(a), luminance(b)), math.min(luminance(a), luminance(b))
    return (high + 0.05) / (low + 0.05)
end

T["mixes the sidebar colors from the theme in light and dark"] = function ()
    -- Given onedark-like light and dark palettes
    local results = {}
    for _, theme in ipairs({
        { background = "light", bg = 0xfafafa, fg = 0x383a42, accent = 0x0184bc },
        { background = "dark", bg = 0x282c34, fg = 0xabb2bf, accent = 0x56b6c2 }
    }) do
        vim.cmd("highlight clear")
        vim.o.background = theme.background
        vim.api.nvim_set_hl(0, "Normal", { fg = theme.fg, bg = theme.bg })
        vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = theme.accent })
        -- When the sidebar styles are initialized
        require("herdr-core.ui.highlights").setup()
        ---@param name string
        ---@return vim.api.keyset.get_hl_info
        local function get(name)
            return vim.api.nvim_get_hl(0, { name = "HerdrCore" .. name, link = false })
        end
        local faint = assert(get("Program").fg)
        results[theme.background] = {
            inverted = get("SpaceActive").fg == theme.bg and get("SpaceActive").bold == true,
            selection_differs = get("Selected").bg ~= get("Active").bg and get("Active").bg ~= theme.bg,
            readable = contrast(faint, theme.bg) >= 3 and contrast(faint, assert(get("Active").bg)) >= 3
                and contrast(faint, assert(get("Selected").bg)) >= 3,
            fainter = contrast(faint, theme.bg) < contrast(theme.fg, theme.bg)
        }
    end
    -- Then both themes invert the front space, tell the selection from the front terminal, and keep faint text readable
    local expected = { inverted = true, selection_differs = true, readable = true, fainter = true }
    MiniTest.expect.equality(results, { light = expected, dark = expected })
end

T["gives labels bold text and spaces distinct theme backgrounds"] = function ()
    -- Given the editor's theme colors
    -- When sidebar highlights are initialized
    require("herdr-core.ui.highlights").setup()
    -- Then labels are bold and space backgrounds differ when selected
    MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "HerdrCoreLabel" }).bold, true)
    local space = vim.api.nvim_get_hl(0, { name = "HerdrCoreSpace", link = false })
    local active = vim.api.nvim_get_hl(0, { name = "HerdrCoreSpaceActive", link = false })
    MiniTest.expect.equality(type(space.bg), "number")
    MiniTest.expect.equality(type(active.bg), "number")
    MiniTest.expect.equality(space.bg ~= active.bg, true)
end

return T
