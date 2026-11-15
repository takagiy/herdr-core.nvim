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

---@param address string
---@param fields? table
---@return HerdrCoreTerminal
local function terminal(address, fields)
    return vim.tbl_extend(
        "force", { address = address, labels = {}, folder = "/app", turn = 0, created_ms = 1 }, fields or {}
    ) --[[@as HerdrCoreTerminal]]
end

-- When Neovim gains focus or shows other terminals, `update` can ask to mark each shown terminal as seen.
T["asks to mark the shown terminals as seen when Neovim is focused"] = function ()
    -- Given a terminal that finished turn 2 and one that is not shown
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1", { turn = 2, labels = { ["herdr.seen"] = "1" } })
    state.terminals.t2 = terminal("t2", { turn = 3, labels = { ["herdr.seen"] = "1" } })
    -- When focused Neovim shows only the first
    local _, effects = core.update(state, { type = "focus_changed", focused = true, terminals = { "t1" } })
    -- Then only the shown terminal is marked seen up to its turn
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.seen", value = "2" } })
end

-- When a terminal becomes blocked or done while nobody looks at it, `update` can ask to notify the user.
T["asks to notify when a terminal nobody looks at becomes blocked"] = function ()
    -- Given a working terminal named build, shown in a Neovim that is not focused, and a second shown in a focused one
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1", { status = "working", labels = { ["herdr-core-nvim.name"] = "build" } })
    state.terminals.t2 = terminal("t2", { status = "working" })
    local unfocused = core.update(state, { type = "focus_changed", focused = false, terminals = { "t1" } })
    local focused = core.update(state, { type = "focus_changed", focused = true, terminals = { "t2" } })
    -- When each becomes blocked
    local _, notified = core.update(unfocused, {
        type = "status_changed",
        terminal = "t1",
        status = "blocked",
        status_ms = 2
    })
    local _, quiet = core.update(focused, {
        type = "status_changed",
        terminal = "t2",
        status = "blocked",
        status_ms = 2
    })
    -- Then only the one nobody looks at is notified
    MiniTest.expect.equality(notified, { { type = "notify", terminal = "t1", name = "build", status = "blocked" } })
    MiniTest.expect.equality(quiet, {})
end

-- When the user chooses a terminal, `update` can ask to focus its window or to show it, as the opening policy decides.
T["asks to focus a chosen terminal's window or to show it"] = function ()
    -- Given a terminal shown in window 1003 and one that is not shown, with the default policy and a custom one
    local core = require("herdr-core.core.state")
    local state = core.new()
    local custom = core.new({
        open = function (address)
            return { type = "show_terminal", terminal = address, placement = "vertical" }
        end
    })
    local windows = { t1 = "1003" }
    -- When each is chosen
    local _, shown = core.update(state, { type = "terminal_chosen", terminal = "t1", windows = windows })
    local _, hidden = core.update(state, { type = "terminal_chosen", terminal = "t2", windows = windows })
    local _, policy = core.update(custom, { type = "terminal_chosen", terminal = "t2", windows = windows })
    -- Then the shown one is focused and the hidden one is shown as the policy decides
    MiniTest.expect.equality(shown, { { type = "focus_window", window = "1003" } })
    MiniTest.expect.equality(hidden, { { type = "show_terminal", terminal = "t2", placement = "tab" } })
    MiniTest.expect.equality(policy, { { type = "show_terminal", terminal = "t2", placement = "vertical" } })
end

-- When the user activates a heading, `update` can fold or unfold it.
T["folds a heading and unfolds it again"] = function ()
    -- Given a space heading
    local core = require("herdr-core.core.state")
    local state = core.new()
    -- When it is activated twice
    local folded = core.update(state, { type = "heading_toggled", id = "/app" })
    local unfolded = core.update(folded, { type = "heading_toggled", id = "/app" })
    -- Then it is folded after the first and unfolded after the second
    MiniTest.expect.equality(folded.folded["/app"], true)
    MiniTest.expect.equality(unfolded.folded["/app"], nil)
end

-- When the user asks for a new terminal, `update` can ask for a shell where the opening policy decides.
T["asks for a shell in the folder the request came from"] = function ()
    -- Given a request from a terminal window in /app/src, under the space /app
    local core = require("herdr-core.core.state")
    local request = {
        type = "new_terminal_requested",
        placement = "vertical",
        tab = "tab-9",
        terminal_folder = "/app/src",
        editor_folder = "/home"
    }
    -- When it is made from the terminal window, and again from the space heading
    local _, from_window = core.update(core.new(), request)
    local from_space = vim.tbl_extend("force", request, { space_root = "/app" }) --[[@as HerdrCoreNewTerminalRequested]]
    local _, from_heading = core.update(core.new(), from_space)
    -- Then the shell starts in the terminal's folder, or in the space root for the heading
    MiniTest.expect.equality(from_window, {
        {
            type = "run_shell",
            folder = "/app/src",
            placement = "vertical",
            labels = { ["herdr.tab"] = "tab-9", ["herdr.seen"] = "0" }
        }
    })
    MiniTest.expect.equality(assert(from_heading[1]).folder, "/app")
end

-- When the user marks a terminal unread, `update` can ask to lower its `herdr.seen` label.
T["asks to lower herdr.seen when a terminal is marked unread"] = function ()
    -- Given a terminal seen up to its turn 4
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1", { turn = 4, labels = { ["herdr.seen"] = "4" } })
    -- When the user marks it unread
    local _, effects = core.update(state, { type = "unread_requested", terminal = "t1" })
    -- Then its herdr.seen label is lowered below its turn
    MiniTest.expect.equality(effects, { { type = "set_label", terminal = "t1", key = "herdr.seen", value = "3" } })
end

-- When the state changes, `view` can return the sidebar rows and the number of terminals waiting, keeping their order.
T["returns the sidebar rows and the waiting count in a stable order"] = function ()
    -- Given a blocked terminal in /app and an older idle one in /docs, with /docs folded
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1", { status = "blocked", status_ms = 20, labels = { ["herdr.space"] = "/app" } })
    state.terminals.t2 = terminal("t2", {
        folder = "/docs",
        status = "idle",
        status_ms = 10,
        labels = {
            ["herdr.space"] = "/docs"
        }
    })
    state = core.update(state, { type = "heading_toggled", id = string.char(0) .. "/docs" })
    -- When the view is taken, and taken again after /docs becomes the newest
    local next_state, rows, waiting = core.view(state)
    next_state.terminals.t2 = vim.tbl_extend("force", next_state.terminals.t2, { status_ms = 30 })
    local _, again = core.view(next_state)
    -- Then /app with its terminal comes first, /docs shows only its heading, one terminal waits, and the order holds
    ---@param list HerdrCoreSidebarRow[]
    ---@return string[]
    local function describe(list)
        local described = {}
        for _, row in ipairs(list) do
            described[#described + 1] = row.kind .. ":" .. (row.address or row.root)
        end
        return described
    end
    MiniTest.expect.equality(describe(rows), { "space:/app", "terminal:t1", "space:/docs" })
    MiniTest.expect.equality(waiting, 1)
    MiniTest.expect.equality(describe(again), describe(rows))
end

-- When a foreground program changes without the folder changing, `update` can skip looking up the repository root again.
T["skips the repository lookup when only the foreground program changes"] = function ()
    -- Given a terminal whose folder is /app
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1", { program = "pwsh" })
    -- When cargo comes to the foreground in the same folder
    local updated, effects = core.update(
        state,
        {
            type = "foreground_changed",
            terminal = "t1",
            folder = "/app",
            program = "cargo"
        }
    )
    -- Then the program is stored and no lookup is asked for
    MiniTest.expect.equality(updated.terminals.t1.program, "cargo")
    MiniTest.expect.equality(effects, {})
end

return T
