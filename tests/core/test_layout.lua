local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["restores a saved layout"] = function ()
    -- Given a stored tab and terminal window
    local layout = require("herdr-core.core.layout")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    -- When the stored layout is loaded
    local state, effects = layout.update(layout.new(), { type = "layout_loaded", value = value, version = 3 })
    -- Then it requests that layout and remembers the version
    MiniTest.expect.equality(state.version, 3)
    MiniTest.expect.equality(effects, { { type = "show_layout", value = value } })
end

T["starts empty when no layout has been saved"] = function ()
    -- Given a core without saved layout data
    local layout = require("herdr-core.core.layout")
    -- When it reports no value
    local state, effects = layout.update(layout.new(), { type = "layout_loaded", version = 0 })
    -- Then no terminal windows need to be restored
    MiniTest.expect.equality(state.value, { tabs = {} })
    MiniTest.expect.equality(effects, {})
end

T["saves local changes against the last read version"] = function ()
    -- Given version three of an empty layout
    local layout = require("herdr-core.core.layout")
    local state = layout.update(layout.new(), { type = "layout_loaded", value = { tabs = {} }, version = 3 })
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    -- When a local terminal window is opened
    local _, effects = layout.update(state, { type = "layout_changed", value = value })
    -- Then the save carries version three
    MiniTest.expect.equality(effects, { { type = "save_layout", value = value, version = 3 } })
end

T["saves terminal windows without file windows"] = function ()
    -- Given a split containing a file and a terminal plus a file-only tab
    local layout = require("herdr-core.core.layout")
    local window = { kind = "terminal", id = "w1", terminal = "t1" }
    local value = {
        tabs = {
            {
                id = "tab1",
                root = {
                    kind = "split",
                    id = "split1",
                    axis = "row",
                    children = { { kind = "file", id = "file1" }, window }
                }
            },
            { id = "files", root = { kind = "file", id = "file2" } }
        }
    }
    -- When the local arrangement changes
    local state, effects = layout.update(layout.new(), { type = "layout_changed", value = value })
    -- Then only the terminal remains and the source tree is unchanged
    MiniTest.expect.equality(state.value, { tabs = { { id = "tab1", root = window } } })
    MiniTest.expect.equality(assert(effects[1]).value, state.value)
    MiniTest.expect.equality(#value.tabs, 2)
end

T["shows a newer layout from another editor"] = function ()
    -- Given a previously loaded empty layout
    local layout = require("herdr-core.core.layout")
    local state = layout.update(layout.new(), { type = "layout_loaded", value = { tabs = {} }, version = 1 })
    local value = { tabs = { { id = "other", root = { kind = "terminal", id = "w2", terminal = "t2" } } } }
    -- When another editor writes a newer version
    local updated, effects = layout.update(state, { type = "layout_loaded", value = value, version = 2 })
    -- Then the newer layout is shown
    MiniTest.expect.equality(updated.value, value)
    MiniTest.expect.equality(effects, { { type = "show_layout", value = value } })
end

T["reapplies a local tab change after a version conflict"] = function ()
    -- Given local and remote editors adding different tabs to the same base
    local layout = require("herdr-core.core.layout")
    local first = { id = "first", root = { kind = "terminal", id = "w1", terminal = "t1" } }
    local ours = { id = "ours", root = { kind = "terminal", id = "w2", terminal = "t2" } }
    local theirs = { id = "theirs", root = { kind = "terminal", id = "w3", terminal = "t3" } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = { tabs = { first } }, version = 1 })
    state = layout.update(state, { type = "layout_changed", value = { tabs = { first, ours } } })
    -- When the save conflicts with the remote addition
    local updated, effects = layout.update(state, {
        type = "layout_conflict",
        value = { tabs = { first, theirs } },
        version = 2
    })
    -- Then both additions survive and saving retries against the new version
    MiniTest.expect.equality(updated.value, { tabs = { first, theirs, ours } })
    MiniTest.expect.equality(effects, {
        { type = "show_layout", value = updated.value },
        {
            type = "save_layout",
            value = updated.value,
            version = 2
        }
    })
end

T["removes ended terminals and empty tabs"] = function ()
    -- Given a terminal in its own tab and in a split with another terminal
    local layout = require("herdr-core.core.layout")
    local ended = { kind = "terminal", id = "w1", terminal = "t1" }
    local kept = { kind = "terminal", id = "w2", terminal = "t2" }
    local state = layout.update(layout.new(), {
        type = "layout_loaded",
        version = 2,
        value = {
            tabs = {
                { id = "empty", root = ended },
                {
                    id = "kept",
                    root = {
                        kind = "split",
                        id = "split",
                        children = { ended, kept },
                        axis = "row"
                    }
                }
            }
        }
    })
    -- When the first terminal ends
    local updated = layout.update(state, { type = "terminal_ended", terminal = "t1" })
    -- Then empty tabs and redundant splits are removed
    MiniTest.expect.equality(updated.value, { tabs = { { id = "kept", root = kept } } })
end

T["saves a closed window without stopping its program"] = function ()
    -- Given a saved terminal tab
    local layout = require("herdr-core.core.layout")
    local state = layout.update(layout.new(), {
        type = "layout_loaded",
        version = 2,
        value = {
            tabs = {
                { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } }
            }
        }
    })
    -- When its window is closed locally
    local _, effects = layout.update(state, { type = "layout_changed", value = { tabs = {} } })
    -- Then the only request is to save the empty arrangement
    MiniTest.expect.equality(effects, { { type = "save_layout", value = { tabs = {} }, version = 2 } })
end

T["keeps local edits to an existing tab after a conflict"] = function ()
    -- Given a saved tab whose terminal is changed locally
    local layout = require("herdr-core.core.layout")
    local first = { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } }
    local edited = { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t2" } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = { tabs = { first } }, version = 1 })
    state = layout.update(state, { type = "layout_changed", value = { tabs = { edited } } })
    -- When the save conflicts with a newer unchanged tab
    local updated = layout.update(state, { type = "layout_conflict", value = { tabs = { first } }, version = 2 })
    -- Then the local edit survives
    MiniTest.expect.equality(updated.value, { tabs = { edited } })
end

T["keeps a local tab deletion after a conflict"] = function ()
    -- Given a saved tab that is closed locally
    local layout = require("herdr-core.core.layout")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = value, version = 1 })
    state = layout.update(state, { type = "layout_changed", value = { tabs = {} } })
    -- When another editor saves before this editor
    local updated = layout.update(state, { type = "layout_conflict", value = value, version = 2 })
    -- Then the closed tab stays closed
    MiniTest.expect.equality(updated.value, { tabs = {} })
end

T["keeps a remote deletion when its tab is unchanged locally"] = function ()
    -- Given a saved tab and a different tab added locally
    local layout = require("herdr-core.core.layout")
    local first = { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } }
    local added = { id = "tab2", root = { kind = "terminal", id = "w2", terminal = "t2" } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = { tabs = { first } }, version = 1 })
    state = layout.update(state, { type = "layout_changed", value = { tabs = { first, added } } })
    -- When the other editor has closed the first tab
    local updated = layout.update(state, { type = "layout_conflict", value = { tabs = {} }, version = 2 })
    -- Then the deleted tab is not brought back
    MiniTest.expect.equality(updated.value, { tabs = { added } })
end

T["ignores an older layout notification"] = function ()
    -- Given a layout already read at version three
    local layout = require("herdr-core.core.layout")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = value, version = 3 })
    -- When a delayed notification for version two arrives
    local updated, effects = layout.update(state, { type = "layout_loaded", value = { tabs = {} }, version = 2 })
    -- Then it cannot undo the newer arrangement
    MiniTest.expect.equality(updated, state)
    MiniTest.expect.equality(effects, {})
end

T["does not save an unchanged window arrangement"] = function ()
    -- Given a loaded terminal layout
    local layout = require("herdr-core.core.layout")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = value, version = 1 })
    -- When restoring its windows triggers a local layout event
    local _, effects = layout.update(state, { type = "layout_changed", value = value })
    -- Then no redundant write can trigger a synchronization loop
    MiniTest.expect.equality(effects, {})
end

T["accepts its saved version without rebuilding unchanged windows"] = function ()
    -- Given a local layout waiting for its save notification
    local layout = require("herdr-core.core.layout")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    local state = layout.update(layout.new(), { type = "layout_changed", value = value })
    -- When the saved value is announced with a new version
    local updated, effects = layout.update(state, { type = "layout_loaded", value = value, version = 1 })
    -- Then the version advances, pending changes clear and windows stay in place
    MiniTest.expect.equality(updated, { value = value, version = 1 })
    MiniTest.expect.equality(effects, {})
end

T["merges a remote notification while local changes are pending"] = function ()
    -- Given an unsaved local tab and a different tab saved remotely
    local layout = require("herdr-core.core.layout")
    local ours = { id = "ours", root = { kind = "terminal", id = "w1", terminal = "t1" } }
    local theirs = { id = "theirs", root = { kind = "terminal", id = "w2", terminal = "t2" } }
    local state = layout.update(layout.new(), { type = "layout_changed", value = { tabs = { ours } } })
    -- When the remote update arrives before our save completes
    local updated, effects = layout.update(
        state, { type = "layout_loaded", value = { tabs = { theirs } }, version = 1 }
    )
    -- Then both tabs survive and the merged value is saved against the new version
    MiniTest.expect.equality(updated.value, { tabs = { theirs, ours } })
    MiniTest.expect.equality(assert(effects[2]).type, "save_layout")
end

T["does not rebuild the layout when an unshown terminal ends"] = function ()
    -- Given a layout showing one terminal
    local layout = require("herdr-core.core.layout")
    local value = { tabs = { { id = "tab1", root = { kind = "terminal", id = "w1", terminal = "t1" } } } }
    local state = layout.update(layout.new(), { type = "layout_loaded", value = value, version = 1 })
    -- When a different background terminal ends
    local updated, effects = layout.update(state, { type = "terminal_ended", terminal = "other" })
    -- Then no windows or shared data need changing
    MiniTest.expect.equality(updated, state)
    MiniTest.expect.equality(effects, {})
end

T["clears restored terminal windows when the shared value is deleted"] = function ()
    -- Given an existing restored terminal tab
    local layout = require("herdr-core.core.layout")
    local state = layout.update(layout.new(), {
        type = "layout_loaded",
        version = 1,
        value = {
            tabs = {
                {
                    id = "tab1",
                    root = {
                        kind = "terminal",
                        id = "w1",
                        terminal = "t1"
                    }
                }
            }
        }
    })
    -- When another editor deletes the shared value
    local updated, effects = layout.update(state, { type = "layout_loaded", version = 2 })
    -- Then the empty layout is applied without killing any program
    MiniTest.expect.equality(updated.value, { tabs = {} })
    MiniTest.expect.equality(effects, { { type = "show_layout", value = { tabs = {} } } })
end

return T
