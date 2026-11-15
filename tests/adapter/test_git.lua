local MiniTest = require("mini.test")
local T = MiniTest.new_set()

T["returns the repository root for a nested folder"] = function ()
    -- Given a nested folder inside this repository
    local folder = vim.fn.getcwd() .. "/lua/herdr-core"
    ---@type string?
    local root
    local completed = false
    -- When its repository root is requested
    require("herdr-core.adapter.git").root(folder, nil, function (value)
        root = value
        completed = true
    end)
    assert(vim.wait(5000, function () return completed end))
    -- Then Git's repository root is returned
    MiniTest.expect.equality(root, (vim.fn.getcwd():gsub("\\", "/")))
end

T["returns no root outside a repository"] = function ()
    -- Given a temporary folder outside any repository
    local folder = vim.fn.tempname()
    vim.fn.mkdir(folder, "p")
    local completed = false
    ---@type string?
    local root = "pending"
    -- When its root is requested
    require("herdr-core.adapter.git").root(folder, nil, function (value)
        root = value
        completed = true
    end)
    local finished = vim.wait(5000, function () return completed end)
    vim.fn.delete(folder, "d")
    -- Then no repository root is returned
    MiniTest.expect.equality(finished, true)
    MiniTest.expect.equality(root, nil)
end

T["uses hc exec on the requested remote machine"] = function ()
    -- Given a process boundary capturing the requested argv
    local system = vim.system
    local argv
    ---@param command   string[]
    ---@param _options  table?
    ---@param callback? fun(result: vim.SystemCompleted)
    ---@return vim.SystemObj
    vim.system = function (command, _options, callback)
        argv = command
        assert(callback)({ code = 0, signal = 0, stdout = "/remote/project\n", stderr = "" })
        return {} --[[@as vim.SystemObj]] -- No process methods are used by this adapter.
    end
    ---@type string?
    local result
    -- When a remote root is requested
    local ok, err = pcall(function ()
        require("herdr-core.adapter.git").root("/remote/project/src", "server", function (value) result = value end)
    end)
    vim.system = system
    assert(ok, err)
    -- Then the lookup runs there, not on the local computer
    MiniTest.expect.equality(
        argv,
        { "hc", "exec", "--on", "server", "--", "git", "-C", "/remote/project/src", "rev-parse", "--show-toplevel" }
    )
    MiniTest.expect.equality(result, "/remote/project")
end

T["returns no root when the executable cannot be started"] = function ()
    -- Given a missing git or hc executable
    local system = vim.system
    vim.system = function () error("ENOENT") end
    local completed = false
    ---@type string?
    local root = "pending"
    -- When a root lookup is attempted
    local ok = pcall(function ()
        require("herdr-core.adapter.git").root("/app", nil, function (value)
            root = value
            completed = true
        end)
    end)
    vim.system = system
    -- Then the optional root lookup completes without crashing the client
    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(completed, true)
    MiniTest.expect.equality(root, nil)
end

T["returns the worktree root rather than the main checkout"] = function ()
    -- Given a temporary repository with an additional worktree
    local repository = vim.fn.tempname()
    local worktree = vim.fn.tempname()
    vim.fn.mkdir(repository, "p")
    assert(vim.system({ "git", "init", repository }):wait().code == 0)
    assert(vim.system({
            "git",
            "-C",
            repository,
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "--allow-empty",
            "-m",
            "fixture"
        }):wait().code == 0)
    assert(vim.system({ "git", "-C", repository, "worktree", "add", "-b", "other", worktree }):wait().code == 0)
    local completed = false
    ---@type string?
    local root
    -- When the worktree's root is requested
    require("herdr-core.adapter.git").root(worktree, nil, function (value)
        root = value
        completed = true
    end)
    local finished = vim.wait(5000, function () return completed end)
    assert(vim.system({ "git", "-C", repository, "worktree", "remove", worktree }):wait().code == 0)
    vim.fn.delete(repository, "rf")
    -- Then the worktree root is returned
    MiniTest.expect.equality(finished, true)
    MiniTest.expect.equality(root, (worktree:gsub("\\", "/")))
end

return T
