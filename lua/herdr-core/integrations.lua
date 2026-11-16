-- Integrations put a hook into an agent's settings that labels its hc terminal with the conversation it runs.
local M = {}

---@alias HerdrCoreIntegrationStatus 'installed' | 'outdated' | 'missing'

---@class HerdrCoreHookCommandOptions
---@field id?            string[] Payload fields that hold the conversation id, tried in order.
---@field id_env?        string   A variable that holds the id, read before the payload.
---@field parent_id_env? string   A variable that holds a parent conversation's id: its events are ignored.
---@field reply?         string   Text the hook prints, for agents that expect an answer.
---@field script?        string   A script to run instead of the built-in one, called with the same arguments.

---@class HerdrCoreIntegrationContext
---@field directory    string
---@field hook_command fun(event: 'started' | 'ended', options?: HerdrCoreHookCommandOptions): string

---@class HerdrCoreIntegrationStep
---@field check fun(context: HerdrCoreIntegrationContext): HerdrCoreIntegrationStatus
---@field apply fun(context: HerdrCoreIntegrationContext)

---@class HerdrCoreProgram
---@field app?  string   The name the agent reported to hc.
---@field name? string   The foreground process's name.
---@field argv? string[] The foreground process's arguments.

---@class HerdrCoreIntegration
---@field label           string
---@field directory       fun(): string?
---@field install         HerdrCoreIntegrationStep[]
---@field resume_command  fun(id: string): string
---@field matches_program fun(program: HerdrCoreProgram): boolean

---@return string
function M.script()
    local data = vim.fn.stdpath("data") --[[@as string]]
    return vim.fs.joinpath(data, "herdr-core", "session-hook.lua")
end

-- Copied on every start so the hook commands in agents' settings never name the plugin's own folder.
function M.copy_script()
    local root = vim.fn.fnamemodify(assert(debug.getinfo(1, "S")).source:sub(2), ":h:h:h")
    local target = M.script()
    vim.fn.mkdir(vim.fs.dirname(target), "p")
    vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(root, "assets", "session-hook.lua"), "b"), target, "b")
end

---@param spec { env?: string, path: string }
---@return fun(): string?
function M.directory(spec)
    return function ()
        local value = spec.env and vim.env[spec.env]
        local path = vim.fs.normalize(value and value ~= "" and value or spec.path)
        return vim.fn.isdirectory(path) == 1 and path or nil
    end
end

-- The same interpreters as the Herdr desktop app: the program they run is named in their arguments.
local interpreters = {}
for _, name in ipairs({
    "node",
    "bun",
    "bunx",
    "deno",
    "python",
    "python3",
    "npx",
    "pnpm",
    "yarn",
    "uv",
    "uvx",
    "ruby",
    "bundle",
    "env",
    "sudo",
    "nice",
    "time",
    "watch",
    "nodemon"
}) do
    interpreters[name] = true
end

---@param word string
---@return string
local function base(word)
    word = (word:match("[^/\\]+$") or word):gsub("^%-+", ""):gsub("%.[eE][xX][eE]$", "")
    return word:lower()
end

---@param program HerdrCoreProgram
---@return string[]
local function candidates(program)
    if program.app and program.app ~= "" then return { program.app:lower() } end
    local argv = program.argv and #program.argv > 0 and program.argv or { program.name }
    if not argv[1] then return {} end
    local first = base(argv[1])
    if not interpreters[first] then return { first } end
    local names = {}
    for index = 2, #argv do
        local argument = argv[index]
        if argument:sub(1, 1) ~= "-" then
            local stem = base(argument):gsub("%.[mc]?[jt]s$", ""):gsub("%.py$", ""):gsub("%.rb$", "")
            if not interpreters[stem] then names[#names + 1] = stem end
        end
    end
    names[#names + 1] = first
    return names
end

-- The name a terminal's foreground program goes by, as the Herdr desktop app sees it.
---@param program HerdrCoreProgram
---@return string?
function M.identify(program)
    return candidates(program)[1]
end

---@param names string[]
---@return fun(program: HerdrCoreProgram): boolean
function M.program(names)
    local wanted = {}
    for _, name in ipairs(names) do
        wanted[name:lower()] = true
    end
    return function (program)
        for _, name in ipairs(candidates(program)) do
            if wanted[name] then return true end
        end
        return false
    end
end

---@param argument string
---@return string
local function quote(argument)
    if argument:match("^[%w_./:%-]+$") then return argument end
    return '"' .. argument .. '"'
end

---@param name     string
---@param event    'started' | 'ended'
---@param options? HerdrCoreHookCommandOptions
---@return string
function M.hook_command(name, event, options)
    options = options or {}
    local argv = { "nvim", "-l", options.script or M.script(), name, "--event", event }
    for _, field in ipairs(options.id or {}) do
        vim.list_extend(argv, { "--id", field })
    end
    for _, flag in ipairs({ "id_env", "parent_id_env", "reply" }) do
        if options[flag] then vim.list_extend(argv, { "--" .. flag:gsub("_", "-"), options[flag] }) end
    end
    return table.concat(vim.tbl_map(quote, argv), " ")
end

---@param name     string
---@param options? HerdrCoreHookCommandOptions
---@return string
local function marker(name, options)
    return quote((options or {}).script or M.script()) .. " " .. quote(name) .. " --event "
end

---@param value  any
---@param indent string
---@return string
local function encode(value, indent)
    if type(value) ~= "table" or value == vim.NIL then return vim.json.encode(value) end
    if next(value) == nil then return getmetatable(value) and "{}" or "[]" end
    local inner = indent .. "  "
    local items = {}
    if vim.islist(value) then
        for _, item in ipairs(value) do
            items[#items + 1] = inner .. encode(item, inner)
        end
        return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = vim.tbl_keys(value)
    table.sort(keys)
    for _, key in ipairs(keys) do
        items[#items + 1] = inner .. vim.json.encode(key) .. ": " .. encode(value[key], inner)
    end
    return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "}"
end

---@param path string
---@return table
local function read_json(path)
    if vim.fn.filereadable(path) == 0 then return vim.empty_dict() end
    local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if not ok or type(value) ~= "table" then error(vim.fs.basename(path) .. " is not JSON", 0) end
    return value
end

---@param path  string
---@param value table
local function write_json(path, value)
    vim.fn.writefile(vim.split(encode(value, ""), "\n", { plain = true }), path)
end

---@class HerdrCoreHooksOptions: HerdrCoreHookCommandOptions
---@field file   string                               Settings file, relative to the integration's directory.
---@field events { started?: string, ended?: string } The agent's names for those events.

---@param name    string
---@param options HerdrCoreHooksOptions
---@return HerdrCoreIntegrationStep
local function hooks(name, options)
    local mine = marker(name, options)
    ---@param context  HerdrCoreIntegrationContext
    ---@param settings table
    ---@param visit    fun(event: string, command: string, groups: table[])
    local function each(context, settings, visit)
        settings.hooks = settings.hooks or vim.empty_dict()
        for _, kind in ipairs({ "started", "ended" }) do
            local event = options.events[kind] --[[@as string?]]
            if event then
                settings.hooks[event] = settings.hooks[event] or {}
                visit(event, context.hook_command(kind, options), settings.hooks[event])
            end
        end
    end
    ---@param context HerdrCoreIntegrationContext
    ---@return string
    local function path(context)
        return vim.fs.joinpath(context.directory, options.file)
    end
    return {
        check = function (context)
            local exact, wanted, ours = 0, 0, false
            each(context, read_json(path(context)), function (_, command, groups)
                wanted = wanted + 1
                local found = false
                for _, group in ipairs(groups) do
                    for _, hook in ipairs(group.hooks or {}) do
                        if hook.command == command then
                            found = true
                        elseif type(hook.command) == "string" and hook.command:find(mine, 1, true) then
                            ours = true
                        end
                    end
                end
                if found then exact = exact + 1 end
            end)
            if exact == wanted and not ours then return "installed" end
            return (ours or exact > 0) and "outdated" or "missing"
        end,
        apply = function (context)
            local file = path(context)
            local settings = read_json(file)
            each(context, settings, function (event, command, groups)
                local kept, present = {}, false
                for _, group in ipairs(groups) do
                    local inner = {}
                    for _, hook in ipairs(group.hooks or {}) do
                        local stale = type(hook.command) == "string" and hook.command ~= command
                            and hook.command:find(mine, 1, true)
                        if hook.command == command then present = true end
                        if not stale then inner[#inner + 1] = hook end
                    end
                    if #inner > 0 then
                        group.hooks = inner
                        kept[#kept + 1] = group
                    end
                end
                if not present then
                    kept[#kept + 1] = { hooks = { { type = "command", command = command, timeout = 10 } } }
                end
                settings.hooks[event] = kept
            end)
            write_json(file, settings)
        end
    }
end

-- A hooks step is made per integration, because its commands carry the integration's name.
---@param options HerdrCoreHooksOptions
---@return fun(name: string): HerdrCoreIntegrationStep
function M.hooks(options)
    return function (name) return hooks(name, options) end
end

---@param value boolean | string | number
---@return string
local function toml_value(value)
    return type(value) == "string" and vim.json.encode(value) or tostring(value)
end

---@param lines  string[]
---@param dotted string
---@return integer? header, integer? line, string? value
local function find_toml(lines, dotted)
    local section, key = dotted:match("^(.*)%.([^.]+)$")
    assert(section and key, "A TOML key needs its table: " .. dotted)
    local header, current
    for index, line in ipairs(lines) do
        local name = line:match("^%s*%[([^%]]+)%]%s*$")
        if name then
            current = vim.trim(name)
            if current == section and not header then header = index end
        elseif current == section then
            local found = line:match("^%s*" .. vim.pesc(key) .. "%s*=%s*(.-)%s*$")
            if found then return header, index, found end
        end
    end
    return header, nil, nil
end

-- shortcut: edits TOML line by line like Herdr; keys written as dotted keys or inline tables are not found.
---@param options { file: string, set: table<string, boolean | string | number> }
---@return HerdrCoreIntegrationStep
function M.toml(options)
    ---@param context HerdrCoreIntegrationContext
    ---@return string
    local function path(context)
        return vim.fs.joinpath(context.directory, options.file)
    end
    ---@param context HerdrCoreIntegrationContext
    ---@return string[]
    local function lines(context)
        return vim.fn.filereadable(path(context)) == 1 and vim.fn.readfile(path(context)) or {}
    end
    return {
        check = function (context)
            local content, status = lines(context), "installed"
            for dotted, value in pairs(options.set) do
                local _, line, found = find_toml(content, dotted)
                if not line then return "missing" end
                if found ~= toml_value(value) then status = "outdated" end
            end
            return status
        end,
        apply = function (context)
            local content = lines(context)
            for dotted, value in pairs(options.set) do
                local section, key = assert(dotted:match("^(.*)%.([^.]+)$"))
                local entry = key .. " = " .. toml_value(value)
                local header, line = find_toml(content, dotted)
                if line then
                    content[line] = entry
                elseif header then
                    table.insert(content, header + 1, entry)
                else
                    if #content > 0 and content[#content] ~= "" then content[#content + 1] = "" end
                    vim.list_extend(content, { "[" .. section .. "]", entry })
                end
            end
            vim.fn.writefile(content, path(context))
        end
    }
end

---@type table<string, table>
M.builtin = {
    claude = {
        directory = M.directory({ env = "CLAUDE_CONFIG_DIR", path = "~/.claude" }),
        install = { M.hooks({ file = "settings.json", events = { started = "SessionStart", ended = "SessionEnd" } }) },
        resume_command = function (id) return "claude --resume " .. id end,
        matches_program = M.program({ "claude", "claude-code" })
    },
    codex = {
        directory = M.directory({ env = "CODEX_HOME", path = "~/.codex" }),
        install = {
            M.hooks({
                file = "hooks.json",
                events = { started = "SessionStart", ended = "SessionEnd" },
                parent_id_env = "CODEX_THREAD_ID"
            }),
            M.toml({ file = "config.toml", set = { ["features.hooks"] = true } })
        },
        resume_command = function (id) return "codex resume " .. id end,
        matches_program = M.program({ "codex" })
    }
}

-- User definitions replace the fields they name; `false` turns a built-in off.
---@param overrides? table<string, table | false>
---@return table<string, HerdrCoreIntegration>
function M.resolve(overrides)
    local result = {}
    for name, definition in pairs(vim.tbl_extend("force", M.builtin, overrides or {})) do
        if definition then
            local merged = vim.tbl_extend("force", M.builtin[name] or {}, definition)
            local steps = {}
            for _, step in ipairs(merged.install or {}) do
                steps[#steps + 1] = type(step) == "function" and step(name) or step
            end
            merged.install = steps
            merged.label = merged.label or name
            result[name] = merged
        end
    end
    return result
end

local rank = { missing = 1, outdated = 2, installed = 3 }

---@param name       string
---@param definition HerdrCoreIntegration
---@return HerdrCoreIntegrationContext?
local function context_of(name, definition)
    local directory = definition.directory()
    if not directory then return nil end
    return {
        directory = directory,
        hook_command = function (event, options) return M.hook_command(name, event, options) end
    }
end

---@param context    HerdrCoreIntegrationContext
---@param definition HerdrCoreIntegration
---@return HerdrCoreIntegrationStatus
local function worst(context, definition)
    ---@type HerdrCoreIntegrationStatus
    local status = "installed"
    for _, step in ipairs(definition.install) do
        local current = step.check(context)
        if rank[current] < rank[status] then status = current end
    end
    return status
end

-- The integration's state, or nil when its agent is not on this machine.
---@param name       string
---@param definition HerdrCoreIntegration
---@return HerdrCoreIntegrationStatus?, string?
function M.status(name, definition)
    local context = context_of(name, definition)
    if not context then return nil end
    local ok, status = pcall(worst, context, definition)
    if not ok then return "missing", tostring(status) end
    return status
end

---@param name       string
---@param definition HerdrCoreIntegration
---@return HerdrCoreIntegrationStatus, string?
function M.install(name, definition)
    local context = context_of(name, definition)
    if not context then return "missing", "agent not found" end
    local ok, failure = pcall(function ()
        for _, step in ipairs(definition.install) do
            if step.check(context) ~= "installed" then step.apply(context) end
        end
    end)
    if not ok then return M.status(name, definition) or "missing", tostring(failure) end
    local status, err = M.status(name, definition)
    if status ~= "installed" then
        return status or "missing", err or ("still " .. tostring(status) .. " after install")
    end
    return "installed"
end

return M
