local test = require("assert")
local providerstate = require("helpers.providerstate")
local M = {}

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

function M.preservesTheHostTableAndQueriesParallelismPerCall()
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
        {["nupp.runtime.standardos"] = true, ["nupp.util.internal.uuid"] = true},
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
    test.eq(first.platform, "fixture")
    test.eq(first.arch, "fixture64")
    test.eq(first.endianness, "little")
    test.eq(first.pointerbits, 64)
    test.eq(first.parallelism, 2)
    count = 7
    test.eq(original.info().parallelism, 7)
    test.eq(first.parallelism, 2)
    test.eq(queries, 2)
    test.eq(original.monotonic, monotonic)
    test.eq(original.walltime, walltime)
    test.eq(uuidLoads, 0, "system and clock queries do not select a UUID provider")
    local random, ordered = original.uuid4, original.uuid7
    test.eq(random, surface.uuid4, "the public table and exported function share one callable")
    test.eq(ordered, surface.uuid7)
    test.eq(original.uuid4, random, "repeated public reads retain their callable identity")
    test.eq(original.uuid7, ordered)
    test.eq(random(), valid4)
    test.eq(original.uuid4(), valid4)
    test.eq(ordered(), valid7)
    test.eq(surface.uuid7(), valid7)
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
    local program = require("program")
    local environment = require("nupp.compiler.project.env")
    local env = environment.new(assert(environment.compilerRoot()))
    local source = [[
local function describe(value: os.Info): string return value.platform end
local facts: os.Info = os.info()
local monotonic: number = os.monotonic()
local wall: number = os.walltime()
local random: string = os.uuid4()
local ordered: string = os.uuid7()
local bytes: string = os.randombytes(7)
return describe(facts), monotonic, wall, random, ordered, bytes
]]
    local parsed = parser.parse(source, "system-services.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "system-services.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    program.installSourceModules()
    local image = program.image(parsed, "systemservices")
    assert(program.names(image, "nupp.runtime.standardos"))
    assert(
        parsed.effects["runtime.system"]
        and parsed.effects["runtime.clocks"]
        and parsed.effects["runtime.uuid"]
        and parsed.effects["runtime.crypto"]
    )
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local chunk = assert(loadImage(image))
    local platform, monotonic, wall, random, ordered, bytes = chunk()
    test.eq(platform, os.info().platform)
    test.eq(type(monotonic), "number")
    test.eq(type(wall), "number")
    test.eq(#random, 36)
    test.eq(#ordered, 36)
    test.eq(#bytes, 7)
    test.eq(os.randombytes, require("nupp.runtime.entropy").randombytes)
    test.eq(require("os"), os)
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

function M.browserFileMutationsKeepAppPathAuthorityAndNormalizeFailures()
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
    local root = require("helpers.paths").tests .. "/.."
    for _, source in ipairs({
        'local path: io.Path = io.Path.of("tree")\nreturn os.remove(path, true)',
        'local from: os.AppPath = assert(os.appdir("data"))\nreturn os.rename(from, from:join("new"))',
    }) do
        local parsed = parser.parse(source, "file-mutations.nupp")
        test.eq(#parsed.errors, 0)
        local env = require("nupp.compiler.project.env").new(root, {cache = false})
        local diagnostics = checker.check(parsed, "file-mutations.nupp", env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        assert(parsed.effects["runtime.files"], "file mutations must package their provider path")
    end
end

function M.temporaryNamesReportDeprecation()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local root = require("helpers.paths").tests .. "/.."
    local env = require("nupp.compiler.project.env").new(root, {cache = false})
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
    local env = require("nupp.compiler.project.env").new(root, {cache = false})
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
        'local present: boolean?, err: io.Error? = os.exists("a")\nprint(present, err)',
        'local matches: {io.Path}? = os.glob("src/*.nupp")\nprint(matches)',
        'os.setappid("example", "notes")\nlocal data: os.AppPath? = os.appdir("data")\nprint(data)',
        'local caps: os.FsCaps = os.fscaps()\nlocal glob: boolean = caps.glob\nprint(glob)',
        'local scratch = assert(os.mktemp(nil, ".json"))\nprint(scratch:tostring())\nscratch:close()',
    }
    for _, source in ipairs(accepted) do
        local parsed = parser.parse(source, "filesystem-surface.nupp")
        test.eq(#parsed.errors, 0, source)
        local env = require("nupp.compiler.project.env").new(root, {cache = false})
        local diagnostics = checker.check(parsed, "filesystem-surface.nupp", env)
        test.eq(#diagnostics, 0, (diagnostics[1] and diagnostics[1].msg or "") .. "\n" .. source)
        local _, errors, _, emitted = gen.generate(parsed, "filesystem-surface.nupp")
        test.eq(#errors, 0)
        assert(emitted["runtime.files"], "a filesystem call must package its provider: " .. source)
    end
    for _, source in ipairs({
        "os.fscaps().glob = false",
        'os.appdir("documents")',
        'local present: boolean = os.exists("a")',
        'local info = io.files.info("a")',
        'print(os.userdir, os.setreadonly)',
    }) do
        local parsed = parser.parse(source, "filesystem-refused.nupp")
        local env = require("nupp.compiler.project.env").new(root, {cache = false})
        local diagnostics = checker.check(parsed, "filesystem-refused.nupp", env)
        assert(#diagnostics > 0, "the checker accepted: " .. source)
    end
end

return M
