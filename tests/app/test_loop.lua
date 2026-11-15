local MiniTest = require("mini.test")
local T = MiniTest.new_set()

---@param effects table<string, table[]>
---@param seen    table[]
---@return HerdrCoreLoopCore
local function fake_core(effects, seen)
    ---@param state table
    ---@param event table
    ---@return table, table[]
    local function update(state, event)
        seen[#seen + 1] = event
        return { count = state.count + 1 }, effects[event.type] or {}
    end
    ---@param state table
    ---@return table, HerdrCoreSidebarRow[], integer
    local function view(state)
        return state, { { kind = "summary", lines = {} } }, state.count
    end
    return { update = update, view = view }
end

-- When an event arrives, the loop can pass it to the core and carry out the returned effects in order.
T["passes an event to the core and carries out its effects in order"] = function ()
    -- Given a core that answers one event with two effects
    local seen, done, drawn = {}, {}, {}
    local loop = require("herdr-core.app.loop").new({
        core = fake_core({ started = { { type = "first" }, { type = "second" } } }, seen),
        state = { count = 0 },
        handlers = {
            first = function () done[#done + 1] = "first" end,
            second = function () done[#done + 1] = "second" end
        },
        render = function (rows, waiting) drawn = { #rows, waiting } end
    })
    -- When the event arrives
    loop.dispatch({ type = "started" })
    -- Then the core sees it, the effects run in order, and the sidebar is drawn from the new state
    MiniTest.expect.equality(seen, { { type = "started" } })
    MiniTest.expect.equality(done, { "first", "second" })
    MiniTest.expect.equality(drawn, { 1, 1 })
end

-- When an effect asks for information, the loop can pass the answer back to the core as an event.
T["passes the answer to an effect back to the core"] = function ()
    -- Given a core that asks for a repository root, and a handler that finds it
    local seen = {}
    local loop = require("herdr-core.app.loop").new({
        core = fake_core({ started = { { type = "find_repo_root", folder = "/app/src" } } }, seen),
        state = { count = 0 },
        handlers = {
            find_repo_root = function (effect, dispatch)
                dispatch({
                    type = "repo_root_found",
                    folder = effect.folder,
                    root = "/app"
                })
            end
        },
        render = function () end
    })
    -- When the event that asks arrives
    loop.dispatch({ type = "started" })
    -- Then the answer reaches the core as the next event
    MiniTest.expect.equality(seen, {
        { type = "started" },
        {
            type = "repo_root_found",
            folder = "/app/src",
            root = "/app"
        }
    })
end

-- When an effect fails, the loop can pass the failure back to the core as an event and keep running.
T["reports a failing effect to the core and runs the rest"] = function ()
    -- Given two effects where the first one fails
    local seen, done, reported = {}, {}, {}
    local loop = require("herdr-core.app.loop").new({
        core = fake_core({ started = { { type = "broken" }, { type = "fine" } } }, seen),
        state = { count = 0 },
        handlers = {
            broken = function () error("hc label failed") end,
            fine = function () done[#done + 1] = "fine" end
        },
        render = function () end,
        report = function (message) reported[#reported + 1] = message end
    })
    -- When the event arrives
    loop.dispatch({ type = "started" })
    -- Then the failure reaches the core as an event and the second effect still runs
    ---@type { type: string, effect: table, error: string }
    local failure = assert(seen[2])
    MiniTest.expect.equality(failure.type, "effect_failed")
    MiniTest.expect.equality(failure.effect, { type = "broken" })
    MiniTest.expect.equality(failure.error:find("hc label failed", 1, true) ~= nil, true)
    MiniTest.expect.equality(done, { "fine" })
    -- and the user is told about it
    MiniTest.expect.equality(#reported, 1)
end

-- When the event stream from the core closes, the loop can follow it again after a short wait.
T["follows the event stream again after it closes"] = function ()
    -- Given a stream that delivers one event and then closes
    local seen = {}
    local loop = require("herdr-core.app.loop").new({
        core = fake_core({}, seen),
        state = { count = 0 },
        handlers = {},
        render = function () end
    })
    local started = 0
    ---@param callback  fun(event: table?, err: string?)
    ---@param on_closed fun()
    ---@return fun()
    local function watch(callback, on_closed)
        started = started + 1
        if started == 1 then
            callback({ type = "started" })
            on_closed()
        end
        return function () end
    end
    -- When the loop follows it
    local stop = loop.follow(watch, 10)
    vim.wait(1000, function () return started == 2 end)
    stop()
    -- Then the event reaches the core and the stream is followed again
    MiniTest.expect.equality(seen, { { type = "started" } })
    MiniTest.expect.equality(started, 2)
end

-- When the event stream keeps closing right away, the loop can wait longer each time before following it again.
T["waits longer each time the stream closes without delivering anything"] = function ()
    -- Given a stream that closes three times without an event, then delivers one and closes
    local loop = require("herdr-core.app.loop").new({
        core = fake_core({}, {}),
        state = { count = 0 },
        handlers = {},
        render = function () end
    })
    local starts = 0
    ---@param callback  fun(event: table?, err: string?)
    ---@param on_closed fun()
    ---@return fun()
    local function watch(callback, on_closed)
        starts = starts + 1
        if starts == 4 then callback({ type = "started" }) end
        if starts <= 4 then on_closed() end
        return function () end
    end
    local delays = {}
    local defer_fn = vim.defer_fn
    ---@param fn function
    ---@param ms integer
    ---@return table
    vim.defer_fn = function (fn, ms)
        delays[#delays + 1] = ms
        fn()
        return {}
    end
    -- When the loop follows it
    local stop = loop.follow(watch, 100)
    vim.defer_fn = defer_fn
    stop()
    -- Then each wait doubles, and the wait starts over once an event arrives
    MiniTest.expect.equality(delays, { 100, 200, 400, 100 })
end

return T
