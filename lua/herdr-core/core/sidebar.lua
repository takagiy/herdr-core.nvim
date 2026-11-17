local M = {}
local attention = require("herdr-core.core.attention")
local terminals_module = require("herdr-core.core.terminals")

---@class HerdrCoreSidebarRow
---@field kind      'machine' | 'space' | 'terminal' | 'summary' | 'new_terminal' | 'setup_heading' | 'setup_button' | 'setup_text' | 'setup_item' | 'setup_error'
---@field root      string?
---@field address   string?
---@field machine   string?
---@field connected boolean?
---@field status    string?
---@field lines     string[]
---@field waiting   integer?
---@field guide?    string                                                                                                                                         Tree lines before a child's status, such as "│ └ ".
---@field id        string?
---@field group?    string                                                                                                                                         The Setup heading a setup row belongs to.
---@field name?     string                                                                                                                                         The integration a setup item installs.
---@field button?   string                                                                                                                                         The text of the row's button.
---@field action?   'install' | 'install_all' | 'dismiss'

---@class HerdrCoreSidebarGroup
---@field root      string
---@field machine   string?
---@field terminals HerdrCoreTerminal[]
---@field updated   integer

---@class HerdrCoreSidebarOptions
---@field machines?  table<string, boolean>
---@field folded?    table<string, boolean>
---@field collapsed? boolean

---@class HerdrCoreSidebarState
---@field groups    table<string, integer>
---@field terminals table<string, integer>
---@field locations table<string, string>

---@param previous? HerdrCoreSidebarState
---@param terminals HerdrCoreTerminal[]
---@param options?  HerdrCoreSidebarOptions
---@return HerdrCoreSidebarState, HerdrCoreSidebarRow[]
function M.update(previous, terminals, options)
    options = options or {}
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
        local root = head.labels["herdr.space"] or head.folder
        local key = (head.machine or "") .. "\0" .. root
        groups[key] = groups[key] or { root = root, machine = head.machine, terminals = {}, updated = 0 }
        groups[key].updated = math.max(groups[key].updated, terminal.status_ms or terminal.created_ms)
        table.insert(groups[key].terminals, terminal)
    end
    local roots = {}
    for root in pairs(groups) do
        table.insert(roots, root)
    end
    table.sort(roots, function (a, b)
        local first, second = groups[a], groups[b]
        if first.machine ~= second.machine then return (first.machine or "") < (second.machine or "") end
        if previous then
            local ap, bp = previous.groups[a] or 0, previous.groups[b] or 0
            if ap ~= bp then return ap < bp end
        end
        if first.updated ~= second.updated then return first.updated > second.updated end
        return a < b
    end)
    ---@type HerdrCoreSidebarRow[]
    local rows = {}
    ---@type HerdrCoreSidebarState
    local state = { groups = {}, terminals = {}, locations = {} }
    local machine = ""
    local total_waiting = 0
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
        if group.machine and group.machine ~= machine then
            table.insert(rows, {
                kind = "machine",
                id = "machine:" .. group.machine,
                lines = {},
                machine = group.machine,
                connected = not options.machines or options.machines[group.machine] ~= false
            })
            machine = group.machine
        end
        local waiting = 0
        for _, terminal in ipairs(group.terminals) do
            if waits(terminal) then waiting = waiting + 1 end
        end
        total_waiting = total_waiting + waiting
        local machine_folded = group.machine and options.folded and options.folded["machine:" .. group.machine]
        if not machine_folded then
            table.insert(rows, {
                kind = "space",
                root = group.root,
                machine = group.machine,
                lines = {},
                waiting = waiting
            })
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
        -- Each family in the space's order, children right under their parent, siblings in that order too.
        ---@param parent? string
        ---@param prefix  string
        local function add(parent, prefix)
            local family = children(parent)
            for index, terminal in ipairs(family) do
                local last = index == #family
                terminal_index = terminal_index + 1
                state.terminals[terminal.address] = terminal_index
                state.locations[terminal.address] = root
                if not machine_folded then
                    -- The name the command was run by: hc names the file a link points to, such as claude's version.
                    local command = terminal.argv and terminal.argv[1] or terminal.program or ""
                    local program = command:match([=[[^/\]+$]=]) or ""
                    program = program:gsub("^%-+", ""):gsub("%.[eE][xX][eE]$", "")
                    local below = waiting_below(terminal)
                    table.insert(rows, {
                        kind = "terminal",
                        address = terminal.address,
                        status = attention.display(terminal, child(terminal)).status,
                        guide = parent and prefix .. (last and "└ " or "├ ") or nil,
                        waiting = below > 0 and below or nil,
                        lines = {
                            terminal.labels["herdr-core-nvim.name"] or terminal.name or terminal.address,
                            program
                        }
                    })
                end
                add(terminal.address, parent and prefix .. (last and "  " or "│ ") or "")
            end
        end
        add(nil, "")
    end
    if options.collapsed then
        return state, { { kind = "summary", lines = {}, waiting = total_waiting } }
    end
    return state, rows
end

return M
