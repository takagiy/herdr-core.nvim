-- Agents' hooks run this as `nvim -l session-hook.lua <integration> --event started|ended [options]`.
-- It labels the hc terminal the agent runs in, so herdr-core.nvim can resume the conversation after a reboot.
local M = {}

local fields = { "session_id", "sessionId", "conversation_id", "conversationId" }

---@class HerdrCoreHookOptions
---@field name           string
---@field event          'started' | 'ended'
---@field ids            string[]
---@field id_env?        string
---@field parent_id_env? string
---@field reply?         string

---@param argv string[]
---@return HerdrCoreHookOptions?
function M.parse(argv)
    local options = { name = argv[1], ids = {} }
    local index = 2
    while argv[index] do
        local flag, value = argv[index], argv[index + 1]
        if flag == "--event" then
            options.event = value
        elseif flag == "--id" then
            options.ids[#options.ids + 1] = value
        elseif flag == "--id-env" then
            options.id_env = value
        elseif flag == "--parent-id-env" then
            options.parent_id_env = value
        elseif flag == "--reply" then
            options.reply = value
        end
        index = index + 2
    end
    if not options.name or (options.event ~= "started" and options.event ~= "ended") then return nil end
    if #options.ids == 0 then options.ids = fields end
    return options --[[@as HerdrCoreHookOptions]]
end

---@param value any
---@return string?
local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

---@param argv  string[]
---@param input string                       What the agent wrote to the hook's stdin.
---@param env   table<string, string>
---@param run   fun(argv: string[]): string? Runs a command and returns its stdout, or nil when it fails.
---@return string? reply
function M.main(argv, input, env, run)
    local options = M.parse(argv)
    if not options then return nil end
    local terminal = text(env.HC_TERMINAL_ID)
    if not terminal then return options.reply end
    local ok, payload = pcall(vim.json.decode, input ~= "" and input or "{}")
    payload = ok and type(payload) == "table" and payload or {}
    local id = options.id_env and text(env[options.id_env])
    for _, field in ipairs(options.ids) do
        id = id or text(payload[field])
    end
    -- An agent started from inside another one inherits its parent's id; its events are not this terminal's.
    local parent = options.parent_id_env and text(env[options.parent_id_env])
    if parent and parent ~= id then return options.reply end
    if options.event == "ended" then
        run({ "hc", "label", terminal, "herdr-core-nvim.agent=", "herdr-core-nvim.session=", "herdr-core-nvim.pid=" })
    elseif id then
        local labels = {
            "hc", "label", terminal, "herdr-core-nvim.agent=" .. options.name, "herdr-core-nvim.session=" .. id
        }
        -- The terminal's first process changes only when hc restarts the terminal, not when the user quits the agent.
        local found, record = pcall(vim.json.decode, run({ "hc", "get", terminal, "--json" }) or "")
        if found and type(record) == "table" and type(record.pid) == "number" then
            labels[#labels + 1] = "herdr-core-nvim.pid=" .. record.pid
        end
        run(labels)
    end
    return options.reply
end

if arg and arg[0] then
    local reply = M.main(arg, io.read("a") or "", vim.fn.environ(), function (argv)
        local result = vim.system(argv, { text = true }):wait()
        return result.code == 0 and result.stdout or nil
    end)
    if reply then io.write(reply) end
end

return M
