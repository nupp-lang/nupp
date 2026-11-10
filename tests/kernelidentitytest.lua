local inputs = require("nupp.compiler.project.checkinputs")
local incremental = require("nupp.compiler.project.incremental")
local instances = require("helpers.providerstate")
local stable = require("nupp.compiler.stable")
local fs = require("nupp.compiler.fs")
local M = {}

local function fixture(callback)
    local root = os.tmpname()
    os.remove(root)
    assert(fs.mkdir(root .. "/src/nupp/compiler/syntax"))

    local function write(path, text)
        assert(fs.writeFile(root .. "/" .. path, text))
    end

    local okay, problem = pcall(callback, fs.canonical(root), write)
    os.remove(root, true)
    assert(okay, problem)
end

function M.checkedInputsIgnoreUnreadBodiesAndTrackSemanticReads()
    fixture(function(root, write)
        local lexer = "module nupp.compiler.syntax.lexer\nexport function scan(): integer return 1 end\n"
        local dependency = "module dep\nexport type Scalar = integer\nexport type Indexed = Shared\n"
        local generator = [[
local gen = {}
@comptime function gen.Shape(T: type): type return types.optional(T) end
return gen
]]
        local declaration = "global record Shared\n    value: integer\nend\n"
        write("src/nupp/compiler/syntax/lexer.nupp", lexer)
        write("src/dep.nupp", dependency)
        write("src/gen.nupp", generator)
        write("src/shared.nupp", declaration)
        write(
            "src/main.nupp",
            [[
local dep = require('dep')
local gen = require('gen')
local value: gen.Shape(integer) = nil
local dependency: dep.Scalar? = nil
local shared: dep.Indexed? = nil
return value, dependency, shared
]]
        )

        local function key(config)
            config = config or {include = {"src"}}
            local project = incremental.new(root, {config = config, cache = false, nativeCompilerServices = false})
            local path = root .. "/src/main.nupp"
            for _, diagnostic in ipairs(project.checkFile(path).diags) do
                assert(diagnostic.severity ~= "error", diagnostic.msg)
            end
            for _, diagnostic in ipairs(project.checkFile(root .. "/src/dep.nupp").diags) do
                assert(diagnostic.severity ~= "error", diagnostic.msg)
            end
            local indexed = false
            for _, dependency in ipairs(project.projectDependencies(root .. "/src/dep.nupp")) do
                indexed = indexed or dependency.name == "projectEntries" and dependency.key == "Shared"
            end
            assert(indexed, "the imported module must observe the global declaration")
            for _, dependency in ipairs(project.projectDependencies(path)) do
                assert(dependency.key ~= "Shared", "the root must not directly observe the global declaration")
            end

            return assert(inputs.digest(project, {path}, stable({target = "aarch64-apple-darwin", config = config})))
        end

        local original = key()
        write("src/nupp/compiler/syntax/lexer.nupp", lexer:gsub("return 1", "return 2"))
        assert(key() == original, "an unread carried compiler body is not checked data")
        write("src/dep.nupp", dependency:gsub("= integer", "= number"))
        assert(key() ~= original, "a checked interface edit changes the key")
        write("src/dep.nupp", dependency)
        write("src/gen.nupp", generator:gsub("optional%(T%)", "optional(types.array(T))"))
        assert(key() ~= original, "type-function behavior is part of the checked interface")
        write("src/gen.nupp", generator)
        write("src/shared.nupp", declaration:gsub("value: integer", "value: string"))
        assert(key() ~= original, "an indexed declaration changes the project answer")
        write("src/shared.nupp", declaration)
        assert(key({include = {"src"}, strict = true}) ~= original, "effective configuration is part of the key")
    end)
end

function M.checkedExternalInputsIncludeAbsentCandidates()
    fixture(function(root, write)
        write("src/imported.nupp", "local header = cheader('observed.h')\nreturn header\n")
        write("src/main.nupp", "local imported = require('imported')\nreturn imported\n")
        local path = root .. "/src/main.nupp"

        local function key()
            local project = incremental.new(root, {
                config = {include = {"src"}},
                cache = false,
                nativeCompilerServices = false
            })
            project.checkFile(path)
            assert(#project.externalInputs(path) == 0, "the root must not directly observe the external file")
            local observations = project.externalInputs(root .. "/src/imported.nupp")
            assert(#observations > 0, "the checker must observe the header candidates")

            return assert(inputs.digest(project, {path}, "external-fixture"))
        end

        local missing = key()
        write("src/observed.h", "typedef int Observed;\n")
        assert(key() ~= missing, "an absent external candidate becoming present changes the key")
    end)
end

function M.nativeUnitPublishesOnlyADetachedFingerprint()
    fixture(function(root, write)
        write("src/model.nupp", "module model\nexport function value(): uint64 return 1ULL end\n")
        local unit = instances.instance({["nupp.compiler.vm.nativeunit"] = true})("nupp.compiler.vm.nativeunit")

        local function key()
            local session = unit.session(
                root,
                {{path = root .. "/src/model.nupp", moduleName = "model"}},
                "aarch64-apple-darwin",
                {"src"},
                true
            )
            local digest = assert(session.cacheFingerprint())
            assert(type(digest) == "string" and session.project == nil)

            return digest
        end

        local first = key()
        write("src/model.nupp", "module model\nexport function value(): uint64 return 2ULL end\n")
        assert(key() ~= first, "the lowered body is part of the detached fingerprint")
        local sealed = unit.session(
            root,
            {{path = root .. "/src/model.nupp", moduleName = "model"}},
            "aarch64-apple-darwin",
            {"src"},
            true
        )
        assert(sealed.cacheFingerprint())
        write("src/model.nupp", "module model\nexport function value(): uint64 return 3ULL end\n")
        assert(sealed.cacheFingerprint() == nil, "a changed sealed snapshot cannot publish a reusable key")
    end)
end

function M.unverifiablePrivateInputsDisableKernelReuse()
    fixture(function(root, write)
        for _, path in ipairs({
            "src/nupp/core",
            "src/nupp/runtime/vm",
            "src/nupp/compiler/decls",
            "native/crates/vm/decls",
            "tests/core/units"
        }) do
            assert(fs.mkdir(root .. "/" .. path))
        end
        assert(fs.mkdir(root .. "/src/test"))
        write("src/nupp/core/unitrunner.nupp", 'return require("nupp.compiler." .. name)\n')
        write("src/nupp/compiler/syntax/lexer.nupp", "return 1\n")
        write("src/nupp/compiler/computed.nupp", 'return require("test.outside")\n')
        write("src/test/outside.nupp", "return 1\n")
        write("tests/core/units/nupp.lua", "return {}\n")
        local authorized = true
        local private = true
        local environment = setmetatable(
            {
                getenv = function(name)
                    if name == "NUPP_UNIT_COMPILER_PIN" then
                        return nil
                    end
                    if private and name == "NUPP_VM_CLI_IMAGE" then
                        return root .. "/.nupp/native-producer/" .. string.rep("b", 64) .. "/compiler.image"
                    end
                    if private and name == "NUPP_VM_BINARY" then
                        return root .. "/.nupp/native-producer/" .. string.rep("b", 64) .. "/runtime"
                    end

                    return os.getenv(name)
                end
            },
            {__index = os}
        )
        local kernel = instances.instance(
            {["nupp.core.kernelcompiler"] = true},
            {
                ["nupp.core.produceridentity"] = {
                    running = function()
                        return authorized and "verified-pair" or nil
                    end
                },
                ["nupp.compiler.imagemodules"] = {
                    carriedModules = function()
                        return {["nupp.core.unitrunner"] = true, ["nupp.compiler.syntax.lexer"] = true}
                    end
                },
            },
            nil,
            {os = environment}
        )("nupp.core.kernelcompiler")
        local narrow, broad = kernel.keyed(root, function()
            return "checked-data"
        end), kernel.keyed(root)
        write("src/nupp/compiler/syntax/lexer.nupp", "return 2\n")
        assert(
            kernel.keyed(root, function()
                return "checked-data"
            end) == narrow,
            "verified fixed code ignores a carried lexer body edit"
        )
        assert(kernel.keyed(root) ~= broad, "missing observations retain the source key")

        local function checked()
            return "checked-data"
        end

        write("src/nupp/compiler/computed.nupp", 'return require("test.outside") -- changed compiler code\n')
        assert(kernel.keyed(root, checked) ~= narrow, "uncarried computed compiler code remains an executable input")
        write("src/nupp/compiler/computed.nupp", 'return require("test.outside")\n')
        write("src/test/outside.nupp", "return 2\n")
        assert(kernel.keyed(root, checked) ~= narrow, "computed compiler modules retain outside literal dependencies")
        write("src/test/outside.nupp", "return 1\n")
        local _, outerReusable = kernel.keyed(root)
        assert(not outerReusable, "private outer selections cannot bypass observed external inputs")
        local _, unknownReusable = kernel.keyed(root, function()
            return nil
        end)
        assert(not unknownReusable, "unknown observations cannot reuse persistent kernels")
        local _, failedReusable = kernel.keyed(root, function()
            error("unencodable observation")
        end)
        assert(not failedReusable, "failed observation encoding cannot reuse persistent kernels")
        assert(
            kernel.keyed(root, function()
                return "changed-checked-data"
            end) ~= narrow,
            "checked observations remain key inputs"
        )
        write("src/nupp/runtime/vm/observed.d.nupp", "declare function observed(): nil\n")
        assert(
            kernel.keyed(root, function()
                return "checked-data"
            end) ~= narrow,
            "explicit declaration data remains a key input"
        )
        authorized = false
        assert(
            kernel.keyed(root, function()
                return "checked-data"
            end) == kernel.keyed(root),
            "unknown producer evidence keeps the source key"
        )
        local observed = false
        local _, invalidReusable = kernel.keyed(root, function()
            observed = true
            return "data"
        end)
        assert(not invalidReusable and not observed, "failed private authorization neither observes nor reuses")
        private = false
        local _, ordinaryReusable = kernel.keyed(root, function()
            observed = true
            return "data"
        end)
        assert(ordinaryReusable and not observed, "ordinary builds preserve their existing key without observing")
        assert(inputs.digest({}, {}, "unknown") == nil, "unavailable observation APIs are not an empty dependency set")
    end)
end

return M
