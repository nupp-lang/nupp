local testAssert = require("assert")
local fixtures = require("helpers.providerstate")
local M = {}

local function runtime(storage)

    return fixtures.instance(
        {['binary._representation'] = true, ['nupp.runtime.storage'] = true, ['nupp.runtime.structvalue'] = true,},
        {['nupp.runtime.target'] = {dialect = 'luajit'}, ['nupp.runtime.provider.nativestorage'] = storage,}
    )
end

function M.facadesRetainSelectedRepresentationMembers()
    local allocateBytes = function()
        return 'allocated'
    end
    local structs = {}
    local storage = {representation = 'native', structs = structs, allocbytes = allocateBytes}
    local load = runtime(storage)

    assert(load('nupp.runtime.storage').allocateBytes == allocateBytes)
    assert(storage.allocateBytes == nil, 'the implementation has no preceding public allocation key')
    assert(load('nupp.runtime.structvalue') == structs)
end

function M.missingStorageStructsUseTheTableFallback()
    local load = runtime({representation = 'native'})
    assert(load('nupp.runtime.structvalue').referencevalued)
end

function M.incompatibleStorageIsRejectedBeforeUse()
    local load = runtime({representation = 'linear32'})
    local ok, problem = pcall(load, 'binary._representation')
    assert(not ok and tostring(problem):find('target requires native pointer storage', 1, true))
end

function M.canonicalStorageBindingRetainsTheFrozenProviderAndOperations()
    local raw = package.loaded["nupp.runtime.provider.nativestorage"]
    local selected = require("binary._representation").storage
    local binding = require("nupp.vm.storagebinding")
    assert(raw == binding and selected == raw, "the provider table keeps its identity")
    assert(binding.structs == package.loaded["nupp.runtime.structvalue"])
    assert(binding.structs.referencevalued == true)
    testAssert.eq(binding.structs.referenceValued, nil)
    testAssert.eq(binding.allocateBytes, nil)
    testAssert.eq(binding.allocateArray, nil)
    local old = require("nupp.runtime.storage")
    assert(old.allocateBytes == binding.allocbytes and old.sizeOf == binding.sizeof)
    local bytes = binding.allocbytes(8)
    testAssert.eq(binding.sizeof(bytes), 8)
    binding.fill(bytes, 8, 17)
    testAssert.eq(bytes[0], 17)
    testAssert.eq(bytes[7], 17)
    assert(not pcall(binding.allocbytes, -1))
    assert(not pcall(binding.allocbytes, 0.5))
end

function M.nativeAllocationConsumersUseCanonicalProviderOperations()
    local environment = require("nupp.compiler.project.env")
    local root = assert(environment.compilerRoot())
    local path = root .. "/native/crates/vm/tests/storage-consumers-input.nupp"
    local source = assert(require("nupp.compiler.fs").readFile(path))
    local parsed = require("nupp.compiler.syntax.parser").parse(source, path)
    testAssert.eq(#parsed.errors, 0)
    for _, diagnostic in ipairs(
        require("helpers.fragment").check(parsed, path, environment.new(root), {
            moduleName = "nupp.tests.vmstorageconsumers",
        })
    ) do
        assert(diagnostic.severity and diagnostic.severity ~= "error", diagnostic.msg)
    end
    local value = require("program").run(parsed, "nupp.tests.vmstorageconsumers", path)
    testAssert.eq(value.run(), 42)
end

return M
