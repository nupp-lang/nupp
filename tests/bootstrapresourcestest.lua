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

local function fixture(action, expression, failure, readerFailure)
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
    local readerReady = false
    local previousReader = bootstrap.reader
    bootstrap.reader = function(found)
        assert(found == root and carried["/compiler/decls/prelude.d.nupp"] == "current declaration\n")
        if readerFailure then
            error("reader refused", 0)
        end
        readerReady = true

        return 1
    end
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
                assert(readerReady, "current namespace reader precedes emission")
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
    bootstrap.reader = previousReader
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

function M.currentNamespaceReaderPreservesPrivatePackageBoundaries()
    local environment = require("nupp.compiler.project.env")
    local previous = environment.packageNamespace
    local ok, problem = pcall(function()
        assert(bootstrap.reader(ROOT) > 0)
        assert(environment.packageNamespace("bytes") == "nupp")
        assert(environment.packageNamespace("binary") == "binary")
        assert(environment.packageNamespace("app.main") == "app")
        local context = {
            ensureProjectIndex = function()
                return {}
            end,
        }
        assert(environment.moduleAccess(context, "bytes", "nupp.io.internal.bytes") == nil)
        assert(environment.moduleAccess(context, "nupp.io.internal.bytes", "bytes.internal.bytestypes") == nil)
        assert(environment.moduleAccess(context, "app.main", "bytes.internal.bytestypes") ~= nil)
    end)
    environment.packageNamespace = previous
    assert(ok, problem)
end

function M.failedReaderPreservesThePreviousImage()
    fixture(
        function(root, _, emitted)
            local path = root .. "/compiler.image"
            write(path, "previous image\n")
            local ok, problem = pcall(bootstrap.emit, root, path)
            assert(not ok and problem == "reader refused" and not emitted())
            assert(read(path) == "previous image\n")
        end,
        nil,
        false,
        true
    )
end

function M.missingOrDuplicateNamespaceSourceCannotReplaceTheReader()
    local environment = require("nupp.compiler.project.env")
    local previous = environment.packageNamespace
    local source = read(ROOT .. "/src/nupp/compiler/project/env.nupp")
    local inputs = {
        source:gsub("local STANDARD_ROOTS:", "local RENAMED_ROOTS:", 1),
        source .. "\nlocal STANDARD_ROOTS: {[string]: boolean} = {}\n",
        source .. "\nfunction envMod.packageNamespace(moduleName: string): string\nreturn moduleName\nend\n",
    }
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/src/nupp/compiler/project'") == 0)
    local ok, problem = pcall(function()
        for _, input in ipairs(inputs) do
            write(root .. "/src/nupp/compiler/project/env.nupp", input)
            local refreshed, refusal = pcall(bootstrap.reader, root)
            assert(not refreshed and tostring(refusal):find("one ", 1, true), tostring(refusal))
            assert(environment.packageNamespace == previous, "refused source changed the live reader")
        end
    end)
    environment.packageNamespace = previous
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, problem)
end

return M
