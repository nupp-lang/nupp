local ROOT = require("helpers.paths").tests .. "/.."
local bootstrap = assert(loadfile(ROOT .. "/scripts/bootstrap-compiler.lua"))()
local M = {}

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end

local function fixture(action, expression, failure)
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/src/nupp/tools/vm' '" .. root .. "/src/nupp/compiler/decls'") == 0)
    write(root .. "/nupp.lua", "return {}\n")
    write(root .. "/src/nupp/compiler/decls/prelude.d.nupp", "current declaration\n")
    write(
        root .. "/src/nupp/tools/vm/project.nupp",
        "project.ROOT_EXTRAS = " .. (expression or '"one,"\n    .. "two"') .. "\n\n"
    )
    local carried = {["/compiler/decls/prelude.d.nupp"] = "old declaration\n", removed = "old"}
    local emitted = false
    local replacements = {
        ["nupp.vm.cliResources"] = carried,
        ["nupp.compiler.vm.resources"] = {
            source = function()
                return 'return {["/compiler/decls/prelude.d.nupp"]="current declaration\\n"}'
            end
        },
        ["nupp.compiler.bundled"] = {
            source = function(relative)
                return carried["/compiler" .. relative]
            end
        },
        ["nupp.tools.vm.project"] = {
            emit = function(found, entry, extras)
                assert(found == root and entry == "nupp.tools.vm.root" and extras == "one,two")
                assert(carried["/compiler/decls/prelude.d.nupp"] == "current declaration\n")
                assert(carried.removed == nil and package.preload["nupp.embedded"]() == carried)
                emitted = true
                if failure then
                    error("emitter refused", 0)
                end

                return "candidate image\n"
            end
        }
    }
    local saved = {}
    for name, value in pairs(replacements) do
        saved[name] = package.loaded[name]
        package.loaded[name] = value
    end
    local preload = package.preload["nupp.embedded"]
    local ok, problem = pcall(action, root, carried, function()
        return emitted
    end)
    for name in pairs(replacements) do
        package.loaded[name] = saved[name]
    end
    package.preload["nupp.embedded"] = preload
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, problem)
end

function M.selfEmissionUsesCurrentResourcesThroughRetainedTable()
    fixture(function(root, _, emitted)
        bootstrap.emit(root, root .. "/compiler.image")
        assert(emitted())
        assert(read(root .. "/compiler.image") == "candidate image\n")
    end)
end

function M.rootExtrasAreReadAsLiteralData()
    fixture(
        function(root, carried, emitted)
            local ok, problem = pcall(bootstrap.emit, root, root .. "/compiler.image")
            assert(not ok and tostring(problem):find("literal module names", 1, true))
            assert(not emitted() and carried.removed == "old")
        end,
        '"one," .. unexpected()'
    )
end

function M.failedEmissionPreservesThePreviousImage()
    fixture(
        function(root, _, emitted)
            local path = root .. "/compiler.image"
            write(path, "previous image\n")
            local ok, problem = pcall(bootstrap.emit, root, path)
            assert(not ok and problem == "emitter refused" and emitted())
            assert(read(path) == "previous image\n")
        end,
        nil,
        true
    )
end

return M
