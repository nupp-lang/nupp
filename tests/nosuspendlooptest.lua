local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local sharedEnv = envMod.new(here)

local function diagnose(source)
    local result = parser.parse(source, "test.g.nupp")
    assert(#result.errors == 0, "loop annotation did not parse")
    local refusals = {}
    for _, diagnostic in ipairs(check.check(result, "test.g.nupp", sharedEnv)) do
        if diagnostic.code == "NUPP2701" then
            refusals[#refusals + 1] = diagnostic
        end
    end

    return refusals, result
end

local M = {}

function M.numericHeaderAndBody()
    local number = "local function number(): number\n" .. "    coroutine.yield()\n    return 1\nend\n"
    assert(#diagnose(number .. "@nosuspend\nfor i = number(), 2 do\nend") == 1)

    local noisy = "local function noisy(): nil\n    coroutine.yield()\nend\n"
    local refusals = diagnose(noisy .. "@nosuspend\nfor i = 1, 2 do\n    noisy()\nend\nnoisy()")
    assert(#refusals == 1, "the region covers the body and ends with the loop")
end

function M.genericIteratorStep()
    local iterator = "local function iter(): function(): integer?\n"
        .. "    return function(): integer?\n        coroutine.yield()\n        return nil\n    end\nend\n"
    local refusals = diagnose(iterator .. "@nosuspend\nfor value in iter() do\n    print(value)\nend")
    assert(#refusals == 1 and refusals[1].msg:find("iterator", 1, true), "the implicit iterator step is covered")
end

function M.whileAndRepeatConditions()
    local condition = "local function condition(): boolean\n" .. "    coroutine.yield()\n    return false\nend\n"
    assert(#diagnose(condition .. "@nosuspend\nwhile condition() do\nend") == 1)
    assert(#diagnose(condition .. "@nosuspend\nrepeat\nuntil condition()") == 1)
end

function M.loopBodyCleanup()
    local resource = table.concat(
        {
            "local record Resource value: integer end",
            "local park: function(): nil = nil as any",
            "local function settling(takes value: Resource): nil park() end",
            "local function open(): affine(Resource, settling)",
            "    return new Resource(value = 1)",
            "end",
        },
        "\n"
    ) .. "\n"
    local refusals = diagnose(resource .. "@nosuspend\nfor i = 1, 2 do\n    local value = open()\nend")
    assert(
        #refusals == 1 and refusals[1].msg:find("settling", 1, true),
        "a loop body owner must settle without suspending"
    )
end

function M.annotationErases()
    local source = "@nosuspend\nfor index = 1, 3 do\n    print(index)\nend\n"
    local refusals, result = diagnose(source)
    assert(#refusals == 0)
    local code = gen.generate(result, "test")
    assert(
        not code:find("nosuspend", 1, true) and code:find("for index", 1, true),
        "the annotation is erased without removing the loop"
    )
end

return M
