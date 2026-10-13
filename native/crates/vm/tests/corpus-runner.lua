-- Each suite keeps its existing assertions; this driver only invokes its cases.
local runner = {}

function runner.main(argv)
    require("nupp.vm.math")
    require("nupp.compiler.syntax.triviaarena").install(require("nupp.compiler.syntax.triviaarena.table"))
    require("nupp.compiler.vm.chunks").install()
    local suite = require(argv[1])
    local hooks = {beforeAll = true, afterAll = true, beforeEach = true, afterEach = true}
    local names = {}
    for name, value in pairs(suite) do
        assert(type(name) == "string" and name ~= "" and not name:find("[%c]"), "invalid test name")
        assert(type(value) == "function", "test entry is not a function: " .. name)
        if not hooks[name] and (not argv[2] or name == argv[2]) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    local passed, failed = 0, 0
    local json = require("nupp.codec.json")
    local test = require("nupp.test")

    local function report(name, ok, problem, context)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
        io.write(
            json.encode({
                suite = argv[1],
                name = name,
                ok = ok,
                error = not ok and (test.notExecutedReason(problem) or test.skipReason(problem) or tostring(problem))
                or nil,
                disposition = test.isNotExecuted(problem) and "not-executed"
                or test.isSkip(problem) and "skipped"
                or nil,
                capabilities = context and context.capabilities or nil,
                facts = context and context.facts or nil,
                metrics = context and context.metrics or nil
            }),
            "\n"
        )
    end

    local function invoke(fn)
        if fn then
            return pcall(fn)
        end
        return true
    end

    local ready, problem = invoke(suite.beforeAll)
    if not ready then
        report("beforeAll", false, problem)
    else
        for _, name in ipairs(names) do
            local context = {facts = {}, metrics = {}, capabilities = {}, fixtures = {}}
            context.fixture = function()
                error("VM corpus fixture store is not implemented", 0)
            end
            rawset(_G, "__NUPP_TEST_CASE_CONTEXT", context)
            local ok, why = invoke(suite.beforeEach)
            if ok then
                ok, why = pcall(suite[name])
            end
            local cleaned, cleanupProblem = invoke(suite.afterEach)
            if not cleaned then
                why = (not ok and tostring(why) .. "\n" or "") .. "afterEach failed: " .. tostring(cleanupProblem)
                ok = false
            end
            rawset(_G, "__NUPP_TEST_CASE_CONTEXT", nil)
            report(name, ok, why, context)
        end
    end
    local cleaned, cleanupProblem = invoke(suite.afterAll)
    if not cleaned then
        report("afterAll", false, cleanupProblem)
    end
    io.write(json.encode({suite = argv[1], passed = passed, failed = failed, total = passed + failed}), "\n")

    return failed == 0 and 0 or 1
end

return runner
