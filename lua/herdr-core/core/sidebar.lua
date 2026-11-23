local M = {}
local attention = require("herdr-core.core.attention")
local terminals_module = require("herdr-core.core.terminals")

-- A row a resource lists. The sidebar shows the named fields; what the resource's actions need goes in `props`.
---@class HerdrCoreItem
---@field kind                'item'
---@field id?                 string          Tells the item from the others across notifications; its place does when missing.
---@field name                string
---@field detail?             string
---@field status?             string
---@field notification_count? integer
---@field is_highlighted?     boolean
---@field items?              HerdrCoreItem[]
---@field props?              table

-- A heading with items under it.
---@class HerdrCoreSection
---@field kind                'section'
---@field id?                 string
---@field name                string
---@field notification_count? integer
---@field items?              HerdrCoreItem[]
---@field props?              table

---@alias HerdrCoreElement HerdrCoreSection | HerdrCoreItem

---@class HerdrCoreArmContext
---@field parent? HerdrCoreElement              The element the monitor lists items under.
---@field notify  fun(list: HerdrCoreElement[]) Replaces what the resource lists there.

---@class HerdrCoreMonitor
---@field arm    fun(ctx: HerdrCoreArmContext) Called when the parent appears and each time it changes.
---@field disarm fun()

---@class HerdrCoreActionContext
---@field item    HerdrCoreItem
---@field parent? HerdrCoreElement The element the item is listed under.

---@alias HerdrCoreResourceAction fun(ctx: HerdrCoreActionContext)

---@class HerdrCoreResource
---@field name     string
---@field parent?  string                                          A resource's name followed by `[]` for each level down, as `terminals[][]`.
---@field monitor? fun(): HerdrCoreMonitor                         Missing only for `terminals`, whose elements the sidebar makes.
---@field actions? table<string, HerdrCoreResourceAction>
---@field keys?    table<string, string | HerdrCoreResourceAction> What a key does on the items; `use` stands for Enter and a click.

---@class HerdrCoreSidebarRow
---@field kind         'section' | 'item' | 'summary' | 'new_terminal' | 'setup_heading' | 'setup_button' | 'setup_text' | 'setup_item' | 'setup_error'
---@field status       string?
---@field lines        string[]
---@field waiting      integer?
---@field guide?       string                                                                                                                           Tree lines before a deeper item's status, such as "│ └ ".
---@field highlighted? boolean
---@field top?         boolean                                                                                                                          Whether the item is at the top, under no section.
---@field id?          string                                                                                                                           The id of the element the row shows.
---@field group?       string                                                                                                                           The Setup heading a setup row belongs to.
---@field name?        string                                                                                                                           The integration a setup item installs.
---@field button?      string                                                                                                                           The text of the row's button.
---@field action?      'install' | 'install_all' | 'dismiss'
---@field resource?    string                                                                                                                           The name of the resource the row's element belongs to.
---@field keys?        table<string, string | HerdrCoreResourceAction>                                                                                  The keys the row takes.
---@field item?        HerdrCoreElement                                                                                                                 The element the row shows.
---@field parent?      HerdrCoreElement                                                                                                                 The element the row's element is listed under.

---@class HerdrCoreSidebarGroup
---@field root      string
---@field terminals HerdrCoreTerminal[]
---@field updated   integer

-- What resources notified, by the resource's name and the key of the element it is listed under.
---@alias HerdrCoreListed table<string, table<string, HerdrCoreElement[]>>

-- The elements monitors are wanted for, by the resource's name and the element's key; false stands for a
-- resource without a parent.
---@alias HerdrCoreWanted table<string, table<string, HerdrCoreElement | false>>

---@class HerdrCoreSidebarOptions
---@field collapsed? boolean
---@field resources? HerdrCoreResource[]
---@field items?     HerdrCoreListed
---@field front?     string              The terminal in front in the current tabpage.

---@class HerdrCoreSidebarState
---@field groups    table<string, integer>
---@field terminals table<string, integer>
---@field locations table<string, string>

-- An element with what tells where it is: its resource, how deep it is in what that resource listed, and a
-- key no other element has.
---@class HerdrCoreSidebarNode
---@field element  HerdrCoreElement
---@field resource HerdrCoreResource
---@field depth    integer
---@field key      string
---@field parent?  HerdrCoreElement

-- The resource a parent names, such as `terminals` in "terminals[][]"; nil when it is not written that way.
---@param parent any
---@return string?
local function named(parent)
    if type(parent) ~= "string" then return nil end
    local name, levels = parent:match("^(.-)([%[%]]+)$")
    if not name or name == "" or levels ~= string.rep("[]", math.floor(#levels / 2)) then return nil end
    return name
end

-- Why the resources cannot be used, or nil.
---@param resources HerdrCoreResource[]
---@return string?
function M.problem(resources)
    -- The resource each name lists under; false for one at the top.
    ---@type table<string, string | false>
    local parents = {}
    for index, resource in ipairs(resources) do
        local name = resource.name
        if type(name) ~= "string" or name == "" then return "resource " .. index .. ": name must be a string" end
        if parents[name] ~= nil then return name .. ": two resources have this name" end
        if name ~= "terminals" and type(resource.monitor) ~= "function" then
            return name .. ": monitor must be a function"
        end
        local above = resource.parent ~= nil and named(resource.parent)
        if above == nil then return name .. ": parent must be a resource's name followed by []" end
        parents[name] = above
    end
    for _, resource in ipairs(resources) do
        local seen, name = {}, parents[resource.name]
        while name do
            if parents[name] == nil then return resource.name .. ": no resource is named " .. name end
            if seen[name] then return resource.name .. ": its parents make a loop" end
            seen[name] = true
            name = parents[name]
        end
    end
    return nil
end

-- The spaces as sections, each with its terminals as items, and the order they are kept in.
---@param previous? HerdrCoreSidebarState
---@param terminals HerdrCoreTerminal[]
---@param front?    string
---@return HerdrCoreSidebarState, HerdrCoreSection[]
local function spaces(previous, terminals, front)
    ---@type table<string, HerdrCoreTerminal>
    local by_address = {}
    for _, terminal in ipairs(terminals) do
        by_address[terminal.address] = terminal
    end
    ---@param terminal HerdrCoreTerminal
    ---@return boolean
    local function child(terminal)
        return terminals_module.is_child(by_address, terminal)
    end
    -- The top of a family: its children share its space.
    ---@param terminal HerdrCoreTerminal
    ---@return HerdrCoreTerminal
    local function top(terminal)
        local seen = {}
        while child(terminal) and not seen[terminal.address] do
            seen[terminal.address] = true
            terminal = by_address[terminal.parent]
        end
        return terminal
    end
    ---@param terminal HerdrCoreTerminal
    ---@return boolean
    local function waits(terminal)
        return attention.display(terminal, child(terminal)).waiting
    end
    ---@type table<string, HerdrCoreSidebarGroup>
    local groups = {}
    for _, terminal in ipairs(terminals) do
        local head = top(terminal)
        -- Other machines are to be a resource of their own; until then their terminals are left out.
        if not head.machine then
            local root = head.labels["herdr.space"] or head.folder
            groups[root] = groups[root] or { root = root, terminals = {}, updated = 0 }
            groups[root].updated = math.max(groups[root].updated, terminal.status_ms or terminal.created_ms)
            table.insert(groups[root].terminals, terminal)
        end
    end
    local roots = vim.tbl_keys(groups)
    table.sort(roots, function (a, b)
        local first, second = groups[a], groups[b]
        if previous then
            local ap, bp = previous.groups[a] or 0, previous.groups[b] or 0
            if ap ~= bp then return ap < bp end
        end
        if first.updated ~= second.updated then return first.updated > second.updated end
        return a < b
    end)
    ---@type HerdrCoreSidebarState
    local state = { groups = {}, terminals = {}, locations = {} }
    ---@type HerdrCoreSection[]
    local sections = {}
    local terminal_index = 0
    for group_index, root in ipairs(roots) do
        state.groups[root] = group_index
        local group = groups[root]
        table.sort(group.terminals, function (a, b)
            local ap = a.labels["herdr.pinned"] ~= nil and a.labels["herdr.pinned"] ~= ""
            local bp = b.labels["herdr.pinned"] ~= nil and b.labels["herdr.pinned"] ~= ""
            if ap ~= bp then return ap end
            if previous then
                local first = previous.locations[a.address] == root and previous.terminals[a.address] or 0
                local second = previous.locations[b.address] == root and previous.terminals[b.address] or 0
                if first ~= second then return first < second end
            end
            local first, second = a.status_ms or a.created_ms, b.status_ms or b.created_ms
            if first ~= second then return first > second end
            return a.address < b.address
        end)
        local waiting = 0
        for _, terminal in ipairs(group.terminals) do
            if waits(terminal) then waiting = waiting + 1 end
        end
        ---@param parent? string
        ---@return HerdrCoreTerminal[]
        local function children(parent)
            return vim.tbl_filter(
                function (terminal) return (child(terminal) and terminal.parent or nil) == parent end, group.terminals
            )
        end
        ---@param terminal HerdrCoreTerminal
        ---@return integer
        local function waiting_below(terminal)
            local count = 0
            for _, inner in ipairs(children(terminal.address)) do
                count = count + (waits(inner) and 1 or 0) + waiting_below(inner)
            end
            return count
        end
        -- Each terminal takes its place in the order as it is met: a family's children right under their parent.
        ---@param terminal HerdrCoreTerminal
        ---@return HerdrCoreItem
        local function item(terminal)
            terminal_index = terminal_index + 1
            state.terminals[terminal.address] = terminal_index
            state.locations[terminal.address] = root
            -- The name the command was run by: hc names the file a link points to, such as claude's version.
            local command = terminal.argv and terminal.argv[1] or terminal.program or ""
            local program = command:match([=[[^/\]+$]=]) or ""
            program = program:gsub("^%-+", ""):gsub("%.[eE][xX][eE]$", "")
            local below, pinned = waiting_below(terminal), terminal.labels["herdr.pinned"]
            return {
                kind = "item",
                id = terminal.address,
                name = terminal.labels["herdr-core-nvim.name"] or terminal.name or terminal.address,
                detail = program,
                status = attention.display(terminal, child(terminal)).status,
                notification_count = below > 0 and below or nil,
                is_highlighted = terminal.address == front or nil,
                items = vim.tbl_map(item, children(terminal.address)),
                props = {
                    address = terminal.address,
                    space = terminal.labels["herdr.space"] or terminal.folder,
                    is_pinned = pinned ~= nil and pinned ~= ""
                }
            }
        end
        sections[#sections + 1] = {
            kind = "section",
            id = root,
            name = vim.fs.basename(root),
            notification_count = waiting > 0 and waiting or nil,
            items = vim.tbl_map(item, children(nil)),
            props = { space = root }
        }
    end
    return state, sections
end

-- The rows of the sidebar, the elements monitors are wanted for, and the number that waits for the user.
---@param previous? HerdrCoreSidebarState
---@param terminals HerdrCoreTerminal[]
---@param options?  HerdrCoreSidebarOptions
---@return HerdrCoreSidebarState, HerdrCoreSidebarRow[], HerdrCoreWanted, integer waiting
function M.update(previous, terminals, options)
    options = options or {}
    local resources = options.resources or { { name = "terminals" } }
    local listed = options.items or {}
    local state, sections = spaces(previous, terminals, options.front)
    ---@type HerdrCoreSidebarRow[]
    local rows = {}
    ---@type HerdrCoreWanted
    local wanted = {}
    for _, resource in ipairs(resources) do
        if resource.monitor then
            wanted[resource.name] = {}
        end
    end
    ---@param list?    HerdrCoreElement[]
    ---@param resource HerdrCoreResource
    ---@param depth    integer
    ---@param prefix   string
    ---@param parent?  HerdrCoreElement
    ---@return HerdrCoreSidebarNode[]
    local function nodes(list, resource, depth, prefix, parent)
        ---@type HerdrCoreSidebarNode[]
        local result = {}
        for index, element in ipairs(list or {}) do
            result[#result + 1] = {
                element = element,
                resource = resource,
                depth = depth,
                key = prefix .. "\0" .. (element.id or "#" .. index),
                parent = parent
            }
        end
        return result
    end
    -- What goes under a node: its element's own items, then what the resources naming its level list there.
    ---@param node HerdrCoreSidebarNode
    ---@return HerdrCoreSidebarNode[]
    local function below(node)
        local result = nodes(node.element.items, node.resource, node.depth + 1, node.key, node.element)
        local level = node.resource.name .. string.rep("[]", node.depth)
        for _, other in ipairs(resources) do
            local keyed = wanted[other.name]
            if keyed and other.parent == level then
                keyed[node.key] = node.element
                local theirs = (listed[other.name] or {})[node.key]
                vim.list_extend(result, nodes(theirs, other, 1, node.key .. "\0" .. other.name, node.element))
            end
        end
        return result
    end
    -- Rows for the nodes and all that goes under them. `prefix` holds the guides of the levels above; without
    -- it the nodes are at the top or right under a section, where an item takes two lines.
    ---@param list    HerdrCoreSidebarNode[]
    ---@param prefix? string
    ---@param top?    boolean
    local function add(list, prefix, top)
        for index, node in ipairs(list) do
            local element, last = node.element, index == #list
            if element.kind == "section" then
                rows[#rows + 1] = {
                    kind = "section",
                    id = element.id,
                    lines = { tostring(element.name) },
                    waiting = element.notification_count,
                    resource = node.resource.name,
                    item = element
                }
                add(below(node))
            else
                rows[#rows + 1] = {
                    kind = "item",
                    id = element.id,
                    status = element.status,
                    guide = prefix and prefix .. (last and "└ " or "├ ") or nil,
                    lines = { tostring(element.name), element.detail },
                    waiting = element.notification_count,
                    highlighted = element.is_highlighted,
                    top = top,
                    resource = node.resource.name,
                    keys = node.resource.keys,
                    item = element,
                    parent = node.parent
                }
                add(below(node), prefix and prefix .. (last and "  " or "│ ") or "")
            end
        end
    end
    local waiting = 0
    for _, resource in ipairs(resources) do
        if not resource.parent then
            ---@type table<string, HerdrCoreElement | false>?
            local keyed = wanted[resource.name]
            if keyed then keyed[""] = false end
            -- The terminals' elements are made here; the others' are what their monitors notified.
            ---@type HerdrCoreElement[]?
            local list = sections
            if keyed then list = (listed[resource.name] or {})[""] end
            for _, element in ipairs(list or {}) do
                waiting = waiting + (element.notification_count or 0)
            end
            add(nodes(list, resource, 1, resource.name), nil, true)
        end
    end
    if options.collapsed then
        return state, { { kind = "summary", lines = {}, waiting = waiting } }, wanted, waiting
    end
    return state, rows, wanted, waiting
end

---@class HerdrCoreRunAction
---@field type 'run_action'
---@field run  HerdrCoreResourceAction
---@field ctx  HerdrCoreActionContext

-- What a key pressed on an item asks for: the function given for the key, or the action of the item's
-- resource that the key names, to be run with the item.
---@param resources HerdrCoreResource[]
---@param event     { resource: string, key: string, item: HerdrCoreItem, parent?: HerdrCoreElement }
---@return HerdrCoreRunAction[]
function M.press(resources, event)
    for _, resource in ipairs(resources) do
        if resource.name == event.resource then
            local found = (resource.keys or {})[event.key]
            local run = type(found) == "function" and found or (resource.actions or {})[found]
            if type(run) == "function" then
                return { { type = "run_action", run = run, ctx = { item = event.item, parent = event.parent } } }
            end
        end
    end
    return {}
end

return M
