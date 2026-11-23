local M = {}

-- Why a list cannot be shown, or nil. Sections can only be at the top of a list that is not under an element.
---@param list  any
---@param under boolean Whether the list goes under an element.
---@return string?
local function problem(list, under)
    ---@param elements any
    ---@param sections boolean
    ---@return string?
    local function check(elements, sections)
        if type(elements) ~= "table" or not vim.islist(elements) then return "sections and items go in a list" end
        for _, element in ipairs(elements) do
            if type(element) ~= "table" or (element.kind ~= "item" and element.kind ~= "section") then
                return "an element must be made with Section or Item"
            end
            if element.kind == "section" and not sections then return "a section can only be at the top" end
            if type(element.name) ~= "string" then return "an element must have a name" end
            local found = element.items ~= nil and check(element.items, false)
            if found then return found end
        end
        return nil
    end
    return check(list, not under)
end

---@class HerdrCoreMonitors
---@field sync fun(effect: HerdrCoreSyncMonitors) Arms and disarms monitors as the core asks.
---@field stop fun()                              Disarms every monitor.

---@class HerdrCoreArmed
---@field instance HerdrCoreMonitor
---@field armed    boolean
---@field notify   fun(list: HerdrCoreElement[])

-- Keeps the monitors that are armed, and turns what they notify into events for the core.
---@param dispatch fun(event: HerdrCoreItemsListed)
---@param report   fun(message: string)
---@return HerdrCoreMonitors
function M.new(dispatch, report)
    ---@type table<string, HerdrCoreArmed>
    local held = {}
    ---@type table<string, boolean>
    local reported = {}
    -- What was notified since the last event. It goes to the core in one event, so the sidebar is drawn once.
    ---@type { monitor: HerdrCoreArmed, resource: string, parent: string, under: boolean, items: any } []
    local pending = {}
    local active = true
    -- A monitor fails the same way each time it is armed, so each failure is reported once.
    ---@param resource string
    ---@param message  string
    local function fail(resource, message)
        message = resource .. ": " .. message
        if reported[message] then return end
        reported[message] = true
        report(message)
    end
    local function flush()
        local notes = pending
        pending = {}
        ---@type { resource: string, parent: string, items: HerdrCoreElement[] } []
        local lists = {}
        for _, note in ipairs(notes) do
            if note.monitor.armed then
                local found = problem(note.items, note.under)
                if found then
                    fail(note.resource, found)
                else
                    lists[#lists + 1] = { resource = note.resource, parent = note.parent, items = note.items }
                end
            end
        end
        if active and #lists > 0 then dispatch({ type = "items_listed", lists = lists }) end
    end
    ---@param effect HerdrCoreSyncMonitors
    local function sync(effect)
        for _, entry in ipairs(effect.disarm) do
            local id = entry.resource .. "\0" .. entry.key
            ---@type HerdrCoreArmed?
            local monitor = held[id]
            if monitor then
                held[id] = nil
                monitor.armed = false
                local ok, failure = pcall(monitor.instance.disarm)
                if not ok then fail(entry.resource, tostring(failure)) end
            end
        end
        for _, entry in ipairs(effect.arm) do
            local id = entry.resource .. "\0" .. entry.key
            ---@type HerdrCoreArmed?
            local monitor = held[id]
            if not monitor then
                local ok, instance = pcall(entry.monitor)
                if ok and type(instance) == "table"
                    and type(instance.arm) == "function" and type(instance.disarm) == "function" then
                    ---@type HerdrCoreArmed
                    local made = { instance = instance, armed = true, notify = function () end }
                    -- A monitor notifies from wherever its source calls back; the list is taken up on the main loop.
                    ---@param list HerdrCoreElement[]
                    made.notify = function (list)
                        if #pending == 0 then vim.schedule(flush) end
                        pending[#pending + 1] = {
                            monitor = made,
                            resource = entry.resource,
                            parent = entry.key,
                            under = entry.parent ~= nil,
                            items = list
                        }
                    end
                    held[id], monitor = made, made
                else
                    fail(entry.resource, ok and "monitor must return a table with arm and disarm" or tostring(instance))
                end
            end
            if monitor then
                local ok, failure = pcall(monitor.instance.arm, { parent = entry.parent, notify = monitor.notify })
                if not ok then fail(entry.resource, tostring(failure)) end
            end
        end
    end
    local function stop()
        active = false
        for _, monitor in pairs(held) do
            monitor.armed = false
            pcall(monitor.instance.disarm)
        end
        held = {}
    end
    return { sync = sync, stop = stop }
end

return M
