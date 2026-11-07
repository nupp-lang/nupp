local test = require("assert")
local fs = require("nupp.compiler.fs")
local M = {}

local function project(source, body)
    local root = os.tmpname()
    os.remove(root)
    assert(fs.mkdir(root))
    assert(fs.writeFile(root .. "/nupp.lua", 'return {include = {"."}}\n'))
    assert(fs.writeFile(root .. "/main.nupp", source))
    local instance = require("helpers.contractproject").open(root)
    local ok, problem = pcall(body, instance, root)
    assert(os.execute(("rm -rf %q"):format(root)) == 0)
    assert(ok, problem)
end

function M.absoluteAndRelativeChecksKeepDiagnosticRanges()
    project("local value: string = 42\nreturn value\n", function(instance, root)
        local accepted, relative = instance.check({"main.nupp"})
        local absoluteAccepted, absolute = instance.check({root .. "/main.nupp"})
        test.eq(accepted, false)
        test.eq(absoluteAccepted, false)
        test.deepeq(absolute, relative)
        test.eq(relative[1].code, "NUPP2001")
        assert(relative[1].range.start.offset > 0)
        assert(relative[1].range["end"].offset > relative[1].range.start.offset)
    end)
end

function M.capturedExecutionRestoresPrintAfterSuccessAndFailure()
    local original = print
    project('print("one", nil, 3)\n', function(instance)
        test.eq(instance.run("main.nupp", true), "one\tnil\t3\n")
        test.eq(print, original)
    end)
    project('print("before failure")\nerror("intentional fixture failure")\n', function(instance)
        local ok, problem = pcall(instance.run, "main.nupp", true)
        test.eq(ok, false)
        test.matches(tostring(problem), "intentional fixture failure")
        test.eq(print, original)
    end)
end

return M
