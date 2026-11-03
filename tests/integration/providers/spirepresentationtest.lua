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

return M
