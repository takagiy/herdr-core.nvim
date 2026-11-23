local MiniTest = require("mini.test")
local T = MiniTest.new_set()

---@class HerdrCoreTestMonitors
---@field monitors HerdrCoreMonitors
---@field events   HerdrCoreItemsListed[]
---@field reports  string[]

-- The monitors with what they sent to the core and what they reported.
---@return HerdrCoreTestMonitors
local function start()
    local events, reports = {}, {}
    local factory = require("herdr-core.adapter.resources")
    local monitors = factory.new(
        function (event) events[#events + 1] = event end, function (message) reports[#reports + 1] = message end
    )
    return { monitors = monitors, events = events, reports = reports }
end

-- When the core asks to arm a monitor, the adapter can make one instance for the element and arm it with the element; asked again, it can arm the same instance with the same notify.
T["makes one monitor for an element and arms it each time it is asked"] = function ()
    -- Given a monitor that records how it is made and armed
    local made = 0
    ---@type HerdrCoreArmContext[]
    local armed = {}
    local monitor = function ()
        made = made + 1
        return { arm = function (ctx) armed[#armed + 1] = ctx end, disarm = function () end }
    end
    local started = start()
    local first, second = { kind = "item", name = "t1" }, { kind = "item", name = "t1", status = "working" }
    -- When the core asks to arm it for an element, and again after the element changed
    for _, parent in ipairs({ first, second }) do
        started.monitors.sync({
            type = "sync_monitors",
            arm = { { resource = "task", key = "k", monitor = monitor, parent = parent } },
            disarm = {}
        })
    end
    -- Then one instance is armed twice, each time with the element as it is, and with the same notify
    MiniTest.expect.equality({ made, #armed }, { 1, 2 })
    local once, again = assert(armed[1]), assert(armed[2])
    MiniTest.expect.equality(
        { once.parent == first, again.parent == second, once.notify == again.notify }, { true, true, true }
    )
end

-- When monitors notify, the adapter can pass what they listed to the core in one event, on the main loop.
-- When a monitor is disarmed, the adapter can call its disarm once and ignore what it notifies afterwards.
T["sends what monitors notified in one event and ignores a disarmed monitor"] = function ()
    -- Given a monitor at the top that notifies a section when armed, one under an element that notifies an item, and one that is disarmed
    local disarmed = 0
    ---@param list   HerdrCoreElement[]
    ---@param calls? { notify?: fun(list: HerdrCoreElement[]) }
    ---@return fun(): HerdrCoreMonitor
    local function notifying(list, calls)
        return function ()
            return {
                arm = function (ctx)
                    if calls then calls.notify = ctx.notify end
                    ctx.notify(list)
                end,
                disarm = function () disarmed = disarmed + 1 end
            }
        end
    end
    local section = { { kind = "section", name = "Notes", items = { { kind = "item", name = "a" } } } }
    local item = { { kind = "item", name = "task" } }
    ---@type { notify?: fun(list: HerdrCoreElement[]) }
    local late = {}
    local started = start()
    -- When the three are armed, the third is disarmed and then notifies again
    started.monitors.sync({
        type = "sync_monitors",
        arm = {
            { resource = "notes", key = "", monitor = notifying(section) },
            { resource = "task", key = "k", monitor = notifying(item), parent = { kind = "item", name = "t1" } },
            { resource = "gone", key = "", monitor = notifying(item, late) }
        },
        disarm = {}
    })
    started.monitors.sync({ type = "sync_monitors", arm = {}, disarm = { { resource = "gone", key = "" } } })
    local notify = assert(late.notify)
    notify(item)
    vim.wait(1000, function () return #started.events > 0 end)
    -- Then one event carries the lists of the two that are armed, and the third was disarmed once
    MiniTest.expect.equality(started.events, {
        {
            type = "items_listed",
            lists = {
                { resource = "notes", parent = "", items = section },
                {
                    resource = "task",
                    parent = "k",
                    items = item
                }
            }
        }
    })
    MiniTest.expect.equality(disarmed, 1)
end

-- When a monitor cannot be made, fails to arm, or notifies something that cannot be shown, the adapter can report it once and go on; it can still disarm a monitor whose arm failed.
T["reports a monitor that fails once and still disarms it"] = function ()
    -- Given a monitor without disarm, one whose arm fails, and one under an element that notifies a section
    local disarmed = 0
    local broken = function () return { arm = function () end } end
    local failing = function ()
        return { arm = function () error("no source", 0) end, disarm = function () disarmed = disarmed + 1 end }
    end
    local wrong = function ()
        return {
            arm = function (ctx) ctx.notify({ { kind = "section", name = "Deep" } }) end,
            disarm = function () disarmed = disarmed + 1 end
        }
    end
    local started = start()
    ---@type HerdrCoreSyncMonitors
    local effect = {
        type = "sync_monitors",
        arm = {
            { resource = "broken", key = "", monitor = broken },
            { resource = "failing", key = "", monitor = failing },
            { resource = "wrong", key = "k", monitor = wrong, parent = { kind = "item", name = "t1" } }
        },
        disarm = {}
    }
    -- When they are armed twice, the notification is taken up, and everything is stopped
    started.monitors.sync(effect)
    started.monitors.sync(effect)
    vim.wait(200, function () return #started.reports >= 3 end)
    started.monitors.stop()
    -- Then each failure is reported once, nothing is sent to the core, and the two with a disarm are disarmed
    MiniTest.expect.equality(started.reports, {
        "broken: monitor must return a table with arm and disarm",
        "failing: no source",
        "wrong: a section can only be at the top"
    })
    MiniTest.expect.equality({ #started.events, disarmed }, { 0, 2 })
end

return T
