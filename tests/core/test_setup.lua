local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local setup = require("herdr-core.core.setup")
local state = require("herdr-core.core.state")

---@param rows HerdrCoreSidebarRow[]
---@return string[][]
local function shown(rows)
    return vim.tbl_map(function (row) return { row.kind, row.lines[1], row.button or "" } end, rows)
end

local two = {
    type = "setup_checked",
    items = {
        { name = "codex", label = "codex", status = "outdated" },
        { name = "claude", label = "claude", status = "missing" },
        { name = "gemini", label = "gemini", status = "installed" }
    }
}

T["shows integrations that need setting up under one heading"] = function ()
    -- Given two agents to set up and one already set up
    local current = setup.update(setup.new(), two)
    -- When the panel is viewed
    local rows = setup.view(current)
    -- Then the heading offers both, the outdated one updates and the installed one is hidden
    MiniTest.expect.equality(shown(rows), {
        { "setup_heading", "Integration", "Install all" },
        { "setup_text", "Supported agents detected.", "" },
        { "setup_item", "claude", "Install" },
        { "setup_item", "codex", "Update" },
        { "setup_button", "", "Dismiss" }
    })
end

T["leaves Install all out when only one integration is left"] = function ()
    -- Given one agent to set up
    local current = setup.update(setup.new(), {
        type = "setup_checked",
        items = { { name = "claude", label = "claude", status = "missing" } }
    })
    -- When the panel is viewed
    local rows = setup.view(current)
    -- Then the heading has no button and Dismiss stays at the bottom
    MiniTest.expect.equality(shown(rows)[1], { "setup_heading", "Integration", "" })
    MiniTest.expect.equality(shown(rows)[#rows], { "setup_button", "", "Dismiss" })
end

T["installs the requested or every pending integration"] = function ()
    -- Given two pending agents
    local current = setup.update(setup.new(), two)
    -- When one, then all are requested
    local _, one = setup.update(current, { type = "setup_requested", names = { "codex" } })
    local _, all = setup.update(current, { type = "setup_requested" })
    -- Then each asks to install those names
    MiniTest.expect.equality(one, { { type = "install_integrations", names = { "codex" } } })
    MiniTest.expect.equality(all, { { type = "install_integrations", names = { "claude", "codex" } } })
end

T["explains a failed install and hides finished ones"] = function ()
    -- Given two pending agents
    local current = setup.update(setup.new(), two)
    -- When claude fails and codex succeeds
    current = setup.update(current, {
        type = "setup_result",
        name = "claude",
        status = "missing",
        error = "settings.json is not JSON"
    })
    current = setup.update(current, { type = "setup_result", name = "codex", status = "installed" })
    -- Then claude offers a retry with the reason, and codex is gone
    local rows = shown(setup.view(current))
    MiniTest.expect.equality({ rows[1], rows[3], rows[4] }, {
        { "setup_heading", "Integration", "" },
        { "setup_item", "claude", "Retry" },
        { "setup_error", "! settings.json is not JSON", "" }
    })
end

T["hides the dismissed panel until Neovim restarts"] = function ()
    -- Given the core with pending agents
    local current = state.update(state.new(), two)
    -- When the panel is dismissed
    current = state.update(current, { type = "setup_dismissed" })
    -- Then the view has no setup rows
    local _, rows = state.view(current)
    MiniTest.expect.equality(vim.tbl_filter(function (row) return row.kind:find("^setup") ~= nil end, rows), {})
end

return T
