local fixtures = require("providerstate")
local M = {}

local function runtime(storage, integers, dialect)
    local advertised = {
        ["nupp.runtime.representation.spi.CstorageProvider"] = {"fixture.storage"},
        ["nupp.runtime.representation.spi.Int64Provider"] = integers and {"fixture.integers"} or {},
    }

    return fixtures.instance(
        {["nupp.spi"] = true, ["nupp.runtime.representation"] = true, ["nupp.runtime.int64"] = true,},
        {
            ["nupp.spi.index"] = advertised,
            ["nupp.runtime.target"] = {dialect = dialect or "luajit"},
            ["fixture.storage"] = storage,
            ["fixture.integers"] = integers,
        }
    )
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
