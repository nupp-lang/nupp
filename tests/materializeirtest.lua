local testAssert = require("nupp.test")
local ir = require("nupp.compiler.comptime.materialize.ir")
local codec = require("nupp.compiler.comptime.materialize.codec")
local providers = require("nupp.compiler.comptime.materialize.providers")

local M = {}

function M.rendersADirectValueWithoutSourceFragments()
    local rendered, failure = ir.render({
        tag = "table",
        fields = {{name = "answer", value = {tag = "literal", value = 42}},},
    })
    testAssert.equal(failure, nil, "valid IR renders")
    testAssert.equal(rendered, "{answer=42}", "direct value")
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
    testAssert.equal(failure, nil, "factory IR renders")
    testAssert.equal(
        rendered,
        "function(_nupp_m1) local _nupp_m2=(_nupp_m1).build;return (_nupp_m2)(3) end",
        "locals are renderer-owned"
    )
    testAssert.equal(rendered:find("\n", 1, true), nil, "the factory occupies one logical line")
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
    testAssert.equal(codec.canonical(first), codec.canonical(second), "mixed keys have canonical bytes")
end

function M.renderedDataIsClosedAndStaysOnOneLine()
    local rendered, failure = codec.render({line = "first\nsecond"})
    testAssert.equal(failure, nil, "a newline string renders")
    testAssert.equal(rendered:find("\n", 1, true), nil, "rendered data occupies one logical line")
    local value = assert(loadstring("return " .. rendered))()
    testAssert.equal(value.line, "first\nsecond", "one-line quoting preserves the value")

    local unsupported, unsupportedFailure = codec.render({[false] = 1})
    testAssert.equal(unsupported, nil, "unsupported keys are not discarded")
    testAssert.equal(unsupportedFailure, "invalid", "unsupported key failure")
    local nonfinite, nonfiniteFailure = codec.render(math.huge)
    testAssert.equal(nonfinite, nil, "nonfinite numbers are not ambient globals")
    testAssert.equal(nonfiniteFailure, "invalid", "nonfinite failure")
end

function M.rejectsMalformedCollectionsAndInvalidLuaForms()
    local ok, rendered, failure = pcall(ir.render, {
        tag = "call",
        callee = {tag = "helper", name = "nupp.fieldcodec.keyed"},
        args = "not a list",
    })
    assert(ok, "malformed worker IR must return a failure")
    testAssert.equal(rendered, nil, "malformed call does not render")
    assert(failure and failure.message:find("not a list", 1, true), failure and failure.message)

    local _, keyword = ir.render({tag = "table", fields = {{name = "end", value = {tag = "literal", value = 1}}},})
    assert(keyword and keyword.message:find("invalid", 1, true), keyword and keyword.message)

    local newline, newlineFailure = ir.render({tag = "literal", value = "first\nsecond"})
    testAssert.equal(newlineFailure, nil, "newline literal renders")
    testAssert.equal(newline:find("\n", 1, true), nil, "IR output occupies one logical line")
    testAssert.equal(assert(loadstring("return " .. newline))(), "first\nsecond", "IR quoting preserves the value")

    local _, afterReturn = ir.render({
        tag = "function",
        body = {
            {tag = "return", value = {tag = "literal", value = 1}},
            {tag = "callstat", value = {tag = "call", callee = {tag = "helper", name = "nupp.fieldcodec.keyed"}}},
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
    testAssert.equal(failure.code, "NUPP2415", "worker data is validated before lowering")
end

function M.canonicalNumbersPreserveSubtypeAndExactBits()
    local seen = {}
    for _, text in ipairs({
        "9007199254740992",
        "9007199254740993",
        "9223372036854775806",
        "9223372036854775807",
        "-9223372036854775808",
        "-9223372036854775807",
        "1",
        "1.0",
        "0",
        "0.0",
        "-0.0",
    }) do
        local value = assert(tonumber(text))
        local encoded, failure = codec.canonical(value)
        testAssert.equal(failure, nil, "numeric canonical data is valid")
        assert(not seen[encoded], text .. " collides with " .. tostring(seen[encoded]))
        seen[encoded] = text
        testAssert.equal(codec.canonical(value), encoded, "canonical identity is stable")
    end
end

function M.numericRenderersPreserveExactLiterals()
    local metadata = require("nupp.compiler.vm.metadata")
    for _, text in ipairs({
        "9007199254740993",
        "9223372036854775807",
        "-9223372036854775808",
        "-9223372036854775807",
        "0",
        "1",
        "1.0",
        "0.0",
        "-0.0",
    }) do
        local value = assert(tonumber(text))
        local data, dataFailure = codec.render(value)
        local expression, expressionFailure = ir.render({tag = "literal", value = value})
        testAssert.equal(dataFailure, nil, "numeric data renders")
        testAssert.equal(expressionFailure, nil, "numeric IR renders")
        testAssert.equal(data, text, "data preserves numeric literal")
        testAssert.equal(expression, text, "IR preserves numeric literal")
        testAssert.equal(metadata.literal(value).token.text, text, "metadata preserves numeric token")
        for _, rendered in ipairs({data, expression}) do
            local decoded = assert(loadstring("return " .. rendered))()
            testAssert.equal(math.type(decoded), math.type(value), "rendering preserves numeric subtype")
            testAssert.equal(decoded, value, "rendering preserves numeric value")
            if value == 0 then
                testAssert.equal(1 / decoded, 1 / value, "rendering preserves zero sign")
            end
        end
    end
end

return M
