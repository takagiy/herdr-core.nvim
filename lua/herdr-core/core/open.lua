local M = {}

---@class HerdrCoreFocusWindow
---@field type   'focus_window'
---@field window string

---@class HerdrCoreShowTerminal
---@field type      'show_terminal'
---@field terminal  string
---@field placement 'tab' | 'vertical' | 'horizontal'

---@alias HerdrCoreOpenEffect HerdrCoreFocusWindow | HerdrCoreShowTerminal

---@param terminal string
---@param windows  table<string, string>
---@param policy?  fun(terminal: string): HerdrCoreOpenEffect
---@return HerdrCoreOpenEffect
function M.choose(terminal, windows, policy)
    ---@type string?
    local window = windows[terminal]
    if window then
        return { type = "focus_window", window = window }
    end
    if policy then
        return policy(terminal)
    end
    return { type = "show_terminal", terminal = terminal, placement = "tab" }
end

---@class HerdrCoreOpenContext
---@field space_root      string?
---@field terminal_folder string?
---@field editor_folder   string

---@class HerdrCoreRunShell
---@field type      'run_shell'
---@field folder    string
---@field placement 'tab' | 'vertical' | 'horizontal'
---@field labels    table<string, string>

---@param context   HerdrCoreOpenContext
---@param placement 'tab' | 'vertical' | 'horizontal'
---@param tab       string
---@return HerdrCoreRunShell
function M.new_terminal(context, placement, tab)
    return {
        type = "run_shell",
        folder = context.space_root or context.terminal_folder or context.editor_folder,
        placement = placement,
        labels = {
            ["herdr.tab"] = tab,
            ["herdr.seen"] = "0"
        }
    }
end

return M
