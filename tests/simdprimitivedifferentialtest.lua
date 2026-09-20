-- The complete species/operation corpus is also consumed by CI's exact-tier
-- native/Wasm matrix. This focused suite exercises representative boundaries.
local M = {}
local generator = require("tests.simd.primitives")
local runner = require("tests.simd.runner")
local HERE = runner.root() .. "/tests"

function M.explicitPrimitivesMatchIndependentScalarSemantics()
    local report = runner.native(generator.generate{lanes = {2, 3, 17, 64, "preferred"}})
    assert(report.cases > 0 and report.nativeCalls >= report.probes)
    local vm = os.getenv("NUPP_SIMD_LUA") or "luajit"
    runner.command("cd " .. runner.quote(report.directory) .. " && " .. runner.quote(vm)
        .. " " .. runner.quote(HERE .. "/simd/execute-scalar.lua"), report.directory .. "/scalar-execution.log")
    local scalar = runner.json(report.directory .. "/scalar-result.json")
    assert(scalar.cases == report.cases and scalar.probes == report.probes and scalar.nativeCalls > 0)
end

function M.unsupportedPrimitiveDomainsHavePositionedRefusals()
    local parser = require("nupp.compiler.parser")
    local check = require("nupp.compiler.check")
    local env = require("nupp.compiler.env").new(HERE .. "/..")
    local compile = require("nupp.compiler.aot.compile")
    local diagnostic = require("nupp.compiler.diagnostics")
    local target = assert(require("nupp.compiler.aot.target").select("aarch64-apple-darwin", "neon"))
    local cases = {
        {"floatBitwise", "local s = assert(simd.species(array.float, 4)); local a = s:splat(1); return (a & a):extract(1)", "bitwise"},
        {"floatSwizzle", "local s = assert(simd.species(array.float, 4)); local a = s:splat(1); return a:swizzle(a):extract(1)", "integer"},
        {"floatPrefixXor", "local s = assert(simd.species(array.float, 4)); return s:splat(1):prefixXor():extract(1)", "integer"},
        {"reinterpretWidth", "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 4)); return s:reinterpret(t:splat(1)):extract(1)", "width"},
        {"convertSpecies", "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 3)); return s:convert(t:splat(1)):extract(1)", "Fixed"},
        {"extractZero", "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(0)", "lane"},
        {"extractPastEnd", "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(5)", "lane"},
        {"insertPastEnd", "local s = assert(simd.species(array.float, 4)); return s:splat(1):insert(5, 2):extract(1)", "lane"},
        {"preferredExtractPastEnd", "local s = assert(simd.species(array.float)); return s:splat(1):extract(5)", "lane"},
        {"preferredInsertPastEnd", "local s = assert(simd.species(array.float)); return s:splat(1):insert(5, 2):extract(1)", "lane"},
        {"preferredTranspose", "local s = assert(simd.species(array.float)); local a, b = simd.transpose(s:splat(1), s:splat(2)); return a:extract(1) + b:extract(1)", "fixed-width", 7},
        {"narrowGatherIndices", "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.uint8, 4)); return s:gather(input, t:iota(1, 1)):extract(1)", "indices"},
    }
    for _, case in ipairs(cases) do
        local filename = "simd-domain-" .. case[1] .. ".g.nupp"
        local source = [[local simd = require("nupp.simd")
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
@aot
local function refused(borrows input: span.Span<float>): number
    ]] .. case[2]:gsub("; ", "\n    ") .. [[
end
return {refused=refused}
]]
        local tree = parser.parse(source, filename)
        assert(#tree.errors == 0, case[1] .. ": invalid refusal fixture")
        local problems = {}
        for _, problem in ipairs(check.check(tree, filename, env)) do
            if diagnostic.isFatal(problem) then problems[#problems + 1] = problem end
        end
        if #problems == 0 then
            local _, lowered = compile.artifacts(source, filename, tree, "refusal", target)
            problems = lowered
        end
        assert(#problems > 0, case[1] .. ": unsupported operation was accepted")
        local found = false
        for _, problem in ipairs(problems) do
            local text = problem.message or problem.msg or ""
            if text:find(case[3], 1, true) then
                assert(problem.line == (case[4] or 6 + select(2, case[2]:gsub(";", ""))) and (problem.column or problem.col or 0) > 0,
                    case[1] .. ": refusal lost its source position")
                found = true
            end
        end
        assert(found, case[1] .. ": wrong refusal: " .. tostring(problems[1].message or problems[1].msg))
    end
end

return M
