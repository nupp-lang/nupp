local test = require("assert")
local identity = require("nupp.compiler.apiidentity")
local program = require("program")
local nativeonly = require("nupp.compiler.check.nativeonly")
local targetLayout = require("nupp.compiler.targetlayout")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local envMod = require("nupp.compiler.project.env")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

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
        test.equal(element, "float64")
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
        test.equal(callIdentity({kind = "name", exactCallExport = {identity = module .. ".species"}}), "simd.species")
        test.equal(
            callIdentity({
                kind = "name",
                token = {definition = {exactCallExport = {identity = module .. ".reducer.wrappingSum"}}},
            }),
            "simd.reducer.wrappingSum"
        )
    end
    test.equal(
        callIdentity({
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
    local species = lanes.species(array.float64)
    for at, active in species:over(#values) do
        species:store(values, at, species:load(values, at, active) * factor, active)
    end
end
]]

function M.finalAndLegacyImportsKeepNativeVectorLoopOperations()
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
        local source = SCALE:format(
            module
        )
            .. [[
const values = array.scalar(array.float64, 5)
with rows = values:write() do
    for index = 1, 5 do rows[index] = index end
    scale(rows, 2.0)
end
local rows = values:read()
return rows[1], rows[5]
]]
        local parsed = parser.parse(source, "simd-identity.nupp")
        test.equal(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "simd-identity.nupp", env)
        test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
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
            test.equal(after, before)
        end
        before = after
        program.installSourceModules()
        local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        local first, last = execute()
        test.equal(first, 2)
        test.equal(last, 10)
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
            local cursor = groupIndex * math.u32.wrap(4) + localIndex
            if cursor < #input and cursor < #output then
                output[cursor + 1] = input[cursor + 1] + math.u32.wrap(1)
            end
        end)
    end)
end
]]

function M.finalAndLegacyGpuImportsKeepTheCheckedWorkgroupContract()
    local before
    for _, module in ipairs({"nupp.gpu", "gpu"}) do
        local env = envMod.new(HERE .. "/..")
        local resolveModule, resolveExports = env.resolveModule, env.resolveModuleExports
        function env:resolveModule(name, ...)
            return resolveModule(self, name == "nupp.gpu" and "gpu" or name, ...)
        end

        function env:resolveModuleExports(name, ...)
            return resolveExports(self, name == "nupp.gpu" and "gpu" or name, ...)
        end

        local parsed = parser.parse(WORKGROUP:format(module), "gpu-identity.nupp")
        test.equal(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "gpu-identity.nupp", env)
        test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local calls = {}

        local function visit(node)
            if node.kind == "call" then
                local canonical = callIdentity(node.obj)
                if canonical == "gpu.workgroups" then
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
        test.equal(#calls, 1)
        local call = calls[1]
        test.equal(#call.args.exprs, 3)
        test.equal(call.args.exprs[3].kind, "funcExpr")
        local canonical = callIdentity(call.obj)
        if before then
            test.equal(canonical, before)
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
    test.equal(#parsed.errors, 0)
    local env = envMod.new(HERE .. "/..")
    local diagnostics = checker.check(parsed, "simd-root.nupp", env)
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    test.equal(program.run(parsed, "simd-root", "simd-root.nupp"), true)
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
    local value, available = program.run(parsed, "compute-shadow", "compute-shadow.nupp")
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
        test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    end

    return env
end

local function checkedSimd(source, env)
    local parsed = parser.parse(source, "simd-case.nupp")
    test.equal(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "simd-case.nupp", env)
    return parsed, diagnostics
end

local CASE_KERNEL = [[
local array = require("nupp.mem.array")
local simd = require("simd")
@aot
local function fold(): number
    local floating = simd.reducer.orderedSum(0.0)
    local exact = simd.reducer.wrappingSum(array.int32, 0)
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
    local total: int32 = simd.horizontal.wrappingSum(integers:splat(3))
    local at: integer = simd.horizontal.propagatingArgMax(floats:splat(2.0))
    return total, at
end
]]

function M.lowercaseSimdDeclarationsKeepVerifiedOperations()
    local before
    for _, lowercase in ipairs({false, true}) do
        local source = lowercase and lowercaseSimdNamespaces(CASE_KERNEL) or CASE_KERNEL
        local parsed, diagnostics = checkedSimd(source .. "\nreturn fold(), horizontal()", simdEnvironment(lowercase))
        test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
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
        test.matches(fold, lowercase and "orderedsum" or "orderedSum")
        test.matches(fold, lowercase and "wrappingsum" or "wrappingSum")
        test.matches(horizontal, "Simd wrappingSum int32")
        test.matches(horizontal, "Simd horizontal%.propagatingArgMax float64")
        if before then
            test.equal(horizontal, before, "public casing changed private SIMD operations")
        end
        before = horizontal
        program.installSourceModules()
        local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        local reduced, total, at = execute()
        local runtime = require("simd")
        test.equal(runtime.reducer.orderedsum, runtime.reducer.orderedSum)
        test.equal(runtime.reducer.wrappingsum, runtime.reducer.wrappingSum)
        test.equal(reduced, 3.5)
        test.equal(total, 12)
        test.equal(at, 1)
    end
end

function M.lowercaseSimdContractsKeepRefusalsAndMethodCase()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("simd")
@aot
local function invalid(): number
    local floats = assert(simd.species(array.float64, 4))
    return simd.horizontal.wrappingSum(floats:splat(1.0))
end
]]
    for _, lowercase in ipairs({false, true}) do
        local input = lowercase and lowercaseSimdNamespaces(source) or source
        local _, diagnostics = checkedSimd(input, simdEnvironment(lowercase))
        test.equal(#diagnostics, 1)
        test.equal(diagnostics[1].code, "NUPP2006")
    end
    -- The frozen host has no scalar lane namespace. The native vector storage
    -- contract is checked above; this test executes only its existing operations.
    test.equal(require("nupp.simd").lane, nil)
    local _, diagnostics = checkedSimd(
        [[
local simd = {horizontal = {wrappingsum = function(value: number): number return value + 1 end}}
return simd.horizontal.wrappingsum(2)
]],
        simdEnvironment(true)
    )
    test.equal(#diagnostics, 0, "a shadowed table remains an ordinary call")
end

return M
