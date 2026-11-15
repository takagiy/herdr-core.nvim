local M = {}
---@type fun()?
local stop_previous

---@class HerdrCoreConfig
---@field auto_insert?   boolean
---@field sidebar_width? integer
---@field sidebar_keys?  HerdrCoreSidebarKeys
---@field open?          fun(terminal: string): HerdrCoreOpenEffect
---@field notify?        fun(name: string, status: string)

---@param config? HerdrCoreConfig
---@return table
function M.setup(config)
    config = config or {}
    if vim.fn.executable("hc") == 0 then
        vim.notify("hc is not on PATH. Install herdr-core before calling setup().", vim.log.levels.ERROR)
        return {}
    end
    if stop_previous then stop_previous() end
    local hc = require("herdr-core.adapter.hc")
    local git = require("herdr-core.adapter.git")
    local notifier = require("herdr-core.adapter.notifier")
    local core = require("herdr-core.core.state")
    local terminal = require("herdr-core.ui.terminal")
    local layout = require("herdr-core.ui.layout")
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
    local sidebar = require("herdr-core.ui.sidebar").create(function (action, row, value)
        if not row then return end
        if action == "activate" then
            if row.kind ~= "terminal" then
                if row.kind == "machine" and row.id then dispatch({ type = "machine_toggled", id = row.id }) end
                return
            end
            local windows = {}
            for _, window in ipairs(vim.api.nvim_list_wins()) do
                local address = vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address
                if address then windows[address] = tostring(window) end
            end
            dispatch({ type = "terminal_chosen", terminal = row.address, windows = windows })
        elseif action == "rename" then
            dispatch({ type = "terminal_named", terminal = row.address, name = value })
        elseif action == "pin" then
            local record = loop.state().terminals[row.address]
            dispatch({ type = "terminal_pinned", terminal = row.address, pinned = not record.labels["herdr.pinned"] })
        elseif action == "unread" then
            dispatch({ type = "unread_requested", terminal = row.address })
        elseif action == "new_terminal" then
            local record = row.address and loop.state().terminals[row.address]
            dispatch({
                type = "new_terminal_requested",
                placement = "tab",
                tab = identifier(),
                space_root = row.root or (record and record.labels["herdr.space"]),
                editor_folder = vim.fn.getcwd()
            })
        end
    end, config.sidebar_keys)
    local handlers = {
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
        state = core.new({ open = config.open }),
        handlers = handlers,
        render = sidebar.render,
        report = report
    })
    require("herdr-core.ui.highlights").setup()
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
        dispatch({ type = "focus_changed", focused = value.focused, terminals = value.terminals })
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
