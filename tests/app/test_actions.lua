local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["requests new terminals in each placement"] = function ()
    -- Given actions connected to the core and a window context
    local events = {}
    local actions = require("herdr-core.app.actions").new(function (event)
        events[#events + 1] = event
    end, function () return { editor_folder = "/home", terminal_folder = "/app" } end, function () return "tab-1" end)
    -- When each opening action is called
    actions.new_tab()
    actions.new_vertical()
    actions.new_horizontal()
    -- Then each request carries its placement and the current folder context
    for index, placement in ipairs({ "tab", "vertical", "horizontal" }) do
        MiniTest.expect.equality(events[index], {
            type = "new_terminal_requested",
            placement = placement,
            tab = "tab-1",
            editor_folder = "/home",
            terminal_folder = "/app"
        })
    end
end

T["requests sidebar toggle and focus"] = function ()
    -- Given actions connected to the core
    local events = {}
    local factory = require("herdr-core.app.actions")
    local actions = factory.new(
        function (event) events[#events + 1] = event end, function () return { editor_folder = "/home" } end,
        function () return "tab-1" end
    )
    -- When the sidebar actions are called
    actions.toggle_sidebar()
    actions.focus_sidebar()
    -- Then the core receives both requests
    MiniTest.expect.equality(events, {
        { type = "sidebar_requested", action = "toggle" },
        { type = "sidebar_requested", action = "focus" }
    })
end

return T
