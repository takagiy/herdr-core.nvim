local M = {}

---@class HerdrCoreLoopCore
---@field update fun(state: any, event: table): any, table[]
---@field view   fun(state: any): any, HerdrCoreSidebarRow[], integer

---@class HerdrCoreLoopOptions
---@field core     HerdrCoreLoopCore
---@field state    any
---@field handlers table<string, fun(effect: table, dispatch: fun(event: table))>
---@field render   fun(rows: HerdrCoreSidebarRow[], waiting: integer)
---@field report?  fun(message: string)

---@alias HerdrCoreWatch fun(callback: fun(event: table?, err: string?), on_closed: fun()): fun()

---@class HerdrCoreLoop
---@field dispatch fun(event: table)
---@field state    fun(): any
---@field follow   fun(watch: HerdrCoreWatch, wait: integer): fun()

---@param options HerdrCoreLoopOptions
---@return HerdrCoreLoop
function M.new(options)
    local state = options.state
    ---@param event table
    local function dispatch(event)
        local effects
        state, effects = options.core.update(state, event)
        for _, effect in ipairs(effects) do
            local handler = options.handlers[effect.type]
            local ok, failure = pcall(handler or function () end, effect, dispatch)
            if not ok then
                if options.report then options.report(tostring(failure)) end
                dispatch({ type = "effect_failed", effect = effect, error = tostring(failure) })
            end
        end
        local rows, waiting
        state, rows, waiting = options.core.view(state)
        options.render(rows, waiting)
    end
    ---@param watch HerdrCoreWatch
    ---@param wait  integer
    ---@return fun()
    local function follow(watch, wait)
        ---@type { active: boolean, stop: fun(), delivered: boolean, delay: integer? }
        local following = { active = true, stop = function () end, delivered = false }
        ---@param event table?
        ---@param err   string?
        local function deliver(event, err)
            if not following.active then return end
            if event then
                dispatch(event)
            elseif err then
                if options.report then options.report(err) end
                dispatch({ type = "watch_failed", error = err })
            end
        end
        local function start()
            if not following.active then return end
            -- The stream calls back from outside the main loop, where Neovim's API cannot run.
            local scheduled = vim.schedule_wrap(deliver)
            following.stop = watch(function (event, err)
                if event then following.delivered = true end
                scheduled(event, err)
            end,
                function ()
                    -- A stream that closes before delivering anything waits twice as long each time, up to 30 seconds.
                    local delay = wait
                    if following.delay and not following.delivered then
                        delay = math.min(following.delay * 2, 30000) --[[@as integer]]
                    end
                    following.delay, following.delivered = delay, false
                    vim.defer_fn(start, delay)
                end)
        end
        start()
        return function ()
            following.active = false
            following.stop()
        end
    end
    return { dispatch = dispatch, state = function () return state end, follow = follow }
end

return M
