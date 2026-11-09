local test = require("assert")
local steps = require("nupp.tools.vm.buildsteps")
local fs = require("nupp.compiler.fs")

-- Each test keeps its steps in a store of its own.
local M = {}

local function store(fresh)
    local path = os.tmpname()
    os.remove(path)
    assert(fs.mkdir(path))
    local getenv = os.getenv
    os.getenv = function(name)
        if name == "NUPP_CACHE_HOME" then
            return path
        elseif name == "NUPP_VM_BUILD_FRESH" then
            return fresh
        end
        return getenv(name)
    end

    return path, function()
        os.getenv = getenv
    end
end

local function entries(path)
    local found = {}
    for name in fs.children(path .. "/build-steps") do
        found[#found + 1] = path .. "/build-steps/" .. name
    end
    table.sort(found)

    return found
end

function M.reusesExactlyTheInputsItKept()
    local _, restore = store()
    local inputs = {"image " .. string.rep("a", 64), "tool " .. string.rep("b", 64)}
    test.eq(steps.kept("parallel AOT", inputs), nil)
    steps.keep("parallel AOT", inputs, {["compiler.o"] = "object bytes", ["compiler.o.maps"] = "maps"})
    local kept = assert(steps.kept("parallel AOT", inputs))
    test.eq(kept["compiler.o"], "object bytes")
    test.eq(kept["compiler.o.maps"], "maps")
    -- Another input, another step name or another order is another step.
    test.eq(steps.kept("parallel AOT", {inputs[1], "tool " .. string.rep("c", 64)}), nil)
    test.eq(steps.kept("native core lowering", inputs), nil)
    test.eq(steps.kept("parallel AOT", {inputs[2], inputs[1]}), nil)
    restore()
end

function M.missesWhenAnOutputIsChangedOrMissing()
    local path, restore = store()
    local inputs = {"image " .. string.rep("d", 64)}
    steps.keep("parallel AOT", inputs, {["compiler.o"] = "object bytes", ["compiler.o.rs"] = "sidecar"})
    local files = entries(path)
    local object, sidecar
    for _, file in ipairs(files) do
        if file:sub(-#".compiler.o") == ".compiler.o" then
            object = file
        elseif file:sub(-#".compiler.o.rs") == ".compiler.o.rs" then
            sidecar = file
        end
    end
    assert(object and sidecar, "every output is kept as a file")
    assert(fs.writeFile(object, "object bytez"))
    test.eq(steps.kept("parallel AOT", inputs), nil)
    assert(fs.writeFile(object, "object bytes"))
    assert(steps.kept("parallel AOT", inputs))
    os.remove(sidecar)
    test.eq(steps.kept("parallel AOT", inputs), nil)
    restore()
end

function M.missesWhenTheReceiptIsDamaged()
    local path, restore = store()
    local inputs = {"image " .. string.rep("e", 64)}
    steps.keep("native core lowering", inputs, {["runtime.clif"] = "clif"})
    for _, file in ipairs(entries(path)) do
        if file:sub(-4) == ".bin" then
            assert(fs.writeFile(file, "not a receipt"))
        end
    end
    test.eq(steps.kept("native core lowering", inputs), nil)
    restore()
end

function M.freshBuildsKeepAndReuseNothing()
    local path, restore = store("1")
    local inputs = {"image " .. string.rep("f", 64)}
    steps.keep("parallel AOT", inputs, {["compiler.o"] = "bytes"})
    test.eq(fs.exists(path .. "/build-steps"), false)
    test.eq(steps.kept("parallel AOT", inputs), nil)
    restore()
end

return M
