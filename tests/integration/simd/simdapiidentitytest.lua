local test = require("assert")
local identity = require("nupp.compiler.apiidentity")
local program = require("program")
local nativeonly = require("nupp.compiler.check.nativeonly")
local targetLayout = require("nupp.compiler.targetlayout")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local HERE = require("helpers.paths").tests

local M = {}
local identityContext = {
    lookupEntry = function()
        return nil
    end
}

local function callIdentity(node)
    return identity.expression(identityContext, node)
end

local function fixedVector(module)
    return {
        tag = "nominal",
        origin = {moduleName = module, name = "Vector"},
        typeArgs = {
            {tag = "float64"},
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
        test.eq(element, "float64")
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
        test.eq(callIdentity({kind = "name", exactCallExport = {identity = module .. ".species"}}), "simd.species")
        test.eq(
            callIdentity({
                kind = "name",
                token = {definition = {exactCallExport = {identity = module .. ".reducer.wrappingSum"}}},
            }),
            "simd.reducer.wrappingSum"
        )
    end
    test.eq(
        callIdentity({
            kind = "dotIndex",
            obj = {kind = "name", token = {text = "simd", definition = {}}},
            name = {text = "species"}
        }),
        nil
    )
end

local SCALE = [[
local array = require("nupp.array")
local span = require("binary.span")
local lanes = require(%q)
@aot
local function scale(exclusive values: span.WriteSpan<float>, factor: float): nil
    local species = lanes.species(array.float64)
    for at, active in species:over(#values) do
        species:store(values, at, species:load(values, at, active) * factor, active)
    end
end
]]

function M.importAndGlobalRootKeepNativeVectorLoopOperations()
    local env = envMod.new(HERE .. "/..")
    local before
    for _, imported in ipairs({true, false}) do
        local source = SCALE:format(
            "simd"
        )
            .. [[
const values = array.scalar(array.float64, 5)
do local rows = values:write() ;
    for index = 1, 5 do rows[index] = index end
    scale(rows, 2.0)
end
local rows = values:read()
return rows[1], rows[5]
]]
        if not imported then
            source = source:gsub('local lanes = require%("simd"%)', "local lanes = simd")
        end
        local parsed = parser.parse(source, "simd-identity.nupp")
        test.eq(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "simd-identity.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local listing = {}
        local image = program.image(parsed, "simd-identity", "simd-identity.nupp", listing)
        local after
        for _, entry in ipairs(listing) do
            if entry.image:match("^function scale ") then
                after = entry.image
            end
        end
        assert(after, "the checked scale loop must have a native VM body")
        if before then
            test.eq(after, before)
        end
        before = after
        program.installSourceModules()
        local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        local first, last = execute()
        test.eq(first, 2)
        test.eq(last, 10)
    end
end

local WORKGROUP = [[
local gpu = require(%q)
local span = require("binary.span")
@aot(target = "gpu")
local function increment(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): nil
    local groups = math.u32.div(math.u32.wrap(#input), math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        phases:run(function(localIndex: uint32)
            local cursor = groupIndex * math.u32.wrap(4) + localIndex
            if cursor < #input and cursor < #output then
                output[cursor + 1] = input[cursor + 1] + math.u32.wrap(1)
            end
        end)
    end)
end
]]

function M.importAndGlobalRootKeepTheCheckedWorkgroupContract()
    local before
    for _, imported in ipairs({true, false}) do
        local env = envMod.new(HERE .. "/..")
        local source = WORKGROUP:format("io.gpu")
        if not imported then
            source = source:gsub('local gpu = require%("io%.gpu"%)', "local gpu = io.gpu")
        end
        local parsed = parser.parse(source, "gpu-identity.nupp")
        test.eq(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "gpu-identity.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local calls = {}

        local function visit(node)
            if node.kind == "call" then
                local canonical = callIdentity(node.obj)
                if canonical == "io.gpu.workgroups" then
                    calls[#calls + 1] = node
                end
            end
            for _, child in ipairs(node) do
                if type(child) == "table" and child.kind ~= "token" then
                    visit(child)
                end
            end
        end

        visit(parsed.root)
        test.eq(#calls, 1)
        local call = calls[1]
        test.eq(#call.args.exprs, 3)
        test.eq(call.args.exprs[3].kind, "funcExpr")
        local canonical = callIdentity(call.obj)
        if before then
            test.eq(canonical, before)
        end
        before = canonical
    end
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
    test.eq(program.run(parsed, "simd-root", "simd-root.nupp"), true)
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
    local value, available = program.run(parsed, "compute-shadow", "compute-shadow.nupp")
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

local function simdEnvironment()
    return envMod.new(HERE .. "/..", {cache = false})
end

local function checkedSimd(source, env)
    local parsed = parser.parse(source, "simd-case.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "simd-case.nupp", env)
    return parsed, diagnostics
end

local CASE_KERNEL = [[
local array = require("nupp.array")
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
    local floats = assert(simd.species(array.float64, 4))
    local total: int32 = simd.horizontal.wrappingsum(integers:splat(3))
    local at: integer = simd.horizontal.propagatingargmax(floats:splat(2.0))
    return total, at
end
]]

function M.lowercaseSimdDeclarationsKeepVerifiedOperations()
    do
        local parsed, diagnostics = checkedSimd(CASE_KERNEL .. "\nreturn fold(), horizontal()", simdEnvironment())
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local listing = {}
        local image = program.image(parsed, "simd-case", "simd-case.nupp", listing)
        local horizontal, fold
        for _, entry in ipairs(listing) do
            if entry.image:match("^function horizontal ") then
                horizontal = entry.image
            end
            if entry.image:match("^function fold ") then
                fold = entry.image
            end
        end
        assert(horizontal and fold, "both checked kernels must have native VM bodies")
        test.matches(fold, "orderedsum")
        test.matches(fold, "wrappingsum")
        test.matches(horizontal, "Simd wrappingSum int32")
        test.matches(horizontal, "Simd horizontal%.propagatingArgMax float64")
        program.installSourceModules()
        local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        local reduced, total, at = execute()
        local runtime = require("simd")
        test.eq(runtime.reducer.orderedSum, nil)
        test.eq(runtime.reducer.wrappingSum, nil)
        test.eq(type(runtime.reducer.orderedsum), "function")
        test.eq(type(runtime.reducer.wrappingsum), "function")
        test.eq(reduced, 3.5)
        test.eq(total, 12)
        test.eq(at, 1)
    end
end

function M.lowercaseSimdContractsKeepRefusalsAndMethodCase()
    local source = [[
local array = require("nupp.array")
local simd = require("simd")
@aot
local function invalid(): number
    local floats = assert(simd.species(array.float64, 4))
    return simd.horizontal.wrappingsum(floats:splat(1.0))
end
]]
    do
        local _, diagnostics = checkedSimd(source, simdEnvironment())
        test.eq(#diagnostics, 1)
        test.eq(diagnostics[1].code, "NUPP2006")
    end
    -- The frozen host has no scalar lane namespace. The native vector storage
    -- contract is checked above; this test executes only its existing operations.
    test.eq(require("nupp.simd").lane, nil)
    local _, diagnostics = checkedSimd(
        [[
local simd = {horizontal = {wrappingsum = function(value: number): number return value + 1 end}}
return simd.horizontal.wrappingsum(2)
]],
        simdEnvironment()
    )
    test.eq(#diagnostics, 0, "a shadowed table remains an ordinary call")
end

return M
