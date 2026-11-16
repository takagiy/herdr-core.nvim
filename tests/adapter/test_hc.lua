local MiniTest = require("mini.test")
local system = vim.system
local T = MiniTest.new_set({ hooks = { post_case = function () vim.system = system end } })

---@param output string | string[]
---@param code?  integer
---@return string[][], table[]
local function fake_process(output, code)
    local calls = {}
    local options = {}
    ---@param argv      string[]
    ---@param _options  table?
    ---@param callback? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (argv, _options, callback)
        calls[#calls + 1] = argv
        options[#options + 1] = _options or {}
        local index = #options
        local body = type(output) == "string" and output or assert(output[#calls])
        local feed = options[index].stdout
        if type(feed) == "function" then feed(nil, body .. string.char(10)) end
        assert(callback)({ code = code or 0, signal = 0, stdout = body, stderr = code and "failed" or "" })
        -- hc connect gets its request through write(), not opts.stdin.
        ---@param _    vim.SystemObj
        ---@param data string
        local function write(_, data)
            options[index].stdin = data
        end
        return { kill = function () end, write = write } --[[@as vim.SystemObj]]
    end
    return calls, options
end

T["provides an attach argv without shell interpolation"] = function ()
    -- Given a terminal address
    local hc = require("herdr-core.adapter.hc")
    -- When the UI asks how to attach
    local argv = hc.attach("t1")
    -- Then it receives a direct process argv
    MiniTest.expect.equality(argv, { "hc", "attach", "t1" })
end

T["keeps a remote terminal address qualified when attaching"] = function ()
    -- Given a terminal on a named remote machine
    local hc = require("herdr-core.adapter.hc")
    -- When the UI requests its attach command
    local argv = hc.attach("server/t1")
    -- Then the machine and address remain one argument
    MiniTest.expect.equality(argv, { "hc", "attach", "server/t1" })
end

T["starts a kept terminal without agent identity variables"] = function ()
    -- Given hc answering terminal.run with a new address
    local calls, options = fake_process(vim.json.encode({ jsonrpc = "2.0", id = 1, result = { address = "t2" } }))
    ---@type string?
    local address
    -- When a program is started with a folder, name and labels
    require("herdr-core.adapter.hc").run({
        folder = "/project with spaces",
        name = "build",
        labels = { ["herdr.tab"] = "tab1" },
        argv = { "claude" }
    }, function (value) address = value end)
    -- Then hc keeps it and clears what would make agents think they run inside another agent
    local request = vim.json.decode(assert(options[1]).stdin)
    MiniTest.expect.equality(calls[1], { "hc", "connect" })
    MiniTest.expect.equality(request.method, "terminal.run")
    MiniTest.expect.equality(request.params.keep, true)
    MiniTest.expect.equality(request.params.argv, { "claude" })
    MiniTest.expect.equality(request.params.cwd, "/project with spaces")
    MiniTest.expect.equality(request.params.name, "build")
    MiniTest.expect.equality(request.params.labels, { ["herdr.tab"] = "tab1" })
    MiniTest.expect.equality(request.params.env.CODEX_THREAD_ID, "")
    MiniTest.expect.equality(request.params.env.CLAUDECODE, "")
    MiniTest.expect.equality(address, "t2")
end

T["types text into a terminal and sets several labels at once"] = function ()
    -- Given hc accepting commands
    local calls = fake_process("{}")
    local errors = {}
    local hc = require("herdr-core.adapter.hc")
    -- When a line is sent and two labels are set
    hc.send("t3", "codex resume abc", function (err) errors[#errors + 1] = err or false end)
    hc.labels("t3", { ["herdr-core-nvim.session"] = "", ["herdr-core-nvim.agent"] = "" }, function (err)
        errors[#errors + 1] = err or false
    end)
    -- Then each is one hc call with its own arguments
    MiniTest.expect.equality(calls, {
        { "hc", "send", "--json", "t3", "codex resume abc" },
        { "hc", "label", "--json", "t3", "herdr-core-nvim.agent=", "herdr-core-nvim.session=" }
    })
    MiniTest.expect.equality(errors, { false, false })
end

T["keeps the foreground arguments and the agent name for telling programs apart"] = function ()
    -- Given a terminal running node with a script, whose agent reported its own name
    fake_process(vim.json.encode({
            terminals = {
                {
                    address = "t1",
                    cwd = "/app",
                    foreground = { name = "node", cwd = "/app", argv = { "node", "/opt/gemini/gemini.js" } },
                    labels = {},
                    status = { state = "idle", app = "gemini" },
                    created_ms = 1
                }
            }
        }))
    ---@type HerdrCoreTerminalsListed?
    local event
    -- When the list is converted
    require("herdr-core.adapter.hc").list(function (value) event = value end)
    -- Then the terminal carries both
    local terminal = assert(assert(event).terminals[1])
    MiniTest.expect.equality({ terminal.argv, terminal.app }, { { "node", "/opt/gemini/gemini.js" }, "gemini" })
end

T["converts a terminal list to a core event"] = function ()
    -- Given hc JSON with a remote foreground process and status record
    local calls = fake_process(vim.json.encode({
            terminals = {
                {
                    address = "server/t1",
                    cwd = "/start",
                    foreground = { name = "fish", cwd = "/app" },
                    labels = { ["herdr.space"] = "/app" },
                    status = { state = "working" },
                    status_ms = 5,
                    created_ms = 1,
                    turn = 2,
                    name = "build"
                }
            }
        }))
    ---@type HerdrCoreTerminalsListed?
    local event
    -- When the terminal list is requested
    require("herdr-core.adapter.hc").list(function (value) event = value end)
    -- Then hc details are translated into core data
    MiniTest.expect.equality(calls[1], { "hc", "ls", "--json" })
    MiniTest.expect.equality(event, {
        type = "terminals_listed",
        terminals = {
            {
                address = "server/t1",
                machine = "server",
                folder = "/app",
                program = "fish",
                name = "build",
                labels = { ["herdr.space"] = "/app" },
                status = "working",
                status_ms = 5,
                created_ms = 1,
                turn = 2
            }
        }
    })
end

T["reports a failed label write with the terminal and error"] = function ()
    -- Given hc refusing a label write
    local calls = fake_process("", 1)
    ---@type string?
    local failure
    -- When a label is written
    require("herdr-core.adapter.hc").label("t1", "herdr-core-nvim.name", "build", function (err) failure = err end)
    -- Then the exact write and its failure are available to the caller
    MiniTest.expect.equality(calls[1], { "hc", "label", "--json", "t1", "herdr-core-nvim.name=build" })
    MiniTest.expect.equality(failure, "failed")
end

T["reports a missing hc executable without throwing"] = function ()
    -- Given hc cannot be started
    vim.system = function () error("hc: ENOENT") end
    ---@type string?
    local failure
    -- When the terminal list is requested
    local ok = pcall(function () require("herdr-core.adapter.hc").list(function (_, err) failure = err end) end)
    -- Then the caller receives the startup error
    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(type(failure), "string")
    MiniTest.expect.equality(assert(failure):find("ENOENT", 1, true) ~= nil, true)
end

T["rejects invalid JSON instead of replacing the terminal list"] = function ()
    -- Given a malformed hc response
    fake_process("not JSON")
    ---@type HerdrCoreTerminalsListed?
    local event
    ---@type string?
    local failure
    -- When the terminal list is requested
    require("herdr-core.adapter.hc").list(function (value, err)
        event = value
        failure = err
    end)
    -- Then no replacement list is emitted and the caller gets the error
    MiniTest.expect.equality(event, nil)
    MiniTest.expect.equality(failure, "Invalid hc JSON response")
end

T["rejects malformed terminal fields before returning a replacement list"] = function ()
    -- Given a terminal record containing a nonnumeric turn
    fake_process(vim.json.encode({
            terminals = {
                {
                    address = "t1",
                    cwd = "/app",
                    labels = {},
                    created_ms = 1,
                    turn = "bad"
                }
            }
        }))
    ---@type HerdrCoreTerminalsListed?
    local event
    ---@type string?
    local failure
    -- When the list is decoded
    require("herdr-core.adapter.hc").list(function (value, err)
        event = value
        failure = err
    end)
    -- Then malformed state cannot reach the core
    MiniTest.expect.equality(event, nil)
    MiniTest.expect.equality(type(failure), "string")
end

-- When reading the layout, the hc adapter can return the doc's value and version.
T["reads the layout although hc connect stays open after replying"] = function ()
    -- Given an hc connect that replies on stdout and keeps running, as it does on Windows
    local killed = false
    ---@param _        string[]
    ---@param options  vim.SystemOpts?
    ---@param on_exit? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (_, options, on_exit)
        local feed = assert(options).stdout
        assert(type(feed) == "function")
        vim.schedule(function ()
            feed(
                nil,
                vim.json.encode({
                    jsonrpc = "2.0",
                    id = 1,
                    result = {
                        value = { tabs = {} },
                        version = 5
                    }
                })
                    .. string.char(10)
            )
        end)
        return {
            write = function () end,
            kill = function ()
                killed = true
                if on_exit then on_exit({ code = 1, signal = 15, stdout = "", stderr = "" }) end
            end
        } --[[@as vim.SystemObj]]
    end
    ---@type HerdrCoreLayoutLoaded?
    local event
    -- When the shared layout is requested
    require("herdr-core.adapter.hc").read_layout(function (result) event = result end)
    vim.wait(1000, function () return event ~= nil end)
    -- Then the reply is used without waiting for hc connect to exit, and the process is stopped
    MiniTest.expect.equality(event, { type = "layout_loaded", value = { tabs = {} }, version = 5 })
    MiniTest.expect.equality(killed, true)
end

T["reads the shared layout through plain JSON RPC"] = function ()
    -- Given a JSON-RPC doc.get response
    local value = { tabs = {} }
    local calls, options = fake_process(vim.json.encode({
            jsonrpc = "2.0",
            id = 1,
            result = {
                value = value,
                version = 3
            }
        }))
    ---@type HerdrCoreLayoutLoaded?
    local event
    -- When the shared layout is requested
    require("herdr-core.adapter.hc").read_layout(function (result) event = result end)
    -- Then hc connect carries the API-only method and returns its version
    MiniTest.expect.equality(calls[1], { "hc", "connect" })
    MiniTest.expect.equality(vim.json.decode(assert(options[1]).stdin), {
        jsonrpc = "2.0",
        id = 1,
        method = "doc.get",
        params = {
            name = "herdr-core-nvim"
        }
    })
    MiniTest.expect.equality(event, { type = "layout_loaded", value = value, version = 3 })
end

T["returns a fresh layout after a refused versioned save"] = function ()
    -- Given a doc.set conflict followed by the latest doc.get result
    local latest = { tabs = {} }
    local calls, options = fake_process({
        vim.json.encode(
            { jsonrpc = "2.0", id = 1, error = { message = "stale version", data = { kind = "conflict" } } }
        ),
        vim.json.encode({ jsonrpc = "2.0", id = 1, result = { value = latest, version = 4 } })
    })
    ---@type HerdrCoreLayoutLoaded | HerdrCoreLayoutConflict?
    local event
    -- When an older layout version is saved
    require("herdr-core.adapter.hc").save_layout({ tabs = {} }, 3, function (result) event = result end)
    -- Then the latest layout is returned for the core to merge
    MiniTest.expect.equality(#calls, 2)
    MiniTest.expect.equality(vim.json.decode(assert(options[1]).stdin).params.version, 3)
    MiniTest.expect.equality(event, { type = "layout_conflict", value = latest, version = 4 })
end

T["returns the saved layout and its new version after a successful write"] = function ()
    -- Given a successful doc.set reply
    fake_process(vim.json.encode({ jsonrpc = "2.0", id = 1, result = { version = 5 } }))
    local value = { tabs = {} }
    ---@type HerdrCoreLayoutLoaded | HerdrCoreLayoutConflict?
    local event
    -- When version four is saved
    require("herdr-core.adapter.hc").save_layout(value, 4, function (result) event = result end)
    -- Then the core can acknowledge its write
    MiniTest.expect.equality(event, { type = "layout_loaded", value = value, version = 5 })
end

T["rejects a malformed shared layout without applying it"] = function ()
    -- Given an invalid split in a shared document
    fake_process(vim.json.encode({
            jsonrpc = "2.0",
            id = 1,
            result = {
                version = 2,
                value = {
                    tabs = {
                        {
                            id = "tab1",
                            root = {
                                kind = "split",
                                id = "bad",
                                children = "invalid"
                            }
                        }
                    }
                }
            }
        }))
    ---@type HerdrCoreLayoutLoaded?
    local event
    ---@type string?
    local failure
    -- When the shared layout is read
    require("herdr-core.adapter.hc").read_layout(function (value, err)
        event = value
        failure = err
    end)
    -- Then it cannot reach the window restoration code
    MiniTest.expect.equality(event, nil)
    MiniTest.expect.equality(type(failure), "string")
end

T["converts streamed fact changes even when JSON lines are split"] = function ()
    -- Given an hc event stream captured at the process boundary
    ---@type vim.SystemOpts?
    local options
    ---@param _argv string[]
    ---@param opts? vim.SystemOpts
    ---@return vim.SystemObj
    vim.system = function (_argv, opts)
        options = opts
        return { kill = function () end, write = function () end } --[[@as vim.SystemObj]]
    end
    ---@type table[]
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    local feed = assert(assert(options).stdout)
    assert(type(feed) == "function")
    local body = vim.json.encode({
        method = "event",
        params = {
            seq = 1,
            type = "status",
            terminal = "t1",
            data = {
                status = {
                    state = "working"
                }
            }
        }
    })
    -- When a status line arrives in chunks followed by foreground, labels and finish
    feed(nil, body:sub(1, 12))
    feed(nil, body:sub(13) .. "\n")
    feed(
        nil,
        vim.json.encode({
            method = "event",
            params = {
                seq = 2,
                type = "foreground",
                terminal = "t1",
                data = {
                    cwd = "/app",
                    name = "fish"
                }
            }
        })
            .. "\n"
    )
    feed(
        nil,
        vim.json.encode({
            method = "event",
            params = {
                seq = 3,
                type = "labels",
                terminal = "t1",
                data = {
                    labels = {
                        a = "b"
                    }
                }
            }
        })
            .. "\n"
    )
    feed(
        nil,
        vim.json.encode({ method = "event", params = { seq = 4, type = "finished", terminal = "t1", data = {} } }) .. "\n"
    )
    stop()
    -- Then four core events arrive with the matching data
    MiniTest.expect.equality(#events, 4)
    MiniTest.expect.equality(assert(events[1]).status, "working")
    MiniTest.expect.equality(events[2], {
        type = "foreground_changed",
        terminal = "t1",
        folder = "/app",
        program = "fish"
    })
    MiniTest.expect.equality(events[3], { type = "labels_changed", terminal = "t1", labels = { a = "b" } })
    MiniTest.expect.equality(events[4], { type = "terminal_ended", terminal = "t1" })
end

---@param replies? string[]
---@return fun(line: string), string[][]
local function fake_stream(replies)
    local calls = {}
    local reply = 0
    ---@type vim.SystemOpts?
    local stream
    ---@param argv      string[]
    ---@param options?  vim.SystemOpts
    ---@param callback? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (argv, options, callback)
        calls[#calls + 1] = argv
        if argv[2] == "events" then
            stream = options
        else
            reply = reply + 1
            local body = assert((replies or {})[reply])
            local feed = options and options.stdout
            if type(feed) == "function" then feed(nil, body .. string.char(10)) end
            assert(callback)({ code = 0, signal = 0, stdout = body, stderr = "" })
        end
        return { kill = function () end, write = function () end } --[[@as vim.SystemObj]]
    end
    return function (line)
        local feed = assert(stream).stdout
        assert(type(feed) == "function")
        feed(nil, line)
    end,
        calls
end

T["loads the initial event snapshot before reading the layout"] = function ()
    -- Given a subscription and a stored layout response
    local feed, calls = fake_stream({ vim.json.encode({ id = 1, result = { value = { tabs = {} }, version = 2 } }) })
    ---@type table[]
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    -- When the initial terminal snapshot arrives
    feed(
        vim.json.encode({ seq = 3, terminals = { { address = "t1", cwd = "/app", created_ms = 1, labels = {} } } }) .. "\n"
    )
    stop()
    -- Then terminal data is emitted and layout reading follows subscription
    MiniTest.expect.equality(assert(events[1]).type, "terminals_listed")
    MiniTest.expect.equality(assert(events[2]).type, "layout_loaded")
    MiniTest.expect.equality(calls[1], { "hc", "events", "--json" })
    MiniTest.expect.equality(calls[2], { "hc", "connect" })
end

T["refetches its document when a document event arrives"] = function ()
    -- Given a changed shared layout and an active event stream
    local feed = fake_stream({ vim.json.encode({ id = 1, result = { value = { tabs = {} }, version = 4 } }) })
    ---@type table[]
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    -- When a doc notification without a value arrives
    feed(vim.json.encode({
            method = "event",
            params = {
                seq = 5,
                type = "doc",
                data = {
                    name = "herdr-core-nvim",
                    version = 4
                }
            }
        })
            .. "\n")
    stop()
    -- Then doc.get supplies the value and version
    MiniTest.expect.equality(events, { { type = "layout_loaded", value = { tabs = {} }, version = 4 } })
end

T["refreshes after missed events and ignores older queued events"] = function ()
    -- Given a stream that missed updates and fresh terminal and layout responses
    local feed = fake_stream({
        vim.json.encode({
            id = 1,
            result = {
                value = {
                    tabs = {}
                },
                version = 4
            }
        })
    })
    ---@type table[]
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    -- When a missed notification is followed by an older queued status change
    feed(vim.json.encode({ method = "missed", params = { seq = 5, terminals = {} } }) .. "\n")
    feed(vim.json.encode({
            method = "event",
            params = {
                seq = 4,
                type = "status",
                terminal = "t1",
                data = {
                    status = {
                        state = "working"
                    }
                }
            }
        })
            .. "\n")
    stop()
    -- Then only fresh snapshots are emitted
    MiniTest.expect.equality(events, {
        { type = "terminals_listed", terminals = {} },
        {
            type = "layout_loaded",
            value = {
                tabs = {}
            },
            version = 4
        }
    })
end

T["uses the missed snapshot without a second terminal list request"] = function ()
    -- Given a missed notification already carrying an authoritative terminal snapshot
    local feed, calls = fake_stream({ vim.json.encode({ id = 1, result = { value = { tabs = {} }, version = 4 } }) })
    local stop = require("herdr-core.adapter.hc").watch(function () end)
    -- When that notification arrives
    feed(vim.json.encode({ method = "missed", params = { seq = 5, terminals = {} } }) .. "\n")
    stop()
    -- Then only the shared document is fetched, avoiding a stale list race
    MiniTest.expect.equality(calls, { { "hc", "events", "--json" }, { "hc", "connect" } })
end

T["converts created restarted and turn notifications"] = function ()
    -- Given an event stream and terminal record
    local feed = fake_stream()
    ---@type table[]
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    local record = { address = "t1", cwd = "/app", labels = {}, created_ms = 1 }
    -- When a terminal starts, restarts and completes a turn
    feed(
        vim.json.encode({ method = "event", params = { seq = 1, type = "created", terminal = "t1", data = record } }) .. "\n"
    )
    feed(
        vim.json.encode({ method = "event", params = { seq = 2, type = "restarted", terminal = "t1", data = record } }) .. "\n"
    )
    feed(
        vim.json.encode({ method = "event", params = { seq = 3, type = "turn", terminal = "t1", data = { turn = 2 } } }) .. "\n"
    )
    stop()
    -- Then records are added or replaced and the turn counter is updated
    MiniTest.expect.equality(assert(events[1]).type, "terminal_started")
    MiniTest.expect.equality(assert(events[2]).type, "terminal_started")
    MiniTest.expect.equality(events[3], { type = "turn_changed", terminal = "t1", turn = 2 })
end

T["clears foreground program data without losing the last folder"] = function ()
    -- Given a live terminal with a foreground process in the core state
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", folder = "/app", program = "fish", labels = {}, created_ms = 1, turn = 0 }
    local feed = fake_stream()
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then state = core.update(state, event) end
    end)
    -- When the foreground process disappears
    feed(vim.json.encode({
            method = "event",
            params = { seq = 1, type = "foreground", terminal = "t1", data = vim.NIL }
        })
            .. "\n")
    stop()
    -- Then the program clears and the last known folder remains
    MiniTest.expect.equality(state.terminals.t1.program, nil)
    MiniTest.expect.equality(state.terminals.t1.folder, "/app")
end

T["keeps a lost terminal while clearing its foreground process"] = function ()
    -- Given a terminal whose program can recover into a shell
    local core = require("herdr-core.core.state")
    local state = core.new()
    state.terminals.t1 = { address = "t1", folder = "/app", program = "fish", labels = {}, created_ms = 1, turn = 0 }
    local feed = fake_stream()
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then state = core.update(state, event) end
    end)
    -- When its running program is lost
    feed(vim.json.encode({
            method = "event",
            params = {
                seq = 1,
                type = "lost",
                terminal = "t1",
                data = {
                    reason = "holder_lost"
                }
            }
        })
            .. "\n")
    stop()
    -- Then the terminal survives with no stale foreground name
    MiniTest.expect.equality(state.terminals.t1.folder, "/app")
    MiniTest.expect.equality(state.terminals.t1.program, nil)
end

T["uses a record carried by a newly matching labels event"] = function ()
    -- Given a labels event introducing a previously unknown terminal
    local feed = fake_stream()
    ---@type table[]
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    local record = { address = "t1", cwd = "/app", labels = { a = "b" }, created_ms = 1 }
    -- When its full record accompanies the labels
    feed(vim.json.encode({
            method = "event",
            params = {
                seq = 1,
                type = "labels",
                terminal = "t1",
                data = {
                    labels = record.labels,
                    record = record
                }
            }
        })
            .. "\n")
    stop()
    -- Then the terminal can be added instead of dropping an unknown label update
    MiniTest.expect.equality(assert(events[1]).type, "terminal_started")
    MiniTest.expect.equality(assert(events[1]).terminal.address, "t1")
end

-- When hc reports the same folder with backslashes in one place and slashes in another, the hc adapter can report both as the same folder.
T["reports a folder the same way whichever separator hc used"] = function ()
    if vim.fn.has("win32") == 0 then MiniTest.skip("hc reports backslashes only on Windows") end
    -- Given hc listing a terminal by its start folder and later reporting its foreground folder with backslashes
    fake_process(vim.json.encode({
            terminals = { { address = "t1", cwd = "C:/work/app", created_ms = 1, labels = {} } }
        }))
    ---@type HerdrCoreTerminalsListed?
    local listed
    require("herdr-core.adapter.hc").list(function (event) listed = event end)
    ---@type vim.SystemOpts?
    local stream
    ---@param _        string[]
    ---@param options? vim.SystemOpts
    ---@return vim.SystemObj
    vim.system = function (_, options)
        stream = options
        return { kill = function () end, write = function () end } --[[@as vim.SystemObj]]
    end
    ---@type HerdrCoreForegroundChanged?
    local changed
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event and event.type == "foreground_changed" then changed = event --[[@as HerdrCoreForegroundChanged]] end
    end)
    -- When the foreground event arrives
    local feed = assert(stream).stdout
    assert(type(feed) == "function")
    feed(
        nil,
        vim.json.encode({
            jsonrpc = "2.0",
            method = "event",
            params = {
                seq = 1,
                terminal = "t1",
                type = "foreground",
                data = {
                    cwd = table.concat({ "C:", "work", "app" }, string.char(92)),
                    name = "cmd.EXE"
                }
            }
        })
            .. string.char(10)
    )
    stop()
    -- Then both report the same folder
    MiniTest.expect.equality(assert(changed).folder, assert(assert(listed).terminals[1]).folder)
end

-- When the event stream closes, the hc adapter can report that it closed.
T["reports that the event stream closed"] = function ()
    -- Given an event stream
    ---@type fun(result: vim.SystemCompleted)?
    local exit
    ---@param _        string[]
    ---@param _options vim.SystemOpts?
    ---@param on_exit? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (_, _options, on_exit)
        exit = on_exit
        return { kill = function () end, write = function () end } --[[@as vim.SystemObj]]
    end
    local closed = false
    require("herdr-core.adapter.hc").watch(function () end, function () closed = true end)
    -- When hc events exits, as it does when the core restarts
    assert(exit)({ code = 1, signal = 0, stdout = "", stderr = "core restarted" })
    -- Then the caller learns that the stream closed
    MiniTest.expect.equality(closed, true)
end

T["omits finished terminals from list and event snapshots"] = function ()
    -- Given an event snapshot containing a live terminal and a finished terminal
    local snapshot = vim.json.encode({
        seq = 1,
        terminals = {
            { address = "t1", state = "live", cwd = "/app", labels = {}, created_ms = 1 },
            { address = "t4", state = "finished", cwd = "/app", labels = {}, created_ms = 1 }
        }
    })
    fake_process(snapshot)
    local addresses = {}
    -- When the initial event snapshot is translated
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event and event.type == "terminals_listed" then
            local listed = event --[[@as HerdrCoreTerminalsListed]]
            for _, record in ipairs(listed.terminals) do
                addresses[#addresses + 1] = record.address
            end
        end
    end)
    stop()
    -- Then only the live terminal can be chosen in the sidebar
    MiniTest.expect.equality(addresses, { "t1" })
end

T["does not revive a finished terminal when its labels change"] = function ()
    -- Given a label event carrying a finished terminal record
    local feed = fake_stream()
    local events = {}
    local stop = require("herdr-core.adapter.hc").watch(function (event)
        if event then events[#events + 1] = event end
    end)
    -- When another client changes its labels
    feed(vim.json.encode({
            method = "event",
            params = {
                seq = 1,
                type = "labels",
                terminal = "t4",
                data = {
                    labels = {},
                    record = {
                        address = "t4",
                        state = "finished",
                        cwd = "/app",
                        labels = {},
                        created_ms = 1
                    }
                }
            }
        })
            .. string.char(10))
    stop()
    -- Then the terminal remains ended instead of being added again
    MiniTest.expect.equality(events, { { type = "terminal_ended", terminal = "t4" } })
end

return T
