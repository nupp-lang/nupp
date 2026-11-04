local test = require("assert")
local project = require("nupp.tools.vm.project")
local compile = require("nupp.tools.cli.compile")
local environment = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local kernels = require("nupp.compiler.vm.kernels")
local graph = require("nupp.compiler.vm.graph")
local program = require("program")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local BINDING = ROOT .. "/native/crates/vm/lib/nupp/vm/simdbinding.nupp"
local M = {}

function M.publicLabelSelectsOnlyTheFrozenHostBinding()
    test.eq(project.resolve({}, ROOT, "simd"), BINDING)
    test.eq(project.resolve({}, ROOT, "nupp.simd"), nil)
end

function M.publicBindingPreservesTheHostObjectAndRefusals()
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local host = require("nupp.simd")
    local sum = host.horizontal.algebraicsum or host.horizontal.algebraicSum
    local env = environment.new(ROOT)
    table.insert(env.roots, 1, ROOT .. "/native/crates/vm/lib")
    local image = assert(compile.image(BINDING, env, nil))
    local binding = assert(loadImage(image))()
    test.eq(binding, host)
    test.eq(binding.horizontal.algebraicsum, sum)
    test.eq(binding.horizontal.algebraicSum, nil)
    local saved, preload = package.loaded.simd, package.preload.simd
    package.loaded.simd = nil
    package.preload.simd = function()
        return binding
    end
    local ok, problem = pcall(function()
        test.eq(require("simd"), host)
        test.eq(require("simd"), binding)
        test.eq(binding.vectors(), nil)
        for _, namespace in ipairs({binding.horizontal, binding.reducer}) do
            for name, value in pairs(namespace) do
                if type(value) == "function" then
                    test.eq(name, name:lower())
                    test.eq(namespace[name:lower()], value, name .. " must retain its frozen handle")
                end
            end
        end
        for _, operation in ipairs({binding.species, binding.horizontal.algebraicsum}) do
            local allowed, reason = pcall(operation)
            test.eq(allowed, false)
            test.matches(tostring(reason), "SIMD operation requires a statically resolved call")
        end
        local reducer = binding.reducer.any()
        test.eq(reducer:value(), false)
        reducer:add(false)
        test.eq(reducer:value(), false)
        reducer:add(true)
        test.eq(reducer:value(), true)
        local total = binding.reducer.orderedsum(0.0)
        total:add(1.5)
        total:add(2.5)
        test.eq(total:value(), 4)
    end)
    package.loaded.simd, package.preload.simd = saved, preload
    assert(ok, problem)
end

function M.directAndAliasedPublicKernelCallsProduceTheSameGraph()
    local before
    for _, aliased in ipairs({false, true}) do
        local source = [[
local array = require("nupp.mem.array")
local lanes = require("simd")
]] .. (
            aliased and "local reduce = lanes.horizontal.algebraicsum\n" or ""
        ) .. [[
local function sum(): float64
    local species = lanes.species(array.float64, 4)
]] .. (
            aliased and "return reduce(species:splat(1))" or "return lanes.horizontal.algebraicsum(species:splat(1))"
        ) .. "\nend\n"
        local parsed = parser.parse(source, "vm-kernel-identity.nupp")
        test.eq(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "vm-kernel-identity.nupp", environment.new(ROOT))
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local sum
        for _, statement in ipairs(parsed.root.blocks[1].stats) do
            if statement.kind == "localFuncStmt" and statement.name.text == "sum" then
                sum = statement
            end
        end
        local result, reason = kernels.tryBuild(assert(sum).body)
        assert(result, reason)
        graph.verify(result)
        local operations = {}
        for _, block in ipairs(result.blocks) do
            operations[#operations + 1] = {op = block.op, args = block.args, term = block.term}
        end
        if before then
            test.deepeq(operations, before)
        end
        before = operations
    end
end

local function checked(source)
    local parsed = parser.parse(source, "vm-namespace-casing.nupp")
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, "vm-namespace-casing.nupp", environment.new(ROOT, {cache = false}))
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)

    return parsed
end

function M.lowercaseHorizontalIdentitiesKeepFrozenInstructionsAndResults()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("simd")
local floats = assert(simd.species(array.float64, 4)):splat(2.0)
local integers = assert(simd.species(array.int32, 4)):splat(3)
return simd.horizontal.orderedsum(floats),
    simd.horizontal.wrappingsum(integers),
    simd.horizontal.propagatingargmax(floats)
]]
    do
        local parsed = checked(source)
        local listing = {}
        local image = program.image(parsed, "vm.namespace.casing", nil, listing)
        local functions = {}
        for _, fn in ipairs(listing) do
            functions[#functions + 1] = fn.image
        end
        local instructions = table.concat(functions, "\n")
        test.matches(instructions, "orderedSum")
        test.matches(instructions, "wrappingSum")
        test.matches(instructions, "horizontal%.propagatingArgMax")
        program.installSourceModules()
        local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        local total, exact, index = execute()
        test.eq(total, 8)
        test.eq(exact, 12)
        test.eq(index, 1)
    end
end

function M.lowercaseMathValuesSelectTheExistingPrivateNamespace()
    local parsed = checked([[
local wrap = math.wrapangle
local delta = math.dtangle
return wrap(4), delta(3, -3)
]])
    local image = program.image(parsed, "vm.math.casing")
    test.eq(program.names(image, "nupp.vm.math"), true)
    test.eq(program.names(image, "wrapangle"), true)
    test.eq(program.names(image, "dtangle"), true)
    for _, old in ipairs({"wrapAngle", "deltaAngle", "deltaangle"}) do
        test.eq(program.names(image, old), false)
    end
    local shadow = checked(
        [[
local math = {wrapangle = function(value: number): number return value + 19 end}
return math.wrapangle(1)
]]
    )
    test.eq(program.names(program.image(shadow, "vm.math.shadow"), "nupp.vm.math"), false)
    test.eq(program.run(shadow, "vm.math.shadow"), 20)
end

function M.lowercaseHorizontalShadowsRemainOrdinaryCalls()
    local shadow = checked(
        [[
local simd = {horizontal = {orderedsum = function(value: number): number return value + 7 end}}
return simd.horizontal.orderedsum(2)
]]
    )
    test.eq(program.run(shadow, "vm.simd.shadow"), 9)
end

function M.shortMathNamesKeepResultsWithoutRetiredAliases()
    local env = environment.new(ROOT)
    table.insert(env.roots, 1, ROOT .. "/native/crates/vm/lib")
    local image = assert(compile.image(ROOT .. "/native/crates/vm/lib/nupp/vm/math.nupp", env))
    local namespace = assert(assert(rawget(_G, "__nupp_load_image"))(image))()
    test.eq(namespace, rawget(_G, "math"))
    test.eq(namespace.vec2.length, nil)
    test.eq(namespace.vec2.distance, nil)
    test.eq(namespace.quat.length, nil)
    test.eq(namespace.quat.multiply, nil)
    test.eq(namespace.vec2.len(3, 4), 5)
    test.eq(namespace.vec2.dist(0, 0, 3, 4), 5)
    test.eq(namespace.quat.len(0, 0, 0, 2), 2)
    local x, y, z, w = namespace.quat.mul(0, 0, 0, 1, 1, 2, 3, 4)
    test.eq(x, 1)
    test.eq(y, 2)
    test.eq(z, 3)
    test.eq(w, 4)
end

local CONVERTERS = {"fromF16Bits", "toF16Bits", "fromBF16Bits", "toBF16Bits"}

function M.scalarConvertersKeepLowercaseHelperLookupsAndFrozenIdentities()
    local namespace = require("nupp.vm.math")
    for _, name in ipairs(CONVERTERS) do
        test.eq(namespace.f32[name], nil)
        test.eq(type(namespace.f32[name:lower()]), "function")
    end
    local parsed = checked(
        [[
local half: float32 = math.f32.fromf16bits(0x3c00)
local halfBits: uint32 = math.f32.tof16bits(1.5)
local short: float32 = math.f32.frombf16bits(0x3f80)
local shortBits: uint32 = math.f32.tobf16bits(1.5)
return half, halfBits, short, shortBits, math.f32.exp(0.0)
]]
    )
    local intrinsic = {}

    local function visit(node)
        if node.scalarIntrinsic then
            intrinsic[node.scalarIntrinsic] = true
        end
        for _, child in ipairs(node) do
            if type(child) == "table" then
                visit(child)
            end
        end
    end

    visit(parsed.root)
    for _, name in ipairs(CONVERTERS) do
        test.eq(intrinsic["f32." .. name], true)
    end
    test.eq(intrinsic["f32.exp"], true)
    local image = program.image(parsed, "vm.scalar.helpers", "vm-scalar-helpers.nupp")
    program.installSourceModules()
    local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
    local half, halfBits, short, shortBits, exponential = execute()
    test.eq(half, 1)
    test.eq(halfBits, 0x3e00)
    test.eq(short, 1)
    test.eq(shortBits, 0x3fc0)
    test.eq(exponential, 1)
    test.eq(program.names(image, "nupp.vm.math"), true)
    for _, name in ipairs(CONVERTERS) do
        test.eq(program.names(image, name:lower()), true)
        test.eq(program.names(image, name), false)
    end
end

function M.scalarConverterNamesKeepTypeRefusalsAndRetireOldFields()
    local env = environment.new(ROOT, {cache = false})
    for _, name in ipairs(CONVERTERS) do
        for _, variant in ipairs({{name:lower(), "NUPP2006"}, {name, "NUPP2004"}}) do
            local parsed = parser.parse('return math.f32.' .. variant[1] .. '("invalid")', "vm-scalar-refusal.nupp")
            test.eq(#parsed.errors, 0)
            local found = false
            for _, item in ipairs(checker.check(parsed, "vm-scalar-refusal.nupp", env)) do
                if item.severity == "error" and item.code == variant[2] then
                    test.eq(item.line, 1)
                    found = true
                end
            end
            test.eq(found, true, variant[1] .. " retains its positioned refusal")
        end
    end
end

function M.scalarConverterShadowsRemainOrdinaryCalls()
    for _, name in ipairs({"fromF16Bits", "fromf16bits"}) do
        local source = (
            [=[
local math = {f32 = {%s = function(value: string): string return value .. "!" end}}
return math.f32.%s("kept")
]=]
        ):format(name, name)
        local parsed = checked(source)
        local image = program.image(parsed, "vm.scalar.shadow", "vm-scalar-shadow.nupp")
        test.eq(program.names(image, "nupp.vm.math"), false)
        test.eq(assert(assert(rawget(_G, "__nupp_load_image"))(image))(), "kept!")
    end
end

return M
