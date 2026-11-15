local ok, err = pcall(function ()
    dofile("scripts/minimal_init.lua")
    local MiniTest = require("mini.test")
    MiniTest.run()
    if #MiniTest.current.all_cases == 0 then
        vim.cmd.qall()
    end
end)

if not ok then
    io.stderr:write(tostring(err), "\n")
    vim.cmd("cquit 1")
end
