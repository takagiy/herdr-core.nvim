local MiniTest = require("mini.test")
local system, has = vim.system, vim.fn.has
local T = MiniTest.new_set({
    hooks = {
        post_case = function ()
            vim.system = system
            vim.fn.has = has
        end
    }
})

T["uses a Windows OS toast with data passed outside the script"] = function ()
    -- Given Windows and a captured process invocation
    ---@type string[]?
    local command
    ---@type table?
    local environment
    ---@param _feature string
    ---@return integer
    vim.fn.has = function (_feature) return 1 end
    ---@param argv      string[]
    ---@param options?  vim.SystemOpts
    ---@param callback? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (argv, options, callback)
        command, environment = argv, assert(options).env
        assert(callback)({ code = 0, signal = 0, stdout = "", stderr = "" })
        return {} --[[@as vim.SystemObj]]
    end
    -- When a terminal needs attention
    require("herdr-core.adapter.notifier").send("build '<&", "blocked", function () end)
    -- Then a hidden PowerShell process receives notification text as environment values
    MiniTest.expect.equality(assert(command)[1], "powershell.exe")
    MiniTest.expect.equality(environment, {
        HERDR_NOTIFICATION_TITLE = "build '<&",
        HERDR_NOTIFICATION_BODY = "blocked"
    })
end

T["uses the native macOS and Linux notification commands"] = function ()
    -- Given captured process invocations on macOS followed by Linux
    ---@type string[][]
    local commands = {}
    local platform = "macunix"
    ---@param feature string
    ---@return integer
    vim.fn.has = function (feature) return feature == platform and 1 or 0 end
    ---@param argv      string[]
    ---@param _options? vim.SystemOpts
    ---@param callback? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (argv, _options, callback)
        commands[#commands + 1] = argv
        assert(callback)({ code = 0, signal = 0, stdout = "", stderr = "" })
        return {} --[[@as vim.SystemObj]]
    end
    -- When each platform sends an attention notification
    local notifier = require("herdr-core.adapter.notifier")
    notifier.send("build", "done", function () end)
    platform = "linux"
    notifier.send("build", "blocked", function () end)
    -- Then native commands receive text as separate arguments
    MiniTest.expect.equality(assert(commands[1])[1], "osascript")
    MiniTest.expect.equality(assert(commands[1])[5], "build")
    MiniTest.expect.equality(commands[2], { "notify-send", "--", "build", "blocked" })
end

T["uses a custom notification function instead of starting an OS command"] = function ()
    -- Given a user-provided notifier and a forbidden OS process boundary
    vim.system = function () error("OS notifier must not run") end
    local delivered
    ---@type string?
    local failure
    ---@param name   string
    ---@param status string
    local function notify(name, status)
        delivered = { name, status }
    end
    -- When attention is reported
    require("herdr-core.adapter.notifier").send("build", "blocked", function (err) failure = err end, notify)
    -- Then the user's notifier receives the name and status
    MiniTest.expect.equality(delivered, { "build", "blocked" })
    MiniTest.expect.equality(failure, nil)
end

T["reports a failed OS command without throwing"] = function ()
    -- Given the OS notification executable is unavailable
    vim.system = function () error("notifier unavailable") end
    ---@type string?
    local failure
    -- When an attention notification is sent
    local ok = pcall(require("herdr-core.adapter.notifier").send, "build", "done", function (err) failure = err end)
    -- Then the plugin stays alive and receives the error
    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(type(failure), "string")
end

return T
