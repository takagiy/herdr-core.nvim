local M = {}
local counter = 0
local applying = false

---@return string
local function identifier()
    counter = counter + 1
    return vim.fn.getpid() .. "-" .. vim.fn.reltimestr(vim.fn.reltime()) .. "-" .. counter
end

---@param tree table
---@return HerdrCoreLayoutNode?
local function read_node(tree)
    if tree[1] == "leaf" then
        local window = tree[2]
        ---@type string?
        local address = vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address
        if not address then return nil end
        local id = vim.w[window].herdr_core_id or identifier()
        vim.w[window].herdr_core_id = id
        return { kind = "terminal", id = id, terminal = address }
    end
    ---@type HerdrCoreLayoutNode[]
    local children = {}
    for _, child in ipairs(tree[2]) do
        local node = read_node(child)
        if node then children[#children + 1] = node end
    end
    if #children == 0 then return nil end
    if #children == 1 then return children[1] end
    return {
        kind = "split",
        id = "split-" .. assert(children[1]).id,
        axis = tree[1] == "row" and "row" or "column",
        children = children
    }
end

---@return HerdrCoreLayoutValue
function M.read()
    local tabs = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local root = read_node(vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab)))
        if root then
            local id = vim.t[tab].herdr_core_id or identifier()
            vim.t[tab].herdr_core_id = id
            tabs[#tabs + 1] = { id = id, root = root }
        end
    end
    return { tabs = tabs }
end

---@param node HerdrCoreLayoutNode
---@return HerdrCoreLayoutNode
local function first_leaf(node)
    if node.kind == "terminal" then return node end
    return first_leaf(assert((node.children or {})[1]))
end

---@param value      HerdrCoreLayoutValue
---@param buffer_for fun(address: string): integer
local function show(value, buffer_for)
    ---@type table<string, table<string, boolean>>
    local wanted = {}
    ---@param node HerdrCoreLayoutNode
    ---@param ids  table<string, boolean>
    local function remember(node, ids)
        if node.kind == "terminal" then
            ids[node.id] = true
            return
        end
        for _, child in ipairs(node.children or {}) do
            remember(child, ids)
        end
    end
    for _, saved in ipairs(value.tabs) do
        wanted[saved.id] = {}
        remember(saved.root, wanted[saved.id])
        ---@type integer?
        local target
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
            if vim.t[tab].herdr_core_id == saved.id then
                target = tab
                break
            end
        end
        local existing_tab = target ~= nil
        if target then
            vim.api.nvim_set_current_tabpage(target)
        else
            vim.cmd.tabnew()
            target = vim.api.nvim_get_current_tabpage()
            vim.t[target].herdr_core_id = saved.id
        end
        ---@type table<string, integer>
        local windows = {}
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(target)) do
            local id = vim.w[window].herdr_core_id
            if id and vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address then windows[id] = window end
        end
        ---@param leaf   HerdrCoreLayoutNode
        ---@param anchor integer
        ---@param axis   'row' | 'column'
        ---@return integer
        local function place(leaf, anchor, axis)
            ---@type integer?
            local window = windows[leaf.id]
            if window then
                if window ~= anchor then vim.fn.win_splitmove(window, anchor, {vertical = axis == "row", rightbelow = true}) end
                return window
            end
            vim.api.nvim_set_current_win(anchor)
            vim.cmd(axis == "row" and "rightbelow vsplit" or "rightbelow split")
            window = vim.api.nvim_get_current_win()
            windows[leaf.id] = window
            return window
        end
        ---@param node   HerdrCoreLayoutNode
        ---@param anchor integer
        local function render(node, anchor)
            if node.kind == "terminal" then
                vim.api.nvim_win_set_buf(anchor, buffer_for(assert(node.terminal)))
                vim.w[anchor].herdr_core_id = node.id
                windows[node.id] = anchor
                return
            end
            local children = node.children or {}
            local anchors = { anchor }
            for index = 2, #children do
                anchors[index] = place(
                    first_leaf(assert(children[index])), assert(anchors[index - 1]), assert(node.axis)
                )
            end
            for index, child in ipairs(children) do
                render(child, assert(anchors[index]))
            end
        end
        local root_id = first_leaf(saved.root).id
        local anchor = windows[root_id] or vim.api.nvim_get_current_win()
        if existing_tab and not windows[root_id] then anchor = place(first_leaf(saved.root), anchor, "row") end
        render(saved.root, anchor)
        vim.cmd("tabmove $")
    end
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local ids = wanted[vim.t[tab].herdr_core_id] or {}
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            if vim.b[vim.api.nvim_win_get_buf(window)].herdr_core_address and not ids[vim.w[window].herdr_core_id] then
                if #vim.api.nvim_tabpage_list_wins(tab) > 1 then
                    vim.api.nvim_win_close(window, true)
                elseif #vim.api.nvim_list_tabpages() > 1 then
                    vim.api.nvim_set_current_tabpage(tab)
                    vim.cmd.tabclose()
                else
                    vim.api.nvim_win_set_buf(window, vim.api.nvim_create_buf(true, false))
                end
            end
        end
    end
end

---@param value      HerdrCoreLayoutValue
---@param buffer_for fun(address: string): integer
function M.show(value, buffer_for)
    applying = true
    local focused = vim.api.nvim_get_current_win()
    local ok, failure = pcall(show, value, buffer_for)
    if vim.api.nvim_win_is_valid(focused) then vim.api.nvim_set_current_win(focused) end
    applying = false
    if not ok then error(failure) end
end

---@param callback fun(value: HerdrCoreLayoutValue)
---@return fun()
function M.watch(callback)
    local active, queued = true, false
    local group = vim.api.nvim_create_augroup("HerdrCoreLayout", { clear = true })
    vim.api.nvim_create_autocmd({
        "WinNew",
        "WinClosed",
        "WinEnter",
        "BufWinEnter",
        "BufWinLeave",
        "TabNew",
        "TabClosed",
        "TabEnter"
    },
        {
            group = group,
            callback = function ()
                if applying or queued then return end
                queued = true
                vim.schedule(function ()
                    queued = false
                    if active then callback(M.read()) end
                end)
            end
        })
    return function ()
        active = false
        vim.api.nvim_del_augroup_by_id(group)
    end
end

return M
