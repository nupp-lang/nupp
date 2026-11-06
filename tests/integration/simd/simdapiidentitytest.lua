local test = require("assert")
local compile = require("nupp.compiler.aot.compile")
local lower = require("nupp.compiler.aot.lower")
local generator = require("nupp.compiler.lua.gen")
local text = require("nupp.compiler.aot.text")
local nativeonly = require("nupp.compiler.check.nativeonly")
local targetLayout = require("nupp.compiler.targetlayout")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local HERE = require("helpers.paths").tests

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
        test.eq(element, "float")
        test.eq(lanes, 4)
        test.eq(nativeonly.carriesNativeOnly(value), true)
        test.eq(nativeonly.fieldMakesNativeOnly(value), false)
        value.typeArgs[2].origin.name = "Preferred"
        test.eq(nativeonly.fieldMakesNativeOnly(value), true)
    end
    test.eq(nativeonly.carriesNativeOnly(fixedVector("user.simd")), false)
end

function M.callAliasesKeepSemanticIdentityAndShadowing()
    for _, module in ipairs({"nupp.simd", "simd"}) do
        test.eq(
            lower.callIdentity({
                kind = "name",
                exactCallExport = {identity = module .. ".species"}
            }),
            "simd.species"
        )
        test.eq(
            lower.callIdentity({
                kind = "name",
                token = {definition = {exactCallExport = {identity = module .. ".reducer.wrappingSum"}}},
            }),
            "simd.reducer.wrappingSum"
        )
    end
    test.eq(
        lower.callIdentity({
            kind = "dotIndex",
            obj = {kind = "name", token = {text = "simd", definition = {}}},
            name = {text = "species"}
        }),
        nil
    )
end

local SCALE = [[
local array = table.Array
local span = require("binary.span")
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
        test.eq(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "simd-identity.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local programs, problems = compile.lower(source, "simd-identity.nupp", parsed)
        test.eq(#problems, 0, problems[1] and problems[1].message)
        test.eq(#programs, 1)
        local after = text.programs(programs)
        assert(after:find("simd", 1, true), after)
        if before then
            test.eq(after, before)
        end
        before = after
    end
end

local DIRECT_REDUCERS = [[
local array = table.Array
local span = binary.span
@aot
local function total(borrows values: span.Span<number>): number
    local species = simd.species(array.number)
    local sum = simd.reducer.algebraicsum(0.0)
    for at, active in species:over(#values) do
        sum:add(species:load(values, at, active), active)
    end
    return sum:value()
end
@aot
local function dot(borrows left: span.Span<float>, borrows right: span.Span<float>): float
    local species = simd.species(array.float)
    local sum = simd.reducer.pairwisedot(array.float, 0.0)
    for at, active in species:over(#left) do
        sum:add(species:load(left, at, active), species:load(right, at, active), active)
    end
    return sum:value()
end
]]

function M.directNestedReducerNamespacesKeepCheckedIdentity()
    local env = envMod.new(HERE .. "/..")
    for _, source in ipairs({
        DIRECT_REDUCERS,
        "local reducers = simd.reducer\n" .. DIRECT_REDUCERS:gsub("simd%.reducer%.", "reducers.")
    }) do
        local parsed = parser.parse(source, "direct-reducers.nupp")
        test.eq(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "direct-reducers.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local programs, problems = compile.lower(source, "direct-reducers.nupp", parsed)
        test.eq(#problems, 0, problems[1] and problems[1].message)
        test.eq(#programs, 2)
    end
end

function M.lexicalReducerNamespaceShadowIsNotAnIntrinsic()
    local source = [[
local simd = {reducer = {algebraicsum = function(value: number): number
    return value
end}}
@aot
local function total(): number
    return simd.reducer.algebraicsum(1.0)
end
]]
    local env = envMod.new(HERE .. "/..")
    local parsed = parser.parse(source, "shadow-reducers.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "shadow-reducers.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local _, problems = compile.lower(source, "shadow-reducers.nupp", parsed)
    assert(#problems > 0, "a lexical lookalike must not acquire intrinsic identity")
    test.eq(problems[1].code, "NUPP2905")
end

local WORKGROUP = [[
local gpu = require(%q)
local span = require("binary.span")
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

function M.gpuImportAndDirectNamespaceProduceTheSameVerifiedWorkgroupIR()
    local before
    local direct = WORKGROUP:format("io.gpu"):gsub('local gpu = require%("io%.gpu"%)', "", 1)
    direct = direct:gsub("%f[%w_]gpu%.", "io.gpu.")
    local env = envMod.new(HERE .. "/..")
    for _, source in ipairs({WORKGROUP:format("io.gpu"), direct}) do
        local parsed = parser.parse(source, "gpu-identity.nupp")
        test.eq(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "gpu-identity.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local programs, problems = compile.lower(source, "gpu-identity.nupp", parsed)
        test.eq(#problems, 0, problems[1] and problems[1].message)
        test.eq(#programs, 1)
        test.eq(programs[1].executionTarget, "gpu")
        local after = text.programs(programs)
        if before then
            test.eq(after, before)
        end
        before = after
    end
end

function M.lexicalWorkgroupNamespaceShadowIsNotAnIntrinsic()
    test.eq(
        lower.callIdentity({
            kind = "dotIndex",
            obj = {kind = "name", token = {text = "gpu", definition = {}}},
            name = {text = "workgroups"}
        }),
        nil,
        "a lexical lookalike does not gain the GPU entry identity"
    )
end

function M.finalRootAndDirectImportRetainTheSameFunction()
    local source = [[
local imported = require("simd")
return simd.species == imported.species
]]
    local parsed = parser.parse(source, "simd-root.nupp")
    test.eq(#parsed.errors, 0)
    local env = envMod.new(HERE .. "/..")
    local diagnostics = checker.check(parsed, "simd-root.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, problems = generator.generate(parsed, "simd-root.nupp")
    test.eq(#problems, 0, problems[1] and problems[1].msg)
    test.eq(assert(loadstring(code, "@simd-root.nupp"))(), true)
end

function M.computeLibraryNamesRespectLocalShadowing()
    local source = [[
local simd = {species = function(value: number): number return value + 1 end}
local gpu = {available = function(): boolean return true end}
local events = {id = function(value: number): number return value + 2 end}
return simd.species(1) + events.id(2), gpu.available()
]]
    local parsed = parser.parse(source, "compute-shadow.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "compute-shadow.nupp", envMod.new(HERE .. "/.."))
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, problems = generator.generate(parsed, "compute-shadow.nupp")
    test.eq(#problems, 0, problems[1] and problems[1].msg)
    local value, available = assert(loadstring(code, "@compute-shadow.nupp"))()
    test.eq(value, 6)
    test.eq(available, true)
end

function M.formerPublicModulesAreAbsentAndGpuImplementationStaysPrivate()
    local env = envMod.new(HERE .. "/..")
    for _, name in ipairs({"gpu", "gpu.layout", "gpu.spi", "nupp.gpu", "nupp.gpu.spi", "nupp.simd", "nupp.events"}) do
        test.eq(env.resolveModule(env, name), nil, name)
    end
    test.eq(env.moduleAccess(env, "io.gpu", "nupp.gpu.api"), nil)
    assert(env.resolveModule(env, "nupp.gpu.layout"))
    test.eq(env.moduleAccess(env, "io.gpu", "nupp.gpu.layout"), nil)
    local layoutReason = env.moduleAccess(env, "application", "nupp.gpu.layout")
    assert(layoutReason and layoutReason:find("internal", 1, true), tostring(layoutReason))
    local reason = env.moduleAccess(env, "application", "nupp.gpu.api")
    assert(reason and reason:find("internal", 1, true), tostring(reason))
end

local function lowercaseSimdNamespaces(source)
    for _, namespace in ipairs({"reducer", "horizontal"}) do
        source = source:gsub("%f[%w_]" .. namespace .. "%.([%a_][%w_]*)", function(name)
            return namespace .. "." .. (name:match("^[a-z]") and name:lower() or name)
        end)
    end

    source = source:gsub("local reducer: %b{}", function(declaration)
        return declaration:gsub("(\n    )([a-z][%w_]*)(: function)", function(indent, name, suffix)
            return indent .. name:lower() .. suffix
        end)
    end)

    return source
end

local function simdEnvironment(lowercase)
    local root = HERE .. "/.."
    local env = envMod.new(root, {cache = false})
    if lowercase then
        local path = root .. "/src/simd.nupp"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local _, diagnostics = envMod.checkModuleSource(env, path, lowercaseSimdNamespaces(source), {
            moduleName = "simd"
        })
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    end

    return env
end

local function checkedSimd(source, env)
    local parsed = parser.parse(source, "simd-case.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "simd-case.nupp", env)
    return parsed, diagnostics
end

local CASE_KERNEL = [[
local array = table.Array
local simd = require("simd")
@aot
local function fold(): number
    local floating = simd.reducer.orderedsum(0.0)
    local exact = simd.reducer.wrappingsum(array.int32, 0)
    do
        floating:add(1.5)
        exact:add(2)
    end
    return floating:value() + exact:value()
end
@aot
local function horizontal(): (int32, integer)
    local integers = assert(simd.species(array.int32, 4))
    local floats = assert(simd.species(array.float, 4))
    local total: int32 = simd.horizontal.wrappingsum(integers:splat(3))
    local at: integer = simd.horizontal.propagatingargmax(floats:splat(2.0))
    return total, at
end
]]

function M.lowercaseSimdDeclarationsKeepVerifiedOperations()
    local before
    for _, lowercase in ipairs({false, true}) do
        local source = lowercase and lowercaseSimdNamespaces(CASE_KERNEL) or CASE_KERNEL
        local parsed, diagnostics = checkedSimd(source, simdEnvironment(lowercase))
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local programs, problems = compile.lower(source, "simd-case.nupp", parsed)
        test.eq(#problems, 0, problems[1] and problems[1].message)
        test.eq(#programs, 2)
        local after = text.programs(programs)
        assert(after:find("reducer.ordered.sum", 1, true), after)
        assert(after:find("simd_horizontal", 1, true), after)
        if before then
            test.eq(after, before, "public casing changed private SIMD operations")
        end
        before = after
    end
end

function M.lowercaseSimdContractsKeepRefusalsAndMethodCase()
    local source = [[
local array = table.Array
local simd = require("simd")
@aot
local function invalid(): number
    local floats = assert(simd.species(array.float, 4))
    return simd.horizontal.wrappingsum(floats:splat(1.0))
end
]]
    for _, lowercase in ipairs({false, true}) do
        local input = lowercase and lowercaseSimdNamespaces(source) or source
        local _, diagnostics = checkedSimd(input, simdEnvironment(lowercase))
        test.eq(#diagnostics, 1)
        test.eq(diagnostics[1].code, "NUPP2006")
    end
    local runtime = require("simd")
    test.eq(runtime.lane.fromstorage, runtime.lane.fromstorage, "bootstrap entry must reuse the runtime function")
    local _, diagnostics = checkedSimd(
        [[
local simd = {horizontal = {wrappingsum = function(value: number): number return value + 1 end}}
return simd.horizontal.wrappingsum(2)
]],
        simdEnvironment(true)
    )
    test.eq(#diagnostics, 0, "a shadowed table remains an ordinary call")
end

return M
