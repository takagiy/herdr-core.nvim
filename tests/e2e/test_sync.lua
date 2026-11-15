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

---@param child MiniTest.child
---@param text  string
---@return boolean
local function listed(child, text)
    return session.sidebar(child):find(text, 1, true) ~= nil
end

-- When one Neovim names or pins a terminal, the other Neovim's sidebar can show the change.
T["shows a name given in one Neovim in the other"] = function ()
    -- Given: two Neovims listing the same agent
    session.spawn(nil, "agent")
    local one, two = session.editor(), session.editor()
    session.wait(function () return listed(two, "agent") end, "agent listed in the second Neovim")
    -- When: the first Neovim names it
    one.type_keys(tostring(session.row(one, "agent")) .. "Gr", "<C-u>shared-name<CR>")
    -- Then: the second Neovim's sidebar shows the name
    session.wait(function () return listed(two, "shared-name") end, "name in the second Neovim")
end

-- When one Neovim adds a tab or split or closes a terminal window, the other Neovim can reach the same layout without bringing the closed window back.
T["brings the other Neovim to the same layout"] = function ()
    -- Given: two Neovims on the same core
    local agent = session.spawn(nil, "agent")
    local one, two = session.editor(), session.editor()
    -- When: the first opens the agent with a shell beside it, then closes the shell's window
    session.choose(one, agent)
    session.normal(one)
    one.type_keys("<F6>")
    session.wait(
        function () return vim.inspect(session.layout(one)):find("row", 1, true) ~= nil end, "split in the first Neovim"
    )
    session.wait(
        function () return vim.deep_equal(session.layout(two), session.layout(one)) end, "split in the second Neovim"
    )
    session.normal(one)
    one.type_keys(":close<CR>")
    -- Then: the second Neovim follows, and the closed window does not come back
    session.wait(function () return vim.deep_equal(session.layout(two), { agent }) end, "closed in the second Neovim")
    vim.wait(1000)
    eq(session.layout(one), { agent })
    eq(session.layout(two), { agent })
end

-- When a second Neovim starts with an empty screen, it can restore the saved layout without overwriting it.
T["restores the saved layout in a second Neovim without overwriting it"] = function ()
    -- Given: a Neovim that saved a layout with an agent
    local agent = session.spawn(nil, "agent")
    local one = session.editor()
    session.choose(one, agent)
    session.wait(function () return one.lua_get("e2e_app.state().layout.version") > 0 end, "saved layout")
    -- When: a second Neovim starts
    local two = session.editor()
    -- Then: it shows the saved layout and the first keeps it
    session.wait(function () return vim.deep_equal(session.layout(two), { agent }) end, "restored in the second Neovim")
    vim.wait(1000)
    eq(session.layout(one), { agent })
end

-- When one Neovim moves focus or collapses its sidebar, the other Neovim can keep its own focus and sidebar.
T["keeps focus and the sidebar to each Neovim"] = function ()
    -- Given: two Neovims showing the same agent
    local agent = session.spawn(nil, "agent")
    local one = session.editor()
    session.choose(one, agent)
    local two = session.editor()
    session.wait(function () return vim.deep_equal(session.layout(two), { agent }) end, "restored in the second Neovim")
    local focus, width = two.api.nvim_get_current_win(),
        two.lua_get(
            [[(function ()
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_sidebar then return vim.api.nvim_win_get_width(window) end
        end
    end)()]]
        )
    -- When: the first moves to the sidebar and collapses it
    session.row(one, "agent")
    one.type_keys("G<CR>")
    session.wait(function () return one.api.nvim_win_get_width(0) == 3 end, "collapsed in the first Neovim")
    vim.wait(1000)
    -- Then: the second keeps its focus and sidebar width
    eq(two.api.nvim_get_current_win(), focus)
    eq(
        two.lua_get(
            [[(function ()
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_sidebar then return vim.api.nvim_win_get_width(window) end
        end
    end)()]]
        ), width
    )
end

return T
