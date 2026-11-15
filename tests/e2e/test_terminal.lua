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

return T
