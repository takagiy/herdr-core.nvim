local M = {}

---@class HerdrCoreActions
---@field new_tab        fun()
---@field new_vertical   fun()
---@field new_horizontal fun()
---@field toggle_sidebar fun()
---@field focus_sidebar  fun()

---@param dispatch   fun(event: table)
---@param context    fun(): HerdrCoreOpenContext
---@param identifier fun(): string
---@return HerdrCoreActions
function M.new(dispatch, context, identifier)
    ---@param placement 'tab' | 'vertical' | 'horizontal'
    local function request(placement)
        local event = context()
        dispatch({
            type = "new_terminal_requested",
            placement = placement,
            tab = identifier(),
            editor_folder = event.editor_folder,
            terminal_folder = event.terminal_folder,
            space_root = event.space_root
        })
    end
    return {
        new_tab = function () request("tab") end,
        new_vertical = function () request("vertical") end,
        new_horizontal = function () request("horizontal") end,
        toggle_sidebar = function () dispatch({ type = "sidebar_requested", action = "toggle" }) end,
        focus_sidebar = function () dispatch({ type = "sidebar_requested", action = "focus" }) end
    }
end

return M
