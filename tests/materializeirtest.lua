local testAssert = require("assert")
local ir = require("nupp.compiler.comptime.materialize.ir")
local codec = require("nupp.compiler.comptime.materialize.codec")
local providers = require("nupp.compiler.comptime.materialize.providers")

local M = {}

function M.rendersADirectValueWithoutSourceFragments()
    local rendered, failure = ir.render({
        tag = "table",
        fields = {{name = "answer", value = {tag = "literal", value = 42}},},
    })
    testAssert.eq(failure, nil, "valid IR renders")
    testAssert.eq(rendered, "{answer=42}", "direct value")
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
    testAssert.eq(failure, nil, "factory IR renders")
    testAssert.eq(
        rendered,
        "function(_nupp_m1) local _nupp_m2=(_nupp_m1).build;return (_nupp_m2)(3) end",
        "locals are renderer-owned"
    )
    testAssert.eq(rendered:find("\n", 1, true), nil, "the factory occupies one logical line")
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
    testAssert.eq(codec.canonical(first), codec.canonical(second), "mixed keys have canonical bytes")
end

function M.renderedDataIsClosedAndStaysOnOneLine()
    local rendered, failure = codec.render({line = "first\nsecond"})
    testAssert.eq(failure, nil, "a newline string renders")
    testAssert.eq(rendered:find("\n", 1, true), nil, "rendered data occupies one logical line")
    local value = assert(loadstring("return " .. rendered))()
    testAssert.eq(value.line, "first\nsecond", "one-line quoting preserves the value")

    local unsupported, unsupportedFailure = codec.render({[false] = 1})
    testAssert.eq(unsupported, nil, "unsupported keys are not discarded")
    testAssert.eq(unsupportedFailure, "invalid", "unsupported key failure")
    local nonfinite, nonfiniteFailure = codec.render(math.huge)
    testAssert.eq(nonfinite, nil, "nonfinite numbers are not ambient globals")
    testAssert.eq(nonfiniteFailure, "invalid", "nonfinite failure")
end

function M.rejectsMalformedCollectionsAndInvalidLuaForms()
    local ok, rendered, failure = pcall(ir.render, {
        tag = "call",
        callee = {tag = "helper", name = "nupp.fieldcodec.keyed"},
        args = "not a list",
    })
    assert(ok, "malformed worker IR must return a failure")
    testAssert.eq(rendered, nil, "malformed call does not render")
    assert(failure and failure.message:find("not a list", 1, true), failure and failure.message)

    local _, keyword = ir.render({tag = "table", fields = {{name = "end", value = {tag = "literal", value = 1}}},})
    assert(keyword and keyword.message:find("invalid", 1, true), keyword and keyword.message)

    local newline, newlineFailure = ir.render({tag = "literal", value = "first\nsecond"})
    testAssert.eq(newlineFailure, nil, "newline literal renders")
    testAssert.eq(newline:find("\n", 1, true), nil, "IR output occupies one logical line")
    testAssert.eq(assert(loadstring("return " .. newline))(), "first\nsecond", "IR quoting preserves the value")

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
    testAssert.eq(failure.code, "NUPP2415", "worker data is validated before lowering")
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
        testAssert.eq(failure, nil, "numeric canonical data is valid")
        assert(not seen[encoded], text .. " collides with " .. tostring(seen[encoded]))
        seen[encoded] = text
        testAssert.eq(codec.canonical(value), encoded, "canonical identity is stable")
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
        testAssert.eq(dataFailure, nil, "numeric data renders")
        testAssert.eq(expressionFailure, nil, "numeric IR renders")
        local source = text == "-9223372036854775808" and "0x8000000000000000" or text
        testAssert.eq(data, source, "data preserves numeric literal")
        testAssert.eq(expression, source, "IR preserves numeric literal")
        testAssert.eq(metadata.literal(value).token.text, source, "metadata preserves numeric token")
        for _, rendered in ipairs({data, expression}) do
            local decoded = assert(loadstring("return " .. rendered))()
            testAssert.eq(math.type(decoded), math.type(value), "rendering preserves numeric subtype")
            testAssert.eq(decoded, value, "rendering preserves numeric value")
            if value == 0 then
                testAssert.eq(1 / decoded, 1 / value, "rendering preserves zero sign")
            end
        end
    end
end

return M
