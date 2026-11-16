local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local hook = dofile("assets/session-hook.lua")

---@return string[][], fun(argv: string[]): string?
local function fake_hc()
    local calls = {}
    return calls, function (argv)
            calls[#calls + 1] = argv
            return ""
        end
end

---@param calls string[][]
---@return string[]?
local function labelled(calls)
    for _, call in ipairs(calls) do
        if call[2] == "label" then return call end
    end
end

T["labels the terminal when a conversation starts"] = function ()
    -- Given a codex conversation starting in hc terminal t3
    local calls, run = fake_hc()
    -- When the hook runs for the start
    hook.main({ "codex", "--event", "started" }, '{"session_id":"abc-1"}', { HC_TERMINAL_ID = "t3" }, run)
    -- Then t3 carries the integration and the conversation in one label call
    MiniTest.expect.equality(calls, {
        { "hc", "label", "t3", "herdr-core-nvim.agent=codex", "herdr-core-nvim.session=abc-1" }
    })
end

T["clears the labels when a conversation ends"] = function ()
    -- Given a conversation ending in t3
    local calls, run = fake_hc()
    -- When the hook runs for the end
    hook.main({ "claude", "--event", "ended" }, '{"session_id":"abc-1"}', { HC_TERMINAL_ID = "t3" }, run)
    -- Then both labels are emptied together
    MiniTest.expect.equality(calls, { { "hc", "label", "t3", "herdr-core-nvim.agent=", "herdr-core-nvim.session=" } })
end

T["finds the id among the known field names"] = function ()
    -- Given a payload that names the conversation conversationId
    local calls, run = fake_hc()
    -- When the hook runs without --id
    hook.main({ "agy", "--event", "started" }, '{"conversationId":"c-9"}', { HC_TERMINAL_ID = "t1" }, run)
    -- Then that field is the conversation id
    MiniTest.expect.equality(assert(labelled(calls))[5], "herdr-core-nvim.session=c-9")
end

T["reads only the fields --id names"] = function ()
    -- Given a payload with both a session_id and a conversationId
    local calls, run = fake_hc()
    local input = '{"session_id":"s-1","conversationId":"c-1"}'
    -- When --id asks for conversationId
    hook.main({ "agy", "--event", "started", "--id", "conversationId" }, input, { HC_TERMINAL_ID = "t1" }, run)
    -- Then conversationId wins over the default first field
    MiniTest.expect.equality(assert(labelled(calls))[5], "herdr-core-nvim.session=c-1")
end

T["takes the id from --id-env first"] = function ()
    -- Given grok's session variable and a different payload id
    local calls, run = fake_hc()
    local env = { HC_TERMINAL_ID = "t1", GROK_SESSION_ID = "g-1" }
    -- When --id-env names the variable
    hook.main({ "grok", "--event", "started", "--id-env", "GROK_SESSION_ID" }, '{"session_id":"s-1"}', env, run)
    -- Then the variable's value is the conversation id
    MiniTest.expect.equality(assert(labelled(calls))[5], "herdr-core-nvim.session=g-1")
end

T["ignores a conversation started inside another one"] = function ()
    -- Given a child codex that inherited its parent's thread id
    local calls, run = fake_hc()
    local env = { HC_TERMINAL_ID = "t1", CODEX_THREAD_ID = "parent" }
    local argv = { "codex", "--event", "started", "--parent-id-env", "CODEX_THREAD_ID" }
    -- When its start and end hooks run
    hook.main(argv, '{"session_id":"child"}', env, run)
    argv[3] = "ended"
    hook.main(argv, '{"session_id":"child"}', env, run)
    -- Then the parent's labels stay as they were
    MiniTest.expect.equality(calls, {})
end

T["does nothing outside hc or without an id"] = function ()
    -- Given a hook outside any hc terminal, and one whose payload has no id
    local calls, run = fake_hc()
    -- When both run for a start
    hook.main({ "claude", "--event", "started" }, '{"session_id":"s-1"}', {}, run)
    hook.main({ "claude", "--event", "started" }, "not json", { HC_TERMINAL_ID = "t1" }, run)
    -- Then hc is never called
    MiniTest.expect.equality(calls, {})
end

T["returns the reply in every case"] = function ()
    -- Given antigravity, whose hooks must print JSON
    local _, run = fake_hc()
    local argv = { "agy", "--event", "started", "--reply", "{}" }
    -- When the hook runs inside and outside hc
    local inside = hook.main(argv, '{"conversationId":"c"}', { HC_TERMINAL_ID = "t1" }, run)
    local outside = hook.main(argv, "", {}, run)
    -- Then both return the reply to print
    MiniTest.expect.equality({ inside, outside }, { "{}", "{}" })
end

return T
