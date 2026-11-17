local M = {}

---@param argv     string[]
---@param callback fun(value: table?, err: string?)
---@param stdin?   string
local function request(argv, callback, stdin)
    local started, failure = pcall(vim.system, argv, { text = true, stdin = stdin, timeout = 30000 }, function (result)
        if result.code ~= 0 then
            callback(nil, result.stderr or "hc failed")
            return
        end
        local ok, value = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
        if not ok or type(value) ~= "table" then
            callback(nil, "Invalid hc JSON response")
            return
        end
        callback(value, nil)
    end)
    if not started then callback(nil, tostring(failure)) end
end

---@param method   string
---@param params   table
---@param callback fun(value: table?, err: string?, kind: string?)
local function rpc(method, params, callback)
    local input = vim.json.encode({ jsonrpc = "2.0", id = 1, method = method, params = params }) .. "\n"
    local pending, answered = "", false
    ---@type vim.SystemObj?
    local process
    ---@param value table?
    ---@param err   string?
    ---@param kind  string?
    local function answer(value, err, kind)
        if answered then return end
        answered = true
        -- On Windows hc connect stays open after the reply, so stop it here.
        if process then process:kill(15) end
        callback(value, err, kind)
    end
    local started, failure = pcall(
        vim.system, { "hc", "connect" },
        {
            text = true,
            -- Left open: on Windows, hc connect can exit without the reply once stdin closes.
            stdin = true,
            timeout = 30000,
            stdout = function (err, chunk)
                if answered then return end
                if err then return answer(nil, err) end
                pending = pending .. (chunk or "")
                local line = pending:match("^(.-)\n")
                if not line then return end
                local ok, response = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
                if not ok or type(response) ~= "table" then return answer(nil, "Invalid hc JSON response") end
                if response.error then
                    local problem = response.error
                    return answer(nil, tostring(problem.message), problem.data and problem.data.kind)
                end
                if response.id ~= 1 or type(response.result) ~= "table" then
                    return answer(nil, "Invalid hc RPC response")
                end
                answer(response.result)
            end
        },
        function (result)
            answer(nil, result.stderr ~= "" and result.stderr or "hc connect closed without a reply")
        end
    )
    if not started then
        answer(nil, tostring(failure))
        return
    end
    process = failure --[[@as vim.SystemObj]]
    process:write(input)
end

---@class HerdrCoreRunOptions
---@field folder string
---@field name?  string
---@field labels table<string, string>
---@field argv?  string[]

---@param value any
---@return integer
local function integer(value)
    assert(type(value) == "number" and value >= 0 and value % 1 == 0, "Invalid hc nonnegative integer")
    return math.floor(value)
end

-- hc gives a terminal's start folder with slashes and its foreground folder with backslashes on Windows.
---@param path string
---@return string
local function folder(path)
    return vim.fs.normalize(path, { expand_env = false })
end

---@param record table
---@return HerdrCoreTerminal
local function terminal(record)
    assert(type(record.address) == "string" and type(record.cwd) == "string", "Invalid hc terminal address or cwd")
    assert(type(record.labels) == "table" and type(record.created_ms) == "number", "Invalid hc terminal labels or time")
    for key, value in pairs(record.labels) do
        assert(type(key) == "string" and type(value) == "string", "Invalid hc label")
    end
    local foreground = record.foreground
    if foreground then
        assert(
            type(foreground) == "table" and type(foreground.cwd) == "string" and type(foreground.name) == "string",
            "Invalid hc foreground"
        )
    end
    local argv = foreground and foreground.argv or record.argv
    if record.status then
        assert(type(record.status) == "table" and type(record.status.state) == "string", "Invalid hc status")
    end
    assert(record.name == nil or type(record.name) == "string", "Invalid hc terminal name")
    assert(record.parent == nil or type(record.parent) == "string", "Invalid hc parent")
    assert(argv == nil or (type(argv) == "table" and vim.islist(argv)), "Invalid hc argv")
    for _, argument in ipairs(argv or {}) do
        assert(type(argument) == "string", "Invalid hc argv item")
    end
    local machine = record.address:match("^([^/]+)/")
    local parent = record.parent
    -- A remote core names the parent on its own machine.
    if parent and machine and not parent:find("/", 1, true) then parent = machine .. "/" .. parent end
    return {
        address = record.address,
        machine = machine,
        parent = parent,
        name = record.name,
        folder = folder(foreground and foreground.cwd or record.cwd),
        program = foreground and foreground.name or (record.argv and record.argv[1]),
        labels = record.labels,
        argv = argv,
        status = record.status and record.status.state,
        app = record.status and record.status.app ~= "" and record.status.app or nil,
        turn = integer(record.turn or 0),
        created_ms = integer(record.created_ms),
        status_ms = record.status_ms and integer(record.status_ms) or nil
    }
end

---@param value table
---@return HerdrCoreTerminalsListed
local function listed(value)
    assert(type(value.terminals) == "table" and vim.islist(value.terminals), "Invalid hc terminal list")
    local items = {}
    for _, record in ipairs(value.terminals) do
        if record.state ~= "finished" then items[#items + 1] = terminal(record) end
    end
    return { type = "terminals_listed", terminals = items }
end

---@param callback fun(event: HerdrCoreTerminalsListed?, err: string?)
function M.list(callback)
    request({ "hc", "ls", "--json" }, function (value, err)
        if not value then
            callback(nil, err)
            return
        end
        local ok, event = pcall(listed, value)
        if not ok then
            callback(nil, tostring(event))
            return
        end
        callback(event, nil)
    end)
end

-- Agents read these to tell whether they run inside another agent. A core started from an agent passes them
-- to every terminal, so a new terminal clears them, like Herdr TUI does for its panes.
local inherited = {
    "CODEX_THREAD_ID", "OMPCODE", "CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_MESSAGING_TOKEN"
}

-- Terminals the plugin opens are kept: after a lost program or a reboot, hc gives them a shell in place.
---@param options  HerdrCoreRunOptions
---@param callback fun(address: string?, err: string?)
function M.run(options, callback)
    local env = {}
    for _, key in ipairs(inherited) do
        env[key] = ""
    end
    local params = {
        argv = options.argv or {},
        cwd = options.folder,
        env = env,
        labels = next(options.labels) and options.labels or vim.empty_dict(),
        keep = true
    }
    if options.name then params.name = options.name end
    rpc("terminal.run", params, function (result, err)
        if not result then
            callback(nil, err)
        elseif type(result.address) ~= "string" then
            callback(nil, "hc run returned no address")
        else
            callback(result.address, nil)
        end
    end)
end

---@param address  string
---@param text     string
---@param callback fun(err: string?)
function M.send(address, text, callback)
    request({ "hc", "send", "--json", address, text }, function (_, err) callback(err) end)
end

---@param address  string
---@param labels   table<string, string>
---@param callback fun(err: string?)
function M.labels(address, labels, callback)
    local argv = { "hc", "label", "--json", address }
    local keys = vim.tbl_keys(labels)
    table.sort(keys)
    for _, key in ipairs(keys) do
        argv[#argv + 1] = key .. "=" .. labels[key]
    end
    request(argv, function (_, err) callback(err) end)
end

---@param address string
---@return string[]
function M.attach(address)
    return { "hc", "attach", address }
end

---@param address  string
---@param key      string
---@param value    string
---@param callback fun(err: string?)
function M.label(address, key, value, callback)
    request({ "hc", "label", "--json", address, key .. "=" .. value }, function (_, err) callback(err) end)
end

---@param node table
---@param ids  table<string, boolean>
local function check_node(node, ids)
    assert(
        type(node) == "table" and type(node.id) == "string" and not ids[node.id],
        "Invalid or duplicate layout window id"
    )
    ids[node.id] = true
    if node.kind == "terminal" then
        assert(type(node.terminal) == "string", "Invalid layout terminal")
        return
    end
    assert(node.kind == "split" and (node.axis == "row" or node.axis == "column"), "Invalid layout split")
    assert(
        type(node.children) == "table" and vim.islist(node.children) and #node.children >= 2, "Invalid layout children"
    )
    for _, child in ipairs(node.children) do
        check_node(child, ids)
    end
end

-- Broken tabs are dropped, so one of them does not keep the others from being restored.
---@param value table
---@return HerdrCoreLayoutValue
local function check_layout(value)
    assert(type(value) == "table" and type(value.tabs) == "table" and vim.islist(value.tabs), "Invalid layout tabs")
    local ids, tabs = {}, {}
    for _, tab in ipairs(value.tabs) do
        if type(tab) == "table" and type(tab.id) == "string" and not ids[tab.id] and pcall(check_node, tab.root, {}) then
            ids[tab.id] = true
            tabs[#tabs + 1] = tab
        end
    end
    return vim.tbl_extend("force", value, { tabs = tabs }) --[[@as HerdrCoreLayoutValue]]
end

---@param callback fun(event: HerdrCoreLayoutLoaded?, err: string?)
function M.read_layout(callback)
    rpc("doc.get", { name = "herdr-core-nvim" }, function (result, err)
        if not result then
            callback(nil, err)
            return
        end
        local ok, version = pcall(integer, result.version)
        if not ok then
            callback(nil, tostring(version))
            return
        end
        local value = result.value
        if value then
            local valid, checked = pcall(check_layout, value)
            if not valid then
                callback(nil, tostring(checked))
                return
            end
            value = checked
        end
        callback({ type = "layout_loaded", value = value, version = version }, nil)
    end)
end

---@param value    HerdrCoreLayoutValue
---@param version  integer
---@param callback fun(event: HerdrCoreLayoutLoaded | HerdrCoreLayoutConflict?, err: string?)
function M.save_layout(value, version, callback)
    rpc("doc.set", { name = "herdr-core-nvim", value = value, version = version }, function (result, err, kind)
        if kind == "conflict" then
            M.read_layout(function (latest, failure)
                if not latest then
                    callback(nil, failure)
                    return
                end
                callback(
                    { type = "layout_conflict", value = latest.value or { tabs = {} }, version = latest.version }, nil
                )
            end)
            return
        end
        if not result then
            callback(nil, err)
            return
        end
        local ok, saved = pcall(integer, result.version)
        if not ok then
            callback(nil, tostring(saved))
            return
        end
        callback({ type = "layout_loaded", value = value, version = saved }, nil)
    end)
end

---@param message table
---@return HerdrCoreEvent?
local function fact(message)
    if message.method ~= "event" then return nil end
    local event = message.params
    assert(type(event) == "table" and type(event.terminal) == "string", "Invalid hc event")
    local data = event.data
    if event.type == "lost" then return {type = "foreground_changed", terminal = event.terminal} end
    if event.type == "created" or event.type == "restarted" then
        return { type = "terminal_started", terminal = terminal(data) }
    end
    if event.type == "turn" then
        assert(type(data) == "table", "Invalid hc turn event")
        return { type = "turn_changed", terminal = event.terminal, turn = integer(data.turn) }
    end
    if event.type == "finished" or event.type == "removed" then
        return { type = "terminal_ended", terminal = event.terminal }
    end
    if event.type == "status" then
        assert(type(data) == "table", "Invalid hc status event")
        local status = data.status
        assert(status == nil or (type(status) == "table" and type(status.state) == "string"), "Invalid hc status")
        return {
            type = "status_changed",
            terminal = event.terminal,
            status = status and status.state,
            app = status and status.app ~= "" and status.app or nil,
            status_ms = os.time() * 1000
        }
    end
    if event.type == "foreground" then
        if not data then return {type = "foreground_changed", terminal = event.terminal} end
        assert(
            type(data) == "table" and type(data.cwd) == "string" and type(data.name) == "string",
            "Invalid hc foreground"
        )
        return {
            type = "foreground_changed",
            terminal = event.terminal,
            folder = folder(data.cwd),
            program = data.name,
            argv = type(data.argv) == "table" and data.argv or nil
        }
    end
    if event.type == "labels" then
        assert(type(data) == "table" and type(data.labels) == "table", "Invalid hc labels")
        if data.record then
            if data.record.state == "finished" then return { type = "terminal_ended", terminal = event.terminal } end
            return { type = "terminal_started", terminal = terminal(data.record) }
        end
        for key, value in pairs(data.labels) do
            assert(type(key) == "string" and type(value) == "string", "Invalid hc label")
        end
        return { type = "labels_changed", terminal = event.terminal, labels = data.labels }
    end
    return nil
end

---@param callback   fun(event: HerdrCoreEvent?, err: string?)
---@param on_closed? fun()
---@return fun()
function M.watch(callback, on_closed)
    local pending = ""
    local active = true
    local sequence = -1
    local ok, process = pcall(
        vim.system, { "hc", "events", "--json" },
        {
            text = true,
            stdout = function (err, chunk)
                if not active then return end
                if err then
                    callback(nil, err)
                    return
                end
                if not chunk then return end
                pending = pending .. chunk
                while true do
                    local ending = pending:find("\n", 1, true)
                    if not ending then break end
                    local line = pending:sub(1, ending - 1)
                    pending = pending:sub(ending + 1)
                    local valid, event = pcall(function ()
                        local message = vim.json.decode(line, { luanil = { object = true, array = true } })
                        assert(type(message) == "table", "Invalid hc notification")
                        if message.terminals then
                            sequence = integer(message.seq)
                            callback(listed(message), nil)
                            M.read_layout(callback)
                            return nil
                        end
                        if type(message.params) == "table" and message.params.seq then
                            local seq = integer(message.params.seq)
                            if seq <= sequence then return nil end
                            sequence = seq
                        end
                        if message.method == "missed" then
                            callback(listed(message.params), nil)
                            M.read_layout(callback)
                            return nil
                        end
                        if message.method == "event" and type(message.params) == "table"
                            and message.params.type == "doc" then
                            local params = message.params
                            if not params.machine and type(params.data) == "table"
                                and params.data.name == "herdr-core-nvim" then
                                M.read_layout(callback)
                            end
                            return nil
                        end
                        return fact(message)
                    end)
                    if not valid then
                        callback(nil, tostring(event))
                    elseif event then
                        callback(event, nil)
                    end
                end
            end
        },
        function (result)
            if not active then return end
            callback(nil, result.stderr ~= "" and result.stderr or "hc event stream closed")
            if on_closed then on_closed() end
        end
    )
    if not ok then
        callback(nil, tostring(process))
        return function () end
    end
    return function ()
        if not active then return end
        active = false
        process:kill(15)
    end
end

return M
