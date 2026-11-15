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

-- When the user types into a dummy agent opened from the sidebar, Neovim can show the agent's reply through a real attach.
T["shows the dummy agent response through a real attach"] = function ()
    -- Given: a real dummy agent running in the isolated core
    local address = session.spawn()
    local child = session.editor()
    -- When: the user opens its sidebar row and types through hc attach
    session.choose(child, address)
    session.input(child, "echo first-input")
    -- Then: the program's response, not the terminal's input echo, reaches Neovim
    session.wait(
        function () return session.text(child):find("reply:first-input", 1, true) ~= nil end, "dummy agent response"
    )
end

-- When the terminal buffer is wiped and the agent is opened again from the sidebar, the plugin can reattach to the same agent.
T["reattaches to the same agent after its buffer is wiped"] = function ()
    -- Given: an agent that has already answered through its terminal buffer
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    session.input(child, "echo before-wipe")
    session.wait(function () return session.text(child):find("reply:before-wipe", 1, true) ~= nil end, "first reply")
    -- When: the window is closed, the buffer wiped, and the agent opened again from the sidebar
    session.normal(child)
    child.type_keys(":bwipeout!<CR>")
    session.choose(child, address)
    session.input(child, "echo after-wipe")
    -- Then: the same agent still shows its earlier output and answers the new input
    session.wait(function () return session.text(child):find("reply:after-wipe", 1, true) ~= nil end, "second reply")
    MiniTest.expect.equality(session.text(child):find("reply:before-wipe", 1, true) ~= nil, true)
    MiniTest.expect.equality(session.hc({ "get", "--json", address }).state, "live")
end

-- When Neovim exits and a new Neovim starts the plugin, the plugin can reattach to the same agent.
T["reattaches to the same agent in a new Neovim"] = function ()
    -- Given: an agent that has answered in a Neovim that then exits
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    session.input(child, "echo before-restart")
    session.wait(function () return session.text(child):find("reply:before-restart", 1, true) ~= nil end, "first reply")
    child.stop()
    -- When: a new Neovim starts the plugin and the user types into the restored terminal window
    child = session.editor()
    session.wait(function ()
        return child.lua_get(
            [[(function (address)
            for _, window in ipairs(vim.api.nvim_list_wins()) do
                if vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address == address then
                    vim.api.nvim_set_current_win(window)
                    return true
                end
            end
            return false
        end)(...)]], { address }
        )
    end, "restored terminal window")
    session.input(child, "echo after-restart")
    -- Then: the same agent answers in the new Neovim
    session.wait(function () return session.text(child):find("reply:after-restart", 1, true) ~= nil end, "second reply")
    MiniTest.expect.equality(session.hc({ "get", "--json", address }).state, "live")
end

-- When the dummy agent exits, the plugin can close only the windows that showed it.
T["closes only the agent's window when the agent exits"] = function ()
    -- Given: the agent's window next to a file window in the same tab
    local address = session.spawn()
    local child = session.editor()
    session.choose(child, address)
    local agent_window = child.api.nvim_get_current_win()
    session.normal(child)
    child.type_keys(":vnew<CR>")
    local file_window = child.api.nvim_get_current_win()
    child.api.nvim_set_current_win(agent_window)
    -- When: the agent is told to exit through the attach
    session.input(child, "exit")
    -- Then: hc reports it finished, its window closes, and the file window stays
    session.wait(function () return not child.api.nvim_win_is_valid(agent_window) end, "agent window closed")
    MiniTest.expect.equality(child.api.nvim_win_is_valid(file_window), true)
    MiniTest.expect.equality(session.hc({ "get", "--json", address }).state ~= "live", true)
end

return T
