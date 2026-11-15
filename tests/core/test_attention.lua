local MiniTest = require("mini.test")
local T = MiniTest.new_set()

---@param status string?
---@param turn   integer
---@param seen   string?
---@return HerdrCoreTerminal
local function terminal(status, turn, seen)
    ---@type table<string, string>
    local labels = {}
    if seen then
        labels["herdr.seen"] = seen
    end
    return { address = "t1", labels = labels, turn = turn, status = status, folder = "C:/", created_ms = 1 }
end

T["counts blocked and error terminals as waiting"] = function ()
    -- Given a blocked or errored terminal
    local attention = require("herdr-core.core.attention")
    for _, status in ipairs({ "blocked", "error" }) do
        -- When its attention state is computed
        local state = attention.display(terminal(status, 1, "1"))
        -- Then it still needs the user even though its turn was seen
        MiniTest.expect.equality(state.waiting, true)
        MiniTest.expect.equality(state.status, status)
    end
end

T["marks an unseen completed turn as done"] = function ()
    -- Given a terminal whose latest turn has not been seen
    local attention = require("herdr-core.core.attention")
    -- When its attention state is computed
    local state = attention.display(terminal("idle", 2, "1"))
    -- Then it is done and waiting for the user
    MiniTest.expect.equality(state, { status = "done", waiting = true })
end

T["marks a seen completed turn as idle"] = function ()
    -- Given a completed turn that has already been seen
    local attention = require("herdr-core.core.attention")
    -- When the program still reports done
    local state = attention.display(terminal("done", 2, "2"))
    -- Then the displayed status is idle without attention
    MiniTest.expect.equality(state, { status = "idle", waiting = false })
end

T["marks a visible turn seen only once"] = function ()
    -- Given an unseen terminal in a focused, visible window
    local attention = require("herdr-core.core.attention")
    local current = terminal("done", 2, "1")
    -- When it is observed twice in that turn
    local read, effects = attention.observe({}, current, true, true)
    local _, again = attention.observe(read, current, true, true)
    -- Then only the first observation requests a seen update
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.seen", value = "2" } })
    MiniTest.expect.equality(again, {})
end

T["initializes the seen label even at turn zero"] = function ()
    -- Given a visible terminal without a seen label
    local attention = require("herdr-core.core.attention")
    -- When it is observed at turn zero
    local _, effects = attention.observe({}, terminal("idle", 0, nil), true, true)
    -- Then a seen label is initialized at zero
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.seen", value = "0" } })
end

T["does not mark hidden or unfocused terminals seen"] = function ()
    -- Given a terminal with an unseen turn
    local attention = require("herdr-core.core.attention")
    local current = terminal("done", 2, "1")
    -- When the editor is unfocused or the terminal is not displayed
    local read, effects = attention.observe({}, current, false, true)
    local hidden, hidden_effects = attention.observe({}, current, true, false)
    -- Then neither observation changes seen state
    MiniTest.expect.equality({ read, effects, hidden, hidden_effects }, { {}, {}, {}, {} })
end

T["keeps working status even when an older turn is unread"] = function ()
    -- Given a working terminal with an unread earlier turn
    local attention = require("herdr-core.core.attention")
    -- When its attention state is computed
    local state = attention.display(terminal("working", 2, "1"))
    -- Then working takes precedence over done
    MiniTest.expect.equality(state, { status = "working", waiting = false })
end

T["marks the latest turn unread"] = function ()
    -- Given a terminal whose latest turn was seen
    local attention = require("herdr-core.core.attention")
    -- When the user marks it unread
    local effects = attention.unread(terminal("idle", 2, "2"))
    -- Then seen is lowered by one
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.seen", value = "1" } })
end

T["leaves turn zero unchanged when marked unread"] = function ()
    -- Given a terminal that has not completed a turn
    local attention = require("herdr-core.core.attention")
    -- When the user marks it unread
    local effects = attention.unread(terminal("idle", 0, "0"))
    -- Then there is no negative seen value to write
    MiniTest.expect.equality(effects, {})
end

T["requests notification when an unseen terminal needs attention"] = function ()
    -- Given a working terminal not displayed to the user
    local attention = require("herdr-core.core.attention")
    local before = terminal("working", 1, "1")
    for _, status in ipairs({ "blocked", "done" }) do
        -- When it becomes blocked or completes a turn
        local effect = attention.notification(before, terminal(status, 2, "1"), true, false)
        -- Then a notification describes that terminal and state
        MiniTest.expect.equality(effect, { type = "notify", terminal = "t1", name = "t1", status = status })
    end
end

T["suppresses notifications for a terminal being watched"] = function ()
    -- Given a visible terminal in a focused editor
    local attention = require("herdr-core.core.attention")
    -- When it finishes
    local effect = attention.notification(terminal("working", 1, "1"), terminal("done", 2, "1"), true, true)
    -- Then no notification is requested
    MiniTest.expect.equality(effect, nil)
end

T["does not notify when work starts"] = function ()
    -- Given an idle terminal
    local attention = require("herdr-core.core.attention")
    -- When it starts working out of sight
    local effect = attention.notification(terminal("idle", 1, "1"), terminal("working", 1, "1"), false, false)
    -- Then no notification is requested
    MiniTest.expect.equality(effect, nil)
end

T["does not repeat a notification for the same state and turn"] = function ()
    -- Given a terminal that is already blocked
    local attention = require("herdr-core.core.attention")
    local current = terminal("blocked", 2, "1")
    -- When the same facts are reported again
    local effect = attention.notification(current, current, false, false)
    -- Then no duplicate notification is requested
    MiniTest.expect.equality(effect, nil)
    -- A separate turn event after the blocked status is still the same notification
    MiniTest.expect.equality(attention.notification(current, terminal("blocked", 3, "1"), false, false), nil)
end

T["does not lower an already seen turn"] = function ()
    -- Given seen state written by another client at this turn or beyond
    local attention = require("herdr-core.core.attention")
    for _, seen in ipairs({ "2", "3" }) do
        -- When a terminal with turn two becomes visible
        local _, effects = attention.observe({}, terminal("idle", 2, seen), true, true)
        -- Then the shared seen label is not rewritten or lowered
        MiniTest.expect.equality(effects, {})
    end
end

return T
