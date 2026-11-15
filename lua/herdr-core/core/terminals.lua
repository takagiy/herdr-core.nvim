local M = {}

---@class HerdrCoreTerminal
---@field address    string
---@field machine    string?
---@field name       string?
---@field labels     table<string, string>
---@field status     string?
---@field turn       integer
---@field program    string?
---@field folder     string
---@field created_ms integer
---@field status_ms  integer?

---@class HerdrCoreStatusChanged
---@field type      'status_changed'
---@field terminal  string
---@field status    string?
---@field status_ms integer

---@alias HerdrCoreTerminals table<string, HerdrCoreTerminal>

---@class HerdrCoreTerminalsListed
---@field type      'terminals_listed'
---@field terminals HerdrCoreTerminal[]

---@class HerdrCoreTerminalStarted
---@field type     'terminal_started'
---@field terminal HerdrCoreTerminal

---@class HerdrCoreForegroundChanged
---@field type     'foreground_changed'
---@field terminal string
---@field program  string?
---@field folder   string?

---@class HerdrCoreLabelsChanged
---@field type     'labels_changed'
---@field terminal string
---@field labels   table<string, string>

---@class HerdrCoreTerminalNamed
---@field type     'terminal_named'
---@field terminal string
---@field name     string

---@class HerdrCoreSetLabel
---@field type     'set_label'
---@field terminal string
---@field key      string
---@field value    string

---@class HerdrCoreTerminalPinned
---@field type     'terminal_pinned'
---@field terminal string
---@field pinned   boolean

---@class HerdrCoreTurnChanged
---@field type     'turn_changed'
---@field terminal string
---@field turn     integer

---@param state HerdrCoreTerminals
---@param event HerdrCoreTerminalsListed | HerdrCoreTerminalStarted | HerdrCoreForegroundChanged | HerdrCoreStatusChanged | HerdrCoreLabelsChanged | HerdrCoreTerminalEnded | HerdrCoreTerminalNamed | HerdrCoreTerminalPinned | HerdrCoreTurnChanged
---@return HerdrCoreTerminals, HerdrCoreSetLabel[]
function M.update(state, event)
    if event.type == "terminal_pinned" then
        return state, {
                {
                    type = "set_label",
                    terminal = event.terminal,
                    key = "herdr.pinned",
                    value = event.pinned and "1" or ""
                }
            }
    end
    if event.type == "terminal_named" then
        return state, {
                {
                    type = "set_label",
                    terminal = event.terminal,
                    key = "herdr-core-nvim.name",
                    value = event.name
                }
            }
    end
    local updated = {}
    if event.type == "terminal_ended" then
        for address, terminal in pairs(state) do
            if address ~= event.terminal then
                updated[address] = terminal
            end
        end
        return updated, {}
    end
    if event.type == "foreground_changed" or event.type == "status_changed"
        or event.type == "labels_changed" or event.type == "turn_changed" then
        for address, terminal in pairs(state) do
            updated[address] = terminal
        end
        ---@type HerdrCoreTerminal?
        local current = state[event.terminal]
        if current then
            local terminal = {
                address = current.address,
                machine = current.machine,
                name = current.name,
                labels = current.labels,
                status = current.status,
                turn = current.turn,
                program = current.program,
                folder = current.folder,
                created_ms = current.created_ms,
                status_ms = current.status_ms
            }
            if event.type == "foreground_changed" then
                terminal.program = event.program
                terminal.folder = event.folder or current.folder
            elseif event.type == "status_changed" then
                terminal.status = event.status
                terminal.status_ms = event.status_ms
            elseif event.type == "labels_changed" then
                terminal.labels = event.labels
            else
                terminal.turn = event.turn
            end
            updated[event.terminal] = terminal
        end
        return updated, {}
    end
    if event.type == "terminal_started" then
        for address, terminal in pairs(state) do
            updated[address] = terminal
        end
        updated[event.terminal.address] = event.terminal
        return updated, {}
    end
    for _, terminal in ipairs(event.terminals) do
        updated[terminal.address] = terminal
    end
    return updated, {}
end

return M
