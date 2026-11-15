local ok, err = pcall(function ()
    dofile("scripts/minimal_init.lua")
    local MiniTest = require("mini.test")
    local e2e = vim.env.HERDR_TEST_GROUP == "e2e"
    if e2e then
        for _, executable in ipairs({ "hc", "node" }) do
            assert(vim.fn.executable(executable) == 1, "Missing E2E executable: " .. executable)
        end
    end
    MiniTest.run({
        collect = {
            find_files = function ()
                return vim.tbl_filter(function (path)
                    local is_e2e = path:gsub("\\", "/"):find("tests/e2e/", 1, true) ~= nil
                    return is_e2e == e2e
                end, vim.fn.globpath("tests", "**/test_*.lua", true, true))
            end
        }
    })
    if #MiniTest.current.all_cases == 0 then
        if e2e then error("No E2E cases collected") end
        vim.cmd.qall()
    end
end)

if not ok then
    io.stderr:write(tostring(err), "\n")
    vim.cmd("cquit 1")
end
