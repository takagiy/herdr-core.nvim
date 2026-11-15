local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["focuses an existing terminal window"] = function ()
    -- Given a terminal already displayed in a window
    local opening = require("herdr-core.core.open")
    -- When it is selected
    local effect = opening.choose("t1", { t1 = "window-1" })
    -- Then that window is focused instead of creating another
    MiniTest.expect.equality(effect, { type = "focus_window", window = "window-1" })
end

T["opens an undisplayed terminal in a new tabpage"] = function ()
    -- Given a terminal with no displayed window
    local opening = require("herdr-core.core.open")
    -- When it is selected
    local effect = opening.choose("t1", {})
    -- Then a new tabpage is requested
    MiniTest.expect.equality(effect, { type = "show_terminal", terminal = "t1", placement = "tab" })
end

T["uses a configured opening policy"] = function ()
    -- Given a policy that opens terminals in a vertical split
    local opening = require("herdr-core.core.open")
    ---@param terminal string
    ---@return HerdrCoreOpenEffect
    local policy = function (terminal)
        return { type = "show_terminal", terminal = terminal, placement = "vertical" }
    end
    -- When an undisplayed terminal is selected
    local effect = opening.choose("t1", {}, policy)
    -- Then the requested opening policy is used
    MiniTest.expect.equality(effect, { type = "show_terminal", terminal = "t1", placement = "vertical" })
end

T["starts a shell in the focused terminal's folder"] = function ()
    -- Given a focused terminal with its own folder
    local opening = require("herdr-core.core.open")
    -- When a new shell is requested
    local effect = opening.new_terminal({ terminal_folder = "C:/app", editor_folder = "C:/" }, "tab", "tab-1")
    -- Then it starts in the terminal's folder
    MiniTest.expect.equality(effect.folder, "C:/app")
    MiniTest.expect.equality(effect.type, "run_shell")
end

T["falls back to the editor folder outside terminal windows"] = function ()
    -- Given focus in a file window
    local opening = require("herdr-core.core.open")
    -- When a new shell is requested
    local effect = opening.new_terminal({ editor_folder = "C:/editor" }, "tab", "tab-1")
    -- Then the editor folder is used
    MiniTest.expect.equality(effect.folder, "C:/editor")
end

T["uses the space root when opening from a sidebar row"] = function ()
    -- Given a sidebar row in a different project from the focused terminal
    local opening = require("herdr-core.core.open")
    -- When a new shell is requested from that row
    local effect = opening.new_terminal({
        space_root = "C:/project",
        terminal_folder = "C:/other",
        editor_folder = "C:/"
    }, "tab", "tab-1")
    -- Then the chosen project's root wins
    MiniTest.expect.equality(effect.folder, "C:/project")
end

T["keeps the requested placement for a new shell"] = function ()
    -- Given the three supported placements
    local opening = require("herdr-core.core.open")
    for _, placement in ipairs({ "tab", "vertical", "horizontal" }) do
        -- When a shell is requested in that placement
        local effect = opening.new_terminal({ editor_folder = "C:/" }, placement, "tab-1")
        -- Then the requested placement is preserved
        MiniTest.expect.equality(effect.placement, placement)
    end
end

T["assigns a distinct tab and initial seen turn to each shell"] = function ()
    -- Given two new terminal identities
    local opening = require("herdr-core.core.open")
    -- When shells are requested
    local first = opening.new_terminal({ editor_folder = "C:/" }, "tab", "tab-1")
    local second = opening.new_terminal({ editor_folder = "C:/" }, "tab", "tab-2")
    -- Then each gets its own tab identity and starts seen at turn zero
    MiniTest.expect.equality(first.labels, { ["herdr.tab"] = "tab-1", ["herdr.seen"] = "0" })
    MiniTest.expect.equality(second.labels, { ["herdr.tab"] = "tab-2", ["herdr.seen"] = "0" })
end

return T
