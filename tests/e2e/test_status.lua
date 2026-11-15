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

---@param address string
---@param state   string
local function report(address, state)
    -- --force: hc refuses to type into a blocked terminal, which the next report may follow.
    session.hc({ "send", "--json", "--force", address, "status " .. state })
    session.wait(function ()
        local status = session.hc({ "get", "--json", address }).status
        return status ~= nil and status.state == state
    end, "hc status " .. state)
end

---@param child  MiniTest.child
---@param symbol string
---@param name   string
local function shows(child, symbol, name)
    session.wait(
        function () return session.sidebar(child):find(symbol .. " " .. name, 1, true) ~= nil end, symbol .. " " .. name
    )
end

---@return string
local function notifications()
    local path = vim.env.HERDR_E2E_DUNST_LOG
    return path and vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), "\n") or ""
end

-- When the dummy agent reports `working`, `blocked` and `done` with OSC 7501, hc and the sidebar can show each status.
T["shows each status the agent reports"] = function ()
    -- Given: an agent listed in the sidebar
    local address = session.spawn(nil, "reporter")
    local child = session.editor()
    session.row(child, "reporter")
    -- When / Then: each status it reports reaches hc and the sidebar's symbol
    for state, symbol in pairs({ working = "◐", blocked = "●", done = "✓" }) do
        report(address, state)
        shows(child, symbol, "reporter")
    end
end

-- When a terminal nobody looks at becomes blocked or done, the plugin can run the OS notification command successfully, and on Linux dunst can log it.
T["notifies about a blocked terminal nobody looks at"] = function ()
    if vim.fn.has("linux") == 0 then MiniTest.skip("dunst runs only in the Linux E2E") end
    -- Given: an agent no window shows
    local address = session.spawn(nil, "unwatched")
    local child = session.editor()
    session.row(child, "unwatched")
    -- When: it becomes blocked
    report(address, "blocked")
    -- Then: dunst receives a notification with its name and status, and no error is shown
    session.wait(function ()
        local log = notifications()
        return log:find("unwatched", 1, true) ~= nil and log:find("blocked", 1, true) ~= nil
    end, "notification in dunst")
    eq(child.lua_get("vim.fn.execute('messages')"):find("notif", 1, true), nil)
end

-- When a terminal shown in the focused Neovim becomes blocked or done, the plugin can update the sidebar without a notification.
T["does not notify about a terminal on screen"] = function ()
    -- Given: an agent shown in the focused Neovim
    local address = session.spawn(nil, "onscreen")
    local child = session.editor()
    session.choose(child, address)
    -- When: it becomes blocked
    report(address, "blocked")
    -- Then: the sidebar shows it, and no notification names it
    shows(child, "●", "onscreen")
    vim.wait(1000)
    eq(notifications():find("onscreen", 1, true), nil)
end

-- When the user opens a done terminal in the focused Neovim, both Neovims can show it as read through `herdr.seen`.
T["marks a done terminal read in both Neovims when it is opened"] = function ()
    -- Given: an agent that finished a turn while neither of two Neovims showed it
    local address = session.spawn(nil, "finisher")
    local one, two = session.editor(), session.editor()
    report(address, "working")
    report(address, "done")
    shows(one, "✓", "finisher")
    shows(two, "✓", "finisher")
    -- When: the first Neovim opens it
    session.choose(one, address)
    -- Then: herdr.seen reaches its turn and both show it as read
    session.wait(function ()
        local record = session.hc({ "get", "--json", address })
        return tonumber(record.labels["herdr.seen"]) == record.turn
    end, "herdr.seen at the turn")
    shows(one, "○", "finisher")
    shows(two, "○", "finisher")
end

-- When the user presses `u` on a read done terminal, the plugin can mark it unread in its label and the sidebar.
T["marks a read terminal unread with u"] = function ()
    -- Given: an agent whose finished turn has been read
    local address = session.spawn(nil, "reread")
    local child = session.editor()
    report(address, "working")
    report(address, "done")
    session.choose(child, address)
    shows(child, "○", "reread")
    -- When: the user presses u on its row
    child.type_keys(tostring(session.row(child, "reread")) .. "Gu")
    -- Then: herdr.seen drops below the turn and the row shows done again
    session.wait(function ()
        local record = session.hc({ "get", "--json", address })
        return tonumber(record.labels["herdr.seen"]) == record.turn - 1
    end, "herdr.seen below the turn")
    shows(child, "✓", "reread")
end

return T
