local test = require("assert")
local compile = require("nupp.compiler.aot.compile")
local lower = require("nupp.compiler.aot.lower")
local generator = require("nupp.compiler.lua.gen")
local text = require("nupp.compiler.aot.text")
local nativeonly = require("nupp.compiler.check.nativeonly")
local targetLayout = require("nupp.compiler.targetlayout")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local envMod = require("nupp.compiler.project.env")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local M = {}

local function fixedVector(module)
    return {
        tag = "nominal",
        origin = {moduleName = module, name = "Vector"},
        typeArgs = {
            {tag = "float"},
            {
                tag = "nominal",
                origin = {moduleName = module, name = "Fixed"},
                constArgs = {{tag = "constLiteral", domain = "integer", value = 4}},
            },
        },
    }
end

function M.finalModuleKeepsVectorStorageAndNativeBoundaries()
    for _, module in ipairs({"nupp.simd", "simd"}) do
        local value = fixedVector(module)
        local element, lanes = targetLayout.storageVector(value)
        test.equal(element, "float")
        test.equal(lanes, 4)
        test.equal(nativeonly.carriesNativeOnly(value), true)
        test.equal(nativeonly.fieldMakesNativeOnly(value), false)
        value.typeArgs[2].origin.name = "Preferred"
        test.equal(nativeonly.fieldMakesNativeOnly(value), true)
    end
    test.equal(nativeonly.carriesNativeOnly(fixedVector("user.simd")), false)
end

function M.callAliasesKeepSemanticIdentityAndShadowing()
    for _, module in ipairs({"nupp.simd", "simd"}) do
        test.equal(
            lower.callIdentity({
                kind = "name",
                exactCallExport = {identity = module .. ".species"}
            }),
            "simd.species"
        )
        test.equal(
            lower.callIdentity({
                kind = "name",
                token = {definition = {exactCallExport = {identity = module .. ".reducer.wrappingSum"}}},
            }),
            "simd.reducer.wrappingSum"
        )
    end
    test.equal(
        lower.callIdentity({
            kind = "dotIndex",
            obj = {kind = "name", token = {text = "simd", definition = {}}},
            name = {text = "species"}
        }),
        nil
    )
end

local SCALE = [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local lanes = require(%q)
@aot
local function scale(exclusive values: span.WriteSpan<float>, factor: float): nil
    local species = lanes.species(array.float)
    for at, active in species:over(#values) do
        species:store(values, at, species:load(values, at, active) * factor, active)
    end
end
]]

function M.finalAndLegacyImportsProduceTheSameVerifiedIR()
    local env = envMod.new(HERE .. "/..")
    local resolveModule, resolveExports = env.resolveModule, env.resolveModuleExports
    function env:resolveModule(name, ...)
        return resolveModule(self, name == "nupp.simd" and "simd" or name, ...)
    end

    function env:resolveModuleExports(name, ...)
        return resolveExports(self, name == "nupp.simd" and "simd" or name, ...)
    end

    local before
    for _, module in ipairs({"nupp.simd", "simd"}) do
        local source = SCALE:format(module)
        local parsed = parser.parse(source, "simd-identity.nupp")
        test.equal(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "simd-identity.nupp", env)
        test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local programs, problems = compile.lower(source, "simd-identity.nupp", parsed)
        test.equal(#problems, 0, problems[1] and problems[1].message)
        test.equal(#programs, 1)
        local after = text.programs(programs)
        assert(after:find("simd", 1, true), after)
        if before then
            test.equal(after, before)
        end
        before = after
    end
end

local WORKGROUP = [[
local gpu = require(%q)
local span = require("nupp.mem.span")
@aot(target = "gpu")
local function increment(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): nil
    local groups = math.u32.div(math.u32.wrap(#input), math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        phases:run(function(localIndex: uint32)
            local cursor = math.u32.add(math.u32.mul(groupIndex, math.u32.wrap(4)), localIndex)
            if cursor < #input and cursor < #output then
                output[cursor + 1] = math.u32.add(input[cursor + 1], 1)
            end
        end)
    end)
end
]]

function M.finalAndLegacyGpuImportsProduceTheSameVerifiedWorkgroupIR()
    local before
    for _, module in ipairs({"nupp.gpu", "gpu"}) do
        local programs, problems = compile.lower(WORKGROUP:format(module), "gpu-identity.nupp")
        test.equal(#problems, 0, problems[1] and problems[1].message)
        test.equal(#programs, 1)
        test.equal(programs[1].executionTarget, "gpu")
        local after = text.programs(programs)
        if before then
            test.equal(after, before)
        end
        before = after
    end
end

function M.finalRootAndDirectImportRetainTheSameFunction()
    local source = [[
local imported = require("simd")
return simd.species == imported.species
]]
    local parsed = parser.parse(source, "simd-root.nupp")
    test.equal(#parsed.errors, 0)
    local env = envMod.new(HERE .. "/..")
    local diagnostics = checker.check(parsed, "simd-root.nupp", env)
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, problems = generator.generate(parsed, "simd-root.nupp")
    test.equal(#problems, 0, problems[1] and problems[1].msg)
    test.equal(assert(loadstring(code, "@simd-root.nupp"))(), true)
end

function M.computeLibraryNamesRespectLocalShadowing()
    local source = [[
local simd = {species = function(value: number): number return value + 1 end}
local gpu = {available = function(): boolean return true end}
local events = {id = function(value: number): number return value + 2 end}
return simd.species(1) + events.id(2), gpu.available()
]]
    local parsed = parser.parse(source, "compute-shadow.nupp")
    test.equal(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "compute-shadow.nupp", envMod.new(HERE .. "/.."))
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, problems = generator.generate(parsed, "compute-shadow.nupp")
    test.equal(#problems, 0, problems[1] and problems[1].msg)
    local value, available = assert(loadstring(code, "@compute-shadow.nupp"))()
    test.equal(value, 6)
    test.equal(available, true)
end

function M.formerPublicModulesAreAbsentAndGpuImplementationStaysPrivate()
    local env = envMod.new(HERE .. "/..")
    for _, name in ipairs({"nupp.gpu", "nupp.gpu.layout", "nupp.gpu.spi", "nupp.simd", "nupp.events"}) do
        test.equal(env.resolveModule(env, name), nil, name)
    end
    test.equal(env.moduleAccess(env, "gpu", "nupp.gpu.api"), nil)
    local reason = env.moduleAccess(env, "application", "nupp.gpu.api")
    assert(reason and reason:find("internal", 1, true), tostring(reason))
end

return M
