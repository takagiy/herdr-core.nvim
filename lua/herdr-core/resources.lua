-- What a resource lists in the sidebar is made of sections and items. `terminals` is the resource of the
-- terminals themselves.
local M = {}

-- A heading with items under it.
---@param fields { id?: string, name: string, notification_count?: integer, items?: HerdrCoreItem[], props?: table }
---@return HerdrCoreSection
function M.Section(fields)
    return vim.tbl_extend("force", fields, { kind = "section" }) --[[@as HerdrCoreSection]]
end

-- A row. The sidebar shows the named fields; what the resource's actions need goes in `props`.
---@param fields { id?: string, name: string, detail?: string, status?: string, notification_count?: integer, is_highlighted?: boolean, items?: HerdrCoreItem[], props?: table }
---@return HerdrCoreItem
function M.Item(fields)
    return vim.tbl_extend("force", fields, { kind = "item" }) --[[@as HerdrCoreItem]]
end

-- The spaces with their terminals. Without `keys`, Enter and a click open a terminal, and n, r, p and u start
-- one in its space, rename it, pin it and mark it unread.
---@param options? { keys?: table<string, string | HerdrCoreResourceAction> }
---@return HerdrCoreResource
function M.terminals(options)
    return {
        name = "terminals",
        keys = (options or {}).keys or { use = "open", n = "new_terminal", r = "rename", p = "pin", u = "unread" }
    }
end

return M
