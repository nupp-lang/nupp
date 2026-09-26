local ir = require("nupp.compiler.comptime.materialize.ir")
local codec = require("nupp.compiler.comptime.materialize.codec")
local providers = require("nupp.compiler.comptime.materialize.providers")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local M = {}

function M.rendersADirectValueWithoutSourceFragments()
    local rendered, failure = ir.render({
        tag = "table",
        fields = {{name = "answer", value = {tag = "literal", value = 42}},},
    })
    assertEq(failure, nil, "valid IR renders")
    assertEq(rendered, "{answer=42}", "direct value")
end

function M.rendersAHygienicFactoryOnOneLine()
    local rendered, failure = ir.render({
        tag = "function",
        params = {1},
        body = {
            {tag = "let", id = 2, value = {tag = "field", object = {tag = "local", id = 1}, name = "build",}},
            {
                tag = "return",
                value = {tag = "call", callee = {tag = "local", id = 2}, args = {{tag = "literal", value = 3}},}
            },
        },
    })
    assertEq(failure, nil, "factory IR renders")
    assertEq(
        rendered,
        "function(_nupp_m1) local _nupp_m2=(_nupp_m1).build;return (_nupp_m2)(3) end",
        "locals are renderer-owned"
    )
    assertEq(rendered:find("\n", 1, true), nil, "the factory occupies one logical line")
end

function M.rejectsAnUndeclaredLocal()
    local _, failure = ir.render({tag = "local", id = 99})
    assert(failure and failure.message:find("undeclared", 1, true), failure and failure.message)
end

function M.rejectsRawSourceAndUnknownOperations()
    local _, failure = ir.render({tag = "source", text = "os.execute('no')"})
    assert(failure and failure.message:find("unknown", 1, true), failure and failure.message)
end

function M.canonicalDataOrdersEncodedEntriesRatherThanAmbiguousKeys()
    local first = {}
    first[2] = "number"
    first["2"] = "string"
    local second = {}
    second["2"] = "string"
    second[2] = "number"
    assertEq(codec.canonical(first), codec.canonical(second), "mixed keys have canonical bytes")
end

function M.renderedDataIsClosedAndStaysOnOneLine()
    local rendered, failure = codec.render({line = "first\nsecond"})
    assertEq(failure, nil, "a newline string renders")
    assertEq(rendered:find("\n", 1, true), nil, "rendered data occupies one logical line")
    local value = assert(loadstring("return " .. rendered))()
    assertEq(value.line, "first\nsecond", "one-line quoting preserves the value")

    local unsupported, unsupportedFailure = codec.render({[false] = 1})
    assertEq(unsupported, nil, "unsupported keys are not discarded")
    assertEq(unsupportedFailure, "invalid", "unsupported key failure")
    local nonfinite, nonfiniteFailure = codec.render(math.huge)
    assertEq(nonfinite, nil, "nonfinite numbers are not ambient globals")
    assertEq(nonfiniteFailure, "invalid", "nonfinite failure")
end

function M.rejectsMalformedCollectionsAndInvalidLuaForms()
    local ok, rendered, failure = pcall(ir.render, {
        tag = "call",
        callee = {tag = "helper", name = "nupp.peg.codegen"},
        args = "not a list",
    })
    assert(ok, "malformed worker IR must return a failure")
    assertEq(rendered, nil, "malformed call does not render")
    assert(failure and failure.message:find("not a list", 1, true), failure and failure.message)

    local _, keyword = ir.render({tag = "table", fields = {{name = "end", value = {tag = "literal", value = 1}}},})
    assert(keyword and keyword.message:find("invalid", 1, true), keyword and keyword.message)

    local newline, newlineFailure = ir.render({tag = "literal", value = "first\nsecond"})
    assertEq(newlineFailure, nil, "newline literal renders")
    assertEq(newline:find("\n", 1, true), nil, "IR output occupies one logical line")
    assertEq(assert(loadstring("return " .. newline))(), "first\nsecond", "IR quoting preserves the value")

    local _, afterReturn = ir.render({
        tag = "function",
        body = {
            {tag = "return", value = {tag = "literal", value = 1}},
            {tag = "callstat", value = {tag = "call", callee = {tag = "helper", name = "nupp.peg.codegen"}}},
        },
    })
    assert(afterReturn and afterReturn.message:find("after return", 1, true), afterReturn and afterReturn.message)
end

function M.rejectsAMalformedWorkerEnvelope()
    local expected = {}
    local _, failure = providers.lower(
        {
            kind = "materialized",
            provider = "compiler-test",
            schema = 1,
            family = "Graph",
            fingerprint = "forged",
            payload = {values = {1}, nexts = {9}},
        },
        expected,
        {globalTypes = {["nupp.__MaterializedTest"] = expected}}
    )
    assertEq(failure.code, "NUPP2415", "worker data is validated before lowering")
end

return M
