local fixtures = require("providerstate")
local M = {}

local function runtime(storage, integers, dialect)
    local advertised = {
        ["nupp.runtime.representation.spi.CstorageProvider"] = storage and {"fixture.storage"} or {},
        ["nupp.runtime.representation.spi.Int64Provider"] = integers and {"fixture.integers"} or {},
    }

    return fixtures.instance(
        {
            ["nupp.spi"] = true,
            ["nupp.runtime.representation"] = true,
            ["nupp.runtime.int64"] = true,
            ["nupp.runtime.storage"] = true,
            ["nupp.runtime.structvalue"] = true,
            ["nupp.runtime.wasm"] = true,
        },
        {
            ["nupp.spi.index"] = advertised,
            ["nupp.runtime.target"] = {dialect = dialect or "luajit"},
            ["fixture.storage"] = storage,
            ["fixture.integers"] = integers,
        }
    )
end

local function integerRuntime(providers)
    local names, replacements = {}, {["nupp.runtime.target"] = {dialect = "lua51"},}
    for index, provider in ipairs(providers) do
        local name = "fixture.integers" .. index
        names[index] = name
        replacements[name] = provider
    end
    replacements[
        "nupp.spi.index"
    ] = {
        ["nupp.runtime.representation.spi.CstorageProvider"] = {},
        ["nupp.runtime.representation.spi.Int64Provider"] = names,
    }

    return fixtures.instance(
        {["nupp.spi"] = true, ["nupp.runtime.representation"] = true, ["nupp.runtime.int64"] = true,},
        replacements
    )
end

function M.facadesRetainSelectedRepresentationMembers()
    local allocateBytes = function()
        return "allocated"
    end
    local integers = {}
    local structs = {}
    local host = {}
    local storage = {
        representation = "native",
        integers = integers,
        structs = structs,
        host = host,
        allocateBytes = allocateBytes,
    }
    local load = runtime(storage, integers)

    assert(load("nupp.runtime.storage").allocateBytes == allocateBytes)
    assert(load("nupp.runtime.structvalue") == structs)
    assert(load("nupp.runtime.wasm") == host)
    assert(load("nupp.runtime.int64") == integers)
end

function M.missingPortableProvidersFailAtTheirUseBoundary()
    local load = runtime(nil, nil, "lua51")
    local structs = load("nupp.runtime.structvalue")
    assert(structs.referenceValued)

    local ok, problem = pcall(load, "nupp.runtime.storage")
    assert(not ok and tostring(problem):find("no implementation is available", 1, true), tostring(problem))
    ok, problem = pcall(load, "nupp.runtime.wasm")
    assert(not ok and tostring(problem):find("no host implementation", 1, true), tostring(problem))

    local integers = load("nupp.runtime.int64")
    ok, problem = pcall(function()
        return integers.int64
    end)
    assert(not ok and tostring(problem):find("requires an integer provider", 1, true), tostring(problem))
end

function M.integerDiscoveryUsesUniqueHighestPriority()
    local default = {}
    local winner = {priority = 2}
    local otherDefault = {}
    local load = integerRuntime({default, winner, otherDefault})
    assert(load("nupp.runtime.int64") == winner)

    load = integerRuntime({winner, {priority = 1}, {priority = 2}})
    local ok, problem = pcall(load, "nupp.runtime.int64")
    assert(not ok and tostring(problem):find("highest priority", 1, true), tostring(problem))
end

function M.storageAndIntegerDiscoveryRetainOneInstance()
    local integers = {
        fromNumber = function(value)
            return value
        end
    }
    local storage = {representation = "native", integers = integers}
    for _, external in ipairs({false, true}) do
        local load = runtime(storage, external and integers or nil)
        assert(load("nupp.runtime.representation").storage == storage)
        assert(load("nupp.runtime.int64") == integers)
        assert(load("nupp.runtime.int64").fromNumber(42) == 42)
    end
end

function M.unrelatedIntegerInstancesAreRejected()
    local storage = {representation = "native", integers = {}}
    local load = runtime(storage, {})
    local ok, problem = pcall(load, "nupp.runtime.int64")
    assert(not ok and tostring(problem):find("integers must use the target storage implementation", 1, true))
end

function M.incompatibleStorageIsRejectedBeforeUse()
    local load = runtime({representation = "linear32"})
    local ok, problem = pcall(load, "nupp.runtime.representation")
    assert(not ok and tostring(problem):find("target requires native pointer storage", 1, true))
    load = runtime({representation = "linear32"}, nil, "lua51")
    ok, problem = pcall(load, "nupp.runtime.representation")
    assert(not ok and tostring(problem):find("portable layout operations are missing", 1, true))
end

return M
