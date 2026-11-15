local terminals = require("herdr-core.core.terminals")
local spaces = require("herdr-core.core.spaces")
local layout = require("herdr-core.core.layout")
local M = {}

---@class HerdrCoreState
---@field terminals HerdrCoreTerminals
---@field spaces    HerdrCoreSpaces
---@field layout    HerdrCoreLayoutState

---@alias HerdrCoreEvent HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged | HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict
---@alias HerdrCoreEffect HerdrCoreSetLabel | HerdrCoreSpaceEffect | HerdrCoreLayoutEffect

---@class HerdrCoreUnknownEvent
---@field type 'unknown'

---@return HerdrCoreState
function M.new()
    return { terminals = {}, spaces = spaces.new(), layout = layout.new() }
end

---@param state HerdrCoreState
---@param event HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged | HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreLayoutLoaded | HerdrCoreLayoutChanged | HerdrCoreLayoutConflict | HerdrCoreUnknownEvent
---@return HerdrCoreState, HerdrCoreEffect[]
function M.update(state, event)
    if event.type == "layout_loaded" or event.type == "layout_changed" or event.type == "layout_conflict" then
        local next_layout, effects = layout.update(state.layout, event)
        return { terminals = state.terminals, spaces = state.spaces, layout = next_layout }, effects
    end
    if event.type == "status_changed" or event.type == "turn_changed" or event.type == "labels_changed"
        or event.type == "terminal_named" or event.type == "terminal_pinned" then
        local next_terminals, effects = terminals.update(state.terminals, event)
        return { terminals = next_terminals, spaces = state.spaces, layout = state.layout }, effects
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
        return { terminals = state.terminals, spaces = next_spaces, layout = state.layout }, effects
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
        return { terminals = next_terminals, spaces = state.spaces, layout = state.layout }, effects
    end
    if event.type == "foreground_changed" then
        local next_terminals = terminals.update(state.terminals, event)
        ---@type HerdrCoreTerminal?
        local terminal = next_terminals[event.terminal]
        if not terminal then return state, {} end
        if not event.folder then
            return { terminals = next_terminals, spaces = state.spaces, layout = state.layout }, {}
        end
        local next_spaces, effects = spaces.update(state.spaces, {
            type = "folder_changed",
            terminal = event.terminal,
            folder = event.folder,
            machine = terminal.machine
        })
        return { terminals = next_terminals, spaces = next_spaces, layout = state.layout }, effects
    end
    if event.type == "terminal_ended" then
        local next_terminals = terminals.update(state.terminals, event)
        local next_spaces = spaces.update(state.spaces, event)
        local next_layout, effects = layout.update(state.layout, event)
        return { terminals = next_terminals, spaces = next_spaces, layout = next_layout }, effects
    end
    if event.type == "terminal_started" then
        local updated = terminals.update(state.terminals, event)
        local next_spaces, effects = spaces.update(state.spaces, {
            type = "folder_changed",
            terminal = event.terminal.address,
            folder = event.terminal.folder,
            machine = event.terminal.machine
        })
        return { terminals = updated, spaces = next_spaces, layout = state.layout }, effects
    end
    return state, {}
end

return M
