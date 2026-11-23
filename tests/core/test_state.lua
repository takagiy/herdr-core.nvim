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

T["notifies and counts a child only when it needs the user"] = function ()
    -- Given a working lead, a working child, and a child whose turn is unseen, in a Neovim that is not focused
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1", { status = "working" })
    state.terminals.t2 = terminal("t2", { status = "working", parent = "t1" })
    state.terminals.t3 = terminal("t3", { status = "idle", turn = 2, parent = "t1", labels = { ["herdr.seen"] = "1" } })
    state = core.update(state, { type = "focus_changed", focused = false, terminals = {} })
    -- When the child finishes, or is blocked instead
    local _, finished = core.update(state, { type = "status_changed", terminal = "t2", status = "done", status_ms = 2 })
    local _, blocked = core.update(state, {
        type = "status_changed",
        terminal = "t2",
        status = "blocked",
        status_ms = 2
    })
    local _, _, waiting = core.view(state)
    -- Then only the block is notified, and the unseen turn of a child does not wait for the user
    MiniTest.expect.equality(finished, {})
    MiniTest.expect.equality(blocked, { { type = "notify", terminal = "t2", name = "t2", status = "blocked" } })
    MiniTest.expect.equality(waiting, 0)
end

-- When a saved layout names terminals that finished while no Neovim was running, `update` can restore it without them and save the result.
T["restores a saved layout without terminals that finished meanwhile"] = function ()
    -- Given a terminal list holding only t1, and a saved split of t1 and the finished t4
    local core = require("herdr-core.core.state")
    local state = core.update(core.new(), { type = "terminals_listed", terminals = { terminal("t1") } })
    local saved = {
        tabs = {
            {
                id = "tab1",
                root = {
                    kind = "split",
                    id = "s1",
                    axis = "row",
                    children = {
                        { kind = "terminal", id = "w1", terminal = "t1" },
                        { kind = "terminal", id = "w4", terminal = "t4" }
                    }
                }
            },
            { id = "tab2", root = { kind = "terminal", id = "w5", terminal = "t4" } }
        }
    }
    -- When the saved layout is loaded
    local _, effects = core.update(state, { type = "layout_loaded", value = saved, version = 3 })
    -- Then only t1 is shown, and the layout without t4 is saved
    local alive = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    MiniTest.expect.equality(effects, {
        { type = "show_layout", value = alive },
        { type = "save_layout", value = alive, version = 3 }
    })
end

-- When a saved layout loads before the terminal list, `update` can keep every terminal in it.
T["keeps the saved layout when the terminal list is not known yet"] = function ()
    -- Given no terminal list yet, and a saved layout with t4
    local core = require("herdr-core.core.state")
    local saved = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w4", terminal = "t4" } } } }
    -- When the saved layout is loaded
    local _, effects = core.update(core.new(), { type = "layout_loaded", value = saved, version = 3 })
    -- Then it is shown as saved and not overwritten
    MiniTest.expect.equality(effects, { { type = "show_layout", value = saved } })
end

-- When a later layout names a terminal whose start event has not arrived yet, `update` can keep that terminal.
T["keeps a new terminal in a later layout before its start event"] = function ()
    -- Given a restored layout of t1
    local core = require("herdr-core.core.state")
    local one = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    local state = core.update(core.new(), { type = "terminals_listed", terminals = { terminal("t1") } })
    state = core.update(state, { type = "layout_loaded", value = one, version = 1 })
    -- When a later layout adds t2, which the core has not reported yet
    local two = {
        tabs = {
            { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } },
            { id = "tab2", root = { kind = "terminal", id = "w2", terminal = "t2" } }
        }
    }
    local _, effects = core.update(state, { type = "layout_loaded", value = two, version = 2 })
    -- Then t2 is shown, not dropped
    MiniTest.expect.equality(effects, { { type = "show_layout", value = two } })
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
    -- Given a blocked terminal in /app and an older idle one in /docs
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
    -- When the view is taken, and taken again after /docs becomes the newest
    local next_state, rows, waiting = core.view(state)
    next_state.terminals.t2 = vim.tbl_extend("force", next_state.terminals.t2, { status_ms = 30 })
    local _, again = core.view(next_state)
    -- Then /app with its terminal comes first, /docs also shows its terminal, one terminal waits, and the order holds
    ---@param list HerdrCoreSidebarRow[]
    ---@return string[]
    local function describe(list)
        local described = {}
        for _, row in ipairs(list) do
            described[#described + 1] = row.kind .. ":" .. row.id
        end
        return described
    end
    MiniTest.expect.equality(describe(rows), { "section:/app", "item:t1", "section:/docs", "item:t2" })
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
    local updated, effects = core.update(state, {
        type = "foreground_changed",
        terminal = "t1",
        folder = "/app",
        program = "cargo"
    })
    -- Then the program is stored and no lookup is asked for
    MiniTest.expect.equality(updated.terminals.t1.program, "cargo")
    MiniTest.expect.equality(effects, {})
end

T["returns sidebar requests as view effects"] = function ()
    -- Given the core state
    local core = require("herdr-core.core.state")
    -- When a sidebar action arrives
    local _, effects = core.update(core.new(), { type = "sidebar_requested", action = "toggle" })
    -- Then the UI is asked to carry it out
    MiniTest.expect.equality(effects, { { type = "sidebar", action = "toggle" } })
end

-- A monitor that does nothing: the core keeps it and never calls it.
---@return HerdrCoreMonitor
local function monitor()
    return { arm = function () end, disarm = function () end }
end

-- When the focus changes, `update` can keep the terminal in front, and `view` can mark its row.
T["marks the row of the terminal in front"] = function ()
    -- Given two terminals
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = terminal("t1")
    state.terminals.t2 = terminal("t2")
    -- When the second comes to the front
    local focused = core.update(state, { type = "focus_changed", focused = true, terminals = { "t2" }, front = "t2" })
    local _, rows = core.view(focused)
    -- Then only its row is marked
    local marked = {}
    for _, row in ipairs(rows) do
        if row.highlighted then marked[#marked + 1] = row.id end
    end
    MiniTest.expect.equality(marked, { "t2" })
end

-- When an element a monitor is wanted for appears or changes, `update` can ask to arm the monitor there; when it goes, to disarm it and drop what was listed there.
-- When what a monitor notified arrives, `update` can keep it, and `view` can list it.
T["asks to arm monitors where they are wanted and to disarm them where the element is gone"] = function ()
    -- Given a resource at the top and one under each terminal
    local core = require("herdr-core.core.state")
    local state = core.new({
        resources = {
            { name = "terminals" },
            { name = "top", monitor = monitor },
            { name = "task", parent = "terminals[][]", monitor = monitor }
        }
    })
    ---@param effects table[]
    ---@return table?
    local function sync(effects)
        return vim.tbl_filter(function (effect) return effect.type == "sync_monitors" end, effects)[1]
    end
    -- When a terminal starts, an item arrives under it, its status changes, an unrelated event comes, and it ends
    local started, first = core.update(state, { type = "terminal_started", terminal = terminal("t1") })
    local armed = assert(sync(first))
    local task = assert(armed.arm[2])
    local listed, second = core.update(started, {
        type = "items_listed",
        lists = { { resource = "task", parent = task.key, items = { { kind = "item", name = "a" } } } }
    })
    local _, rows = core.view(listed)
    local changed, third = core.update(listed, {
        type = "status_changed",
        terminal = "t1",
        status = "working",
        status_ms = 2
    })
    local _, fourth = core.update(changed, { type = "sidebar_requested", action = "toggle" })
    local ended, fifth = core.update(changed, { type = "terminal_ended", terminal = "t1" })
    -- Then both are armed at the start, with the terminal for the one under it
    MiniTest.expect.equality(
        vim.tbl_map(
            function (entry) return { entry.resource, entry.monitor == monitor, entry.parent and entry.parent.id } end,
            armed.arm
        ), { { "top", true }, { "task", true, "t1" } }
    )
    -- And the item is kept and listed under the terminal
    MiniTest.expect.equality(sync(second), nil)
    MiniTest.expect.equality(vim.tbl_map(function (row) return row.lines[1] end, rows), { "app", "t1", "a" })
    -- And the one under the terminal is armed again when the terminal changes, and nothing is asked otherwise
    MiniTest.expect.equality(
        vim.tbl_map(function (entry) return entry.resource end, assert(sync(third)).arm), { "task" }
    )
    MiniTest.expect.equality(sync(fourth), nil)
    -- And it is disarmed, with its item dropped, when the terminal ends
    MiniTest.expect.equality(assert(sync(fifth)).disarm, { { resource = "task", key = task.key } })
    MiniTest.expect.equality({ listed.items.task[task.key] ~= nil, ended.items.task[task.key] }, { true })
end

-- When a key is pressed on an item, `update` can ask to run what the key does there.
T["asks to run what a key does on an item"] = function ()
    -- Given the terminals' resource with an action for Enter
    local core = require("herdr-core.core.state")
    local open = function () end
    local state = core.new({
        resources = { { name = "terminals", actions = { open = open }, keys = { use = "open" } } }
    })
    local item = { kind = "item", name = "t1" }
    -- When Enter is pressed on an item
    local _, effects = core.update(state, { type = "key_pressed", resource = "terminals", key = "use", item = item })
    -- Then the action is asked to run with the item
    MiniTest.expect.equality(effects, { { type = "run_action", run = open, ctx = { item = item } } })
end

return T
