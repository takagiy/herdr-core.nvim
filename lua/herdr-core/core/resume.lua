local M = {}

---@class HerdrCoreResumeEffect
---@field type     'resume_session'
---@field terminal string
---@field agent    string
---@field session  string

-- Whether a terminal labelled with `agent` needs its conversation started again, given what runs in front now.
---@alias HerdrCoreResumable fun(agent: string, program: HerdrCoreProgram): boolean

---@param value string?
---@return string?
local function text(value)
    return value ~= nil and value ~= "" and value or nil
end

-- Terminals whose hook left a conversation behind and whose agent no longer runs, each asked for once.
---@param terminals HerdrCoreTerminal[]
---@param resuming  table<string, true>
---@param resumable HerdrCoreResumable?
---@return table<string, true>, HerdrCoreResumeEffect[]
function M.find(terminals, resuming, resumable)
    if not resumable then return resuming, {} end
    local next_resuming, effects = vim.deepcopy(resuming), {}
    local ordered = vim.deepcopy(terminals)
    table.sort(ordered, function (a, b) return a.address < b.address end)
    for _, terminal in ipairs(ordered) do
        local agent = text(terminal.labels["herdr-core-nvim.agent"])
        local session = text(terminal.labels["herdr-core-nvim.session"])
        local program = { app = terminal.app, name = terminal.program, argv = terminal.argv }
        -- The same first process means the user quit the agent; hc restarting the terminal gives it a new one.
        local recorded = text(terminal.labels["herdr-core-nvim.pid"])
        local quit = recorded ~= nil and terminal.pid ~= nil and recorded == tostring(terminal.pid)
        if agent and session and not quit and not terminal.machine and not next_resuming[terminal.address]
            and resumable(agent, program) then
            next_resuming[terminal.address] = true
            effects[#effects + 1] = {
                type = "resume_session",
                terminal = terminal.address,
                agent = agent,
                session = session
            }
        end
    end
    return next_resuming, effects
end

return M
