local MiniTest = require("mini.test")
local T = MiniTest.new_set()

-- When a section or an item is made, the constructor can mark what it is and keep the fields as given.
T["marks sections and items and keeps their fields"] = function ()
    -- Given the constructors
    local resources = require("herdr-core.resources")
    -- When a section holding an item with props is made
    local item = resources.Item({ id = "a", name = "task", detail = "fix login", props = { number = 12 } })
    local section = resources.Section({ name = "Tasks", notification_count = 1, items = { item } })
    -- Then each is marked with its kind and has the fields it was given
    MiniTest.expect.equality(section, {
        kind = "section",
        name = "Tasks",
        notification_count = 1,
        items = { { kind = "item", id = "a", name = "task", detail = "fix login", props = { number = 12 } } }
    })
end

-- When `terminals` is given keys, the definition can carry them; without keys it can carry Enter, n, r, p and u.
T["names the terminals' resource and carries its keys"] = function ()
    -- Given the terminals' resource made with and without keys
    local resources = require("herdr-core.resources")
    -- When both definitions are made
    local with, without = resources.terminals({ keys = { o = "open" } }), resources.terminals()
    -- Then both are named terminals without a monitor, one with its own keys and the other with the usual ones
    MiniTest.expect.equality(with, { name = "terminals", keys = { o = "open" } })
    MiniTest.expect.equality(
        without,
        { name = "terminals", keys = { use = "open", n = "new_terminal", r = "rename", p = "pin", u = "unread" } }
    )
end

return T
