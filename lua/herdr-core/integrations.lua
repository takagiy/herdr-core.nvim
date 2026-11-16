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

-- A file in the plugin's assets folder.
---@param name string
---@return string
function M.asset(name)
    local root = vim.fn.fnamemodify(assert(debug.getinfo(1, "S")).source:sub(2), ":h:h:h")
    return vim.fs.joinpath(root, "assets", name)
end

-- Copied on every start so the hook commands in agents' settings never name the plugin's own folder.
function M.copy_script()
    local target = M.script()
    vim.fn.mkdir(vim.fs.dirname(target), "p")
    vim.fn.writefile(vim.fn.readfile(M.asset("session-hook.lua"), "b"), target, "b")
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

-- JSON files are edited as text, so comments, key order and layout stay; only what this plugin owns changes.

-- Blanks out comments, keeping every other character in its place.
---@param text string
---@return string
local function blank_comments(text)
    local out, index, quoted = {}, 1, false
    while index <= #text do
        local char = text:sub(index, index)
        local pair = text:sub(index, index + 1)
        if quoted then
            if char == "\\" then
                out[#out + 1] = pair
                index = index + 2
            else
                quoted = char ~= '"'
                out[#out + 1] = char
                index = index + 1
            end
        elseif pair == "//" or pair == "/*" then
            local stop = pair == "//" and (text:find("\n", index, true) or #text + 1) - 1 or select(
                2, text:find("*/", index + 2, true)
            )
                or #text
            out[#out + 1] = (text:sub(index, stop):gsub("[^\n]", " "))
            index = stop + 1
        else
            quoted = char == '"'
            out[#out + 1] = char
            index = index + 1
        end
    end
    return table.concat(out)
end

-- Blanks out trailing commas too, which `vim.json.decode` refuses.
---@param text string
---@return string
local function blank_trailing_commas(text)
    local result, position, quoted = {}, 1, false
    while position <= #text do
        local char = text:sub(position, position)
        if quoted and char == "\\" then
            char = text:sub(position, position + 1)
        elseif quoted then
            quoted = char ~= '"'
        elseif char == '"' then
            quoted = true
        elseif char == "," and text:match("^%s*[%]}]", position + 1) then
            char = " "
        end
        result[#result + 1] = char
        position = position + #char
    end
    return table.concat(result)
end

---@param path string
---@return string?
local function read_text(path)
    if vim.fn.filereadable(path) == 0 then return nil end
    return table.concat(vim.fn.readfile(path, "b"), "\n")
end

---@param text string
---@param name string
---@return table
local function decode_jsonc(text, name)
    if vim.trim(text) == "" then return vim.empty_dict() end
    local ok, value = pcall(vim.json.decode, blank_trailing_commas(blank_comments(text)))
    if not ok or type(value) ~= "table" then error(name .. " is not JSON", 0) end
    return value
end

-- One line of JSON with sorted keys, for the parts this plugin adds.
---@param value any
---@return string
local function compact(value)
    if type(value) ~= "table" or value == vim.NIL then return vim.json.encode(value) end
    if next(value) == nil then return getmetatable(value) and "{}" or "[]" end
    if vim.islist(value) then return "[" .. table.concat(vim.tbl_map(compact, value), ", ") .. "]" end
    local keys = vim.tbl_keys(value)
    table.sort(keys)
    local members = vim.tbl_map(function (key) return vim.json.encode(key) .. ": " .. compact(value[key]) end, keys)
    return "{" .. table.concat(members, ", ") .. "}"
end

---@param text     string
---@param position integer
---@return integer
local function space(text, position)
    return text:match("^%s*()", position) --[[@as integer]]
end

-- One past the end of the value that starts at `position`.
---@param clean    string
---@param position integer
---@return integer
local function skip(clean, position)
    local char = clean:sub(position, position)
    if char == '"' then
        position = position + 1
        while clean:sub(position, position) ~= '"' do
            if position > #clean then error("unterminated string", 0) end
            position = position + (clean:sub(position, position) == "\\" and 2 or 1)
        end
        return position + 1
    end
    if char == "{" or char == "[" then
        local depth = 0
        repeat
            char = clean:sub(position, position)
            if char == '"' then
                position = skip(clean, position)
            else
                if char == "{" or char == "[" then
                    depth = depth + 1
                elseif char == "}" or char == "]" then
                    depth = depth - 1
                end
                position = position + 1
            end
        until depth == 0 or position > #clean
        return position
    end
    return clean:match("^[^,%]}%s]*()", position) --[[@as integer]]
end

---@class HerdrCoreJsonPart
---@field start integer Where the member or element starts.
---@field stop  integer One past where it ends.
---@field value integer Where its value starts.
---@field key?  string  The member's key.

-- The members of the object, or the elements of the array, that opens at `open`.
---@param clean string
---@param open  integer
---@return HerdrCoreJsonPart[]
local function parts(clean, open)
    local object = clean:sub(open, open) == "{"
    local result = {}
    local position = space(clean, open + 1)
    while position <= #clean and not ("]}"):find(clean:sub(position, position), 1, true) do
        local part = { start = position, value = position }
        if object then
            local key_end = skip(clean, position)
            part.key = vim.json.decode(clean:sub(position, key_end - 1))
            part.value = space(
                clean,
                assert(clean:match("^%s*:()", key_end)) --[[@as integer]]
            )
        end
        part.stop = skip(clean, part.value)
        if part.stop <= part.value then error("unexpected JSON", 0) end
        result[#result + 1] = part
        position = space(clean, part.stop)
        if clean:sub(position, position) == "," then position = space(clean, position + 1) end
    end
    return result
end

-- Where the value at `keys` opens, and how many of the keys were found on the way.
---@param clean string
---@param keys  string[]
---@return integer open, integer found
local function locate(clean, keys)
    local open = space(clean, 1)
    for depth, key in ipairs(keys) do
        local found
        if clean:sub(open, open) == "{" then
            for _, part in ipairs(parts(clean, open)) do
                if part.key == key then found = part.value end
            end
        end
        if not found then return open, depth - 1 end
        open = found
    end
    return open, #keys
end

---@param text     string
---@param position integer
---@return integer
local function line_start(text, position)
    return text:sub(1, position - 1):match(".*\n()") --[[@as integer?]] or 1
end

-- Adds `piece` as the last member or element of what opens at `open`, laid out like the parts before it.
---@param text     string
---@param comments string  `text` with comments blanked.
---@param open     integer
---@param piece    string
---@return string
local function insert(text, comments, open, piece)
    local clean = blank_trailing_commas(comments)
    local list = parts(clean, open)
    local last = list[#list]
    local close = skip(clean, open) - 1
    local newline = text:find("\r\n", 1, true) and "\r\n" or "\n"
    if not last then
        if not clean:sub(open, close):find("\n", 1, true) then
            return text:sub(1, open) .. piece .. text:sub(open + 1)
        end
        local indent = text:match("^[ \t]*", line_start(text, open)) .. "  "
        return text:sub(1, open) .. newline .. indent .. piece .. text:sub(open + 1)
    end
    local trailing = comments:match("^%s*,", last.stop) ~= nil
    local line = line_start(text, close)
    if line > last.stop and clean:sub(line, close - 1):match("^%s*$") then
        -- The closing bracket has its own line: the piece gets a line above it, indented like the last part.
        local indent = text:match("^[ \t]*", line_start(text, last.start))
        text = text:sub(1, line - 1) .. indent .. piece .. (trailing and "," or "") .. newline .. text:sub(line)
        if trailing then return text end
        return text:sub(1, last.stop - 1) .. "," .. text:sub(last.stop)
    end
    return text:sub(1, last.stop - 1) .. ", " .. piece .. text:sub(last.stop)
end

-- Removes a member or element with the comma that separates it, and its line when nothing else is on it.
---@param text     string
---@param comments string              `text` with comments blanked.
---@param list     HerdrCoreJsonPart[]
---@param index    integer
---@return string
local function remove(text, comments, list, index)
    local part = assert(list[index])
    local first, last = part.start, part.stop - 1
    local after = comments:match("^%s*,()", part.stop) --[[@as integer?]]
    ---@type integer?
    local comma
    if after then
        last = after - 1
    elseif index > 1 then
        -- The last part takes the comma before it, so no trailing comma is left behind.
        comma = comments:find(",", assert(list[index - 1]).stop, true)
        if comma and text:sub(comma + 1, first - 1):match("^%s*$") then
            first, comma = comma, nil
        end
    end
    local line = line_start(text, first)
    local rest = text:match("^[ \t\r]*\n()", last + 1) --[[@as integer?]]
    if rest and text:sub(line, first - 1):match("^[ \t]*$") then
        first, last = line, rest - 1
    end
    text = text:sub(1, first - 1) .. text:sub(last + 1)
    if comma then text = text:sub(1, comma - 1) .. text:sub(comma + 1) end
    return text
end

---@param text  string
---@param keys  string[]
---@param value any
---@param mode  'append' | 'set'
---@param name  string           The file name, for errors.
---@return string
local function edit(text, keys, value, mode, name)
    local comments = blank_comments(text)
    local clean = blank_trailing_commas(comments)
    local open, found = locate(clean, keys)
    local place = name .. ": " .. table.concat(keys, ".")
    if found == #keys then
        if mode == "set" then return text:sub(1, open - 1) .. compact(value) .. text:sub(skip(clean, open)) end
        if clean:sub(open, open) ~= "[" then error(place .. " is not a list", 0) end
        return insert(text, comments, open, compact(value))
    end
    if clean:sub(open, open) ~= "{" then error(place .. " is not inside an object", 0) end
    local rest = mode == "append" and { value } or value
    for index = #keys, found + 2, -1 do
        rest = { [keys[index]] = rest }
    end
    return insert(text, comments, open, vim.json.encode(keys[found + 1]) .. ": " .. compact(rest))
end

---@param tree table
---@param keys string[]
---@return any
local function lookup(tree, keys)
    local value = tree
    for _, key in ipairs(keys) do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

---@param value   any
---@param command string
---@return any
local function fill(value, command)
    if type(value) == "string" then return (value:gsub("{{command}}", function () return command end)) end
    if type(value) ~= "table" then return value end
    local result = {}
    for field, inner in pairs(value) do
        result[field] = fill(inner, command)
    end
    return result
end

---@param value any
---@param mine  string
---@return boolean
local function names(value, mine)
    if type(value) == "string" then return value:find(mine, 1, true) ~= nil end
    if type(value) ~= "table" then return false end
    for _, inner in pairs(value) do
        if names(inner, mine) then return true end
    end
    return false
end

-- Removes this integration's old values from the list at `keys`: those naming it that differ from `value`.
---@param text  string
---@param keys  string[]
---@param value any
---@param mine  string
---@return string
local function prune(text, keys, value, mine)
    while true do
        local comments = blank_comments(text)
        local clean = blank_trailing_commas(comments)
        local open, found = locate(clean, keys)
        if found < #keys or clean:sub(open, open) ~= "[" then return text end
        local list = parts(clean, open)
        ---@type integer?
        local stale
        for index, part in ipairs(list) do
            local item = vim.json.decode(clean:sub(part.value, part.stop - 1))
            if not stale and not vim.deep_equal(item, value) and names(item, mine) then stale = index end
        end
        if not stale then return text end
        text = remove(text, comments, list, stale)
    end
end

---@class HerdrCoreJsonOptions: HerdrCoreHookCommandOptions
---@field file    string | string[]                    Relative to the integration's directory; with several, the first that exists is written.
---@field events? { started?: string, ended?: string } The agent's names for those events.
---@field append? table<string, any>                   Values added to the list at each place, with keys joined by dots.
---@field set?    table<string, any>                   Values written at each place, with keys joined by dots.

---@class HerdrCoreJsonOperation
---@field mode  'append' | 'set'
---@field keys  string[]
---@field value any

-- `{{event}}` in a place and `{{command}}` in a value make one operation per event.
---@param context HerdrCoreIntegrationContext
---@param options HerdrCoreJsonOptions
---@return HerdrCoreJsonOperation[]
local function operations(context, options)
    local result = {}
    local append = options.append or {}
    for _, mode in ipairs({ "append", "set" }) do
        local map = mode == "append" and append or options.set or {}
        local places = vim.tbl_keys(map)
        table.sort(places)
        for _, place in ipairs(places) do
            local value = map[place]
            if place:find("{{event}}", 1, true) or names(value, "{{command}}") then
                if not options.events then error(place .. ": {{event}} and {{command}} need events", 0) end
                for _, kind in ipairs({ "started", "ended" }) do
                    local event = options.events[kind] --[[@as string?]]
                    if event then
                        result[#result + 1] = {
                            mode = mode,
                            keys = vim.split((place:gsub("{{event}}", function () return event end)), ".", {
                                plain = true
                            }),
                            value = fill(value, context.hook_command(kind, options))
                        }
                    end
                end
            else
                result[#result + 1] = { mode = mode, keys = vim.split(place, ".", { plain = true }), value = value }
            end
        end
    end
    return result
end

---@param list  any
---@param value any
---@return boolean
local function holds(list, value)
    for _, item in ipairs(type(list) == "table" and list or {}) do
        if vim.deep_equal(item, value) then return true end
    end
    return false
end

---@param name    string
---@param options HerdrCoreJsonOptions
---@return HerdrCoreIntegrationStep
local function json(name, options)
    local mine = marker(name, options)
    local files = type(options.file) == "table" and options.file or { options.file }
    ---@param context HerdrCoreIntegrationContext
    ---@return { name: string, path: string, text: string? } [] loaded, integer target
    local function load(context)
        local loaded, target = {}, nil
        for index, file in ipairs(files) do
            local path = vim.fs.joinpath(context.directory, file)
            local text = read_text(path)
            loaded[index] = { name = file, path = path, text = text }
            target = target or (text and index)
        end
        return loaded, target or 1
    end
    return {
        check = function (context)
            local loaded, target = load(context)
            local trees = vim.tbl_map(function (file)
                return file.text and decode_jsonc(file.text, file.name) or vim.empty_dict()
            end, loaded)
            local seen = {}
            for _, operation in ipairs(operations(context, options)) do
                local status
                if operation.mode == "set" then
                    local current = lookup(trees[target], operation.keys)
                    status = vim.deep_equal(current, operation.value) and "installed" or current ~= nil and "outdated"
                        or "missing"
                else
                    local found, stale = false, false
                    for _, tree in ipairs(trees) do
                        local list = lookup(tree, operation.keys)
                        for _, item in ipairs(type(list) == "table" and list or {}) do
                            if vim.deep_equal(item, operation.value) then
                                found = true
                            elseif names(item, mine) then
                                stale = true
                            end
                        end
                    end
                    status = stale and "outdated" or found and "installed" or "missing"
                end
                seen[status] = true
            end
            if seen.outdated or (seen.installed and seen.missing) then return "outdated" end
            return seen.missing and "missing" or "installed"
        end,
        apply = function (context)
            local loaded, target = load(context)
            local list = operations(context, options)
            for _, file in ipairs(loaded) do
                if file.text then
                    decode_jsonc(file.text, file.name)
                    for _, operation in ipairs(list) do
                        if operation.mode == "append" then
                            file.text = prune(file.text, operation.keys, operation.value, mine)
                        end
                    end
                end
            end
            local into = assert(loaded[target])
            local created = not into.text
            into.text = into.text or "{}"
            for _, operation in ipairs(list) do
                local present
                if operation.mode == "set" then
                    present = vim.deep_equal(
                        lookup(decode_jsonc(into.text, into.name), operation.keys), operation.value
                    )
                else
                    present = false
                    for _, file in ipairs(loaded) do
                        local tree = file.text and decode_jsonc(file.text, file.name) or {}
                        present = present or holds(lookup(tree, operation.keys), operation.value)
                    end
                end
                if not present then into.text = edit(into.text, operation.keys, operation.value, operation.mode, into.name) end
            end
            for _, file in ipairs(loaded) do
                if file == into and created then
                    vim.fn.mkdir(vim.fs.dirname(file.path), "p")
                    vim.fn.writefile(
                        vim.split(encode(decode_jsonc(assert(file.text), file.name), ""), "\n", { plain = true }),
                        file.path
                    )
                elseif file.text and file.text ~= read_text(file.path) then
                    vim.fn.writefile(vim.split(file.text, "\n", { plain = true }), file.path, "b")
                end
            end
        end
    }
end

-- A json step is made per integration, because its commands carry the integration's name.
---@param options HerdrCoreJsonOptions
---@return fun(name: string): HerdrCoreIntegrationStep
function M.json(options)
    return function (name) return json(name, options) end
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

-- `{{start_command}}` and `{{end_command}}` become the hook commands as JSON strings with quotes, which JavaScript reads too.
---@param options { path: string, source: string } `path` is relative to the integration's directory.
---@return HerdrCoreIntegrationStep
function M.template(options)
    ---@param context HerdrCoreIntegrationContext
    ---@return string
    local function content(context)
        local text = table.concat(vim.fn.readfile(options.source, "b"), "\n")
        return (text:gsub("{{([%w_]+)}}", function (placeholder)
            local event = ({ start_command = "started", end_command = "ended" })[placeholder]
            if event then return vim.json.encode(context.hook_command(event)) end
        end))
    end
    ---@param context HerdrCoreIntegrationContext
    ---@return string
    local function path(context)
        return vim.fs.joinpath(context.directory, options.path)
    end
    return {
        check = function (context)
            local target = path(context)
            if vim.fn.filereadable(target) == 0 then return "missing" end
            return table.concat(vim.fn.readfile(target, "b"), "\n") == content(context) and "installed" or "outdated"
        end,
        apply = function (context)
            local target = path(context)
            vim.fn.mkdir(vim.fs.dirname(target), "p")
            vim.fn.writefile(vim.split(content(context), "\n", { plain = true }), target, "b")
        end
    }
end

-- opencode 2 loads plugins listed in cli.json. While it has not yet moved the old settings there, cli.json must
-- not exist, or the move is skipped; until then the old TUI's registration covers this terminal.
---@return HerdrCoreIntegrationStep
local function opencode_cli()
    local step = M.json({ file = "cli.json", append = { plugins = "./herdr-core-nvim" } })("opencode")
    ---@param context HerdrCoreIntegrationContext
    ---@return boolean
    local function waiting(context)
        if vim.fn.filereadable(vim.fs.joinpath(context.directory, "cli.json")) == 1 then return false end
        local state = vim.env.XDG_STATE_HOME
        local kv = vim.fs.normalize((state and state ~= "" and state or "~/.local/state") .. "/opencode/kv.json")
        return vim.fn.filereadable(vim.fs.joinpath(context.directory, "tui.json")) == 1 or vim.fn.filereadable(kv) == 1
    end
    return {
        check = function (context) return waiting(context) and "installed" or step.check(context) end,
        apply = function (context)
            if not waiting(context) then step.apply(context) end
        end
    }
end

-- Claude Code's layout: a group of hooks, which could also carry a matcher. Several agents copy it.
local claude_hooks = {
    ["hooks.{{event}}"] = { hooks = { { type = "command", command = "{{command}}", timeout = 10 } } }
}

---@type table<string, table>
M.builtin = {
    claude = {
        directory = M.directory({ env = "CLAUDE_CONFIG_DIR", path = "~/.claude" }),
        install = {
            M.json({
                file = "settings.json",
                events = { started = "SessionStart", ended = "SessionEnd" },
                append = claude_hooks
            })
        },
        resume_command = function (id) return "claude --resume " .. id end,
        matches_program = M.program({ "claude", "claude-code" })
    },
    codex = {
        directory = M.directory({ env = "CODEX_HOME", path = "~/.codex" }),
        install = {
            M.json({
                file = "hooks.json",
                events = { started = "SessionStart", ended = "SessionEnd" },
                append = claude_hooks,
                parent_id_env = "CODEX_THREAD_ID"
            }),
            M.toml({ file = "config.toml", set = { ["features.hooks"] = true } })
        },
        resume_command = function (id) return "codex resume " .. id end,
        matches_program = M.program({ "codex" })
    },
    -- The agents below get only a start hook, as in Herdr TUI: their labels stay after they exit.
    droid = {
        directory = M.directory({ path = "~/.factory" }),
        install = { M.json({ file = "settings.json", events = { started = "SessionStart" }, append = claude_hooks }) },
        resume_command = function (id) return "droid --resume " .. id end,
        matches_program = M.program({ "droid" })
    },
    qodercli = {
        directory = M.directory({ env = "QODER_CONFIG_DIR", path = "~/.qoder" }),
        install = {
            M.json({
                file = "settings.json",
                events = { started = "SessionStart" },
                append = {
                    ["hooks.{{event}}"] = {
                        matcher = "*",
                        hooks = {
                            {
                                type = "command",
                                command = "{{command}}",
                                timeout = 10
                            }
                        }
                    }
                }
            })
        },
        resume_command = function (id) return "qodercli --resume " .. id end,
        matches_program = M.program({ "qodercli", "qoderclicn", "qoder", "qodercn" })
    },
    qwen = {
        directory = M.directory({ env = "QWEN_HOME", path = "~/.qwen" }),
        install = {
            M.json({
                file = "settings.json",
                events = { started = "SessionStart" },
                -- Qwen Code counts in milliseconds.
                append = {
                    ["hooks.{{event}}"] = {
                        matcher = "*",
                        hooks = { { type = "command", command = "{{command}}", timeout = 10000 } }
                    }
                }
            })
        },
        resume_command = function (id) return "qwen --resume " .. id end,
        matches_program = M.program({ "qwen", "qwen-code" })
    },
    copilot = {
        directory = M.directory({ env = "COPILOT_HOME", path = "~/.copilot" }),
        install = {
            M.json({
                file = "settings.json",
                events = { started = "SessionStart" },
                append = {
                    ["hooks.{{event}}"] = {
                        type = "command",
                        timeoutSec = 10,
                        [vim.fn.has("win32") == 1 and "powershell" or "bash"] = "{{command}}"
                    }
                }
            })
        },
        resume_command = function (id) return "copilot --resume=" .. id end,
        matches_program = M.program({ "copilot", "github-copilot", "ghcs" })
    },
    cursor = {
        directory = M.directory({ env = "CURSOR_CONFIG_DIR", path = "~/.cursor" }),
        install = {
            M.json({
                file = "hooks.json",
                events = { started = "sessionStart" },
                append = { ["hooks.{{event}}"] = { command = "{{command}}" } },
                set = { version = 1 },
                reply = "{}"
            })
        },
        resume_command = function (id) return "cursor-agent --resume " .. id end,
        matches_program = M.program({ "cursor-agent", "cursor" })
    },
    mastracode = {
        directory = M.directory({ path = "~/.mastracode" }),
        install = {
            M.json({
                file = "hooks.json",
                events = { started = "SessionStart" },
                append = { ["{{event}}"] = { type = "command", command = "{{command}}", timeout = 10000 } }
            })
        },
        resume_command = function (id) return "mastracode --thread " .. id end,
        matches_program = M.program({ "mastracode", "mastra-code" })
    },
    grok = {
        directory = M.directory({ env = "GROK_HOME", path = "~/.grok" }),
        -- Grok reads every JSON file in hooks/, so this file is the plugin's alone.
        install = {
            M.json({
                file = "hooks/herdr-core-nvim.json",
                events = { started = "SessionStart" },
                append = claude_hooks,
                id_env = "GROK_SESSION_ID"
            })
        },
        resume_command = function (id) return "grok --resume " .. id end,
        matches_program = M.program({ "grok", "grok-build" })
    },
    agy = {
        label = "antigravity",
        directory = M.directory({ path = "~/.gemini/config" }),
        -- Antigravity has no session start event; it runs this before every invocation and needs JSON back.
        install = {
            M.json({
                file = "hooks.json",
                events = { started = "PreInvocation" },
                append = { ["herdr-core-nvim.{{event}}"] = { type = "command", command = "{{command}}", timeout = 10 } },
                reply = "{}"
            })
        },
        resume_command = function (id) return "agy --conversation " .. id end,
        matches_program = M.program({ "agy", "antigravity", "antigravity-cli" })
    },
    pi = {
        directory = M.directory({ env = "PI_CODING_AGENT_DIR", path = "~/.pi/agent" }),
        install = { M.template({ path = "extensions/herdr-core-nvim.ts", source = M.asset("integrations/pi.ts") }) },
        resume_command = function (id) return "pi --session " .. id end,
        matches_program = M.program({ "pi" })
    },
    omp = {
        directory = M.directory({ path = "~/.omp/agent" }),
        install = { M.template({ path = "extensions/herdr-core-nvim.ts", source = M.asset("integrations/omp.ts") }) },
        resume_command = function (id) return "omp --resume=" .. id end,
        matches_program = M.program({ "omp" })
    },
    kilo = {
        directory = function ()
            local config = vim.env.XDG_CONFIG_HOME
            return M.directory({ path = (config and config ~= "" and config or "~/.config") .. "/kilo" })()
        end,
        install = { M.template({ path = "plugin/herdr-core-nvim.js", source = M.asset("integrations/kilo.js") }) },
        resume_command = function (id) return "kilo --session " .. id end,
        matches_program = M.program({ "kilo", "kilo-code" })
    },
    opencode = {
        directory = function ()
            local folder = vim.env.OPENCODE_CONFIG_DIR
            if folder and folder ~= "" then return M.directory({ path = folder })() end
            local config = vim.env.XDG_CONFIG_HOME
            return M.directory({ path = (config and config ~= "" and config or "~/.config") .. "/opencode" })()
        end,
        -- Only the TUI knows which session a terminal shows; a server can be shared by several TUIs.
        install = {
            M.template({ path = "herdr-core-nvim.js", source = M.asset("integrations/opencode.js") }),
            M.template({ path = "herdr-core-nvim/tui.js", source = M.asset("integrations/opencode-tui.js") }),
            M.json({ file = { "tui.jsonc", "tui.json" }, append = { plugin = "./herdr-core-nvim.js" } }),
            opencode_cli()
        },
        resume_command = function (id) return "opencode --session " .. id end,
        matches_program = M.program({ "opencode", "opencode2", "open-code" })
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
