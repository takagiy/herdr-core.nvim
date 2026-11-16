local M = {}

---@class HerdrCoreSetupItem
---@field name   string
---@field label  string
---@field status HerdrCoreIntegrationStatus
---@field error? string

---@class HerdrCoreSetupState
---@field items     HerdrCoreSetupItem[]
---@field dismissed table<string, boolean>

---@class HerdrCoreSetupChecked
---@field type  'setup_checked'
---@field items HerdrCoreSetupItem[]

---@class HerdrCoreSetupRequested
---@field type   'setup_requested'
---@field names? string[]          Items to install; without names, every item that needs it.

---@class HerdrCoreSetupResult
---@field type   'setup_result'
---@field name   string
---@field status HerdrCoreIntegrationStatus
---@field error? string

---@class HerdrCoreSetupDismissed
---@field type  'setup_dismissed'
---@field group string

---@class HerdrCoreInstallEffect
---@field type  'install_integrations'
---@field names string[]

---@return HerdrCoreSetupState
function M.new()
    return { items = {}, dismissed = {} }
end

---@param state HerdrCoreSetupState
---@return HerdrCoreSetupItem[]
local function pending(state)
    return vim.tbl_filter(function (item) return item.status ~= "installed" end, state.items)
end

---@param state HerdrCoreSetupState
---@param event HerdrCoreSetupChecked | HerdrCoreSetupRequested | HerdrCoreSetupResult | HerdrCoreSetupDismissed
---@return HerdrCoreSetupState, HerdrCoreInstallEffect[]
function M.update(state, event)
    if event.type == "setup_checked" then
        local items = vim.deepcopy(event.items)
        table.sort(items, function (a, b) return a.name < b.name end)
        return { items = items, dismissed = state.dismissed }, {}
    end
    if event.type == "setup_requested" then
        local names = event.names or vim.tbl_map(function (item) return item.name end, pending(state))
        if #names == 0 then return state, {} end
        return state, { { type = "install_integrations", names = names } }
    end
    if event.type == "setup_result" then
        local items = vim.tbl_map(function (item)
            if item.name ~= event.name then return item end
            return { name = item.name, label = item.label, status = event.status, error = event.error }
        end, state.items)
        return { items = items, dismissed = state.dismissed }, {}
    end
    local dismissed = vim.deepcopy(state.dismissed)
    dismissed[event.group] = true
    return { items = state.items, dismissed = dismissed }, {}
end

-- The rows of the Setup panel; empty when nothing needs setting up.
---@param state HerdrCoreSetupState
---@return HerdrCoreSidebarRow[]
function M.view(state)
    local items = pending(state)
    if #items == 0 or state.dismissed.integration then return {} end
    local group = "integration"
    ---@type HerdrCoreSidebarRow[]
    local rows = {}
    if #items > 1 then
        rows[#rows + 1] = {
            kind = "setup_heading",
            group = group,
            lines = { "Integration" },
            button = "Install all",
            action = "install_all"
        }
        rows[#rows + 1] = {
            kind = "setup_button",
            group = group,
            lines = { "" },
            button = "Not now",
            action = "dismiss"
        }
    else
        rows[#rows + 1] = {
            kind = "setup_heading",
            group = group,
            lines = { "Integration" },
            button = "Not now",
            action = "dismiss"
        }
    end
    rows[#rows + 1] = { kind = "setup_text", group = group, lines = { "Supported agents detected." } }
    for _, item in ipairs(items) do
        rows[#rows + 1] = {
            kind = "setup_item",
            group = group,
            name = item.name,
            lines = { item.label },
            button = item.error and "Retry" or item.status == "outdated" and "Update" or "Install",
            action = "install"
        }
        if item.error then
            rows[#rows + 1] = { kind = "setup_error", group = group, lines = { "! " .. item.error } }
        end
    end
    return rows
end

return M
