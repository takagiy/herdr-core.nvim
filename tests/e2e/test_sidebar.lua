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
local activation = MiniTest.new_set({ parametrize = { { "Enter" }, { "mouse" } } })
T["Enter and mouse"] = activation

---@param child  MiniTest.child
---@param text   string
---@param method string
local function activate(child, text, method)
    local line = session.row(child, text)
    child.type_keys(tostring(line) .. "G0")
    if method == "Enter" then
        child.type_keys("<CR>")
    else
        child.type_keys("<C-l>")
        local pos = child.fn.screenpos(child.api.nvim_get_current_win(), line, 1)
        assert(pos.row > 0 and pos.col > 0, "Sidebar row must be visible")
        child.api.nvim_input_mouse("left", "press", "", 0, pos.row - 1, pos.col - 1)
        child.api.nvim_input_mouse("left", "release", "", 0, pos.row - 1, pos.col - 1)
    end
end

---@param child MiniTest.child
---@param token string
local function reply(child, token)
    session.input(child, "echo " .. token)
    session.wait(
        function () return session.text(child):find("reply:" .. token, 1, true) ~= nil end,
        "dummy agent response " .. token
    )
end

-- When the user chooses a terminal already shown in another tab, the plugin can move to its window without opening another.
---@param method string
activation["focuses the existing terminal window without duplicating its attach"] = function (method)
    -- Given: a terminal displayed in another tab with an existing attach
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    local window, job = child.api.nvim_get_current_win(), child.lua_get("vim.b.terminal_job_id")
    local windows, buffers = child.api.nvim_list_wins(), child.api.nvim_list_bufs()
    session.normal(child)
    child.type_keys(":tabprevious<CR>")
    -- When: the user selects that terminal through the sidebar
    activate(child, "agent", method)
    session.wait(function () return child.api.nvim_get_current_win() == window end, "existing terminal focus")
    -- Then: the same window and attach accept input without creating windows or buffers
    eq(child.api.nvim_list_wins(), windows)
    eq(child.api.nvim_list_bufs(), buffers)
    eq(child.lua_get("vim.b.terminal_job_id"), job)
    reply(child, "existing-window")
end

-- When the user chooses a terminal that no window shows, the plugin can open it in a new tab where the user can type into it.
---@param method string
activation["opens an undisplayed terminal in a new tab and accepts input"] = function (method)
    -- Given: a live terminal with no Neovim window
    local address = session.spawn()
    local child = session.editor()
    local tabs = #child.api.nvim_list_tabpages()
    -- When: the user selects its sidebar row
    activate(child, "agent", method)
    -- Then: a new tab contains its terminal buffer and receives the program's response
    session.wait(function () return child.lua_get("vim.b.herdr_core_address") == address end, "terminal opened")
    eq(#child.api.nvim_list_tabpages(), tabs + 1)
    eq(child.lua_get("vim.bo.buftype"), "terminal")
    reply(child, "new-tab")
end

-- When the user opens a `herdr://` URI directly, the plugin can attach that buffer to the terminal without a duplicate buffer name error.
T["opens a herdr URI without duplicate buffer errors and accepts input"] = function ()
    -- Given: a live terminal listed by the plugin
    local address = session.spawn()
    local child = session.editor()
    session.row(child, "agent")
    local uri = "herdr://" .. (address:match("^([^/]+/)") or "") .. "agent"
    -- When: the user directly edits its URI in the file window
    child.type_keys("<C-w>l", ":edit " .. uri .. "<CR>")
    -- Then: exactly one buffer owns the URI and the real program responds
    session.wait(function () return child.lua_get("vim.b.herdr_core_address") == address end, "URI attach")
    eq(child.api.nvim_buf_get_name(0), uri)
    eq(child.lua_get("vim.bo.buftype"), "terminal")
    eq(
        child.lua_get(
            [[#vim.tbl_filter(function(b) return vim.b[b].herdr_core_address ~= nil end,
        vim.api.nvim_list_bufs())]]
        ), 1
    )
    reply(child, "direct-uri")
end

-- When the user names a terminal with `r`, the plugin can write the `herdr-core-nvim.name` label and show the name in the sidebar while the `herdr://` buffer name stays the same.
T["names a terminal in its label and the sidebar and keeps its buffer name"] = function ()
    -- Given: a terminal displayed in a window and the sidebar
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    local buffer = child.api.nvim_get_current_buf()
    local uri = child.api.nvim_buf_get_name(buffer)
    -- When: the user replaces the name through the real r prompt
    local line = session.row(child, "agent")
    child.type_keys(tostring(line) .. "Gr", "<C-u>renamed-agent<CR>")
    -- Then: hc and the sidebar use the new name, and the buffer keeps the name hc can attach by
    session.wait(function ()
        return session.hc({ "get", "--json", address }).labels["herdr-core-nvim.name"] == "renamed-agent"
    end, "renamed hc label")
    session.row(child, "renamed-agent")
    MiniTest.expect.equality(child.api.nvim_buf_get_name(buffer), uri)
end

-- When the user presses `p` twice on a terminal, the plugin can pin it and unpin it in the `herdr.pinned` label and the sidebar.
T["toggles the pin label and sidebar order"] = function ()
    -- Given: two unpinned terminals in a stable sidebar order
    local addresses = { session.spawn(nil, "first"), session.spawn(nil, "second") }
    local child = session.editor()
    local names = { "first", "second" }
    if session.row(child, names[1]) > session.row(child, names[2]) then
        names[1], names[2], addresses[1], addresses[2] = names[2], names[1], addresses[2], addresses[1]
    end
    -- When: the lower terminal is pinned and then unpinned through p
    local line = session.row(child, names[2])
    child.type_keys(tostring(line) .. "Gp")
    session.wait(
        function () return session.hc({ "get", "--json", addresses[2] }).labels["herdr.pinned"] == "1" end,
        "pin label set"
    )
    session.wait(function () return session.row(child, names[2]) < session.row(child, names[1]) end, "pinned row first")
    child.type_keys(tostring(session.row(child, names[2])) .. "Gp")
    -- Then: the label clears, and pinning the other terminal moves it above the unpinned row
    session.wait(function ()
        local pin = session.hc({ "get", "--json", addresses[2] }).labels["herdr.pinned"]
        return pin == nil or pin == ""
    end, "pin label cleared")
    child.type_keys(tostring(session.row(child, names[1])) .. "Gp")
    session.wait(
        function () return session.row(child, names[1]) < session.row(child, names[2]) end, "unpinned row below"
    )
end

-- When Neovim restarts, the sidebar can show the names and pins stored in hc.
-- When an agent starts another with hc run, the sidebar can list the worker under it on one line and count it on the agent when it is blocked.
T["lists a worker under the agent that started it"] = function ()
    -- Given: an agent and a worker started for it
    local lead = session.spawn(nil, "lead")
    local worker = assert(session.hc({
            "run",
            "--bg",
            "--json",
            "--parent",
            lead,
            "--cwd",
            session.root,
            "--name",
            "worker",
            "--",
            vim.fn.exepath("node"),
            session.env.HERDR_E2E_PROJECT .. "/tests/e2e/dummy-agent.mjs"
        }).address)
    local child = session.editor()
    -- When: the worker reports that it is blocked
    session.hc({ "send", "--json", "--force", worker, "status blocked" })
    -- Then: the worker sits under the agent with a tree guide, and the agent counts it
    session.wait(function ()
        local text = session.sidebar(child)
        return text:find("lead  · 1", 1, true) ~= nil and text:find("    └ ● worker", 1, true) ~= nil
    end, "worker under lead")
end

T["preserves the name and pin after restarting Neovim"] = function ()
    -- Given: a terminal renamed and pinned through the sidebar, alongside another terminal
    local address = session.spawn(nil, "agent")
    session.spawn(nil, "other")
    local child = session.editor()
    child.type_keys(tostring(session.row(child, "agent")) .. "Gr", "<C-u>saved-agent<CR>")
    child.type_keys(tostring(session.row(child, "saved-agent")) .. "Gp")
    session.wait(
        function () return session.hc({ "get", "--json", address }).labels["herdr.pinned"] == "1" end, "saved pin"
    )
    -- When: the user quits Neovim and starts a new editor in the same hc environment
    child.stop()
    child = session.editor()
    -- Then: the saved name and pin remain in hc and the pinned row appears first
    eq(session.hc({ "get", "--json", address }).labels["herdr-core-nvim.name"], "saved-agent")
    eq(session.hc({ "get", "--json", address }).labels["herdr.pinned"], "1")
    eq(session.row(child, "saved-agent") < session.row(child, "other"), true)
end

---@param method string
activation["keeps terminal rows visible when a space heading is activated"] = function (method)
    -- Given: a space heading containing a live terminal
    local address = session.spawn()
    local child = session.editor()
    session.row(child, "agent")
    local heading = vim.fs.basename(
        session.root --[[@as string]]
    )
    -- When: the user presses Enter or clicks on the space heading
    activate(child, heading, method)
    -- Then: its terminal stays visible and usable
    session.row(child, "agent")
    eq(session.hc({ "get", "--json", address }).state, "live")
    session.choose(child, address)
    reply(child, "after-heading-activation")
end

-- When the user clicks `«` and then `»`, the sidebar can collapse to a strip and expand again without changing the terminal windows.
T["collapses and expands the sidebar with its footer without changing terminal placement"] = function ()
    -- Given: an expanded sidebar and a terminal window
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    local window, buffer = child.api.nvim_get_current_win(), child.api.nvim_get_current_buf()
    local windows, tabs = child.api.nvim_list_wins(), child.api.nvim_list_tabpages()
    session.row(child, "agent")
    local sidebar, width = child.api.nvim_get_current_win(), child.api.nvim_win_get_width(0)
    -- When: the user clicks the collapse footer and then the expand footer
    activate(child, "«", "mouse")
    session.wait(function () return child.api.nvim_win_get_width(sidebar) == 3 end, "narrow sidebar")
    eq(session.text(child):find("agent", 1, true), nil)
    activate(child, "»", "mouse")
    -- Then: the original width, rows, tabs and terminal window assignment remain
    session.wait(function () return child.api.nvim_win_get_width(sidebar) == width end, "expanded sidebar")
    session.row(child, "agent")
    eq(child.api.nvim_list_tabpages(), tabs)
    eq(child.api.nvim_list_wins(), windows)
    eq(child.api.nvim_win_get_buf(window), buffer)
    session.choose(child, address)
    reply(child, "after-footer-fold")
end

return T
