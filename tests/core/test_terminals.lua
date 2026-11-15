local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["loads the initial terminal list"] = function ()
    -- Given a terminal snapshot with its identity, status and foreground facts
    local terminals = require("herdr-core.core.terminals")
    local terminal = {
        address = "t1",
        name = "review",
        labels = {},
        status = "working",
        turn = 2,
        program = "codex",
        folder = "C:/app",
        created_ms = 10,
        status_ms = 20
    }
    -- When the snapshot arrives
    local state, effects = terminals.update({}, { type = "terminals_listed", terminals = { terminal } })
    -- Then the facts are stored by address without effects
    MiniTest.expect.equality(state, { t1 = terminal })
    MiniTest.expect.equality(effects, {})
end

T["adds a started terminal without dropping existing terminals"] = function ()
    -- Given a registry with a terminal
    local terminals = require("herdr-core.core.terminals")
    local first = { address = "t1", labels = {}, turn = 0, folder = "C:/app", created_ms = 1 }
    local second = { address = "t2", labels = {}, turn = 0, folder = "C:/other", created_ms = 2 }
    local original = { t1 = first }
    -- When another terminal starts
    local state = terminals.update(original, { type = "terminal_started", terminal = second })
    -- Then both terminals remain and the previous state is unchanged
    MiniTest.expect.equality(state, { t1 = first, t2 = second })
    MiniTest.expect.equality(original, { t1 = first })
end

T["updates the foreground without changing the previous state"] = function ()
    -- Given a terminal running a shell
    local terminals = require("herdr-core.core.terminals")
    local original = {
        t1 = { address = "t1", labels = {}, turn = 0, folder = "C:/", program = "pwsh", created_ms = 1 }
    }
    -- When its foreground changes to an agent in another folder
    local state = terminals.update(original, {
        type = "foreground_changed",
        terminal = "t1",
        program = "claude",
        folder = "C:/app"
    })
    -- Then the new foreground is recorded without mutating the previous terminal
    MiniTest.expect.equality(state.t1.program, "claude")
    MiniTest.expect.equality(state.t1.folder, "C:/app")
    MiniTest.expect.equality(original.t1.program, "pwsh")
    MiniTest.expect.equality(original.t1.folder, "C:/")
end

T["records status and its update time"] = function ()
    -- Given a working terminal
    local terminals = require("herdr-core.core.terminals")
    local original = {
        t1 = {
            address = "t1",
            labels = {},
            turn = 0,
            folder = "C:/",
            created_ms = 1,
            status = "working"
        }
    }
    -- When it reports blocked
    local state = terminals.update(original, {
        type = "status_changed",
        terminal = "t1",
        status = "blocked",
        status_ms = 20
    })
    -- Then status and time are recorded without modifying the old state
    MiniTest.expect.equality(state.t1.status, "blocked")
    MiniTest.expect.equality(state.t1.status_ms, 20)
    MiniTest.expect.equality(original.t1.status, "working")
end

T["replaces the labels reported by the terminal"] = function ()
    -- Given a terminal with an old label
    local terminals = require("herdr-core.core.terminals")
    local original = { t1 = { address = "t1", labels = { old = "value" }, turn = 0, folder = "C:/", created_ms = 1 } }
    -- When its complete labels arrive
    local state = terminals.update(original, { type = "labels_changed", terminal = "t1", labels = { new = "value" } })
    -- Then the new set replaces the old one without mutating it
    MiniTest.expect.equality(state.t1.labels, { new = "value" })
    MiniTest.expect.equality(original.t1.labels, { old = "value" })
end

T["removes an ended terminal"] = function ()
    -- Given one live terminal
    local terminals = require("herdr-core.core.terminals")
    local original = { t1 = { address = "t1", labels = {}, turn = 0, folder = "C:/", created_ms = 1 } }
    -- When its program ends
    local state, effects = terminals.update(original, { type = "terminal_ended", terminal = "t1" })
    -- Then it disappears from the new registry without changing the old one
    MiniTest.expect.equality(state, {})
    MiniTest.expect.equality(original.t1.address, "t1")
    MiniTest.expect.equality(effects, {})
end

T["requests a display name label"] = function ()
    -- Given a terminal to name
    local terminals = require("herdr-core.core.terminals")
    local original = { t1 = { address = "t1", labels = {}, turn = 0, folder = "C:/", created_ms = 1 } }
    -- When the user names it
    local state, effects = terminals.update(original, { type = "terminal_named", terminal = "t1", name = "review" })
    -- Then a write is requested and state waits for the reported label
    MiniTest.expect.equality(state, original)
    MiniTest.expect.equality(effects, {
        {
            type = "set_label",
            terminal = "t1",
            key = "herdr-core-nvim.name",
            value = "review"
        }
    })
end

T["clears the display name"] = function ()
    -- Given a named terminal
    local terminals = require("herdr-core.core.terminals")
    local state = {
        t1 = {
            address = "t1",
            labels = { ["herdr-core-nvim.name"] = "review" },
            turn = 0,
            folder = "C:/",
            created_ms = 1
        }
    }
    -- When the user enters an empty name
    local _, effects = terminals.update(state, { type = "terminal_named", terminal = "t1", name = "" })
    -- Then an empty label value requests removal
    MiniTest.expect.equality(
        effects, { { type = "set_label", terminal = "t1", key = "herdr-core-nvim.name", value = "" } }
    )
end

T["pins a terminal"] = function ()
    -- Given a live terminal
    local terminals = require("herdr-core.core.terminals")
    local original = { t1 = { address = "t1", labels = {}, turn = 0, folder = "C:/", created_ms = 1 } }
    -- When the user pins it
    local state, effects = terminals.update(original, { type = "terminal_pinned", terminal = "t1", pinned = true })
    -- Then the shared pin label is requested without changing state early
    MiniTest.expect.equality(state, original)
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.pinned", value = "1" } })
end

T["unpins a terminal"] = function ()
    -- Given a pinned terminal
    local terminals = require("herdr-core.core.terminals")
    local original = {
        t1 = {
            address = "t1",
            labels = { ["herdr.pinned"] = "1" },
            turn = 0,
            folder = "C:/",
            created_ms = 1
        }
    }
    -- When the user unpins it
    local _, effects = terminals.update(original, { type = "terminal_pinned", terminal = "t1", pinned = false })
    -- Then the empty label value requests removal
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.pinned", value = "" } })
end

T["records a completed turn without changing other terminal facts"] = function ()
    -- Given a terminal at turn one
    local terminals = require("herdr-core.core.terminals")
    local original = { t1 = { address = "t1", labels = {}, turn = 1, folder = "C:/", created_ms = 1 } }
    -- When a turn change arrives separately from its status
    local state = terminals.update(original, { type = "turn_changed", terminal = "t1", turn = 2 })
    -- Then the current turn advances without changing the previous state
    MiniTest.expect.equality(state.t1.turn, 2)
    MiniTest.expect.equality(state.t1.folder, "C:/")
    MiniTest.expect.equality(original.t1.turn, 1)
end

return T
