local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["updates terminal and space state through one entry point"] = function ()
    -- Given an empty application state
    local core = require("herdr-core.core.state")
    local initial = core.new()
    -- When a terminal starts
    local updated, effects = core.update(initial, {
        type = "terminal_started",
        terminal = {
            address = "t1",
            labels = {},
            folder = "/project",
            turn = 0,
            created_ms = 1
        }
    })
    -- Then its data is stored and its repository root is requested
    MiniTest.expect.equality(updated.terminals.t1.folder, "/project")
    MiniTest.expect.equality(effects, { { type = "find_repo_root", terminal = "t1", folder = "/project" } })
    MiniTest.expect.equality(initial.terminals, {})
end

T["ignores unknown events"] = function ()
    -- Given an initialized state
    local core = require("herdr-core.core.state")
    local state = core.new()
    -- When a future event type arrives
    local updated, effects = core.update(state, { type = "unknown" })
    -- Then state is unchanged and no effects run
    MiniTest.expect.equality(updated, state)
    MiniTest.expect.equality(effects, {})
end

T["removes an ended terminal from each state and gathers layout effects"] = function ()
    -- Given a terminal in the list, space map and restored layout
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", labels = {}, folder = "/app", turn = 0, created_ms = 1 }
    state.spaces.t1 = "/app"
    state.layout = {
        version = 1,
        value = {
            tabs = {
                {
                    id = "tab1",
                    root = { kind = "terminal", id = "w1", terminal = "t1" }
                }
            }
        }
    }
    -- When the terminal ends
    local updated, effects = core.update(state, { type = "terminal_ended", terminal = "t1" })
    -- Then every state drops it and layout effects are returned together
    MiniTest.expect.equality(updated.terminals, {})
    MiniTest.expect.equality(updated.spaces, {})
    MiniTest.expect.equality(updated.layout.value, { tabs = {} })
    MiniTest.expect.equality(#effects, 2)
end

T["updates a foreground folder and requests its new space"] = function ()
    -- Given a remote terminal in the application state
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", machine = "server", labels = {}, folder = "/old", turn = 0, created_ms = 1 }
    -- When the foreground process changes directory
    local updated, effects = core.update(state, {
        type = "foreground_changed",
        terminal = "t1",
        folder = "/new",
        program = "fish"
    })
    -- Then the foreground data changes and its remote root is requested
    MiniTest.expect.equality(updated.terminals.t1.folder, "/new")
    MiniTest.expect.equality(
        effects, { { type = "find_repo_root", terminal = "t1", folder = "/new", machine = "server" } }
    )
end

T["initializes terminal data and requests each repository root"] = function ()
    -- Given a fresh application state and an initial terminal list
    local core = require("herdr-core.core.state")
    local items = {
        { address = "t1", labels = {}, folder = "/one", turn = 0, created_ms = 1 },
        { address = "server/t2", machine = "server", labels = {}, folder = "/two", turn = 0, created_ms = 1 }
    }
    -- When the list arrives
    local updated, effects = core.update(core.new(), { type = "terminals_listed", terminals = items })
    -- Then both terminals are stored and roots are requested on their machines
    MiniTest.expect.equality(updated.terminals.t1, items[1])
    MiniTest.expect.equality(effects, {
        { type = "find_repo_root", terminal = "t1", folder = "/one" },
        { type = "find_repo_root", terminal = "server/t2", folder = "/two", machine = "server" }
    })
end

T["applies a repository result for the current terminal folder"] = function ()
    -- Given a terminal inside a repository subfolder
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", labels = {}, folder = "/app/src", turn = 0, created_ms = 1 }
    -- When its repository lookup completes
    local updated, effects = core.update(state, {
        type = "repo_root_found",
        terminal = "t1",
        folder = "/app/src",
        root = "/app"
    })
    -- Then the space is stored and the label write is requested
    MiniTest.expect.equality(updated.spaces.t1, "/app")
    MiniTest.expect.equality(effects, { { type = "set_space", terminal = "t1", space = "/app" } })
end

T["ignores repository results for old folders and ended terminals"] = function ()
    -- Given a terminal that has moved since the lookup started
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", labels = {}, folder = "/new", turn = 0, created_ms = 1 }
    -- When results arrive for the old folder and a terminal that no longer exists
    local updated, effects = core.update(state, {
        type = "repo_root_found",
        terminal = "t1",
        folder = "/old",
        root = "/old"
    })
    local ended, ended_effects = core.update(state, {
        type = "repo_root_found",
        terminal = "gone",
        folder = "/old",
        root = "/old"
    })
    -- Then neither can write a space label
    MiniTest.expect.equality(updated, state)
    MiniTest.expect.equality(ended, state)
    MiniTest.expect.equality(effects, {})
    MiniTest.expect.equality(ended_effects, {})
end

T["routes terminal updates and label write requests"] = function ()
    -- Given a terminal in the application state
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", labels = {}, folder = "/app", turn = 0, created_ms = 1 }
    -- When its status, turn and labels change and naming and pinning are requested
    state = core.update(state, { type = "status_changed", terminal = "t1", status = "working", status_ms = 2 })
    state = core.update(state, { type = "turn_changed", terminal = "t1", turn = 1 })
    state = core.update(state, { type = "labels_changed", terminal = "t1", labels = { custom = "value" } })
    local _, named = core.update(state, { type = "terminal_named", terminal = "t1", name = "build" })
    local _, pinned = core.update(state, { type = "terminal_pinned", terminal = "t1", pinned = true })
    -- Then terminal data and label effects pass through the entry point
    MiniTest.expect.equality(state.terminals.t1.status, "working")
    MiniTest.expect.equality(state.terminals.t1.turn, 1)
    MiniTest.expect.equality(state.terminals.t1.labels, { custom = "value" })
    MiniTest.expect.equality(assert(named[1]).type, "set_label")
    MiniTest.expect.equality(assert(pinned[1]).type, "set_label")
end

T["routes layout events to shared layout state"] = function ()
    -- Given a stored layout from another editor
    local core = require("herdr-core.core.state")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    -- When the layout event arrives
    local updated, effects = core.update(core.new(), { type = "layout_loaded", value = value, version = 2 })
    -- Then the shared layout and restoration request are returned
    MiniTest.expect.equality(updated.layout.value, value)
    MiniTest.expect.equality(effects, { { type = "show_layout", value = value } })
end

return T
