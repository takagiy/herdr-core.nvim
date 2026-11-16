local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local resume = require("herdr-core.core.resume")
local state = require("herdr-core.core.state")

---@param address  string
---@param labels   table<string, string>
---@param program? string
---@param machine? string
---@return HerdrCoreTerminal
local function terminal(address, labels, program, machine)
    return {
        address = address,
        machine = machine,
        labels = labels,
        program = program or "zsh",
        folder = "/app",
        turn = 0,
        created_ms = 1
    }
end

local session = { ["herdr-core-nvim.agent"] = "codex", ["herdr-core-nvim.session"] = "abc" }

-- The agent runs when the foreground program carries its name.
---@param agent   string
---@param program HerdrCoreProgram
---@return boolean
local function resumable(agent, program)
    return agent == "codex" and program.name ~= "codex"
end

T["resumes a conversation whose agent no longer runs"] = function ()
    -- Given a terminal left with codex labels and a shell in front
    -- When terminals are searched
    local resuming, effects = resume.find({ terminal("t1", session) }, {}, resumable)
    -- Then it is asked to resume once, and remembered
    MiniTest.expect.equality(
        effects, { { type = "resume_session", terminal = "t1", agent = "codex", session = "abc" } }
    )
    MiniTest.expect.equality(resuming, { t1 = true })
end

T["leaves terminals that do not need resuming"] = function ()
    -- Given a running agent, an unlabelled shell, an unknown agent, a remote terminal and one already asked
    local terminals = {
        terminal("t1", session, "codex"), terminal("t2", {}),
        terminal("t3", { ["herdr-core-nvim.agent"] = "other", ["herdr-core-nvim.session"] = "x" }),
        terminal("server/t4", session, "zsh", "server"), terminal("t5", session)
    }
    -- When terminals are searched
    local _, effects = resume.find(terminals, { t5 = true }, resumable)
    -- Then none is asked to resume
    MiniTest.expect.equality(effects, {})
end

T["resumes once from the startup list and again after the labels clear"] = function ()
    -- Given the core with a resume rule
    local current = state.new({ resumable = resumable })
    -- When the list arrives twice, the labels are cleared, and the terminal restarts with new labels
    local first, second, third
    current, first = state.update(current, { type = "terminals_listed", terminals = { terminal("t1", session) } })
    current, second = state.update(current, { type = "terminals_listed", terminals = { terminal("t1", session) } })
    current = state.update(current, { type = "labels_changed", terminal = "t1", labels = {} })
    current, third = state.update(current, { type = "terminal_started", terminal = terminal("t1", session) })
    ---@param effects table[]
    ---@return integer
    local function resumes(effects)
        return #vim.tbl_filter(function (effect) return effect.type == "resume_session" end, effects)
    end
    -- Then the first list and the restart each resume, the repeated list does not
    MiniTest.expect.equality({ resumes(first), resumes(second), resumes(third) }, { 1, 0, 1 })
end

return T
