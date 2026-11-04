local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local fs = require("nupp.compiler.fs")

local HERE = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")))
local env = envMod.new(fs.absolute(HERE .. "/.."))
local M = {}

local function compile(name, source, listing)
    local path = fs.absolute(HERE .. "/" .. name .. ".nupp")
    local parsed = parser.parse(source, path)
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg or "syntax errors")
    local diagnostics = check.check(parsed, path, env, {moduleName = name, strict = false})
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "diagnostics")
    if listing then
        program.image(parsed, name, path, listing)
    end

    return program.run(parsed, name, path)
end

function M.statementAssertionsKeepTruthinessEffectsAndFailureMessage()
    local events, ok, message = compile(
        "vmasserttest.statement.fragment",
        [[
local events = ""
local function condition(): boolean
    events ..= "C"
    return true
end
assert(condition(), "successful condition")
assert(0, "zero is true")
assert("", "empty string is true")
local ok, problem = pcall(function(): nil
    assert(false, "assert failure marker")
end)
return events, ok, tostring(problem)
]]
    )
    test.eq(events, "C")
    test.eq(ok, false)
    test(message:find("assert failure marker", 1, true) ~= nil)
end

function M.shadowedAssertionsStillCallTheirFunction()
    local calls, value, message = compile(
        "vmasserttest.shadow.fragment",
        [[
local calls = 0
local seen: any = nil
local text = ""
local function replacement(value: any, message: string): nil
    calls += 1
    seen, text = value, message
end
local assert = replacement
assert(false, "replacement")
return calls, seen, text
]]
    )
    test.eq(calls, 1)
    test.eq(value, false)
    test.eq(message, "replacement")
end

function M.resultAssertionsAndDynamicMessagesKeepTheirValues()
    local first, message, events = compile(
        "vmasserttest.results.fragment",
        [[
local events = ""
local function message(): string
    events ..= "M"
    return "returned message"
end
local first, second = assert(0, message())
assert(true, message())
return first, second, events
]]
    )
    test.eq(first, 0)
    test.eq(message, "returned message")
    test.eq(events, "MM")
end

function M.successfulStatementAssertionsHaveAColdFailureCall()
    local listing = {}
    local run = compile(
        "vmasserttest.branch.fragment",
        [[
return function(value: any): nil
    assert(value, "condition failed")
end
]],
        listing
    )
    local branch, call = false, false
    for _, fn in ipairs(listing) do
        for _, instruction in ipairs(fn.instructions) do
            branch = branch or instruction.op == "JmpIf"
            call = call or instruction.op == "CallDyn"
        end
    end
    test(branch and call)
    run(true)
    local ok, message = pcall(run, false)
    test.eq(ok, false)
    test(tostring(message):find("condition failed", 1, true) ~= nil)
end

return M
