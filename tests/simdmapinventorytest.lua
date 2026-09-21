local M = {}
local maps = require("tests.simd.maps")
local admitted = require("nupp.compiler.aot.admit")

function M.mathMapCorpusCoversEveryAdmittedIdentityAndVariadicForms()
    for _, target in ipairs({"native", "wasm"}) do
        local refused = target == "wasm"
            and {["math.sinh"] = true, ["math.cosh"] = true, ["math.tanh"] = true, ["math.atan2"] = true}
            or {}
        local generated = maps.generate({types = {"float", "number"}, lanes = {2, "preferred"}, target = target})
        local seenElements = {}
        for _, coverage in ipairs(generated.coverage) do
            seenElements[coverage.element] = true
            local actual = {}
            for _, contract in ipairs(coverage.contracts) do
                actual[contract.path] = actual[contract.path] or {}
                assert(not actual[contract.path][contract.arity], "duplicate map contract")
                actual[contract.path][contract.arity] = true
            end
            local actualRefusals = {}
            for _, path in ipairs(coverage.targetRefusals) do
                assert(refused[path]);
                actualRefusals[path] = true
            end
            for path in pairs(refused) do
                assert(actualRefusals[path], "missing explicit portable refusal")
            end
            for path, specification in pairs(admitted.MATH) do
                if not refused[path] then
                    local arities = assert(actual[path], "missing admitted map identity " .. path)
                    for arity = specification.min, specification.max or 4 do
                        assert(arities[arity], "missing admitted map arity " .. path .. "/" .. arity)
                        arities[arity] = nil
                    end
                    assert(next(arities) == nil, "unadmitted map arity")
                    actual[path] = nil
                end
            end
            if coverage.element == "float" then
                for path, arity in pairs({
                    ["nupp.math.f32.min"] = 2,
                    ["nupp.math.f32.max"] = 2,
                    ["nupp.math.f32.fma"] = 3
                }) do
                    local arities = assert(actual[path], "missing corrected map " .. path)
                    assert(arities[arity]);
                    arities[arity] = nil
                    assert(next(arities) == nil)
                    actual[path] = nil
                end
            end
            assert(next(actual) == nil, "map corpus claims an unadmitted identity")
        end
        assert(seenElements.float and seenElements.number)
    end
    local integers = maps.generate({
        types = {"int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"},
        lanes = {2, "preferred"}
    })
    assert(
        next(integers.probes) == nil and #integers.coverage == 0,
        "math maps are explicitly refused for integer species"
    )
end

function M.portableMathTargetRefusalsRemainPositionedAndNativeAccepted()
    local parser = require("nupp.compiler.parser")
    local check = require("fragment")
    local env = require("nupp.compiler.env").new("tests")
    local source = "local functions = {\n    math.sinh,\n    math.cosh,\n    math.tanh,\n    math.atan2,\n}\nreturn functions"
    for _, dialect in ipairs({"luajit"}) do
        local parsed = parser.parse(source, "maps-target.g.nupp")
        assert(#parsed.errors == 0)
        local diagnostics = check.check(parsed, "maps-target.g.nupp", env, {dialect = dialect})
        if dialect == "luajit" then
            assert(#diagnostics == 0)
        else
            assert(#diagnostics == 4, "exactly four runtime-specific math identities")
            local expected = {"math.sinh", "math.cosh", "math.tanh", "math.atan2"}
            for i, diagnostic in ipairs(diagnostics) do
                assert(diagnostic.code == "NUPP3010" and diagnostic.msg:find(expected[i], 1, true))
                assert(
                    diagnostic.line == i + 1 and diagnostic.col == 10,
                    "refusal must point at the authored math member"
                )
            end
        end
    end
end

return M
