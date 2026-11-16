local MiniTest = require("mini.test")
local input = vim.ui.input
local T = MiniTest.new_set({ hooks = { post_case = function () vim.ui.input = input end } })

T["returns the entered terminal name"] = function ()
    -- Given an input UI where the user enters a name
    ---@param options  table?
    ---@param callback fun(value: string?)
    vim.ui.input = function (options, callback)
        MiniTest.expect.equality(assert(options).default, "old")
        callback("build")
    end
    ---@type string?
    local result
    -- When a name is requested
    require("herdr-core.ui.prompt").name("old", function (value) result = value end)
    -- Then the entered value is returned
    MiniTest.expect.equality(result, "build")
end

T["reports cancellation without turning it into an empty name"] = function ()
    -- Given a user cancelling the input UI
    ---@param callback fun(value: string?)
    vim.ui.input = function (_, callback) callback(nil) end
    local called = false
    ---@type string?
    local result = "unchanged"
    -- When a name is requested
    require("herdr-core.ui.prompt").name("old", function (value)
        called = true
        result = value
    end)
    -- Then nil signals cancellation
    MiniTest.expect.equality(called, true)
    MiniTest.expect.equality(result, nil)
end

T["returns an empty name so the caller can clear it"] = function ()
    -- Given a user submitting an empty input
    ---@param callback fun(value: string?)
    vim.ui.input = function (_, callback) callback("") end
    ---@type string?
    local result
    -- When a name is requested
    require("herdr-core.ui.prompt").name("old", function (value) result = value end)
    -- Then empty text remains distinct from cancellation
    MiniTest.expect.equality(result, "")
end

---@type HerdrCoreChoice[]
local places = {
    { label = "/work/app", path = "/work/app" }, { label = "~", path = "/home/takag" },
    { label = "/work/api", path = "/work/api" }
}

---@param keys string
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

T["lists the items in a centered floating window with the cursor row selected"] = function ()
    -- Given an editor 100 columns by 30 lines
    vim.o.columns, vim.o.lines = 100, 30
    -- When the user is asked to choose a place
    require("herdr-core.ui.prompt").choose(places, { prompt = "New terminal" }, function () end)
    local window = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(window)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local highlight = vim.wo[window].winhighlight
    local cursorline = vim.wo[window].cursorline
    press("<Esc>")
    -- Then each item has a row, the window sits in the middle, and the cursor row takes the selection color
    MiniTest.expect.equality(config.relative, "editor")
    MiniTest.expect.equality(
        assert(lines[1]):find("app", 1, true) ~= nil and assert(lines[3]):find("/work/api", 1, true) ~= nil, true
    )
    local middle = assert(config.col) + assert(config.width) / 2
    MiniTest.expect.equality(math.abs(middle - 50) <= 2, true)
    MiniTest.expect.equality(cursorline, true)
    MiniTest.expect.equality(highlight:find("CursorLine:HerdrCoreSelected", 1, true) ~= nil, true)
end

T["returns the item chosen with Enter or a click"] = function ()
    -- Given the list of places
    local chosen = {}
    local prompt = require("herdr-core.ui.prompt")
    -- When the user moves down and presses Enter, then clicks the third row
    prompt.choose(places, {}, function (item) chosen[#chosen + 1] = item end)
    press("j<CR>")
    prompt.choose(places, {}, function (item) chosen[#chosen + 1] = item end)
    local window = vim.api.nvim_get_current_win()
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function () return { winid = window, line = 3, column = 2 } end
    vim.fn.maparg("<LeftRelease>", "n", false, true).callback()
    vim.fn.getmousepos = getmousepos
    -- Then each returns its item
    MiniTest.expect.equality(chosen, { places[2], places[3] })
end

T["returns nil when the user closes or leaves the list"] = function ()
    -- Given the list of places opened three times
    local results = {}
    local prompt = require("herdr-core.ui.prompt")
    local editor = vim.api.nvim_get_current_win()
    -- When it is closed with Esc, with q, and by moving to another window
    for _, close in ipairs({
        function () press("<Esc>") end,
        function () press("q") end,
        function () vim.api.nvim_set_current_win(editor) end
    }) do
        prompt.choose(places, {}, function (item) results[#results + 1] = item or false end)
        close()
    end
    -- Then each reports no choice, and no list is left open
    MiniTest.expect.equality(results, { false, false, false })
    MiniTest.expect.equality(#vim.api.nvim_list_wins(), 1)
end

T["shortens items wider than the editor from the left"] = function ()
    -- Given an editor 50 columns wide and a path longer than that
    vim.o.columns, vim.o.lines = 50, 12
    local long = "~/Codes/very/long/path/to/some/deeply/nested/project/folder"
    -- When the user is asked to choose
    local prompt = require("herdr-core.ui.prompt")
    local items = { { label = long, path = long }, { label = "~", path = "~" } }
    prompt.choose(items, {}, function () end)
    local window = vim.api.nvim_get_current_win()
    local width = vim.api.nvim_win_get_width(window)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local wrap = vim.wo[window].wrap
    press("<Esc>")
    -- Then the window fits the editor, the path keeps its end after an ellipsis, and nothing wraps
    MiniTest.expect.equality(width <= 48, true)
    MiniTest.expect.equality(vim.fn.strdisplaywidth(assert(lines[1])) <= width, true)
    MiniTest.expect.equality(assert(lines[1]):match("^ ….*project/folder $") ~= nil, true)
    MiniTest.expect.equality({ lines[2], wrap }, { " ~ ", false })
end

return T
