local MiniTest = require("mini.test")
local input = vim.ui.input
local T = MiniTest.new_set({ hooks = { post_case = function () vim.ui.input = input end } })

T["returns the entered terminal name"] = function ()
    -- Given an input UI where the user enters a name
    ---@param options  table?
    ---@param callback fun(value: string?)
    vim.ui.input = function (options, callback)
        MiniTest.expect.equality(assert(options).default, "old")
        callback("build")
    end
    ---@type string?
    local result
    -- When a name is requested
    require("herdr-core.ui.prompt").name("old", function (value) result = value end)
    -- Then the entered value is returned
    MiniTest.expect.equality(result, "build")
end

T["reports cancellation without turning it into an empty name"] = function ()
    -- Given a user cancelling the input UI
    ---@param callback fun(value: string?)
    vim.ui.input = function (_, callback) callback(nil) end
    local called = false
    ---@type string?
    local result = "unchanged"
    -- When a name is requested
    require("herdr-core.ui.prompt").name("old", function (value)
        called = true
        result = value
    end)
    -- Then nil signals cancellation
    MiniTest.expect.equality(called, true)
    MiniTest.expect.equality(result, nil)
end

T["returns an empty name so the caller can clear it"] = function ()
    -- Given a user submitting an empty input
    ---@param callback fun(value: string?)
    vim.ui.input = function (_, callback) callback("") end
    ---@type string?
    local result
    -- When a name is requested
    require("herdr-core.ui.prompt").name("old", function (value) result = value end)
    -- Then empty text remains distinct from cancellation
    MiniTest.expect.equality(result, "")
end

return T
