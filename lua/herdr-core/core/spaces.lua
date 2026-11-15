local M = {}

---@alias HerdrCoreSpaces table<string, string>

---@class HerdrCoreRepoRootFound
---@field type     'repo_root_found'
---@field terminal string
---@field folder   string
---@field root     string?
---@field space    string?

---@class HerdrCoreFolderChanged
---@field type     'folder_changed'
---@field terminal string
---@field folder   string
---@field machine  string?

---@class HerdrCoreFindRepoRoot
---@field type     'find_repo_root'
---@field terminal string
---@field folder   string
---@field machine  string?

---@class HerdrCoreSetSpace
---@field type     'set_space'
---@field terminal string
---@field space    string

---@alias HerdrCoreSpaceEffect HerdrCoreFindRepoRoot | HerdrCoreSetSpace

---@class HerdrCoreTerminalEnded
---@field type     'terminal_ended'
---@field terminal string

---@return HerdrCoreSpaces
function M.new()
    return {}
end

---@param state HerdrCoreSpaces
---@param event HerdrCoreRepoRootFound | HerdrCoreFolderChanged | HerdrCoreTerminalEnded
---@return HerdrCoreSpaces, HerdrCoreSpaceEffect[]
function M.update(state, event)
    if event.type == "folder_changed" then
        return state, {
                {
                    type = "find_repo_root",
                    terminal = event.terminal,
                    folder = event.folder,
                    machine = event.machine
                }
            }
    end
    local updated = {}
    for terminal, space in pairs(state) do
        updated[terminal] = space
    end
    if event.type == "terminal_ended" then
        updated[event.terminal] = nil
        return updated, {}
    end
    local space = event.root or event.folder
    updated[event.terminal] = space
    if space == event.space then
        return updated, {}
    end
    return updated, { { type = "set_space", terminal = event.terminal, space = space } }
end

---@param state    HerdrCoreSpaces
---@param terminal string
---@return string?
function M.space_of(state, terminal)
    return state[terminal]
end

return M
