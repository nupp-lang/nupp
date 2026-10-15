-- Where explicit SIMD primitives are refused when an `@aot` body is lowered: each
-- unsupported domain is reported at its source position, before any backend.
local M = {}
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if HERE:sub(1, 1) ~= "/" and not HERE:match("^%a:[/\\]") then
    local pipe = assert(io.popen("pwd"))
    HERE = assert(pipe:read("*l")) .. "/" .. HERE
    pipe:close()
end

function M.unsupportedPrimitiveDomainsHavePositionedRefusals()
    local parser = require("nupp.compiler.syntax.parser")
    local check = require("nupp.compiler.check")
    local env = require("nupp.compiler.project.env").new(HERE .. "/..")
    local compile = require("nupp.compiler.aot.compile")
    local diagnostic = require("nupp.compiler.diagnostics")
    local target = assert(require("nupp.compiler.aot.target").select("aarch64-apple-darwin", "neon"))
    local cases = {
        {
            "floatBitwise",
            "local s = assert(simd.species(array.float, 4)); local a = s:splat(1); return (a & a):extract(1)",
            "bitwise"
        },
        {
            "floatSwizzle",
            "local s = assert(simd.species(array.float, 4)); local a = s:splat(1); return a:swizzle(a):extract(1)",
            "integer"
        },
        {
            "floatPrefixXor",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):prefixXor():extract(1)",
            "integer"
        },
        {
            "reinterpretWidth",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 4)); return s:reinterpret(t:splat(1)):extract(1)",
            "width"
        },
        {
            "convertSpecies",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 3)); return s:convert(t:splat(1)):extract(1)",
            "Fixed"
        },
        {
            "maskSpecies",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.number, 3)); return s:mask(t:mask(true)):select(1, 0):extract(1)",
            "Fixed"
        },
        {
            "preferredMaskWidth",
            "local s = assert(simd.species(array.float)); local t = assert(simd.species(array.number)); return s:mask(t:mask(true)):select(1, 0):extract(1)",
            "lane counts"
        },
        {
            "alignRuntimeCount",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):align(s:splat(2), #input):extract(1)",
            "compile-time"
        },
        {
            "extractRuntimeLane",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(#input)",
            "compile-time"
        },
        {
            "extractPastLanes",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(s.lanes + 1)",
            "lane"
        },
        {
            "preferredExtractPastLanes",
            "local s = assert(simd.species(array.float)); return s:splat(1):extract(s.lanes + 1)",
            "lane"
        },
        {
            "preferredInsertZeroLane",
            "local s = assert(simd.species(array.float)); return s:splat(1):insert(s.lanes - s.lanes, 2):extract(1)",
            "lane"
        },
        {
            "widenPast64",
            "local s = assert(simd.species(array.number)); local w = s:widen(array.number); return w:splat(1):extract(1)",
            "wider than 64 bits",
            7
        },
        {
            "narrowBelow8",
            "local s = assert(simd.species(array.uint8, 4)); local w = s:narrow(array.uint8); return w:splat(1):extract(1)",
            "narrower than 8 bits",
            7
        },
        {
            "widenSkipsAWidth",
            "local s = assert(simd.species(array.uint8)); local w = s:widen(array.uint32); return w:splat(1):extract(1)",
            "next wider element",
            7
        },
        {
            "widenChangesSign",
            "local s = assert(simd.species(array.int8)); local w = s:widen(array.uint16); return w:splat(1):extract(1)",
            "next wider element",
            7
        },
        {
            "narrowSkipsAWidth",
            "local s = assert(simd.species(array.number)); local w = s:narrow(array.uint16); return w:splat(1):extract(1)",
            "next narrower element",
            7
        },
        {
            "widenedMeetsPreferred",
            "local s = assert(simd.species(array.uint8)); local w = s:widen(array.uint16); local t = assert(simd.species(array.uint16)); return (w:splat(1) + t:splat(1)):extract(1)",
            "species identities"
        },
        {
            "preferredConvertWidth",
            "local s = assert(simd.species(array.uint8)); local t = assert(simd.species(array.uint16)); return t:convert(s:splat(1)):extract(1)",
            "widen and narrow"
        },
        {"extractZero", "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(0)", "lane"},
        {"extractPastEnd", "local s = assert(simd.species(array.float, 4)); return s:splat(1):extract(5)", "lane"},
        {
            "insertPastEnd",
            "local s = assert(simd.species(array.float, 4)); return s:splat(1):insert(5, 2):extract(1)",
            "lane"
        },
        {
            "preferredExtractPastEnd",
            "local s = assert(simd.species(array.float)); return s:splat(1):extract(5)",
            "lane"
        },
        {
            "preferredInsertPastEnd",
            "local s = assert(simd.species(array.float)); return s:splat(1):insert(5, 2):extract(1)",
            "lane"
        },
        {
            "preferredTranspose",
            "local s = assert(simd.species(array.float)); local a, b = simd.transpose(s:splat(1), s:splat(2)); return a:extract(1) + b:extract(1)",
            "fixed-width",
            7
        },
        {
            "preferredGatherWidth",
            "local s = assert(simd.species(array.float)); local t = assert(simd.species(array.uint64)); return s:gather(input, t:iota(1, 1)):extract(1)",
            "same logical lane count"
        },
        {
            "narrowGatherIndices",
            "local s = assert(simd.species(array.float, 4)); local t = assert(simd.species(array.uint8, 4)); return s:gather(input, t:iota(1, 1)):extract(1)",
            "indices"
        },
    }
    for _, case in ipairs(cases) do
        local filename = "simd-domain-" .. case[1] .. ".nupp"
        local source = [[local simd = require("nupp.simd")
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
@aot
local function refused(borrows input: span.Span<float>): number
    ]]
            .. case[
                2
            ]:gsub("; ", "\n    ") .. [[
end
return {refused=refused}
]]
        local tree = parser.parse(source, filename)
        assert(#tree.errors == 0, case[1] .. ": invalid refusal fixture")
        local problems = {}
        for _, problem in ipairs(check.check(tree, filename, env)) do
            if diagnostic.isFatal(problem) then
                problems[#problems + 1] = problem
            end
        end
        if #problems == 0 then
            local _, lowered = compile.artifacts(source, filename, tree, target)
            problems = lowered
        end
        assert(#problems > 0, case[1] .. ": unsupported operation was accepted")
        local found = false
        for _, problem in ipairs(problems) do
            local text = problem.message or problem.msg or ""
            if text:find(case[3], 1, true) then
                assert(
                    problem.line == (case[4] or 6 + select(2, case[2]:gsub(";", "")))
                    and (problem.column or problem.col or 0) > 0,
                    case[1] .. ": refusal lost its source position"
                )
                found = true
            end
        end
        assert(found, case[1] .. ": wrong refusal: " .. tostring(problems[1].message or problems[1].msg))
    end
end

return M
