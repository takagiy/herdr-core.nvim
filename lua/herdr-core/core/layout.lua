local M = {}

---@class HerdrCoreLayoutNode
---@field kind      'terminal' | 'file' | 'split'
---@field id        string
---@field terminal  string?
---@field axis?     'row' | 'column'
---@field children? HerdrCoreLayoutNode[]

---@class HerdrCoreLayoutTab
---@field id   string
---@field root HerdrCoreLayoutNode

---@class HerdrCoreLayoutValue
---@field tabs HerdrCoreLayoutTab[]

---@class HerdrCoreLayoutState
---@field value   HerdrCoreLayoutValue
---@field version integer
---@field base?   HerdrCoreLayoutValue

---@class HerdrCoreLayoutLoaded
---@field type    'layout_loaded'
---@field value   HerdrCoreLayoutValue?
---@field version integer
---@field live?   table<string, any>    Terminals known to be running; the others are dropped from the layout.

---@class HerdrCoreLayoutEffect
---@field type    'show_layout' | 'save_layout'
---@field value   HerdrCoreLayoutValue
---@field version integer?

---@return HerdrCoreLayoutState
function M.new()
    return { value = { tabs = {} }, version = 0 }
end

---@param node  HerdrCoreLayoutNode
---@param gone? fun(address: string): boolean
---@return HerdrCoreLayoutNode?
local function terminals_only(node, gone)
    if node.kind == "file" then return nil end
    if node.kind == "terminal" then
        if gone and gone(assert(node.terminal)) then return nil end
        return node
    end
    local children = {}
    for _, child in ipairs(node.children or {}) do
        local kept = terminals_only(child, gone)
        if kept then table.insert(children, kept) end
    end
    if #children == 0 then return nil end
    if #children == 1 then return children[1] end
    return { kind = "split", id = node.id, axis = node.axis, children = children }
end

---@param value HerdrCoreLayoutValue
---@param gone? fun(address: string): boolean
---@return HerdrCoreLayoutValue
local function shared(value, gone)
    local tabs = {}
    for _, tab in ipairs(value.tabs) do
        local root = terminals_only(tab.root, gone)
        if root then table.insert(tabs, {id = tab.id, root = root}) end
    end
    return { tabs = tabs }
end

---@class HerdrCoreLayoutChanged
---@field type  'layout_changed'
---@field value HerdrCoreLayoutValue

---@class HerdrCoreLayoutConflict
---@field type    'layout_conflict'
---@field value   HerdrCoreLayoutValue
---@field version integer

---@param left  HerdrCoreLayoutNode
---@param right HerdrCoreLayoutNode
---@return boolean
local function same_node(left, right)
    if left.kind ~= right.kind or left.id ~= right.id or left.terminal ~= right.terminal or left.axis ~= right.axis then
        return false
    end
    local a, b = left.children or {}, right.children or {}
    if #a ~= #b then return false end
    for index, child in ipairs(a) do
        if not same_node(child, assert(b[index])) then return false end
    end
    return true
end

---@param value HerdrCoreLayoutValue
---@return table<string, HerdrCoreLayoutTab?>
local function by_id(value)
    local result = {}
    for _, tab in ipairs(value.tabs) do
        result[tab.id] = tab
    end
    return result
end

---@param left  HerdrCoreLayoutValue
---@param right HerdrCoreLayoutValue
---@return boolean
local function same_layout(left, right)
    if #left.tabs ~= #right.tabs then return false end
    for index, tab in ipairs(left.tabs) do
        local other = assert(right.tabs[index])
        if tab.id ~= other.id or not same_node(tab.root, other.root) then return false end
    end
    return true
end

---@param state HerdrCoreLayoutState
---@param event HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict | HerdrCoreTerminalEnded
---@return HerdrCoreLayoutState, HerdrCoreLayoutEffect[]
function M.update(state, event)
    if event.type == "terminal_ended" then
        local value = shared(state.value, function (address) return address == event.terminal end)
        if same_layout(state.value, value) then return state, {} end
        return { value = value, version = state.version, base = state.base or state.value },
            { { type = "show_layout", value = value }, { type = "save_layout", value = value, version = state.version } }
    end
    if event.type == "layout_conflict" then
        if event.version < state.version then return state, {} end
        local tabs = {}
        local base = by_id(state.base or state.value)
        local ours = by_id(state.value)
        local known = {}
        for _, tab in ipairs(event.value.tabs) do
            local original, edited = base[tab.id], ours[tab.id]
            if not original or edited then
                if edited and (not original or not same_node(original.root, edited.root)) then
                    table.insert(tabs, edited)
                else
                    table.insert(tabs, tab)
                end
            end
            known[tab.id] = true
        end
        for _, tab in ipairs(state.value.tabs) do
            local original = base[tab.id]
            if not known[tab.id] and (not original or not same_node(original.root, tab.root)) then
                table.insert(tabs, tab)
            end
        end
        local value = { tabs = tabs }
        return { value = value, version = event.version, base = event.value },
            { { type = "show_layout", value = value }, { type = "save_layout", value = value, version = event.version } }
    end
    if event.type == "layout_changed" then
        local value = shared(event.value)
        if same_layout(state.value, value) then return state, {} end
        return { value = value, version = state.version, base = state.base or state.value }, {
                {
                    type = "save_layout",
                    value = value,
                    version = state.version
                }
            }
    end
    if event.version < state.version then return state, {} end
    local value = event.value or { tabs = {} }
    local live = event.live
    -- Terminals that finished while no Neovim was running never sent terminal_ended.
    local alive = live and shared(value, function (address) return live[address] == nil end) or value
    local dropped = not same_layout(value, alive)
    value = alive
    if same_layout(state.value, value) then return {value = value, version = event.version}, {} end
    if state.base then
        return M.update(state, { type = "layout_conflict", value = value, version = event.version })
    end
    ---@type HerdrCoreLayoutEffect[]
    local effects = { { type = "show_layout", value = value } }
    if dropped then table.insert(effects, { type = "save_layout", value = value, version = event.version }) end
    return { value = value, version = event.version }, effects
end

return M
