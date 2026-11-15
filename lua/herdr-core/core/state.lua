local terminals = require("herdr-core.core.terminals")
local spaces = require("herdr-core.core.spaces")
local layout = require("herdr-core.core.layout")
local attention = require("herdr-core.core.attention")
local open = require("herdr-core.core.open")
local M = {}

---@class HerdrCoreState
---@field terminals HerdrCoreTerminals
---@field spaces    HerdrCoreSpaces
---@field layout    HerdrCoreLayoutState
---@field focused   boolean
---@field shown     string[]
---@field read      table<string, integer>
---@field open?     fun(terminal: string): HerdrCoreOpenEffect

---@class HerdrCoreStateOptions
---@field open? fun(terminal: string): HerdrCoreOpenEffect

---@class HerdrCoreTerminalChosen
---@field type     'terminal_chosen'
---@field terminal string
---@field windows  table<string, string>

---@alias HerdrCoreEvent HerdrCoreTerminalChosen | HerdrCoreFocusChanged | HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged | HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict
---@alias HerdrCoreEffect HerdrCoreSetLabel | HerdrCoreSpaceEffect | HerdrCoreLayoutEffect | HerdrCoreOpenEffect | HerdrCoreNotify | HerdrCoreRunShell

---@class HerdrCoreUnknownEvent
---@field type 'unknown'

---@class HerdrCoreFocusChanged
---@field type      'focus_changed'
---@field focused   boolean
---@field terminals string[]

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
        open = options and options.open
    }
end

---@param state   HerdrCoreState
---@param changes table
---@return HerdrCoreState
local function with(state, changes)
    return vim.tbl_extend("force", state, changes) --[[@as HerdrCoreState]]
end

---@param state HerdrCoreState
---@param event HerdrCoreTerminalChosen | HerdrCoreFocusChanged | HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged | HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict | HerdrCoreUnknownEvent
---@return HerdrCoreState, HerdrCoreEffect[]
function M.update(state, event)
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
        return with(state, { focused = event.focused, shown = event.terminals, read = read }), effects
    end
    if event.type == "layout_loaded" or event.type == "layout_changed" or event.type == "layout_conflict" then
        local next_layout, effects = layout.update(state.layout, event)
        return with(state, { terminals = state.terminals, spaces = state.spaces, layout = next_layout }), effects
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
            local notify = attention.notification(before, after, state.focused, visible)
            if notify then table.insert(effects, notify) end
            -- A terminal in front of the user is seen again each time its turn ends.
            local marks
            read, marks = attention.observe(read, after, state.focused, visible)
            vim.list_extend(effects, marks)
        end
        return with(state, { terminals = next_terminals, read = read }), effects
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
        return with(state, { terminals = next_terminals, spaces = state.spaces, layout = state.layout }), effects
    end
    if event.type == "foreground_changed" then
        local next_terminals = terminals.update(state.terminals, event)
        ---@type HerdrCoreTerminal?
        local terminal = next_terminals[event.terminal]
        if not terminal then return state, {} end
        if not event.folder then
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
        return with(state, { terminals = updated, spaces = next_spaces, layout = state.layout }), effects
    end
    return state, {}
end

return M
