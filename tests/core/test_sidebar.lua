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

-- What the terminals' resource put in the props of the element a row shows.
---@param rows  HerdrCoreSidebarRow[]
---@param index integer
---@return table
local function props(rows, index)
    return assert(assert(assert(rows[index]).item).props)
end

-- What tells a row from the others: a terminal's address, a space's root, or the text of other rows.
---@param row HerdrCoreSidebarRow
---@return string
local function label(row)
    local given = row.item and row.item.props or {}
    return given.address or given.space or row.lines[1]
end

-- A monitor that does nothing: the core keeps it and never calls it.
---@return HerdrCoreMonitor
local function monitor()
    return { arm = function () end, disarm = function () end }
end

T["groups local terminals by space without a local heading"] = function ()
    -- Given terminals in two projects
    local sidebar = require("herdr-core.core.sidebar")
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app"), terminal("t2", "/other") })
    -- Then each project is followed by its terminal
    MiniTest.expect.equality(assert(rows[1]).kind, "section")
    MiniTest.expect.equality(props(rows, 1).space, "/app")
    MiniTest.expect.equality(props(rows, 2).address, "t1")
    MiniTest.expect.equality(props(rows, 3).space, "/other")
    MiniTest.expect.equality(props(rows, 4).address, "t2")
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
    MiniTest.expect.equality(props(rows, 1).space, "/other")
    MiniTest.expect.equality(props(rows, 2).address, "t2")
    MiniTest.expect.equality(props(rows, 3).address, "t3")
    MiniTest.expect.equality(props(rows, 4).space, "/app")
end

T["puts pinned terminals first inside their space"] = function ()
    -- Given an older pinned terminal and a newer unpinned terminal
    local sidebar = require("herdr-core.core.sidebar")
    local pinned = terminal("t1", "/app")
    pinned.labels["herdr.pinned"] = "1"
    -- When rows are built
    local _, rows = sidebar.update(nil, { terminal("t2", "/app", { status_ms = 30 }), pinned })
    -- Then the pinned terminal is first
    MiniTest.expect.equality(props(rows, 2).address, "t1")
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
    MiniTest.expect.equality(props(rows, 1).space, "/app")
    MiniTest.expect.equality(props(rows, 2).address, "t1")
    MiniTest.expect.equality(props(rows, 3).address, "t3")
end

T["inserts new terminals and spaces at the top"] = function ()
    -- Given an existing sidebar
    local sidebar = require("herdr-core.core.sidebar")
    local existing = terminal("t1", "/app", { status_ms = 100 })
    local previous = sidebar.update(nil, { existing })
    -- When an older imported terminal and a new space appear
    local _, rows = sidebar.update(previous, { existing, terminal("t2", "/app"), terminal("t3", "/new") })
    -- Then new entries precede existing entries in their groups
    MiniTest.expect.equality(props(rows, 1).space, "/new")
    MiniTest.expect.equality(props(rows, 4).address, "t2")
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
    MiniTest.expect.equality(props(rows, 2).address, "t2")
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

---@param rows HerdrCoreSidebarRow[]
---@return table[]
local function tree(rows)
    return vim.tbl_map(function (row) return { label(row), row.guide } end, rows)
end

T["nests children under their parent in the parent's space"] = function ()
    -- Given a lead with two children in another folder and a grandchild, beside another terminal
    local sidebar = require("herdr-core.core.sidebar")
    local terminals = {
        terminal("t1", "/app", { name = "lead", status_ms = 10 }),
        terminal("t2", "/work", { parent = "t1", status_ms = 30 }),
        terminal("t3", "/work", { parent = "t1", status_ms = 20 }),
        terminal("t4", "/work", { parent = "t2", status_ms = 40 }), terminal("t5", "/app", { status_ms = 5 })
    }
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, terminals)
    -- Then the children follow their parent in its space, newest first, with tree guides
    MiniTest.expect.equality(tree(rows), {
        { "/app" },
        { "t1" },
        { "t2", "├ " },
        { "t4", "│ └ " },
        { "t3", "└ " },
        { "t5" }
    })
end

T["lists a terminal whose parent is gone as a usual one"] = function ()
    -- Given a terminal whose parent has ended
    local sidebar = require("herdr-core.core.sidebar")
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { terminal("t2", "/work", { parent = "t1" }) })
    -- Then it sits in its own space without a guide
    MiniTest.expect.equality(tree(rows), { { "/work" }, { "t2" } })
end

T["counts the children that need the user on their parent and space"] = function ()
    -- Given a lead with a blocked child, a child whose turn is unseen, and a working child
    local sidebar = require("herdr-core.core.sidebar")
    local terminals = {
        terminal("t1", "/app", { status = "working" }),
        terminal("t2", "/app", { parent = "t1", status = "blocked" }),
        terminal("t3", "/app", {
            parent = "t1",
            status = "done",
            turn = 2,
            labels = { ["herdr.space"] = "/app", ["herdr.seen"] = "1" }
        }),
        terminal("t4", "/app", { parent = "t1", status = "working" })
    }
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, terminals)
    -- Then only the blocked child counts, on the lead and on the space, and the finished child shows idle
    local by = {}
    for _, row in ipairs(rows) do
        by[label(row)] = row
    end
    MiniTest.expect.equality({ by["/app"].waiting, by.t1.waiting, by.t3.status }, { 1, 1, "idle" })
end

T["shows the command the user ran rather than the file a link points to"] = function ()
    -- Given claude run through a link to a versioned file, a login shell, and a full path on Windows
    local sidebar = require("herdr-core.core.sidebar")
    local cases = {
        { program = "2.1.326", argv = { "claude", "--resume", "abc" } }, { program = "zsh", argv = { "-zsh" } },
        { program = "claude.exe", argv = { "C:/Users/me/.local/bin/claude.exe" } }
    }
    local shown = {}
    -- When each terminal is displayed
    for _, fields in ipairs(cases) do
        local _, rows = sidebar.update(nil, { terminal("t1", "/app", fields) })
        shown[#shown + 1] = assert(rows[2]).lines[2]
    end
    -- Then the name the command was run by is shown, without a login shell's dash
    MiniTest.expect.equality(shown, { "claude", "zsh", "claude" })
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

-- When a terminal runs on another machine, the sidebar can leave it out.
T["leaves out the terminals of other machines"] = function ()
    -- Given a local terminal and one on another machine
    local sidebar = require("herdr-core.core.sidebar")
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app"), terminal("vps/t1", "/app", { machine = "vps" }) })
    -- Then only the local space and its terminal are listed
    MiniTest.expect.equality(tree(rows), { { "/app" }, { "t1" } })
end

-- When the terminals are listed, the sidebar can give each space as a section and each terminal as an item, with what their actions need in props.
T["gives a space as a section and a terminal as an item"] = function ()
    -- Given a pinned lead with a child, in a space
    local sidebar = require("herdr-core.core.sidebar")
    local lead = terminal("t1", "/home/app", { name = "lead", status = "working", argv = { "claude" } })
    lead.labels["herdr.pinned"] = "1"
    -- When the sidebar is built with the lead in front
    local _, rows = sidebar.update(nil, { lead, terminal("t2", "/home/app", { parent = "t1" }) }, { front = "t1" })
    -- Then the section is named after the folder, and the item carries its address, space and pin, with the child below
    local child = {
        kind = "item",
        id = "t2",
        name = "t2",
        detail = "",
        items = {},
        props = { address = "t2", space = "/home/app", is_pinned = false }
    }
    local item = {
        kind = "item",
        id = "t1",
        name = "lead",
        detail = "claude",
        status = "working",
        is_highlighted = true,
        items = { child },
        props = { address = "t1", space = "/home/app", is_pinned = true }
    }
    MiniTest.expect.equality(
        assert(rows[1]).item,
        { kind = "section", id = "/home/app", name = "app", items = { item }, props = { space = "/home/app" } }
    )
    MiniTest.expect.equality({ assert(rows[2]).highlighted, assert(rows[3]).highlighted }, { true })
end

-- When a resource has no parent, the sidebar can list what it notified at the top in the order of the resources: a section under a heading, an item without one.
T["lists what resources without a parent notified in the order of the resources"] = function ()
    -- Given a resource before the terminals that notified a section, and one after them that notified an item with a child
    local sidebar = require("herdr-core.core.sidebar")
    local options = {
        resources = {
            { name = "notes", monitor = monitor },
            { name = "terminals" },
            {
                name = "todo",
                monitor = monitor
            }
        },
        items = {
            notes = {
                [""] = {
                    {
                        kind = "section",
                        name = "Notes",
                        notification_count = 2,
                        items = { { kind = "item", name = "a" } }
                    }
                }
            },
            todo = {
                [""] = {
                    { kind = "item", name = "b", notification_count = 1, items = { { kind = "item", name = "b1" } } }
                }
            }
        }
    }
    local terminals = { terminal("t1", "/app", { status = "blocked" }) }
    -- When the sidebar is built, and built collapsed
    local _, rows = sidebar.update(nil, terminals, options)
    local _, summary = sidebar.update(nil, terminals, vim.tbl_extend("force", options, { collapsed = true }))
    -- Then the rows follow the resources, the item at the top has no heading, and the counts at the top are summed
    MiniTest.expect.equality(tree(rows), { { "Notes" }, { "a" }, { "/app" }, { "t1" }, { "b" }, { "b1", "└ " } })
    MiniTest.expect.equality(
        vim.tbl_map(function (row) return row.kind end, rows), { "section", "item", "section", "item", "item", "item" }
    )
    MiniTest.expect.equality(assert(summary[1]).waiting, 4)
end

-- When a resource's parent points at a level of another resource, the sidebar can list what it notified under each element of that level, after the element's own items.
T["lists what a resource notified under the elements its parent points at"] = function ()
    -- Given resources for the spaces, the terminals in them, their children and another resource's items, and a lead with a child
    local sidebar = require("herdr-core.core.sidebar")
    local resources = {
        { name = "terminals" }, { name = "space", parent = "terminals[]", monitor = monitor },
        { name = "task", parent = "terminals[][]", monitor = monitor },
        { name = "sub", parent = "terminals[][][]", monitor = monitor },
        { name = "note", parent = "task[]", monitor = monitor }
    }
    local terminals = { terminal("t1", "/app"), terminal("t2", "/app", { parent = "t1" }) }
    -- When every element a monitor is wanted for is answered with an item named after it, until nothing new is wanted
    local items = {}
    for _ = 1, 2 do
        local _, _, wanted = sidebar.update(nil, terminals, { resources = resources, items = items })
        for name, parents in pairs(wanted) do
            items[name] = {}
            for key, parent in pairs(parents) do
                items[name][key] = { { kind = "item", name = name .. " of " .. assert(parent).name } }
            end
        end
    end
    local _, rows = sidebar.update(nil, terminals, { resources = resources, items = items })
    -- Then each is listed under its level, after the terminals and children already there
    MiniTest.expect.equality(tree(rows), {
        { "/app" },
        { "t1" },
        { "t2", "├ " },
        { "sub of t2", "│ └ " },
        { "task of t1", "└ " },
        { "note of task of t1", "  └ " },
        { "space of app" }
    })
end

-- When a row is made, it can carry its resource's name and keys, the element and the element above it; a section's row takes no keys.
T["puts the resource's name and keys, the element and the one above it on a row"] = function ()
    -- Given the terminals' resource with keys
    local sidebar = require("herdr-core.core.sidebar")
    local keys = { use = "open" }
    -- When the sidebar is built
    local _, rows = sidebar.update(
        nil, { terminal("t1", "/app") }, { resources = { { name = "terminals", keys = keys } } }
    )
    -- Then the item's row has the keys, the item and its section, and the section's row has no keys
    local section, item = assert(rows[1]), assert(rows[2])
    MiniTest.expect.equality(
        { section.resource, section.keys == nil, item.resource, item.keys == keys, item.parent == section.item, item.id },
        { "terminals", true, "terminals", true, true, "t1" }
    )
end

-- When an item's row is made, it can carry the menu of its resource's actions: the one Enter and a click run first, the rest by name, each with its label and the keys that run it.
T["puts the menu of the resource's actions on an item's row"] = function ()
    -- Given the terminals' resource with four actions, keys for three of them, and a key holding a function
    local sidebar = require("herdr-core.core.sidebar")
    local run = function () end
    local terminals = {
        name = "terminals",
        actions = { rename = run, open = run, new_terminal = run, archive = run },
        keys = { use = "open", o = "open", r = "rename", n = "new_terminal", d = function () end }
    }
    -- When the sidebar is built
    local _, rows = sidebar.update(nil, { terminal("t1", "/app") }, { resources = { terminals } })
    -- Then the item's menu starts with the action of Enter, lists the rest by name, and leaves out the function
    MiniTest.expect.equality(assert(rows[2]).menu, {
        { action = "open", label = "open", keys = { "o" } },
        { action = "archive", label = "archive", keys = {} },
        { action = "new_terminal", label = "new terminal", keys = { "n" } },
        { action = "rename", label = "rename", keys = { "r" } }
    })
    MiniTest.expect.equality(assert(rows[1]).menu, nil)
end

-- When resources have monitors, the sidebar can say where they are wanted: once without an element for a resource at the top, once for each element of the level for one with a parent.
-- When an element has an id, the sidebar can keep it apart by the id wherever it is listed.
T["says where monitors are wanted, telling elements apart by their ids"] = function ()
    -- Given a resource at the top and one under the terminals, and two terminals
    local sidebar = require("herdr-core.core.sidebar")
    local options = {
        resources = {
            { name = "terminals" },
            { name = "top", monitor = monitor },
            { name = "task", parent = "terminals[][]", monitor = monitor }
        }
    }
    -- When the sidebar is built with either terminal first
    local _, _, wanted = sidebar.update(nil, { terminal("t1", "/app"), terminal("t2", "/app") }, options)
    local _, _, swapped = sidebar.update(
        nil, { terminal("t1", "/app"), terminal("t2", "/app", { status_ms = 9 }) }, options
    )
    -- Then the one at the top is wanted once, the other for each terminal under the same keys, the terminals nowhere
    local parents = vim.tbl_map(function (parent) return assert(parent).id end, vim.tbl_values(wanted.task))
    table.sort(parents)
    local keys, others = vim.tbl_keys(wanted.task), vim.tbl_keys(swapped.task)
    table.sort(keys)
    table.sort(others)
    MiniTest.expect.equality(
        { wanted.terminals == nil, wanted.top, parents }, { true, { [""] = false }, { "t1", "t2" } }
    )
    MiniTest.expect.equality(keys, others)
end

-- When a key is pressed on an item, the sidebar can ask for the function to be run with the item: the one given for the key, or the action its resource names for it.
T["asks for the function a key runs on an item"] = function ()
    -- Given a resource whose keys name an action for Enter and hold a function for d
    local sidebar = require("herdr-core.core.sidebar")
    local open, direct = function () end, function () end
    local resources = {
        { name = "task", actions = { open = open }, keys = { use = "open", d = direct, x = "missing" } }
    }
    local item, parent = { kind = "item", name = "a" }, { kind = "section", name = "s" }
    ---@param resource string
    ---@param key      string
    ---@return table[]
    local function press(resource, key)
        return sidebar.press(resources, { resource = resource, key = key, item = item, parent = parent })
    end
    -- When Enter, d, a key naming no action, a key the resource does not take, and a key of an unknown resource are pressed
    local found = {
        press("task", "use"), press("task", "d"), press("task", "x"), press("task", "q"), press("other", "use")
    }
    -- Then the named action and the function are asked to run with the item and its parent, and the others ask for nothing
    MiniTest.expect.equality(found[1], { { type = "run_action", run = open, ctx = { item = item, parent = parent } } })
    MiniTest.expect.equality({ assert(found[2][1]).run == direct, found[3], found[4], found[5] }, { true, {}, {}, {} })
end

-- When resources cannot be used, `problem` can say which one and why.
T["says which resource cannot be used"] = function ()
    -- Given lists of resources: usable, with an unknown parent, a loop, no monitor, a parent without [], a name used twice, no name
    local sidebar = require("herdr-core.core.sidebar")
    ---@type table[][]
    local lists = {
        {
            { name = "terminals" },
            { name = "a", parent = "terminals[][]", monitor = monitor },
            { name = "b", parent = "a[]", monitor = monitor }
        },
        { { name = "a", parent = "b[]", monitor = monitor } },
        { { name = "a", parent = "b[]", monitor = monitor }, { name = "b", parent = "a[]", monitor = monitor } },
        { { name = "a" } },
        { { name = "a", parent = "terminals", monitor = monitor } },
        { { name = "a", monitor = monitor }, { name = "a", monitor = monitor } },
        { { monitor = monitor } }
    }
    -- When each list is checked
    local found = vim.tbl_map(function (list) return sidebar.problem(list) or false end, lists)
    -- Then the usable list has no problem and the others name the resource and what is wrong
    MiniTest.expect.equality(found, {
        false,
        "a: no resource is named b",
        "a: its parents make a loop",
        "a: monitor must be a function",
        "a: parent must be a resource's name followed by []",
        "a: two resources have this name",
        "resource 1: name must be a string"
    })
end

return T
