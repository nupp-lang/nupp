local fixtures = require("providerstate")
local M = {}

local function runtime(storage)
    local advertised = {['nupp.spi.CstorageProvider'] = storage and {'fixture.storage'} or {}}

    return fixtures.instance(
        {
            ['nupp.runtime.packages'] = true,
            ['nupp.mem.representation'] = true,
            ['nupp.runtime.storage'] = true,
            ['nupp.runtime.structvalue'] = true,
        },
        {
            ['nupp.spi.index'] = advertised,
            ['nupp.runtime.target'] = {dialect = 'luajit'},
            ['fixture.storage'] = storage,
        }
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
    assert(storage.allocateBytes == nil, 'the SPI has no preceding public allocation key')
    assert(load('nupp.runtime.structvalue') == structs)
end

function M.missingStorageStructsUseTheTableFallback()
    local load = runtime({representation = 'native'})
    assert(load('nupp.runtime.structvalue').referencevalued)
end

function M.incompatibleStorageIsRejectedBeforeUse()
    local load = runtime({representation = 'linear32'})
    local ok, problem = pcall(load, 'nupp.mem.representation')
    assert(not ok and tostring(problem):find('target requires native pointer storage', 1, true))
end

return M
