local MiniTest = require("mini.test")
local H = dofile("tests/e2e/helpers.lua")
local eq = MiniTest.expect.equality
---@type table
local session
local T = MiniTest.new_set({
    hooks = {
        pre_case = function () session = H.new() end,
        post_case = function () session.close() end
    }
})

---@param name string
---@return string
local function repository(name)
    local root = session.root .. "/" .. name
    vim.fn.mkdir(root .. "/src", "p")
    assert(vim.system({ "git", "init", "--quiet", root }):wait().code == 0)
    return root
end

---@param address string
---@param folder  string
local function wait_space(address, folder)
    session.wait(function ()
        local space = session.hc({ "get", "--json", address }).labels["herdr.space"]
        return space ~= nil and vim.fs.normalize(space) == vim.fs.normalize(folder)
    end, "space " .. folder)
end

---@param folder string
---@return string
local function shell(folder)
    local address = session.hc({ "run", "--bg", "--json", "--cwd", folder }).address
    assert(type(address) == "string", "hc run returned no address")
    return address
end

-- When a program starts in a subfolder of a git repository, the plugin can put it in the repository root's space.
T["puts a program started in a repository subfolder in the repository's space"] = function ()
    -- Given: a git repository with a subfolder
    local root = repository("app")
    local child = session.editor()
    -- When: an agent starts in the subfolder
    local address = session.spawn(root .. "/src")
    -- Then: hc and the sidebar put it in the repository root's space
    wait_space(address, root)
    session.row(child, "app")
end

-- When a program starts outside any git repository, the plugin can put it in its start folder's space.
T["puts a program started outside a repository in its folder's space"] = function ()
    -- Given: a folder outside any git repository
    local folder = session.root .. "/plain"
    vim.fn.mkdir(folder, "p")
    local child = session.editor()
    -- When: an agent starts there
    local address = session.spawn(folder)
    -- Then: hc and the sidebar put it in that folder's space
    wait_space(address, folder)
    session.row(child, "plain")
end

-- When the user moves a shell into another repository with `cd`, the plugin can move it to that repository's space.
T["moves a shell to the space of the repository it changes into"] = function ()
    -- Given: a shell in repository one
    local one, two = repository("one"), repository("two")
    local address = shell(one)
    local child = session.editor()
    wait_space(address, one)
    session.choose(child, address)
    -- When: the user changes into repository two
    session.input(child, "cd '" .. two .. "/src'")
    -- Then: the shell moves to repository two's space
    wait_space(address, two)
end

-- When one of two terminals in the same tab moves to another repository, the plugin can change only that terminal's space.
T["changes the space of only the terminal that moved"] = function ()
    -- Given: two shells in repository one, side by side in one tab
    local one, two = repository("one"), repository("two")
    local first = shell(one)
    local child = session.editor()
    session.choose(child, first)
    local before = vim.tbl_map(function (t) return t.address end, session.hc({ "ls", "--json" }).terminals)
    session.normal(child)
    child.type_keys("<F6>")
    ---@type string?
    local second
    session.wait(function ()
        for _, t in ipairs(session.hc({ "ls", "--json" }).terminals) do
            if not vim.tbl_contains(before, t.address) then second = t.address end
        end
        return second ~= nil and child.lua_get("vim.b.herdr_core_address") == second
    end, "second shell")
    wait_space(assert(second), one)
    -- When: only the second shell changes into repository two
    session.input(child, "cd '" .. two .. "'")
    -- Then: the second shell moves and the first stays
    wait_space(assert(second), two)
    eq(vim.fs.normalize(session.hc({ "get", "--json", first }).labels["herdr.space"]), vim.fs.normalize(one))
end

return T
