local MiniTest = require("mini.test")
local H = dofile("tests/e2e/helpers.lua")
---@type table
local session
local T = MiniTest.new_set({
    hooks = {
        pre_case = function () session = H.new() end,
        post_case = function () session.close() end
    }
})

---@return integer
local function live()
    local count = 0
    for _, terminal in ipairs(session.hc({ "ls", "--json" }).terminals or {}) do
        if terminal.state == "live" then count = count + 1 end
    end
    return count
end

local placements = MiniTest.new_set({ parametrize = { { "<F5>", "tab" }, { "<F6>", "row" }, { "<F7>", "col" } } })
-- When the user presses the keys for a new terminal in a tab, a vertical split and a horizontal split, the plugin can open a working shell in each place.
T["opens a working shell where the key asks"] = placements

---@param key    string
---@param layout string
placements["in the requested place"] = function (key, layout)
    -- Given: a terminal window showing a dummy agent
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    local tabs, before = #child.api.nvim_list_tabpages(), live()
    local agent_window = child.api.nvim_get_current_win()
    -- When: the user presses the key for a new terminal
    session.normal(child)
    child.type_keys(key)
    session.wait(function () return live() == before + 1 end, "new shell in hc")
    session.wait(function ()
        return child.lua_get("vim.b.herdr_core_address") ~= address and child.lua_get("vim.bo.buftype") == "terminal"
    end, "new shell window")
    -- Then: it sits in the requested place and answers like a shell
    if layout == "tab" then
        MiniTest.expect.equality(#child.api.nvim_list_tabpages(), tabs + 1)
    else
        local old = child.api.nvim_win_get_position(agent_window)
        local new = child.api.nvim_win_get_position(0)
        -- Side by side shares the top row; stacked shares the left column.
        local side_by_side = old[1] == new[1] and old[2] ~= new[2]
        local stacked = old[2] == new[2] and old[1] ~= new[1]
        MiniTest.expect.equality(layout == "row" and side_by_side or layout == "col" and stacked, true)
    end
    session.input(child, "echo shell-$((40+2))")
    session.wait(function () return session.text(child):find("shell-42", 1, true) ~= nil end, "shell output")
end

---@param before string[]
---@return table
local function new_terminal(before)
    ---@type table?
    local found
    session.wait(function ()
        for _, terminal in ipairs(session.hc({ "ls", "--json" }).terminals or {}) do
            if terminal.state == "live" and not vim.tbl_contains(before, terminal.address) then
                found = terminal
                return true
            end
        end
        return false
    end, "new terminal in hc")
    return assert(found)
end

---@return string[]
local function addresses()
    return vim.tbl_map(function (terminal) return terminal.address end, session.hc({ "ls", "--json" }).terminals or {})
end

-- When a new shell is opened from a terminal window, it can start in that terminal's current folder, including folders with spaces and Japanese names.
T["starts a shell in the folder of the terminal it was opened from"] = function ()
    -- Given: a shell that moved into a folder with a space and Japanese characters
    local folder = session.root .. "/作業 folder"
    vim.fn.mkdir(folder, "p")
    local child = session.editor()
    local before = addresses()
    session.normal(child)
    child.type_keys("<F5>")
    local shell = new_terminal(before)
    session.wait(function () return child.lua_get("vim.b.herdr_core_address") == shell.address end, "shell window")
    session.input(child, "cd '" .. folder .. "'")
    session.wait(function ()
        local foreground = session.hc({ "get", "--json", shell.address }).foreground
        return foreground ~= nil and vim.fs.normalize(foreground.cwd) == vim.fs.normalize(folder)
    end, "shell moved")
    -- When: a new shell is opened from that terminal window
    before = addresses()
    session.normal(child)
    child.type_keys("<F5>")
    -- Then: the new shell starts in that folder
    MiniTest.expect.equality(vim.fs.normalize(new_terminal(before).cwd), vim.fs.normalize(folder))
end

-- When a new shell is opened from a file window, it can start in Neovim's current folder.
T["starts a shell in Neovim's folder when opened from a file window"] = function ()
    -- Given: Neovim's current folder set to the session root, with a file window in front
    local child = session.editor()
    child.cmd("cd " .. vim.fn.fnameescape(session.root))
    child.cmd("wincmd l")
    MiniTest.expect.equality(child.lua_get("vim.bo.buftype"), "")
    local before = addresses()
    -- When: a new shell is opened
    child.type_keys("<F5>")
    -- Then: it starts in Neovim's folder
    MiniTest.expect.equality(vim.fs.normalize(new_terminal(before).cwd), vim.fs.normalize(session.root))
end

local openers = MiniTest.new_set({ parametrize = { { "n" }, { "plus" } } })
-- When a new shell is opened from a space heading with `n` or a click on `+`, it can start in that space's folder.
T["starts a shell in the space of a heading"] = openers

---@param method string
openers["with n or the plus button"] = function (method)
    -- Given: a space heading for an agent's folder
    local folder = session.root .. "/space"
    vim.fn.mkdir(folder, "p")
    session.spawn(folder)
    local child = session.editor()
    local line = session.row(child, vim.fs.basename(folder))
    local before = addresses()
    -- When: the user presses n on the heading, or clicks its +
    child.type_keys(tostring(line) .. "G")
    if method == "n" then
        child.type_keys("n")
    else
        child.type_keys("<C-l>")
        local text = child.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
        local pos = child.fn.screenpos(child.api.nvim_get_current_win(), line, #text)
        child.api.nvim_input_mouse("left", "press", "", 0, pos.row - 1, pos.col - 1)
        child.api.nvim_input_mouse("left", "release", "", 0, pos.row - 1, pos.col - 1)
    end
    -- Then: the new shell starts in that space's folder
    MiniTest.expect.equality(vim.fs.normalize(new_terminal(before).cwd), vim.fs.normalize(folder))
end

return T
