local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local environment = require("nupp.compiler.project.env")
local program = require("program")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = environment.new(HERE .. "/..")
local M = {}
local serial = 0

local function checked(source)
    serial = serial + 1
    local name = "numeric-for-" .. serial .. ".nupp"
    local parsed = parser.parse(source, name)
    test.equal(#parsed.errors, 0, "loop fixture syntax")
    for _, diagnostic in ipairs(checker.check(parsed, name, env)) do
        test.assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end

    return parsed, name
end

local function run(source)
    local parsed, name = checked(source)
    return program.run(parsed, name:gsub("%.nupp$", ""))
end

local COLLECT = [[
local values: {string} = {}
local library: any = math
]]
local SAVE = [[
    values[#values + 1] = tostring(library.type(i)) .. ":" .. tostring(i)
    if #values > 8 then error("numeric loop did not terminate") end
]]

function M.integerCountersStopBeforeSignedOverflowAndKeepTheirSubtype()
    for _, row in ipairs({
        {"1, 3", "integer:1,integer:2,integer:3"},
        {
            "18446744073709551614ULL, 18446744073709551615ULL, 1ULL",
            "integer:18446744073709551614,integer:18446744073709551615"
        },
        {"9223372036854775806LL, 9223372036854775807LL", "integer:9223372036854775806,integer:9223372036854775807"},
        {
            "-9223372036854775807LL, -9223372036854775808LL, -1LL",
            "integer:-9223372036854775807,integer:-9223372036854775808"
        },
        {
            "9223372036854775807LL, -9223372036854775808LL, -9223372036854775808LL",
            "integer:9223372036854775807,integer:-1"
        },
        {
            "-9223372036854775808LL, 9223372036854775807LL, 9223372036854775807LL",
            "integer:-9223372036854775808,integer:-1,integer:9223372036854775806"
        },
        {"1LL, 2.5", "integer:1,integer:2"},
        {"3LL, 1LL, -1LL", "integer:3,integer:2,integer:1"},
    }) do
        test.equal(
            run(COLLECT .. "for i = " .. row[1] .. " do\n" .. SAVE .. "end\nreturn table.concat(values, \",\")"),
            row[2]
        )
    end
end

function M.dynamicStepsSelectTheirActualModeAndDirection()
    local function source(start, stop, step)
        return COLLECT
            .. "local function walk(step: number): string\nfor i = "
            .. start
            .. ", "
            .. stop
            .. ", step do\n"
            .. SAVE
            .. "end\nreturn table.concat(values, \",\")\nend\nreturn walk("
            .. step
            .. ")"
    end

    test.equal(run(source("3LL", "1LL", "-1LL")), "integer:3,integer:2,integer:1")
    test.equal(run(source("1LL", "2LL", "0.5")), "float:1.0,float:1.5,float:2.0")
    test.equal(run(source("1.0", "2LL", "1LL")), "float:1.0,float:2.0")
end

function M.boundsAreEvaluatedOnceBeforeTheBodyBindingAndCapturesAreFresh()
    local calls, outer, result = run(
        [[
local calls = 0
local i = 7LL
local function bound(value: number): number
    calls += 1
    return value
end
local captures: {function(): number} = {}
for i = bound(i), bound(i + 2LL), bound(1LL) do
    captures[#captures + 1] = function(): number return i end
end
return calls, i, tostring(captures[1]()) .. "," .. tostring(captures[2]()) .. "," .. tostring(captures[3]())
]]
    )
    test.equal(calls, 3)
    test.equal(tostring(outer), "7")
    test.equal(result, "7,8,9")
end

function M.zeroStepRaisesEvenWhenTheInitialRangeIsEmpty()
    for _, step in ipairs({"0LL", "0.0", "-0.0"}) do
        local parsed, name = checked("for i = 3LL, 1LL, " .. step .. " do end")
        local chunk, problem = program.load(parsed, name:gsub("%.nupp$", ""))
        test.assert(chunk ~= nil, problem)
        local ok, message = pcall(chunk)
        test.equal(ok, false)
        test.assert(tostring(message):find("'for' step is zero", 1, true) ~= nil)
    end
end

return M
