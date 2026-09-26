local runner = require("nupp.tools.cli.testrunner")

local M = {}

function M.workerCommandQuotesShellMetacharactersInTheCompilerPath()
    local compilerRoot = "/tmp/compiler's $HOME `false`"
    local savedGetenv = os.getenv
    local savedArg = arg
    local savedDir = rawget(_G, "__NUPP_TEST_DIR")
    local savedCommand = rawget(_G, "__NUPP_TEST_RUNNER_COMMAND")
    local savedBundled = package.loaded["nupp.compiler.bundled"]
    os.getenv = function(name)
        if name == "NUPP_COMPILER_ROOT" then
            return compilerRoot
        end
        return savedGetenv(name)
    end
    package.loaded["nupp.compiler.bundled"] = {
        source = function()
            return "return 0"
        end,
    }

    local ok, problem = pcall(runner.run, {})
    local command = rawget(_G, "__NUPP_TEST_RUNNER_COMMAND")
    os.getenv = savedGetenv
    arg = savedArg
    rawset(_G, "__NUPP_TEST_DIR", savedDir)
    rawset(_G, "__NUPP_TEST_RUNNER_COMMAND", savedCommand)
    package.loaded["nupp.compiler.bundled"] = savedBundled

    assert(ok, problem)
    assert(command == "'/tmp/compiler'\\''s $HOME `false`/bin/nupp' test --internal-runner", tostring(command))
end

return M
