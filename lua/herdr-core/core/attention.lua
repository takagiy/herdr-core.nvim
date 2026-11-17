local M = {}

---@class HerdrCoreAttention
---@field status  string?
---@field waiting boolean

---@param terminal HerdrCoreTerminal
---@return HerdrCoreAttention
local function plain(terminal)
    if terminal.status == "working" then
        return { status = "working", waiting = false }
    end
    local seen = tonumber(terminal.labels["herdr.seen"])
    if terminal.status ~= "blocked" and terminal.status ~= "error" and seen and terminal.turn > seen then
        return { status = "done", waiting = true }
    end
    if terminal.status == "done" and seen and terminal.turn <= seen then
        return { status = "idle", waiting = false }
    end
    return { status = terminal.status, waiting = terminal.status == "blocked" or terminal.status == "error" }
end

---@param terminal HerdrCoreTerminal
---@param child?   boolean           Whether the terminal that started it is still there.
---@return HerdrCoreAttention
function M.display(terminal, child)
    local display = plain(terminal)
    if child then
        -- A child reports to its parent, so its finished turn is the parent's news; an error stops it like a block.
        if display.status == "done" then return { status = "idle", waiting = false } end
        if display.status == "error" then return { status = "blocked", waiting = true } end
    end
    return display
end

---@param read     table<string, integer>
---@param terminal HerdrCoreTerminal
---@param focused  boolean
---@param visible  boolean
---@return table<string, integer>, HerdrCoreSetLabel[]
function M.observe(read, terminal, focused, visible)
    if not focused or not visible or read[terminal.address] == terminal.turn then
        return read, {}
    end
    local seen = tonumber(terminal.labels["herdr.seen"])
    local updated = {}
    for address, turn in pairs(read) do
        updated[address] = turn
    end
    updated[terminal.address] = terminal.turn
    if seen and seen >= terminal.turn then
        return updated, {}
    end
    return updated, {
            {
                type = "set_label",
                terminal = terminal.address,
                key = "herdr.seen",
                value = tostring(terminal.turn)
            }
        }
end

---@param terminal HerdrCoreTerminal
---@return HerdrCoreSetLabel[]
function M.unread(terminal)
    if terminal.turn == 0 then
        return {}
    end
    return {
        { type = "set_label", terminal = terminal.address, key = "herdr.seen", value = tostring(terminal.turn - 1) }
    }
end

---@class HerdrCoreNotify
---@field type     'notify'
---@field terminal string
---@field name     string
---@field status   string

---@param before  HerdrCoreTerminal
---@param after   HerdrCoreTerminal
---@param focused boolean
---@param visible boolean
---@param child?  boolean
---@return HerdrCoreNotify?
function M.notification(before, after, focused, visible, child)
    if focused and visible then
        return nil
    end
    local display = M.display(after, child)
    if display.status ~= "blocked" and display.status ~= "done" then
        return nil
    end
    if M.display(before, child).status == display.status and (display.status == "blocked" or before.turn == after.turn) then
        return nil
    end
    return {
        type = "notify",
        terminal = after.address,
        name = after.labels["herdr-core-nvim.name"] or after.name or after.address,
        status = display.status
    }
end

return M
