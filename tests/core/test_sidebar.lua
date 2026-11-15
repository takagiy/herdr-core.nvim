local MiniTest = require("mini.test")
local T = MiniTest.new_set()

---@param address string
---@param space   string
---@param extra?  table
---@return HerdrCoreTerminal
local function terminal(address, space, extra)
    local t = { address = address, labels = { ["herdr.space"] = space }, folder = space, turn = 0, created_ms = 1 }
    for k, v in pairs(extra or {}) do
        t[k] = v
    end
    return t
end

T["groups local terminals by space without a local heading"] = function ()
    -- Given terminals in two projects
    local sidebar = require("herdr-core.core.sidebar")
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app"), terminal("t2", "/other") })
    -- Then each project is followed by its terminal
    MiniTest.expect.equality(assert(rows[1]).kind, "space")
    MiniTest.expect.equality(assert(rows[1]).root, "/app")
    MiniTest.expect.equality(assert(rows[2]).address, "t1")
    MiniTest.expect.equality(assert(rows[3]).root, "/other")
    MiniTest.expect.equality(assert(rows[4]).address, "t2")
end

T["groups remote projects under their machine"] = function ()
    -- Given the same project path on local and remote machines
    local sidebar = require("herdr-core.core.sidebar")
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app"), terminal("vps/t1", "/app", { machine = "vps" }) })
    -- Then the local project is direct and the remote one has a machine heading
    MiniTest.expect.equality(assert(rows[3]).kind, "machine")
    MiniTest.expect.equality(assert(rows[3]).machine, "vps")
    MiniTest.expect.equality(assert(rows[4]).root, "/app")
    MiniTest.expect.equality(assert(rows[5]).address, "vps/t1")
end

T["keeps disconnected machines and their terminals"] = function ()
    -- Given a known terminal on a disconnected machine
    local sidebar = require("herdr-core.core.sidebar")
    -- When the machine is reported offline
    local _, rows = sidebar.update(
        nil, { terminal("vps/t1", "/app", { machine = "vps" }) }, { machines = { vps = false } }
    )
    -- Then its heading is marked offline and the terminal remains
    MiniTest.expect.equality(assert(rows[1]).connected, false)
    MiniTest.expect.equality(assert(rows[3]).address, "vps/t1")
end

T["provides a status and two display lines"] = function ()
    -- Given a named working agent
    local sidebar = require("herdr-core.core.sidebar")
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, {
        terminal("t1", "/app", {
            name = "review",
            program = "codex",
            status = "working"
        })
    })
    -- Then status and name precede the program line
    MiniTest.expect.equality(assert(rows[2]).status, "working")
    MiniTest.expect.equality(assert(rows[2]).lines, { "review", "codex" })
end

T["prefers the display name label"] = function ()
    -- Given both a plugin display name and a native hc name
    local sidebar = require("herdr-core.core.sidebar")
    local current = terminal("t1", "/app", { name = "native" })
    current.labels["herdr-core-nvim.name"] = "display"
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { current })
    -- Then the display name label wins
    MiniTest.expect.equality(assert(rows[2]).lines[1], "display")
end

T["uses the native name without a display name"] = function ()
    -- Given a terminal with only its native name
    local sidebar = require("herdr-core.core.sidebar")
    -- When rows are built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app", { name = "native" }) })
    -- Then the native name is shown
    MiniTest.expect.equality(assert(rows[2]).lines[1], "native")
end

T["uses the address without either name"] = function ()
    -- Given a terminal without any name
    local sidebar = require("herdr-core.core.sidebar")
    -- When rows are built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app") })
    -- Then its address is shown
    MiniTest.expect.equality(assert(rows[2]).lines[1], "t1")
end

T["sorts projects and terminals by initial update time"] = function ()
    -- Given mixed project and terminal timestamps
    local sidebar = require("herdr-core.core.sidebar")
    local items = {
        terminal("t1", "/app", { status_ms = 10 }),
        terminal("t2", "/other", { created_ms = 30 }),
        terminal("t3", "/other", {
            status_ms = 20
        })
    }
    -- When the sidebar is first built
    local _, rows = sidebar.update(nil, items)
    -- Then projects and terminals are newest first
    MiniTest.expect.equality(assert(rows[1]).root, "/other")
    MiniTest.expect.equality(assert(rows[2]).address, "t2")
    MiniTest.expect.equality(assert(rows[3]).address, "t3")
    MiniTest.expect.equality(assert(rows[4]).root, "/app")
end

T["puts pinned terminals first inside their space"] = function ()
    -- Given an older pinned terminal and a newer unpinned terminal
    local sidebar = require("herdr-core.core.sidebar")
    local pinned = terminal("t1", "/app")
    pinned.labels["herdr.pinned"] = "1"
    -- When rows are built
    local _, rows = sidebar.update(nil, { terminal("t2", "/app", { status_ms = 30 }), pinned })
    -- Then the pinned terminal is first
    MiniTest.expect.equality(assert(rows[2]).address, "t1")
end

T["keeps rows in place when timestamps change"] = function ()
    -- Given a sidebar with an established project and terminal order
    local sidebar = require("herdr-core.core.sidebar")
    local items = {
        terminal("t1", "/app", { status_ms = 30 }),
        terminal("t2", "/other", { status_ms = 20 }),
        terminal("t3", "/app", {
            status_ms = 10
        })
    }
    local previous = sidebar.update(nil, items)
    items[2].status_ms = 100
    items[3].status_ms = 90
    -- When later status updates arrive
    local _, rows = sidebar.update(previous, items)
    -- Then existing project and terminal rows retain their positions
    MiniTest.expect.equality(assert(rows[1]).root, "/app")
    MiniTest.expect.equality(assert(rows[2]).address, "t1")
    MiniTest.expect.equality(assert(rows[3]).address, "t3")
end

T["inserts new terminals and spaces at the top"] = function ()
    -- Given an existing sidebar
    local sidebar = require("herdr-core.core.sidebar")
    local existing = terminal("t1", "/app", { status_ms = 100 })
    local previous = sidebar.update(nil, { existing })
    -- When an older imported terminal and a new space appear
    local _, rows = sidebar.update(previous, { existing, terminal("t2", "/app"), terminal("t3", "/new") })
    -- Then new entries precede existing entries in their groups
    MiniTest.expect.equality(assert(rows[1]).root, "/new")
    MiniTest.expect.equality(assert(rows[4]).address, "t2")
end

T["puts a moved terminal at the top of its new space"] = function ()
    -- Given a terminal in another space with an established order
    local sidebar = require("herdr-core.core.sidebar")
    local moved = terminal("t2", "/other")
    local first = terminal("t1", "/app", { status_ms = 100 })
    local previous = sidebar.update(nil, { first, moved })
    moved.labels["herdr.space"] = "/app"
    -- When it changes project
    local _, rows = sidebar.update(previous, { first, moved })
    -- Then it goes above existing terminals in its destination
    MiniTest.expect.equality(assert(rows[2]).address, "t2")
end

T["shows the waiting count on a space heading"] = function ()
    -- Given one blocked agent and one unread completed turn
    local sidebar = require("herdr-core.core.sidebar")
    local done = terminal("t2", "/app", { status = "idle", turn = 2 })
    done.labels["herdr.seen"] = "1"
    -- When rows are built
    local _, rows = sidebar.update(
        nil, { terminal("t1", "/app", { status = "blocked" }), done, terminal("t3", "/app") }
    )
    -- Then the heading counts the two waiting agents
    MiniTest.expect.equality(assert(rows[1]).waiting, 2)
end

T["reduces a collapsed sidebar to the total waiting count"] = function ()
    -- Given two waiting terminals in different projects
    local sidebar = require("herdr-core.core.sidebar")
    -- When the entire sidebar is collapsed
    local _, rows = sidebar.update(
        nil,
        {
            terminal("t1", "/app", { status = "blocked" }),
            terminal("t2", "/other", {
                status = "blocked"
            })
        },
        {
            collapsed = true
        }
    )
    -- Then only the total waiting count is exposed
    MiniTest.expect.equality(rows, { { kind = "summary", lines = {}, waiting = 2 } })
end

T["folds remote machines without losing the total waiting count"] = function ()
    -- Given a remote project containing a waiting agent
    local sidebar = require("herdr-core.core.sidebar")
    local items = { terminal("vps/t1", "/app", { machine = "vps", status = "blocked" }) }
    local previous, initial = sidebar.update(nil, items)
    local folded = { [assert(assert(initial[1]).id)] = true }
    -- When the machine is folded
    local _, rows = sidebar.update(previous, items, { folded = folded })
    local _, summary = sidebar.update(previous, items, { folded = folded, collapsed = true })
    -- Then only its machine heading remains and total attention is preserved
    MiniTest.expect.equality(#rows, 1)
    MiniTest.expect.equality(assert(summary[1]).waiting, 1)
end

T["shows executable basenames without Windows exe suffixes"] = function ()
    -- Given executable paths from Windows and Unix foreground processes
    local sidebar = require("herdr-core.core.sidebar")
    local programs = { [[C:\Tools\nvim.exe]], "C:/Tools/claude.EXE", "/usr/bin/fish", "codex", "my.tool" }
    local shown = {}
    -- When each terminal is displayed
    for _, program in ipairs(programs) do
        local _, rows = sidebar.update(nil, { terminal("t1", "/app", { program = program }) })
        shown[#shown + 1] = assert(rows[2]).lines[2]
    end
    -- Then only the executable name is shown and other extensions remain intact
    MiniTest.expect.equality(shown, { "nvim", "claude", "fish", "codex", "my.tool" })
end

return T
