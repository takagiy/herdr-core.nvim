local terminals = require("herdr-core.core.terminals")
local spaces = require("herdr-core.core.spaces")
local layout = require("herdr-core.core.layout")
local attention = require("herdr-core.core.attention")
local open = require("herdr-core.core.open")
local sidebar = require("herdr-core.core.sidebar")
local resume = require("herdr-core.core.resume")
local setup = require("herdr-core.core.setup")
local M = {}

---@class HerdrCoreSidebarRequested
---@field type   'sidebar_requested'
---@field action 'toggle' | 'focus'

---@class HerdrCoreSidebarEffect
---@field type   'sidebar'
---@field action 'toggle' | 'focus'

---@class HerdrCoreState
---@field terminals  HerdrCoreTerminals
---@field spaces     HerdrCoreSpaces
---@field layout     HerdrCoreLayoutState
---@field focused    boolean
---@field shown      string[]
---@field read       table<string, integer>
---@field open?      fun(terminal: string): HerdrCoreOpenEffect
---@field listed?    boolean                                    Whether the terminal list from the core has arrived.
---@field restored?  boolean                                    Whether the saved layout has been restored with that list.
---@field sidebar?   HerdrCoreSidebarState
---@field setup      HerdrCoreSetupState
---@field resuming   table<string, true>                        Terminals already asked to resume.
---@field resumable? HerdrCoreResumable
---@field auto_cd?   boolean
---@field resources  HerdrCoreResource[]                        What the sidebar lists, in order.
---@field items      HerdrCoreListed                            What the resources' monitors notified.
---@field monitored  HerdrCoreWanted                            The elements monitors were last asked to be armed for.
---@field front?     string                                     The terminal in front in the current tabpage.

-- What monitors notified, each list for one resource under one element.
---@class HerdrCoreItemsListed
---@field type  'items_listed'
---@field lists { resource: string, parent: string, items: HerdrCoreElement[] } []

---@class HerdrCoreKeyPressed
---@field type     'key_pressed'
---@field resource string
---@field key      string
---@field item     HerdrCoreItem
---@field parent?  HerdrCoreElement

-- An action chosen from the menu of an item.
---@class HerdrCoreActionChosen
---@field type     'action_chosen'
---@field resource string
---@field action   string
---@field item     HerdrCoreItem
---@field parent?  HerdrCoreElement

-- Monitors to arm with the element they list under, and monitors to disarm.
---@class HerdrCoreSyncMonitors
---@field type   'sync_monitors'
---@field arm    { resource: string, key: string, monitor: (fun(): HerdrCoreMonitor), parent?: HerdrCoreElement } []
---@field disarm { resource: string, key: string } []

---@class HerdrCoreNewTerminalRequested
---@field type             'new_terminal_requested'
---@field placement        'tab' | 'vertical' | 'horizontal'
---@field tab              string
---@field space_root?      string
---@field terminal_folder? string
---@field editor_folder    string

---@class HerdrCoreUnreadRequested
---@field type     'unread_requested'
---@field terminal string

---@class HerdrCoreStateOptions
---@field open?      fun(terminal: string): HerdrCoreOpenEffect
---@field resumable? HerdrCoreResumable
---@field resources? HerdrCoreResource[]
---@field auto_cd?   boolean                                    Whether Neovim's cwd moves to the space of the terminal that comes to the front.

---@class HerdrCoreTerminalChosen
---@field type     'terminal_chosen'
---@field terminal string
---@field windows  table<string, string>

---@alias HerdrCoreEvent HerdrCoreSetupChecked | HerdrCoreSetupRequested | HerdrCoreSetupResult | HerdrCoreSetupDismissed | HerdrCoreSidebarRequested | HerdrCoreUnreadRequested | HerdrCoreNewTerminalRequested | HerdrCoreItemsListed | HerdrCoreKeyPressed | HerdrCoreActionChosen | HerdrCoreTerminalChosen | HerdrCoreFocusChanged | HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged | HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict
---@alias HerdrCoreEffect HerdrCoreResumeEffect | HerdrCoreInstallEffect | HerdrCoreSidebarEffect | HerdrCoreSetLabel | HerdrCoreSpaceEffect | HerdrCoreLayoutEffect | HerdrCoreOpenEffect | HerdrCoreNotify | HerdrCoreRunShell | HerdrCoreSyncMonitors | HerdrCoreRunAction | HerdrCoreChangeCwd

---@class HerdrCoreUnknownEvent
---@field type 'unknown'

---@class HerdrCoreFocusChanged
---@field type      'focus_changed'
---@field focused   boolean
---@field terminals string[]
---@field front?    string          The terminal in front in the current tabpage.
---@field cwd?      string          Neovim's global cwd.

-- Moves Neovim's global cwd.
---@class HerdrCoreChangeCwd
---@field type   'change_cwd'
---@field folder string

---@param options? HerdrCoreStateOptions
---@return HerdrCoreState
function M.new(options)
    return {
        terminals = {},
        spaces = spaces.new(),
        layout = layout.new(),
        focused = true,
        shown = {},
        read = {},
        setup = setup.new(),
        resuming = {},
        open = options and options.open,
        resumable = options and options.resumable,
        auto_cd = options and options.auto_cd,
        resources = options and options.resources or { { name = "terminals" } },
        items = {},
        monitored = {}
    }
end

---@param state   HerdrCoreState
---@param changes table
---@return HerdrCoreState
local function with(state, changes)
    return vim.tbl_extend("force", state, changes) --[[@as HerdrCoreState]]
end

---@param state HerdrCoreState
---@param event HerdrCoreSetupChecked | HerdrCoreSetupRequested | HerdrCoreSetupResult | HerdrCoreSetupDismissed | HerdrCoreSidebarRequested | HerdrCoreUnreadRequested | HerdrCoreNewTerminalRequested | HerdrCoreItemsListed | HerdrCoreKeyPressed | HerdrCoreActionChosen | HerdrCoreTerminalChosen | HerdrCoreFocusChanged | HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged | HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict | HerdrCoreUnknownEvent
---@return HerdrCoreState, HerdrCoreEffect[]
local function step(state, event)
    if event.type == "setup_checked" or event.type == "setup_requested"
        or event.type == "setup_result" or event.type == "setup_dismissed" then
        local next_setup, effects = setup.update(state.setup, event)
        return with(state, { setup = next_setup }), effects
    end
    if event.type == "sidebar_requested" then
        return state, { { type = "sidebar", action = event.action } }
    end
    if event.type == "unread_requested" then
        ---@type HerdrCoreTerminal?
        local terminal = state.terminals[event.terminal]
        return state, terminal and attention.unread(terminal) or {}
    end
    if event.type == "new_terminal_requested" then
        local context = {
            space_root = event.space_root,
            terminal_folder = event.terminal_folder,
            editor_folder = event.editor_folder
        }
        return state, { open.new_terminal(context, event.placement, event.tab) }
    end
    if event.type == "items_listed" then
        local items = state.items
        for _, list in ipairs(event.lists) do
            local theirs = vim.tbl_extend("force", items[list.resource] or {}, { [list.parent] = list.items })
            items = vim.tbl_extend("force", items, { [list.resource] = theirs })
        end
        return with(state, { items = items }), {}
    end
    if event.type == "key_pressed" or event.type == "action_chosen" then
        return state, sidebar.press(state.resources, event)
    end
    if event.type == "terminal_chosen" then
        return state, { open.choose(event.terminal, event.windows, state.open) }
    end
    if event.type == "focus_changed" then
        local read, effects = state.read, {}
        for _, address in ipairs(event.terminals) do
            ---@type HerdrCoreTerminal?
            local shown = state.terminals[address]
            if shown then
                local marks
                read, marks = attention.observe(read, shown, event.focused, true)
                vim.list_extend(effects, marks)
            end
        end
        -- Each time a terminal comes to the front, Neovim's cwd moves to its space. Another machine's folders
        -- are not on this one.
        ---@type HerdrCoreTerminal?
        local front = event.front and event.front ~= state.front and state.terminals[event.front] or nil
        if state.auto_cd and front and not front.machine then
            local folder = front.labels["herdr.space"] or front.folder
            if folder ~= event.cwd then
                effects[#effects + 1] = { type = "change_cwd", folder = folder }
            end
        end
        local focused = with(state, { focused = event.focused, shown = event.terminals, read = read })
        -- Set apart: a nil in the changes would leave the terminal that was in front before.
        focused.front = event.front
        return focused, effects
    end
    if event.type == "layout_loaded" or event.type == "layout_changed" or event.type == "layout_conflict" then
        -- Only the startup restore drops unknown terminals: a later load can name a terminal whose start event is still on its way.
        local restoring = event.type == "layout_loaded" and state.listed and not state.restored
        local loaded = restoring and vim.tbl_extend("force", event, { live = state.terminals }) --[[@as HerdrCoreLayoutLoaded]] or event
        local next_layout, effects = layout.update(state.layout, loaded)
        return with(state, { layout = next_layout, restored = state.restored or restoring }), effects
    end
    if event.type == "status_changed" or event.type == "turn_changed" or event.type == "labels_changed"
        or event.type == "terminal_named" or event.type == "terminal_pinned" then
        local next_terminals, effects = terminals.update(state.terminals, event)
        ---@type HerdrCoreTerminal?, HerdrCoreTerminal?
        local before, after = state.terminals[event.terminal], next_terminals[event.terminal]
        local read = state.read
        if before and after then
            local visible = vim.tbl_contains(state.shown, event.terminal)
            -- shortcut: each Neovim notifies on its own, so two open Neovims notify twice; coordinate through the core if that bothers.
            local child = terminals.is_child(next_terminals, after)
            local notify = attention.notification(before, after, state.focused, visible, child)
            if notify then table.insert(effects, notify) end
            -- A terminal in front of the user is seen again each time its turn ends.
            local marks
            read, marks = attention.observe(read, after, state.focused, visible)
            vim.list_extend(effects, marks)
        end
        local resuming = state.resuming
        -- A cleared conversation may be resumed again after a later loss.
        if after and (after.labels["herdr-core-nvim.session"] or "") == "" and resuming[event.terminal] then
            resuming = vim.deepcopy(resuming)
            resuming[event.terminal] = nil
        end
        return with(state, { terminals = next_terminals, read = read, resuming = resuming }), effects
    end
    if event.type == "repo_root_found" then
        ---@type HerdrCoreTerminal?
        local terminal = state.terminals[event.terminal]
        if not terminal or terminal.folder ~= event.folder then return state, {} end
        local next_spaces, effects = spaces.update(state.spaces, {
            type = "repo_root_found",
            terminal = event.terminal,
            folder = event.folder,
            root = event.root,
            space = terminal.labels["herdr.space"]
        })
        return with(state, { terminals = state.terminals, spaces = next_spaces, layout = state.layout }), effects
    end
    if event.type == "terminals_listed" then
        local next_terminals = terminals.update(state.terminals, event)
        ---@type HerdrCoreEffect[]
        local effects = {}
        for _, terminal in ipairs(event.terminals) do
            local _, requested = spaces.update(state.spaces, {
                type = "folder_changed",
                terminal = terminal.address,
                folder = terminal.folder,
                machine = terminal.machine
            })
            for _, effect in ipairs(requested) do
                effects[#effects + 1] = effect
            end
        end
        local resuming, resumes = resume.find(event.terminals, state.resuming, state.resumable)
        vim.list_extend(effects, resumes)
        return with(state, { terminals = next_terminals, listed = true, resuming = resuming }), effects
    end
    if event.type == "foreground_changed" then
        local next_terminals = terminals.update(state.terminals, event)
        ---@type HerdrCoreTerminal?
        local terminal = next_terminals[event.terminal]
        if not terminal then return state, {} end
        local before = state.terminals[event.terminal]
        if not event.folder or (before and before.folder == event.folder) then
            return with(state, { terminals = next_terminals, spaces = state.spaces, layout = state.layout }), {}
        end
        local next_spaces, effects = spaces.update(state.spaces, {
            type = "folder_changed",
            terminal = event.terminal,
            folder = event.folder,
            machine = terminal.machine
        })
        return with(state, { terminals = next_terminals, spaces = next_spaces, layout = state.layout }), effects
    end
    if event.type == "terminal_ended" then
        local next_terminals = terminals.update(state.terminals, event)
        local next_spaces = spaces.update(state.spaces, event)
        local next_layout, effects = layout.update(state.layout, event)
        return with(state, { terminals = next_terminals, spaces = next_spaces, layout = next_layout }), effects
    end
    if event.type == "terminal_started" then
        local updated = terminals.update(state.terminals, event)
        local next_spaces, effects = spaces.update(state.spaces, {
            type = "folder_changed",
            terminal = event.terminal.address,
            folder = event.terminal.folder,
            machine = event.terminal.machine
        })
        local resuming, resumes = resume.find({ event.terminal }, state.resuming, state.resumable)
        vim.list_extend(effects, resumes)
        return with(state, { terminals = updated, spaces = next_spaces, layout = state.layout, resuming = resuming }),
            effects
    end
    return state, {}
end

-- What the sidebar is built from.
---@param state HerdrCoreState
---@return HerdrCoreSidebarOptions
local function listing(state)
    return { resources = state.resources, items = state.items, front = state.front }
end

-- Keeps the monitors on the elements they are wanted for: asks to arm one where an element is new or has
-- changed and to disarm one where it is gone, and drops what was listed under elements that are gone.
---@param state HerdrCoreState
---@return HerdrCoreState, HerdrCoreSyncMonitors[]
local function monitors(state)
    local watched = vim.tbl_filter(function (resource) return resource.monitor ~= nil end, state.resources)
    if #watched == 0 then return state, {} end
    ---@type HerdrCoreSyncMonitors
    local sync = { type = "sync_monitors", arm = {}, disarm = {} }
    -- Dropping what was listed under an element takes away the elements listed there, so look again after it.
    local dropped = true
    while dropped do
        dropped = false
        local _, _, wanted = sidebar.update(state.sidebar, vim.tbl_values(state.terminals), listing(state))
        local items = state.items
        for _, resource in ipairs(watched) do
            local name = resource.name
            local now, before = wanted[name] or {}, state.monitored[name] or {}
            local keys = vim.tbl_keys(now)
            table.sort(keys)
            for _, key in ipairs(keys) do
                if before[key] == nil or not vim.deep_equal(before[key], now[key]) then
                    sync.arm[#sync.arm + 1] = {
                        resource = name,
                        key = key,
                        monitor = assert(resource.monitor),
                        parent = now[key] or nil
                    }
                end
            end
            local gone = vim.tbl_filter(function (key) return now[key] == nil end, vim.tbl_keys(before))
            table.sort(gone)
            for _, key in ipairs(gone) do
                sync.disarm[#sync.disarm + 1] = { resource = name, key = key }
            end
            local kept = vim.tbl_extend("force", {}, items[name] or {})
            for key in pairs(items[name] or {}) do
                if now[key] == nil then
                    kept[key] = nil
                    dropped = true
                end
            end
            items = vim.tbl_extend("force", items, { [name] = kept })
        end
        state = with(state, { monitored = wanted, items = dropped and items or state.items })
    end
    if #sync.arm == 0 and #sync.disarm == 0 then return state, {} end
    return state, { sync }
end

---@param state HerdrCoreState
---@param event HerdrCoreEvent | HerdrCoreUnknownEvent
---@return HerdrCoreState, HerdrCoreEffect[]
function M.update(state, event)
    local stepped, effects = step(state, event)
    local synced, sync = monitors(stepped)
    if #sync == 0 then return synced, effects end
    return synced, vim.list_extend(vim.list_extend({}, effects), sync)
end

---@param state HerdrCoreState
---@return HerdrCoreState, HerdrCoreSidebarRow[], integer
function M.view(state)
    local order, rows, _, waiting = sidebar.update(state.sidebar, vim.tbl_values(state.terminals), listing(state))
    vim.list_extend(rows, setup.view(state.setup))
    return with(state, { sidebar = order }), rows, waiting
end

return M
