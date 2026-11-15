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

-- Each tab's window tree, with terminal windows by address and other windows left out.
local describe = [[(function ()
    local function node(tree)
        if tree[1] == "leaf" then return vim.b[vim.api.nvim_win_get_buf(tree[2])].herdr_core_address end
        local children = {}
        for _, child in ipairs(tree[2]) do
            local described = node(child)
            if described then children[#children + 1] = described end
        end
        if #children == 0 then return nil end
        if #children == 1 then return children[1] end
        return { tree[1], children }
    end
    local tabs = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local described = node(vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab)))
        if described then tabs[#tabs + 1] = described end
    end
    return tabs
end)()]]

-- Whether the shared layout in the plugin's state still holds a window for the terminal.
local holds = [[(function (address)
    local function walk(node)
        if node.terminal == address then return true end
        for _, child in ipairs(node.children or {}) do
            if walk(child) then return true end
        end
        return false
    end
    for _, tab in ipairs(e2e_app.state().layout.value.tabs) do
        if walk(tab.root) then return true end
    end
    return false
end)(...)]]

---@param child MiniTest.child
---@param tabs  integer
local function wait_saved(child, tabs)
    session.wait(function ()
        return child.lua_get("#e2e_app.state().layout.value.tabs") == tabs
            and child.lua_get("e2e_app.state().layout.version") > 0
    end, "saved layout")
end

---@param child   MiniTest.child
---@param address string
local function open_split(child, address)
    session.choose(child, address)
    session.normal(child)
    child.type_keys("<F6>")
    session.wait(function ()
        return child.lua_get("vim.b.herdr_core_address") ~= address and child.lua_get("vim.bo.buftype") == "terminal"
    end, "split shell")
end

-- When Neovim restarts, the plugin can restore the tab order, the splits and the terminal in each window.
T["restores tabs, splits and terminals after Neovim restarts"] = function ()
    -- Given: one tab with an agent and a shell side by side, and a second tab with another agent
    local first, second = session.spawn(nil, "first"), session.spawn(nil, "second")
    local child = session.editor()
    open_split(child, first)
    session.choose(child, second)
    local before = child.lua_get(describe)
    wait_saved(child, 2)
    -- When: Neovim exits and starts again
    child.stop()
    local restarted = session.editor()
    -- Then: the same tabs, splits and terminals come back
    session.wait(function () return vim.deep_equal(restarted.lua_get(describe), before) end, "restored layout")
end

-- When a window was closed before Neovim restarted, the plugin can leave it closed while its terminal keeps running in hc.
T["keeps a closed window closed after Neovim restarts"] = function ()
    -- Given: an agent and a shell side by side, then the shell's window closed
    local first = session.spawn(nil, "first")
    local child = session.editor()
    open_split(child, first)
    local closed = child.lua_get("vim.b.herdr_core_address")
    session.normal(child)
    child.type_keys(":close<CR>")
    session.wait(function ()
        return not vim.inspect(child.lua_get(describe)):find('"' .. closed .. '"', 1, true)
            and not child.lua_get(holds, { closed })
    end, "layout without the closed window")
    -- When: Neovim exits and starts again
    child.stop()
    local restarted = session.editor()
    session.wait(function () return #restarted.lua_get(describe) == 1 end, "restored layout")
    -- Then: the closed window stays closed and its shell still runs
    eq(vim.inspect(restarted.lua_get(describe)):find('"' .. closed .. '"', 1, true), nil)
    eq(session.hc({ "get", "--json", closed }).state, "live")
end

-- When Neovim starts with a file, the plugin can restore the saved layout and keep the file's window.
T["restores the layout when Neovim starts with a file"] = function ()
    -- Given: a saved layout with one agent
    local first = session.spawn(nil, "first")
    local child = session.editor()
    session.choose(child, first)
    wait_saved(child, 1)
    child.stop()
    local file = session.root .. "/notes.txt"
    vim.fn.writefile({ "kept" }, file)
    -- When: Neovim starts with a file
    local restarted = session.editor(file)
    -- Then: the agent's window comes back and the file's window stays
    session.wait(function () return vim.deep_equal(restarted.lua_get(describe), { first }) end, "restored layout")
    eq(
        restarted.lua_get(
            [[(function (path)
        for _, window in ipairs(vim.api.nvim_list_wins()) do
            if vim.fs.normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window))) == path then return true end
        end
        return false
    end)(...)]], { vim.fs.normalize(file) }
        ), true
    )
end

return T
