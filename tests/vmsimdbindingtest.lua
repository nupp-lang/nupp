local test = require("assert")
local project = require("nupp.tools.vm.project")
local compile = require("nupp.tools.cli.compile")
local environment = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local kernels = require("nupp.compiler.vm.kernels")
local graph = require("nupp.compiler.vm.graph")
local program = require("program")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local BINDING = ROOT .. "/native/crates/vm/lib/nupp/vm/simdbinding.nupp"
local M = {}

function M.publicLabelSelectsOnlyTheFrozenHostBinding()
    test.equal(project.resolve({}, ROOT, "simd"), BINDING)
    test.equal(project.resolve({}, ROOT, "nupp.simd"), nil)
end

function M.publicBindingPreservesTheHostObjectAndRefusals()
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local env = environment.new(ROOT)
    table.insert(env.roots, 1, ROOT .. "/native/crates/vm/lib")
    local image = assert(compile.image(BINDING, env, nil))
    local binding = assert(loadImage(image))()
    local host = require("nupp.simd")
    test.equal(binding, host)
    local saved, preload = package.loaded.simd, package.preload.simd
    package.loaded.simd = nil
    package.preload.simd = function()
        return binding
    end
    local ok, problem = pcall(function()
        test.equal(require("simd"), host)
        test.equal(require("simd"), binding)
        test.equal(binding.vectors(), nil)
        for _, namespace in ipairs({binding.horizontal, binding.reducer}) do
            for name, value in pairs(namespace) do
                if type(value) == "function" then
                    test.equal(namespace[name:lower()], value, name .. " must retain its frozen handle")
                end
            end
        end
        for _, operation in ipairs({
            binding.species,
            binding.horizontal.algebraicSum,
            binding.horizontal.algebraicsum
        }) do
            local allowed, reason = pcall(operation)
            test.equal(allowed, false)
            test.matches(tostring(reason), "SIMD operation requires a statically resolved call")
        end
        local reducer = binding.reducer.any()
        test.equal(reducer:value(), false)
        reducer:add(false)
        test.equal(reducer:value(), false)
        reducer:add(true)
        test.equal(reducer:value(), true)
        local total = binding.reducer.orderedsum(0.0)
        total:add(1.5)
        total:add(2.5)
        test.equal(total:value(), 4)
    end)
    package.loaded.simd, package.preload.simd = saved, preload
    assert(ok, problem)
end

local SOURCE = [[
local array = require("nupp.mem.array")
local lanes = require(%q)
local function sum(): float64
    local species = lanes.species(array.float64, 4)
    return lanes.horizontal.algebraicSum(species:splat(1))
end
]]

-- The shared accepting declarations land separately. Feed their canonical
-- checked identities into this native boundary without changing their types.
local function lowercaseCheckedNamespaces(node)
    if node.namespacePath and node.namespacePath:match("^math%.") then
        node.namespacePath = node.namespacePath:lower()
    end
    if node.simdHorizontal then
        node.simdHorizontal = node.simdHorizontal:lower()
    end
    local original = node.exactCallExport
    if original and original.identity and original.identity:match("%.horizontal%.") then
        local lowered = {}
        for key, value in pairs(original) do
            lowered[key] = value
        end
        lowered.identity, lowered.member = original.identity:lower(), original.member:lower()
        node.exactCallExport = lowered
    end
    for _, child in ipairs(node) do
        if type(child) == "table" then
            lowercaseCheckedNamespaces(child)
        end
    end
end

function M.oldAndFinalKernelIdentitiesProduceTheSameGraph()
    local final = io.open(ROOT .. "/src/simd.nupp", "rb")
    local sourceModule = final and "simd" or "nupp.simd"
    if final then
        final:close()
    end
    local before
    for _, variant in ipairs({{"nupp.simd", false}, {"simd", false}, {"nupp.simd", true}, {"simd", true}}) do
        local name, lowercase = variant[1], variant[2]
        local env = environment.new(ROOT)
        local resolveModule, resolveExports = env.resolveModule, env.resolveModuleExports
        function env:resolveModule(name, ...)
            return resolveModule(self, (name == "simd" or name == "nupp.simd") and sourceModule or name, ...)
        end

        function env:resolveModuleExports(name, ...)
            return resolveExports(self, (name == "simd" or name == "nupp.simd") and sourceModule or name, ...)
        end

        local parsed = parser.parse(SOURCE:format(name), "vm-kernel-identity.nupp")
        test.equal(#parsed.errors, 0)
        local diagnostics = checker.check(parsed, "vm-kernel-identity.nupp", env)
        test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        if lowercase then
            lowercaseCheckedNamespaces(parsed.root)
        end
        local body = parsed.root.blocks[1].stats[3].body
        local result, reason = kernels.tryBuild(body)
        assert(result, reason)
        graph.verify(result)
        local operations = {}
        for _, block in ipairs(result.blocks) do
            operations[#operations + 1] = {op = block.op, args = block.args, term = block.term}
        end
        if before then
            test.deepEqual(operations, before)
        end
        before = operations
    end
end

local function checked(source)
    local parsed = parser.parse(source, "vm-namespace-casing.nupp")
    test.equal(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, "vm-namespace-casing.nupp", environment.new(ROOT, {cache = false}))
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)

    return parsed
end

function M.lowercaseHorizontalIdentitiesKeepFrozenInstructionsAndResults()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("simd")
local floats = assert(simd.species(array.float64, 4)):splat(2.0)
local integers = assert(simd.species(array.int32, 4)):splat(3)
return simd.horizontal.orderedSum(floats),
    simd.horizontal.wrappingSum(integers),
    simd.horizontal.propagatingArgMax(floats)
]]
    local before
    for _, lowercase in ipairs({false, true}) do
        local parsed = checked(source)
        if lowercase then
            lowercaseCheckedNamespaces(parsed.root)
        end
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
        if before then
            test.equal(instructions, before, "public casing must not change frozen instruction names")
        end
        before = instructions
        program.installSourceModules()
        local execute = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        local total, exact, index = execute()
        test.equal(total, 8)
        test.equal(exact, 12)
        test.equal(index, 1)
    end
end

function M.lowercaseMathValuesSelectTheExistingPrivateNamespace()
    local source = [[
local wrap = math.wrapAngle
local delta = math.deltaAngle
return wrap(4), delta(3, -3)
]]
    for _, lowercase in ipairs({false, true}) do
        local parsed = checked(source)
        if lowercase then
            lowercaseCheckedNamespaces(parsed.root)
        end
        local image = program.image(parsed, "vm.math.casing")
        test.equal(program.names(image, "nupp.vm.math"), true)
        test.equal(program.names(image, lowercase and "wrapangle" or "wrapAngle"), true)
        test.equal(program.names(image, lowercase and "deltaangle" or "deltaAngle"), true)
    end
    local shadow = checked(
        [[
local math = {wrapangle = function(value: number): number return value + 19 end}
return math.wrapangle(1)
]]
    )
    test.equal(program.names(program.image(shadow, "vm.math.shadow"), "nupp.vm.math"), false)
    test.equal(program.run(shadow, "vm.math.shadow"), 20)
end

function M.lowercaseHorizontalShadowsRemainOrdinaryCalls()
    local shadow = checked(
        [[
local simd = {horizontal = {orderedsum = function(value: number): number return value + 7 end}}
return simd.horizontal.orderedsum(2)
]]
    )
    test.equal(program.run(shadow, "vm.simd.shadow"), 9)
end

function M.shortMathAliasesReuseTheExistingPrivateFunctions()
    local env = environment.new(ROOT)
    table.insert(env.roots, 1, ROOT .. "/native/crates/vm/lib")
    local image = assert(compile.image(ROOT .. "/native/crates/vm/lib/nupp/vm/math.nupp", env))
    local namespace = assert(assert(rawget(_G, "__nupp_load_image"))(image))()
    test.equal(namespace, rawget(_G, "math"))
    test.equal(namespace.vec2.len, namespace.vec2.length)
    test.equal(namespace.vec2.dist, namespace.vec2.distance)
    test.equal(namespace.quat.len, namespace.quat.length)
    test.equal(namespace.quat.mul, namespace.quat.multiply)
    test.equal(namespace.vec2.len(3, 4), 5)
    test.equal(namespace.vec2.dist(0, 0, 3, 4), 5)
    test.equal(namespace.quat.len(0, 0, 0, 2), 2)
    local x, y, z, w = namespace.quat.mul(0, 0, 0, 1, 1, 2, 3, 4)
    test.equal(x, 1)
    test.equal(y, 2)
    test.equal(z, 3)
    test.equal(w, 4)
end

return M
