local M = {}
---@type fun()?
local stop_previous

---@class HerdrCoreConfig
---@field auto_insert?   boolean
---@field sidebar_width? integer
---@field resources?     HerdrCoreResource[]                                                                                What the sidebar lists, in order; `{ resources.terminals() }` when left out.
---@field open?          fun(terminal: string): HerdrCoreOpenEffect
---@field notify?        fun(name: string, status: string)
---@field picker?        fun(items: HerdrCoreChoice[], options: { prompt: string }, on_choice: fun(item: HerdrCoreChoice?)) Lists the places for a new terminal; vim.ui.select fits.
---@field integrations?  table<string, table | false>                                                                       Integration definitions over the built-in ones; `false` turns one off.

---@param config? HerdrCoreConfig
---@return table
function M.setup(config)
    config = config or {}
    if vim.fn.executable("hc") == 0 then
        vim.notify("hc is not on PATH. Install herdr-core before calling setup().", vim.log.levels.ERROR)
        return {}
    end
    local given = config.resources or { require("herdr-core.resources").terminals() }
    local problem = require("herdr-core.core.sidebar").problem(given)
    if problem then
        vim.notify("herdr-core resources: " .. problem, vim.log.levels.ERROR)
        return {}
    end
    -- The terminals' keys moved to their resource when the terminals became one.
    if (config --[[@as table]]).sidebar_keys then
        vim.notify(
            "herdr-core: sidebar_keys is no longer used. Pass the keys to require('herdr-core.resources').terminals({ keys = ... }) in resources.",
            vim.log.levels.WARN
        )
    end
    if stop_previous then stop_previous() end
    local hc = require("herdr-core.adapter.hc")
    local git = require("herdr-core.adapter.git")
    local notifier = require("herdr-core.adapter.notifier")
    local core = require("herdr-core.core.state")
    local terminal = require("herdr-core.ui.terminal")
    local layout = require("herdr-core.ui.layout")
    local integrations = require("herdr-core.integrations")
    local resolved = integrations.resolve(config.integrations)
    ---@type HerdrCoreLoop
    local loop
    local counter = 0
    ---@return string
    local function identifier()
        counter = counter + 1
        return vim.fn.getpid() .. "-" .. vim.fn.reltimestr(vim.fn.reltime()) .. "-" .. counter
    end
    local active, restored = true, false
    local stops = {}
    ---@param message string
    local function report(message)
        vim.schedule(function () if active then vim.notify(message, vim.log.levels.ERROR) end end)
    end
    ---@param event table
    local function dispatch(event)
        if not active then return end
        if event.type == "layout_loaded" then restored = true end
        if event.type == "layout_changed" and not restored then return end
        loop.dispatch(event)
    end
    ---@param event table?
    ---@param err   string?
    local function receive(event, err)
        vim.schedule(function ()
            if not active then return end
            if err then
                report(err)
            elseif event then
                dispatch(event)
            end
        end)
    end
    ---@param address   string
    ---@param existing? integer
    ---@return integer
    local function buffer_for(address, existing)
        local record = loop.state().terminals[address]
        return terminal.buffer(
            record or { address = address, machine = address:match("^([^/]+)/") }, hc.attach(address), existing
        )
    end
    ---@param effect table
    local function show_terminal(effect)
        if effect.placement == "vertical" then
            vim.cmd.vsplit()
        elseif effect.placement == "horizontal" then
            vim.cmd.split()
        else
            vim.cmd.tabnew()
        end
        vim.api.nvim_set_current_buf(buffer_for(effect.terminal))
    end
    ---@param root string?
    local function start(root)
        dispatch({
            type = "new_terminal_requested",
            placement = "tab",
            tab = identifier(),
            space_root = root,
            editor_folder = vim.fn.getcwd()
        })
    end
    ---@param ctx HerdrCoreActionContext
    ---@return table
    local function props(ctx)
        return assert(ctx.item.props)
    end
    -- What the items of `terminals` can do. Each passes the event for it to the core.
    ---@type table<string, HerdrCoreResourceAction>
    local terminal_actions = {
        open = function (ctx)
            local windows = {}
            for _, window in ipairs(vim.api.nvim_list_wins()) do
                local address = vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address
                if address then windows[address] = tostring(window) end
            end
            dispatch({ type = "terminal_chosen", terminal = props(ctx).address, windows = windows })
        end,
        rename = function (ctx)
            require("herdr-core.ui.prompt").name(ctx.item.name, function (name)
                if name ~= nil then
                    dispatch({ type = "terminal_named", terminal = props(ctx).address, name = name })
                end
            end)
        end,
        pin = function (ctx)
            dispatch({ type = "terminal_pinned", terminal = props(ctx).address, pinned = not props(ctx).is_pinned })
        end,
        unread = function (ctx) dispatch({ type = "unread_requested", terminal = props(ctx).address }) end,
        new_terminal = function (ctx) start(props(ctx).space) end
    }
    -- The definitions go to the core as given; `terminals` gets its actions here, where they can reach the core.
    ---@type HerdrCoreResource[]
    local listed = vim.tbl_map(function (resource)
        if resource.name ~= "terminals" then return resource end
        return vim.tbl_extend("keep", { actions = terminal_actions }, resource)
    end, given)
    local monitors = require("herdr-core.adapter.resources").new(dispatch, report)
    stops[#stops + 1] = monitors.stop
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row, value)
        if not row then return end
        if row.kind:find("^setup_") then
            if row.action == "install" then
                dispatch({ type = "setup_requested", names = { row.name } })
            elseif row.action == "install_all" then
                dispatch({ type = "setup_requested" })
            elseif row.action == "dismiss" then
                dispatch({ type = "setup_dismissed" })
            end
        elseif row.kind == "new_terminal" then
            ---@type HerdrCoreChoice[]
            local places = {}
            ---@param path string
            local function offer(path)
                path = vim.fs.normalize(path)
                for _, place in ipairs(places) do
                    if place.path == path then return end
                end
                places[#places + 1] = { label = vim.fn.fnamemodify(path, ":~"), path = path }
            end
            offer(vim.fn.getcwd())
            local home = vim.fn.expand("~") --[[@as string]]
            offer(home)
            local _, rows = core.view(loop.state())
            for _, space in ipairs(rows) do
                -- The sections of `terminals` are the spaces; their ids are the spaces' roots.
                if space.kind == "section" and space.resource == "terminals" and space.id then offer(space.id) end
            end
            local picker = config.picker or require("herdr-core.ui.prompt").choose
            picker(places, { prompt = "New terminal" }, function (place)
                if place then start(place.path) end
            end)
        elseif row.kind == "item" and action == "action" then
            dispatch({
                type = "action_chosen",
                resource = row.resource,
                action = value,
                item = row.item,
                parent = row.parent
            })
        elseif row.kind == "item" then
            -- Enter and a click are the key `use`.
            dispatch({
                type = "key_pressed",
                resource = row.resource,
                key = action == "key" and value or "use",
                item = row.item,
                parent = row.parent
            })
        end
    end)
    -- Resume commands are typed one after another, a little apart, as Herdr TUI does.
    local next_resume = 0
    local handlers = {
        resume_session = function (effect)
            local definition = resolved[effect.agent] --[[@as HerdrCoreIntegration?]]
            -- The id is typed into a shell: anything but an id-like word could run something else.
            if not definition or not effect.session:match("^[%w%-_.:]+$") then return end
            local now = math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1000)
            local delay = math.max(0, next_resume - now)
            next_resume = math.max(now, next_resume) + 100
            vim.defer_fn(function ()
                if not active then return end
                local cleared = {
                    ["herdr-core-nvim.agent"] = "",
                    ["herdr-core-nvim.session"] = "",
                    ["herdr-core-nvim.pid"] = ""
                }
                hc.labels(effect.terminal, cleared, function (err)
                    if err then return report(err) end
                    hc.send(effect.terminal, definition.resume_command(effect.session), function (failure)
                        if failure then report(failure) end
                    end)
                end)
            end, delay)
        end,
        install_integrations = function (effect)
            for _, name in ipairs(effect.names) do
                local definition = resolved[name] --[[@as HerdrCoreIntegration?]]
                if definition then
                    local status, err = integrations.install(name, definition)
                    receive({ type = "setup_result", name = name, status = status, error = err })
                end
            end
        end,
        find_repo_root = function (effect)
            git.root(effect.folder, effect.machine, function (root)
                receive({ type = "repo_root_found", terminal = effect.terminal, folder = effect.folder, root = root })
            end)
        end,
        set_label = function (effect)
            hc.label(effect.terminal, effect.key, effect.value, function (err) if err then report(err) end end)
        end,
        set_space = function (effect)
            hc.label(effect.terminal, "herdr.space", effect.space, function (err) if err then report(err) end end)
        end,
        save_layout = function (effect) hc.save_layout(effect.value, effect.version, receive) end,
        show_layout = function (effect) layout.show(effect.value, buffer_for) end,
        show_terminal = show_terminal,
        focus_window = function (effect)
            vim.api.nvim_set_current_win(
                assert(tonumber(effect.window)) --[[@as integer]]
            )
        end,
        notify = function (effect)
            notifier.send(effect.name, effect.status, function (err) if err then report(err) end end, config.notify)
        end,
        run_shell = function (effect)
            hc.run({ folder = effect.folder, labels = effect.labels }, function (address, err)
                vim.schedule(function ()
                    if not active then return end
                    if err then
                        report(err)
                    elseif address then
                        show_terminal({ terminal = address, placement = effect.placement })
                    end
                end)
            end)
        end,
        sync_monitors = function (effect) monitors.sync(effect) end,
        run_action = function (effect) effect.run(effect.ctx) end,
        sidebar = function (effect)
            if effect.action == "focus" then
                vim.api.nvim_set_current_win(sidebar.show())
            else
                sidebar.toggle()
            end
        end
    }
    loop = require("herdr-core.app.loop").new({
        core = core,
        state = core.new({
            open = config.open,
            resumable = function (agent, program)
                local definition = resolved[agent]
                return definition ~= nil and definition.matches_program ~= nil
                    and not definition.matches_program(program)
            end,
            resources = listed
        }),
        handlers = handlers,
        render = sidebar.render,
        report = report
    })
    require("herdr-core.ui.highlights").setup()
    local copied, failure = pcall(integrations.copy_script)
    if not copied then report(tostring(failure)) end
    vim.schedule(function ()
        if not active then return end
        local items = {}
        for name, definition in pairs(resolved) do
            local ok, status, err = pcall(integrations.status, name, definition)
            if not ok then
                status, err = "missing", tostring(status)
            end
            if status then
                items[#items + 1] = { name = name, label = definition.label, status = status, error = err }
            end
        end
        dispatch({ type = "setup_checked", items = items })
    end)
    sidebar.show(config.sidebar_width)
    stops[#stops + 1] = terminal.setup(function (uri, buffer)
        for address, record in pairs(loop.state().terminals) do
            if terminal.name(record) == uri then
                local attached = buffer_for(address, buffer)
                vim.api.nvim_set_current_buf(attached)
                if attached ~= buffer then vim.api.nvim_buf_delete(buffer, { force = true }) end
                return
            end
        end
        report("Unknown terminal: " .. uri)
    end, config.auto_insert)
    stops[#stops + 1] = layout.watch(function (value) dispatch({ type = "layout_changed", value = value }) end)
    stops[#stops + 1] = require("herdr-core.ui.focus").watch(function (value)
        dispatch({ type = "focus_changed", focused = value.focused, terminals = value.terminals, front = value.front })
    end)
    stops[#stops + 1] = loop.follow(function (callback, on_closed)
        return hc.watch(function (event, err)
            if event and event.type == "layout_loaded" then restored = true end
            callback(event, err)
        end, on_closed)
    end, 1000)
    local actions = require("herdr-core.app.actions").new(dispatch, function ()
        local record = loop.state().terminals[vim.b.herdr_core_address]
        return { editor_folder = vim.fn.getcwd(), terminal_folder = record and record.folder }
    end, identifier
    )
    local function stop()
        if not active then return end
        active = false
        for _, cleanup in ipairs(stops) do
            cleanup()
        end
        sidebar.close()
    end
    M.actions = actions
    stop_previous = stop
    return { actions = actions, stop = stop, state = loop.state }
end

return M
