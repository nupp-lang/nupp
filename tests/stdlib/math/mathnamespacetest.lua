local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local gen = require("nupp.compiler.lua.gen")
local stdlib = require("nupp.compiler.stdlib")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")
local M = {}

local function compile(source)
    local parsed = parser.parse(source, "math-namespace.nupp")
    test.eq(#parsed.errors, 0)
    for _, diagnostic in ipairs(check.check(parsed, "math-namespace.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local code, diagnostics = gen.generate(parsed, "math-namespace.nupp")
    test.eq(#diagnostics, 0)

    return parsed, code
end

function M.finalMathCallsKeepTheExistingNumericContracts()
    local parsed, code = compile(
        [[
local family = math.u32
local add = family.add
local wrapped: uint32 = add(family.wrap(-1), 1)
local bits: uint32 = math.f32.tobits(math.f32.narrow(1))
return wrapped, bits, math.lerp(10, 20, 0.25)
]]
    )
    assert(parsed.effects["stdlib.math"], "the final surface retains its runtime dependency")
    local wrapped, bits, interpolated = assert(loadstring(code))()
    test.eq(wrapped, 0)
    test.eq(bits, 0x3f800000)
    test.eq(interpolated, 12.5)
end

function M.shadowedMathCallsRemainOrdinaryCalls()
    local parsed, code = compile(
        [[
local math = {u32 = {add = function(a: number, b: number): number return a + b + 40 end}}
return math.u32.add(1, 2)
]]
    )
    test.eq(parsed.effects and parsed.effects["stdlib.math"], nil)
    test.eq(assert(loadstring(code))(), 43)
end

function M.ordinaryMathDoesNotSelectTheExtensionRuntime()
    local parsed = compile("return math.sqrt(9)")
    test.eq(parsed.effects and parsed.effects["stdlib.math"], nil)
end

function M.onlyTheFinalMathSurfaceIsInstalled()
    local names = {"lerp", "wrapangle", "dtangle", "i32", "u32", "u64", "f32", "vec2", "quat"}
    local saved = {}
    for _, name in ipairs(names) do
        saved[name] = rawget(math, name)
    end
    local prior = rawget(_G, "nupp")
    local ok, problem = pcall(function()
        rawset(_G, "nupp", {})
        assert(loadstring(stdlib.bootstrap({["stdlib.math"] = true})))()
        test.eq(rawget(nupp, "math"), nil, "the old public math table is not installed")
        test.eq(rawget(math, "wrapAngle"), nil)
        test.eq(rawget(math, "deltaAngle"), nil)
        test.eq(rawget(math, "deltaangle"), nil)
        for _, name in ipairs(names) do
            assert(math[name] ~= nil, name .. " is installed on the math table")
        end
    end)
    rawset(_G, "nupp", prior)
    for _, name in ipairs(names) do
        rawset(math, name, saved[name])
    end
    assert(ok, problem)
end

return M
