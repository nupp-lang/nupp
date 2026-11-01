local test = require("assert")
local M = {}

function M.theArgumentLibraryKeepsTheActualRawArgv()
    local original = rawget(_G, "arg")
    local before, sequential = {}, {}
    for key, value in pairs(original) do
        before[key] = value
    end
    for key, value in ipairs(original) do
        sequential[key] = value
    end
    local count = #original
    local argv = require("arg")
    test.eq(argv, original)
    test.eq(argv, arg)
    test.eq(require("arg"), argv)
    test.eq(#argv, count)
    local after, traversed = {}, {}
    for key, value in pairs(argv) do
        after[key] = value
    end
    for key, value in ipairs(argv) do
        traversed[key] = value
    end
    test.deepeq(after, before)
    test.deepeq(traversed, sequential)
    for _, name in ipairs({"parse", "schema", "optParser", "getopt", "application", "command"}) do
        test.eq(rawget(argv, name), nil, name)
        test.eq(type(argv[name]), "function", name)
        test.eq(argv[name], getmetatable(argv).__index[name])
    end
    test.eq(rawget(argv, "Arguments"), nil, "derive providers remain erased")
    test.eq(rawget(argv, "Command"), nil, "derive providers remain erased")
    test.eq(argv.decodeAs, nil)
    test.eq(argv.style, nil)
end

function M.theTypedFacadeKeepsProvidersAliasesAndShadowing()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("fragment")
    local gen = require("nupp.compiler.lua.gen")
    local environment = require("nupp.compiler.project.env").new(".")
    local runtime = require("nupp.compiler.runtime")

    local function compile(path, env)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local parsed = parser.parse(source, path)
        if #parsed.errors > 0 then
            return nil, parsed.errors[1].msg
        end
        local diags = checker.check(parsed, path, env)
        if #diags > 0 then
            return nil, diags[1].msg
        end
        local code, generated = gen.generate(parsed, path)
        if #generated > 0 then
            return nil, generated[1].msg
        end

        return code
    end

    local removeLoader = runtime.install(environment, compile)
    local ok, problem = pcall(function()
        local code, reason = compile("tests/fixtures/argfacade.nupp", environment)
        test(code, reason)
        assert(loadstring(code, "@tests/fixtures/argfacade.nupp"))()
    end)
    removeLoader()
    if not ok then
        error(problem, 0)
    end
end

return M
