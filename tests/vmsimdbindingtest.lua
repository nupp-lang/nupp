local test = require("nupp.test")
local project = require("nupp.tools.vm.project")
local compile = require("nupp.tools.cli.compile")
local environment = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local kernels = require("nupp.compiler.vm.kernels")
local graph = require("nupp.compiler.vm.graph")
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
        for _, operation in ipairs({binding.species, binding.horizontal.algebraicSum}) do
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

function M.oldAndFinalKernelIdentitiesProduceTheSameGraph()
    local final = io.open(ROOT .. "/src/simd.nupp", "rb")
    local sourceModule = final and "simd" or "nupp.simd"
    if final then
        final:close()
    end
    local before
    for _, name in ipairs({"nupp.simd", "simd"}) do
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

return M
