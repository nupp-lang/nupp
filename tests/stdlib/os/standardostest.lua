local test = require("assert")
local providerstate = require("helpers.providerstate")
local M = {}
local sharedEnv

local function environment()
    sharedEnv = sharedEnv or require("nupp.compiler.project.env").new(require("helpers.paths").root)
    return sharedEnv
end

function M.fileOperationsRemainUsableWithoutAClockProvider()
    local removed, renamed
    local host = {
        remove = function(path)
            removed = path
            return true
        end,
        rename = function(from, to)
            renamed = {from, to}
            return true
        end,
    }
    local load = providerstate.instance(
        {["nupp.runtime.standardos"] = true},
        {["nupp.runtime.timeprovider"] = {}, ["nupp.runtime.system"] = {}, ["nupp.runtime.entropy"] = {},},
        {
            ["nupp.runtime.clocks"] = function()
                error("nupp.time: no clock provider is available")
            end,
        },
        {os = host}
    )
    local surface = load("nupp.runtime.standardos")
    test.eq(surface.value, host)
    test.eq(host.remove("temporary"), true)
    test.eq(host.rename("before", "after"), true)
    test.eq(removed, "temporary")
    test.deepeq(renamed, {"before", "after"})
    test.raises(host.monotonic, "no clock provider is available")
    test.raises(host.walltime, "no clock provider is available")
end

function M.preservesTheHostTableAndCachesImmutableSystemInfo()
    local count, queries = 2, 0
    local uuidLoads, calls4, calls7 = 0, 0, 0
    local valid4 = "12345678-1234-4123-8123-123456789abc"
    local valid7 = "12345678-1234-7123-8123-123456789abc"
    local original = {
        clock = function()
            return 9
        end
    }
    local monotonic, walltime = function()
        return 123.5
    end, function()
        return 1700000000123
    end
    local uuid4, uuid7 = function()
        calls4 = calls4 + 1
        return valid4
    end, function()
        calls7 = calls7 + 1
        return valid7
    end
    local randombytes = function(count)
        return ("r"):rep(count)
    end
    local load = providerstate.instance(
        {["nupp.runtime.standardos"] = true, ["nupp.runtime.systeminfo"] = true, ["nupp.util.internal.uuid"] = true},
        {
            ["nupp.runtime.system"] = {
                platform = "fixture",
                architecture = "fixture64",
                endianness = "little",
                pointerBits = 64,
                availableParallelism = function()
                    queries = queries + 1;
                    return count
                end,
            },
            ["nupp.runtime.timeprovider"] = {provider = {now = monotonic, walltime = walltime}},
            ["nupp.runtime.entropy"] = {randombytes = randombytes},
        },
        {
            ["nupp.runtime.uuidprovider"] = function()
                uuidLoads = uuidLoads + 1
                return {uuid4 = uuid4, uuid7 = uuid7}
            end,
        },
        {os = original}
    )
    local surface = load("nupp.runtime.standardos")
    test.eq(surface.value, original)
    test.eq(queries, 0)
    local first = original.info()
    test.eq(queries, 0, "constructing the report performs no query")
    test.eq(first.platform, "fixture")
    test.eq(first.arch, "fixture64")
    test.eq(first.endianness, "little")
    test.eq(first.pointerbits, 64)
    test.eq(first.parallelism, 2)
    count = 7
    test.eq(original.info(), first, "the immutable report is shared")
    test.eq(original.info().parallelism, 2, "parallelism is cached after first access")
    test.eq(queries, 1)
    for _, key in ipairs({"platform", "arch", "endianness", "pointerbits", "parallelism", "fs", "extra"}) do
        test.raises(
            function()
                first[key] = false
            end,
            "immutable"
        )
    end
    test.raises(
        function()
            setmetatable(first, {})
        end,
        "protected metatable"
    )
    test.eq(original.monotonic, monotonic)
    test.eq(original.walltime, walltime)
    test.eq(uuidLoads, 0, "system and clock queries do not select a UUID provider")
    local make = original.uuid
    test.eq(make, surface.uuid, "the public table and exported function share one callable")
    test.eq(original.uuid, make, "repeated public reads retain their callable identity")
    test.eq(original.uuid4, nil)
    test.eq(original.uuid7, nil)
    for _, invalid in ipairs({0, 1, 5, 6, 8, 4.5, "4", true}) do
        test.raises(
            function()
                make(invalid)
            end,
            "UUID version must be 4 or 7"
        )
    end
    test.raises(
        function()
            make()
        end,
        "UUID version must be 4 or 7"
    )
    test.eq(uuidLoads, 0, "invalid versions do not select a UUID provider")
    test.eq(make(4), valid4)
    test.eq(original.uuid(4), valid4)
    test.eq(make(7), valid7)
    test.eq(surface.uuid(7), valid7)
    test.eq(uuidLoads, 1, "both UUID versions retain the same selected provider")
    test.eq(calls4, 2, "each public version 4 call invokes its provider exactly once")
    test.eq(calls7, 2, "each public version 7 call invokes its provider exactly once")
    test.eq(surface.randombytes, randombytes)
    test.eq(original.randombytes, randombytes)
    test.eq(original.randombytes(3), "rrr")
    test.eq(require("nupp.runtime.standardmath").value.randombytes, nil)
    test.eq(original.clock(), 9)
end

function M.checkedInfoAndServicesUseThePrivateContract()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local root = require("helpers.paths").tests .. "/.."
    local env = environment()
    local source = [[
local function describe(value: os.Info): string return value.platform end
local facts: os.Info = os.info()
local monotonic: number = os.monotonic()
local wall: number = os.walltime()
local random: string = os.uuid(4)
local ordered: string = os.uuid(7)
local bytes: string = os.randombytes(7)
return describe(facts), monotonic, wall, random, ordered, bytes
]]
    local parsed = parser.parse(source, "system-services.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "system-services.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, generated = gen.generate(parsed, "system-services.nupp")
    test.eq(#generated, 0)
    assert(code:find('require("nupp.runtime.standardos")', 1, true))
    assert(
        parsed.effects["runtime.system"]
        and parsed.effects["runtime.clocks"]
        and parsed.effects["runtime.uuid"]
        and parsed.effects["runtime.crypto"]
    )
    local platform, monotonic, wall, random, ordered, bytes = assert(loadstring(code))()
    test.eq(platform, os.info().platform)
    test.eq(type(monotonic), "number")
    test.eq(type(wall), "number")
    test.eq(#random, 36)
    test.eq(#ordered, 36)
    test.eq(#bytes, 7)
end

function M.onlyLazySystemFieldsCanSuspend()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local root = require("helpers.paths").tests .. "/.."
    local env = environment()
    for _, field in ipairs({"platform", "arch", "endianness", "pointerbits", "parallelism", "fs"}) do
        local source = "local function read(facts: os.Info): nil\n"
            .. "    @nosuspend do print(facts."
            .. field
            .. ") end\nend"
        local parsed = parser.parse(source, "system-field-effects.nupp")
        test.eq(#parsed.errors, 0, field)
        local diagnostics = checker.check(parsed, "system-field-effects.nupp", env)
        local suspensions = 0
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.severity == "error" then
                test.eq(diagnostic.code, "NUPP2701", diagnostic.msg)
                suspensions = suspensions + 1
            end
        end
        test.eq(suspensions, (field == "parallelism" or field == "fs") and 1 or 0, field)
    end
end

function M.filesystemFactsDoNotPackageTheFilesystemImplementation()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local native = require("nupp.compiler.native")
    local root = require("helpers.paths").tests .. "/.."
    local source = 'local caps: os.FsCaps = os.info().fs\nlocal glob: boolean = caps.glob\nprint(glob)'
    local parsed = parser.parse(source, "filesystem-facts.nupp")
    test.eq(#parsed.errors, 0)
    local env = environment()
    local diagnostics = checker.check(parsed, "filesystem-facts.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local _, generated, _, emitted = gen.generate(parsed, "filesystem-facts.nupp")
    test.eq(#generated, 0)
    local expanded = native.expand(emitted)
    assert(not expanded["runtime.files"] and not expanded["native.files"], "metadata does not select file I/O")
end

function M.clockInstallerDoesNotPackageUnusedProvidersAtAnyOptimizationLevel()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local native = require("nupp.compiler.native")
    local optimize = require("nupp.compiler.lua.optimize")
    local root = require("helpers.paths").tests .. "/.."
    local path = root .. "/src/nupp/runtime/standardos.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    for _, level in ipairs({0, 1, 2}) do
        local parsed = parser.parse(source, path)
        test.eq(#parsed.errors, 0)
        local env = environment()
        local diagnostics = checker.check(parsed, path, env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        optimize.run(parsed, {level = level})
        local code, generated, _, emitted = gen.generate(parsed, path)
        test.eq(#generated, 0)
        local expanded = native.expand(emitted)
        assert(
            not expanded["runtime.uuid"] and not expanded["native.uuid"],
            "OS initialization selected unused UUID support"
        )
        assert(
            not expanded["runtime.files"] and not expanded["native.files"],
            "OS initialization selected unused filesystem support"
        )
        for _, name in ipairs(gen.runtimeModules(code)) do
            assert(
                name ~= "nupp.runtime.bindings.files" and name ~= "io.internal.files",
                "OS initialization packages unused filesystem module " .. name
            )
            assert(
                name ~= "nupp.util.internal.uuid"
                and name ~= "nupp.runtime.uuidprovider"
                and name ~= "nupp.runtime.provider.nativeuuid",
                "OS initialization packages unused UUID module " .. name
            )
        end
    end
end

function M.directAndAliasedUuidCallsCarryTheHelperAndProvider()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local native = require("nupp.compiler.native")
    local root = require("helpers.paths").tests .. "/.."
    local sources = {
        "print(os.uuid(4))",
        "local make = os.uuid\nprint(make(4))",
        "local system = os\nprint(system.uuid(7))",
        "local system = require('os')\nprint(system.uuid(4))",
        "module nupp.uuidfixture\nlocal system = require('nupp.runtime.standardos')\nprint(system.uuid(7))",
        "module nupp.uuidfixture\nlocal system = require('nupp.runtime.standardos')\nlocal make = system.uuid\nprint(make(4))",
    }
    for _, source in ipairs(sources) do
        local path = source:match("^module nupp%.uuidfixture") and root .. "/src/nupp/uuidfixture.nupp"
            or "uuid-features.nupp"
        local parsed = parser.parse(source, path)
        test.eq(#parsed.errors, 0, source)
        local env = environment()
        local diagnostics = checker.check(parsed, path, env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local _, generated, _, emitted = gen.generate(parsed, path)
        test.eq(#generated, 0)
        assert(emitted["runtime.uuid"], "the UUID read lost its explicit feature: " .. source)
        local modules = {}
        for effect in pairs(native.expand(emitted)) do
            local feature = native.feature(effect)
            if feature and feature.runtimeModule then
                modules[feature.runtimeModule] = true
            end
        end
        assert(modules["nupp.util.internal.uuid"], "the UUID feature omits its validating helper")
        assert(modules["nupp.runtime.uuidprovider"], "the UUID feature omits its selected provider")
    end
end

local function fileSurface(host, provider, browser)
    return providerstate.instance(
        {["nupp.runtime.standardos"] = true},
        {
            ["nupp.runtime.system"] = {},
            ["nupp.runtime.timeprovider"] = {},
            ["nupp.runtime.entropy"] = {},
            ["nupp.runtime.bindings.files"] = provider,
        },
        nil,
        {os = host, __nuppBrowser = browser}
    )("nupp.runtime.standardos")
end

function M.fileMutationsPreserveLuaReturnsAndAcceptPaths()
    local seen, providerCalls = {}, 0
    local host = {
        remove = function(path)
            seen[#seen + 1] = path
            return nil, "denied", 13
        end,
        rename = function(from, to)
            seen[#seen + 1] = from
            seen[#seen + 1] = to
            return true
        end,
    }
    local surface = fileSurface(host, {
        remove = function(path, recursive)
            providerCalls = providerCalls + 1
            test.eq(path, "tree")
            test.eq(recursive, true)
            return false, "busy"
        end
    })
    test.eq(surface.value, host)
    local path = {
        tostring = function()
            return "file"
        end
    }
    local ok, reason, code = host.remove(path)
    test.eq(ok, nil)
    test.eq(reason, "denied")
    test.eq(code, 13)
    test.eq(host.rename(path, "destination"), true)
    test.deepeq(seen, {"file", "file", "destination"})
    test.eq(providerCalls, 0, "ordinary native calls retain Lua's implementation")
    ok, reason, code = host.remove("tree", true)
    test.eq(ok, nil)
    test.eq(reason, "busy")
    test.eq(code, nil)
    test.eq(providerCalls, 1)
    test.raises(
        function()
            host.remove("tree", "yes")
        end,
        "recursive must be a boolean"
    )
end

function M.browserFileMutationsKeepPathAuthorityAndNormalizeFailures()
    local path, destination = {}, {}
    local host = {
        remove = function()
            error("native remove reached browser")
        end,
        rename = function()
            error("native rename reached browser")
        end,
    }
    fileSurface(
        host,
        {
            remove = function(received, recursive)
                test.eq(received, path)
                test.eq(recursive, true)
                return true
            end,
            rename = function(from, to)
                test.eq(from, path)
                test.eq(to, destination)
                return false, "rename unsupported"
            end,
        },
        {}
    )
    test.eq(host.remove(path, true), true)
    local ok, reason = host.rename(path, destination)
    test.eq(ok, nil)
    test.eq(reason, "rename unsupported")
end

function M.fileMutationsAcceptPathTypesAndRetainTheirRuntimeFeatures()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local root = require("helpers.paths").tests .. "/.."
    for _, source in ipairs({
        'local path: io.Path = io.Path.of("tree")\nreturn os.remove(path, true)',
        'local from: io.Path = assert(os.appdir("data"))\nreturn os.rename(from, from:join("new"))',
    }) do
        local parsed = parser.parse(source, "file-mutations.nupp")
        test.eq(#parsed.errors, 0)
        local env = environment()
        local diagnostics = checker.check(parsed, "file-mutations.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local _, errors, _, emitted = gen.generate(parsed, "file-mutations.nupp")
        test.eq(#errors, 0)
        assert(emitted["runtime.files"], "file mutations must package their provider path")
    end
end

function M.temporaryNamesReportDeprecation()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local root = require("helpers.paths").tests .. "/.."
    local env = environment()
    for _, source in ipairs({
        "return os.tmpname()",
        "local system = os\nreturn system.tmpname()",
        'local system = require("os")\nreturn system.tmpname()',
        "const {tmpname} = os\nreturn tmpname()",
    }) do
        local parsed = parser.parse(source, "temporary-name.nupp")
        local diagnostics = checker.check(parsed, "temporary-name.nupp", env)
        assert(#diagnostics > 0, "deprecation was lost: " .. source)
        for _, diagnostic in ipairs(diagnostics) do
            test.eq(diagnostic.code, "NUPP2513", source)
            assert(diagnostic.msg:find("manual cleanup", 1, true))
        end
    end
    local source = "local os = {tmpname = function(): string return 'local' end}\nreturn os.tmpname()"
    local parsed = parser.parse(source, "shadowed-temporary-name.nupp")
    local env = environment()
    test.eq(#checker.check(parsed, "shadowed-temporary-name.nupp", env), 0)
end

function M.filesystemFunctionsTypeAsTheirTuplesAndIterators()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local root = require("helpers.paths").tests .. "/.."
    local accepted = {
        'local kind, size, modified, readonly, err = os.stat("a")\n'
        .. "if kind ~= nil then\n"
        .. "    local k: os.FileKind = kind\n"
        .. "    print(k, size, modified, readonly)\n"
        .. "else\n"
        .. "    local e: io.Error? = err\n"
        .. "    print(e)\n"
        .. "end",
        'for name, kind in os.list("src") do\n    local n: string = name\n    local k: os.FileKind = kind\n    print(n, k)\nend',
        'local kind: os.FileKind? = os.stat("a", nofollow = true)\nprint(kind)',
        'local kind: os.FileKind? = os.stat("a", false)\nprint(kind)',
        'local present: boolean?, err: io.Error? = os.exists("a")\nprint(present, err)',
        'local matches: {io.Path}? = os.glob("src/*.nupp")\nprint(matches)',
        'os.setappid("example", "notes")\nlocal data: io.Path = assert(os.appdir("data"))\nlocal file = assert(io.open(data:join("notes.txt"), "w"))\nprint(file)',
        'local scratch = assert(os.mktemp(nil, ".json"))\nprint(scratch:tostring())\nscratch:close()',
    }
    for _, source in ipairs(accepted) do
        local parsed = parser.parse(source, "filesystem-surface.nupp")
        test.eq(#parsed.errors, 0, source)
        local env = environment()
        local diagnostics = checker.check(parsed, "filesystem-surface.nupp", env)
        test.eq(#diagnostics, 0, (diagnostics[1] and diagnostics[1].msg or "") .. "\n" .. source)
        local _, errors, _, emitted = gen.generate(parsed, "filesystem-surface.nupp")
        test.eq(#errors, 0)
        assert(emitted["runtime.files"], "a filesystem call must package its provider: " .. source)
    end
    for _, source in ipairs({
        "os.info().fs.glob = false",
        'os.info().platform = "changed"',
        'os.stat("a", nofollow = "yes")',
        'os.lstat("a")',
        'os.fscaps()',
        "local old: os.AppPath = nil",
        'os.appdir("documents")',
        'local present: boolean = os.exists("a")',
        'local info = io.files.info("a")',
        'print(os.userdir, os.setreadonly)',
    }) do
        local parsed = parser.parse(source, "filesystem-refused.nupp")
        local env = environment()
        local diagnostics = checker.check(parsed, "filesystem-refused.nupp", env)
        assert(#diagnostics > 0, "the checker accepted: " .. source)
    end
end

return M
