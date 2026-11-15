local MiniTest = require("mini.test")

local T = MiniTest.new_set()

-- When the folder is inside a git repository, spaces can put the terminal in the repository root's space.
T["puts a terminal in its repository root's space"] = function ()
    -- Given a terminal whose folder is inside the repository at C:/work/app
    local spaces = require("herdr-core.core.spaces")
    local state = spaces.new()
    -- When the repository root of its folder arrives
    state = spaces.update(state, {
        type = "repo_root_found",
        terminal = "t1",
        folder = "C:/work/app/src",
        root = "C:/work/app"
    })
    -- Then the terminal is in the repository root's space
    MiniTest.expect.equality(spaces.space_of(state, "t1"), "C:/work/app")
end

-- When the folder is outside any git repository, spaces can put the terminal in the folder's own space.
T["uses the folder when it has no repository root"] = function ()
    -- Given a terminal in a folder outside any git repository
    local spaces = require("herdr-core.core.spaces")
    local state = spaces.new()
    -- When the lookup returns no repository root
    state = spaces.update(state, {
        type = "repo_root_found",
        terminal = "t1",
        folder = "C:/scratch"
    })
    -- Then the folder itself is the terminal's space
    MiniTest.expect.equality(spaces.space_of(state, "t1"), "C:/scratch")
end

T["requests the repository root when a folder changes"] = function ()
    -- Given a terminal moving to a new folder
    local spaces = require("herdr-core.core.spaces")
    local state = spaces.new()
    -- When the folder change arrives
    local updated, effects = spaces.update(state, {
        type = "folder_changed",
        terminal = "t1",
        folder = "C:/work/app/src"
    })
    -- Then it requests the root without changing the assigned space yet
    MiniTest.expect.equality(updated, state)
    MiniTest.expect.equality(effects, {
        { type = "find_repo_root", terminal = "t1", folder = "C:/work/app/src" }
    })
end

T["requests a label write when the space differs"] = function ()
    -- Given a terminal still labelled with its previous space
    local spaces = require("herdr-core.core.spaces")
    -- When its repository root is resolved
    local _, effects = spaces.update(spaces.new(), {
        type = "repo_root_found",
        terminal = "t1",
        folder = "C:/work/app/src",
        root = "C:/work/app",
        space = "C:/old"
    })
    -- Then it requests the new space label
    MiniTest.expect.equality(effects, {
        { type = "set_space", terminal = "t1", space = "C:/work/app" }
    })
end

T["skips writing an unchanged space"] = function ()
    -- Given a terminal already labelled with its repository root
    local spaces = require("herdr-core.core.spaces")
    -- When the same root is resolved
    local _, effects = spaces.update(spaces.new(), {
        type = "repo_root_found",
        terminal = "t1",
        folder = "C:/work/app/src",
        root = "C:/work/app",
        space = "C:/work/app"
    })
    -- Then no write is requested
    MiniTest.expect.equality(effects, {})
end

T["requests a repository root on the terminal's machine"] = function ()
    -- Given a terminal on a remote machine
    local spaces = require("herdr-core.core.spaces")
    -- When its folder changes
    local _, effects = spaces.update(spaces.new(), {
        type = "folder_changed",
        terminal = "vps/t1",
        folder = "/work/app",
        machine = "vps"
    })
    -- Then the lookup targets that machine
    MiniTest.expect.equality(effects, {
        { type = "find_repo_root", terminal = "vps/t1", folder = "/work/app", machine = "vps" }
    })
end

T["removes the final terminal from a space"] = function ()
    -- Given two terminals in different spaces
    local spaces = require("herdr-core.core.spaces")
    local state = { t1 = "C:/app", t2 = "C:/other" }
    -- When the last terminal in C:/app ends
    local updated, effects = spaces.update(state, { type = "terminal_ended", terminal = "t1" })
    -- Then only the other space remains and the previous state is intact
    MiniTest.expect.equality(updated, { t2 = "C:/other" })
    MiniTest.expect.equality(state, { t1 = "C:/app", t2 = "C:/other" })
    MiniTest.expect.equality(effects, {})
end

return T
