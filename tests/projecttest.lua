local testAssert = require("nupp.test")
local project = require("nupp.tools.build.project")
local buildPackage = require("nupp.tools.build.package")
local deps = require("nupp.tools.build.deps")
local hash = require("nupp.compiler.hash")
local process = require("nupp.compiler.process")
local store = require("nupp.compiler.project.store")
local nativeStage = require("nupp.tools.build.native")
local buildPlatform = require("nupp.tools.build.platform")
local hostSystem = buildPlatform.hostSystem()
local fs = require("nupp.compiler.fs")
local compilerEnv = require("nupp.compiler.project.env")
local json = require("testjson")
local buildSyntax = require("nupp.compiler.shellsyntax")

local function write(path, text)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then
        os.execute("mkdir -p '" .. dir .. "'")
    end
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

-- Runtime modules without carried Lua artifacts are compiled from staged source.
-- Count those records independently; project invalidation expectations stay exact.
local function compiledRuntimeSources(dir, projectModules)
    local expected, seen = {}, {}
    for _, name in ipairs(projectModules) do
        expected[name] = true
    end
    local state = assert(json.decode(read(dir .. "/out/.nupp-state.json")))
    local prefix = dir .. "/out/cache/runtime-source/"
    local count = 0
    for name, record in pairs(state.modules) do
        if record.sourcePath then
            if record.sourcePath:sub(1, #prefix) == prefix then
                count = count + 1
            else
                assert(expected[name], "unexpected project source module: " .. name)
                seen[name] = true
            end
        end
    end
    for _, name in ipairs(projectModules) do
        assert(seen[name], "missing project source module: " .. name)
    end

    return count
end

--- Where a project's content-keyed stores went.
---
--- Headers, formatting verdicts and type-function results answer about content rather
--- than about a project, so `NUPP_CACHE_DIR` may name one directory for all of them --
--- and the test runner sets it, because a run that makes a project per case would
--- otherwise start every one of them cold. A case about what those stores do has to
--- reach the file that was actually written. The check state is not one of them: it is
--- keyed by module name and stays with the project.
local function contentCacheDir(dir, outDir)
    return os.getenv("NUPP_CACHE_DIR") or (dir .. "/" .. outDir .. "/cache")
end

local function exists(path)
    local f = io.open(path, "rb")
    if not f then
        return false
    end
    f:close()

    return true
end

--- Skips a case that needs a Rust toolchain when the machine has none.
---
--- A cargo dependency is built by cargo, and a machine without one cannot say
--- whether the code that drives it is right. Reported as a skip with the reason,
--- the same way a case needing a C compiler or the HTTP provider is: a run that
--- silently passed would claim coverage it does not have.
local function requireCargo()
    local probe = io.popen("command -v cargo 2>/dev/null")
    local found = probe and probe:read("*l") or nil
    if probe then
        probe:close()
    end
    if found == nil or found == "" then
        require("assert").skip("cargo is unavailable")
    end
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    for name, text in pairs(files) do
        write(dir .. "/" .. name, text)
    end

    return dir
end

local function remove(dir)
    os.execute("rm -rf '" .. dir .. "'")
end

local function libraryName(name)
    if hostSystem == "windows" then
        return name .. ".dll"
    end
    if hostSystem == "darwin" then
        return "lib" .. name .. ".dylib"
    end

    return "lib" .. name .. ".so"
end

local function staticLibraryName(name)
    return "lib" .. name .. ".a"
end

local function executableName(name)
    return name .. (hostSystem == "windows" and ".exe" or "")
end

-- Builds a project's entry module as a VM program and reports what it answered.
-- The manifest's own build is turned into a binary target for the one build and
-- then put back, so the case goes on with the project it wrote.
local function answerFrom(dir)
    local manifest = read(dir .. "/nupp.lua")
    local program, replaced = manifest:gsub(
        'entries%s*=%s*{%s*"main"%s*}',
        'kind = "binary", stub = "nupp", entries = {"answer"}',
        1
    )
    assert(replaced == 1, "the manifest builds main: " .. manifest)
    write(dir .. "/nupp.lua", program)
    write(dir .. "/src/answer.nupp", "print('VALUE ' .. tostring(require('main')))\n")
    local diagnostics = {}
    local built = project.build(dir, {diagnostics = diagnostics})
    write(dir .. "/nupp.lua", manifest)
    os.remove(dir .. "/src/answer.nupp")
    if built ~= 0 then
        return "the program did not build: " .. tostring(diagnostics[1] and diagnostics[1].msg)
    end
    local code, out = process.capture({dir .. "/out/" .. executableName("binary")}, {cwd = dir})
    if code ~= 0 then
        return out or ""
    end

    return out:match("VALUE ([^\r\n]+)") or out
end

local M = {}

function M.payloadWithoutBytecodeDumperKeepsSource()
    local dump = rawget(string, "dump")
    rawset(string, "dump", nil)
    local ok, payload, flags, err = pcall(
        buildPackage.payloadBytes,
        "this is source, not compiled here",
        buildPlatform.hostKey()
    )
    rawset(string, "dump", dump)
    assert(ok, payload)
    testAssert.equal(payload, "this is source, not compiled here")
    testAssert.equal(flags, 0)
    testAssert.equal(err, nil)
end

function M.payloadBytecodeDumperPreservesFlagsAndFailures()
    local dump = rawget(string, "dump")
    local calls = 0
    rawset(string, "dump", function(chunk, options)
        calls = calls + 1
        assert(type(chunk) == "function")
        assert(options == "ds")
        return "test-bytecode"
    end)
    local ok, payload, flags, err = pcall(buildPackage.payloadBytes, "return true", buildPlatform.hostKey())
    rawset(string, "dump", dump)
    assert(ok, payload)
    testAssert.equal(calls, 1)
    testAssert.equal(payload, "test-bytecode")
    testAssert.equal(flags, 1)
    testAssert.equal(err, nil)

    rawset(string, "dump", function()
        error("test dumper failure", 0)
    end)
    ok, payload, flags, err = pcall(buildPackage.payloadBytes, "return true", buildPlatform.hostKey())
    rawset(string, "dump", dump)
    assert(ok, payload)
    testAssert.equal(payload, nil)
    testAssert.equal(flags, nil)
    testAssert.equal(err, "the bundle did not dump: test dumper failure")
end

function M.sha256KnownVectors()
    testAssert.equal(hash.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    testAssert.equal(hash.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end

-- The published XXH64 answers. Cache keys never leave this machine, so
-- nothing forces the digest to be a particular function -- but a hand-rolled
-- one that is subtly wrong is a hand-rolled one nobody notices is wrong, and
-- these vectors are how a rewrite gets caught.
function M.xxh64KnownVectors()
    local function xxh(input, seed)
        -- `xxh64` carries its seed as two `uint32` halves, high then low, the
        -- same as everywhere else in this file; every seed below fits the low
        -- half.
        return hash.hex64(hash.xxh64(input, 0, seed))
    end

    testAssert.equal(xxh("", 0), "ef46db3751d8e999")
    testAssert.equal(xxh("a", 0), "d24ec4f1a98c6e5b")
    testAssert.equal(xxh("abc", 0), "44bc2cf5ad770999")
    testAssert.equal(xxh("abcd", 0), "de0327b0d25d92cc")
    testAssert.equal(xxh("heiå", 0), "b9d3d990d2001a1a")
    testAssert.equal(xxh("", 1), "d5afba1336a3be4b")
    testAssert.equal(xxh("Nobody inspects the spammish repetition", 0), "fbcea83c8a378bf1")
end

-- The formatter reaches the same digest through native host services, so the
-- fast path must keep every durable cache key compatible with the portable
-- implementation. Exercise the stripe boundary, all tail branches, binary
-- bytes, and enough input for the performance-sensitive path.
function M.theNativeContentDigestMatchesThePortableOne()
    local nativeHash = require("nupp.compiler.hostservices").hash
    local inputs = {
        "",
        "a",
        "abc",
        ("x"):rep(31),
        ("y"):rep(32),
        ("z"):rep(33),
        string.char(0, 255, 128, 1, 7),
        ("Nobody inspects the spammish repetition\0"):rep(4096),
    }
    for size = 0, 96 do
        local bytes = {}
        for index = 1, size do
            bytes[index] = string.char((index * 131 + size) % 256)
        end
        inputs[#inputs + 1] = table.concat(bytes)
    end
    for index, input in ipairs(inputs) do
        testAssert.equal(nativeHash.digest(input), hash.digest(input), "portable digest input " .. index)
    end
end

-- The eight bytes a stamped binary's trailer records. The Rust base provider
-- recomputes them on every run of that binary before handing a byte of the
-- payload to Lua, so this is one contract with two spellings and these are the
-- numbers both have to produce. The order matters as much as the value: the
-- field is little-endian so that a binary stamped on one machine verifies on
-- another, and a digest written the other way round would still be eight bytes
-- and still be wrong.
function M.theTrailerDigestIsLittleEndianXxh64()
    local function trailer(input)
        local bytes = hash.trailerDigest(input)
        local out = {}
        for index = 1, 8 do
            out[index] = ("%02x"):format(bytes:byte(index))
        end

        return table.concat(out)
    end

    -- The same published vectors as above, read back the other way round.
    testAssert.equal(trailer(""), "99e9d85137db46ef")
    testAssert.equal(trailer("a"), "5b6e8ca9f1c44ed2")
    testAssert.equal(trailer("abc"), "990977adf52cbc44")

    -- Either side of the thirty-two byte stripe loop, and a tail that reaches
    -- the four-byte branch and then the byte one.
    testAssert.equal(#hash.trailerDigest(("x"):rep(31)), 8)
    testAssert.equal(trailer(("x"):rep(31)), "f0993b08010ddd60")
    testAssert.equal(trailer(("y"):rep(32)), "66ce95341d1fda64")
    testAssert.equal(trailer(("z"):rep(33)), "68024ec6531224c5")
    testAssert.equal(trailer(string.char(0, 255, 128, 1, 7)), "950d048cbb3ee7b9")
end

-- Every tail branch and the stripe loop, at every length that reaches them.
-- The interesting failures here are off-by-one, not wrong constants: a digest
-- that ignores the last byte agrees with itself forever.
function M.digestSeparatesEveryLength()
    local seen = {}
    for n = 0, 200 do
        local input = ("abcdefgh"):rep(30):sub(1, n)
        local d = hash.digest(input)
        testAssert.equal(#d, 32)
        testAssert.equal(seen[d], nil)
        seen[d] = n
        testAssert.equal(hash.digest(input), d)
    end
    -- A one-byte change anywhere has to move the answer, including in the
    -- final byte, which is the one a tail loop drops.
    for _, n in ipairs({1, 4, 7, 8, 15, 16, 31, 32, 33, 64, 100}) do
        local input = ("x"):rep(n)
        local flipped = input:sub(1, n - 1) .. "y"
        assert(hash.digest(input) ~= hash.digest(flipped), "digest ignored the last byte at length " .. n)
    end
end

function M.windowsMkdirUsesNativePathAndIsIdempotent()
    testAssert.equal(fs.join("C:/one", "D:/two"), "D:/two", "joining an absolute Windows path does not prefix it")
    local command = process.mkdirCommand("build/nupp", true)
    testAssert.equal(table.concat(command, " "), "cmd /d /c if not exist build\\nupp mkdir build\\nupp")

    local posix = process.mkdirCommand("build/nupp", false)
    testAssert.equal(table.concat(posix, " "), "mkdir -p build/nupp")
end

function M.windowsAbsolutePathsAreNotModulesUnderTheCurrentRoot()
    local path = "C:/Users/runner/AppData/Local/Temp/backend/source/example.nupp"
    testAssert.equal(
        compilerEnv.moduleNameInRoots({"."}, path),
        nil,
        "a drive path outside the project has no canonical module name"
    )
    assert(
        not compilerEnv.isProjectPath({roots = {"."}, config = {}, rootDir = "."}, path),
        "a drive path outside the project is not project source"
    )
    testAssert.equal(
        compilerEnv.moduleNameInRoots({"."}, "source/example.nupp"),
        "source.example",
        "a relative path remains a module beneath the current root"
    )
end

-- A relative path that climbs out of its root with `..` was named as if it were
-- beneath it: `../mini.nupp` against "." became the module "...mini", which
-- import-c then wrote as the generated module's name. A `..` that stays inside
-- keeps the name its spelling always had, because a source loaded through that
-- spelling is already known by it.
function M.aPathThatClimbsOutOfItsRootIsNotAModuleBeneathIt()
    for _, case in ipairs({
        {".", "../mini.nupp"},
        {"src", "src/../mini.nupp"},
        {"src", "src/a/../../b.nupp"},
        {"/work/p", "/work/p/../q/c.nupp"},
    }) do
        testAssert.equal(compilerEnv.moduleNameInRoots({case[1]}, case[2]), nil, case[2])
        assert(
            not compilerEnv.isProjectPath({roots = {case[1]}, config = {}, rootDir = "."}, case[2]),
            case[2] .. " is not project source"
        )
    end
    testAssert.equal(compilerEnv.moduleNameInRoots({"src"}, "src/a/b.nupp"), "a.b")
    testAssert.equal(
        compilerEnv.moduleNameInRoots({"."}, "tests/../src/a.nupp"),
        "tests....src.a",
        "a .. that stays inside keeps its spelling"
    )
    assert(compilerEnv.isProjectPath({roots = {"."}, config = {}, rootDir = "."}, "tests/../src/a.nupp"))
end

function M.isolatedProcessStopsAtItsWallClockDeadline()
    if hostSystem == "windows" then
        return
    end
    local code = process.captureIsolated({"sh", "-c", "while :; do :; done"}, {timeoutMs = 50})
    testAssert.equal(code, 124, "the process is killed at its deadline")
end

function M.isolatedProcessCapturesACompletedResponse()
    local code, output = process.captureIsolated({"sh", "-c", "printf worker-ready"}, {timeoutMs = 1000})
    testAssert.equal(code, 0, "the completed child succeeds")
    testAssert.equal(output, "worker-ready", "the private output is returned")
end

function M.isolatedProcessAppliesAMemoryCeilingWhenSupported()
    if hostSystem == "windows" then
        return
    end
    local code, output = process.captureIsolated({"sh", "-c", "printf memory-bounded"}, {
        timeoutMs = 1000,
        memoryMb = 256
    })
    testAssert.equal(code, 0, "the bounded child succeeds")
    testAssert.equal(output, "memory-bounded", "the bounded child returns its response")
end

function M.persistsVersionedMaterializationProductsAndObservations()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        [
            "src/main.nupp"
        ] = [[
local record Position
    x: number
end

const PositionCodec: nupp.reflect.FieldCodec<Position> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end

return PositionCodec:encode(new Position(x = 1))
]],
    })
    local cold, coldStats = {}, {}
    testAssert.equal(project.build(dir, {produced = cold, stats = coldStats}), 0)
    testAssert.equal(#cold.materializations, 1, "the cold build reports its materialization")
    local observation = cold.materializations[1]
    testAssert.equal(observation.provider, "fieldcodec", "provider observation")
    testAssert.equal(observation.schema, 2, "provider schema")
    testAssert.equal(observation.backend, "keyed", "selected backend")
    assert(observation.blueprintSize > 0 and observation.generatedSize > 0, "bounded sizes are reported")
    testAssert.equal(observation.abis.runtimeExpression, 2, "runtime-expression ABI")
    testAssert.equal(observation.blueprint, nil, "the public record omits the canonical payload")
    testAssert.equal(observation.generated, nil, "the public record omits generated source")

    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    local cached = state.modules.main.materializations[1]
    assert(
        cached.blueprint and cached.blueprint.fingerprint == observation.fingerprint,
        "the manifest cache retains the canonical blueprint"
    )
    assert(
        type(cached.generated) == "string" and #cached.generated > 0,
        "the manifest cache retains the backend output"
    )

    local warm, warmStats = {}, {}
    testAssert.equal(project.build(dir, {produced = warm, stats = warmStats}), 0)
    testAssert.equal(warmStats.checkedModules, 0, "the cached build rechecks nothing")
    testAssert.equal(
        warm.materializations[1].fingerprint,
        observation.fingerprint,
        "the cached build reports the same canonical product"
    )
    remove(dir)
end

function M.cachedProducersRetainNestedRuntimeTypeWitnesses()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include={"src"},build={outDir="out",entries={"main"}}}',
        -- Reaches the reflection modules from the start, so the edit below changes
        -- only the consumer and not what the build has to link.
        [
            "src/main.nupp"
        ] = 'local models=require("witnessmodels") local _=nupp.reflect.runtime(models.Parent) '
        .. "return models.make().child.value",
        [
            "src/witnessmodels.nupp"
        ] = [[
local models = {}
local record Child
    value: integer
end
record models.Parent
    child: Child
end
function models.make(): models.Parent
    return new models.Parent(child = new Child(value = 7))
end
return models
]],
    })
    testAssert.equal(project.build(dir, {}), 0)
    write(
        dir .. "/src/main.nupp",
        [[
local models = require("witnessmodels")
local info = nupp.reflect.runtime(models.Parent)
local child = nupp.reflect.runtimeType(info, info.fields[1].type as integer)
local value = models.make()
return child == getmetatable(value.child) and value.child.value == 7
]]
    )
    local stats = {}
    testAssert.equal(project.build(dir, {stats = stats}), 0)
    testAssert.equal(stats.checkedModules, 1, "only the consumer changed")
    testAssert.equal(answerFrom(dir), "true")
    remove(dir)
end

function M.foreignWitnessesSurviveCollectionBetweenModuleLoads()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include={"src"},build={outDir="out",entries={"main"}}}',
        ["src/childmodels.nupp"] = [[
local models = {}
record models.Child
    value: integer
end
return models
]],
        [
            "src/parentmodels.nupp"
        ] = [[
local children = require("childmodels")
local models = {}
record models.Parent
    child: children.Child
end
return models
]],
        [
            "src/main.nupp"
        ] = [[
local children = require("childmodels")
collectgarbage("collect")
collectgarbage("collect")
local parents = require("parentmodels")
local info = nupp.reflect.runtime(parents.Parent)
return nupp.reflect.runtimeType(info, info.fields[1].type as integer) == children.Child
]],
    })
    testAssert.equal(project.build(dir, {}), 0)
    testAssert.equal(answerFrom(dir), "true")
    remove(dir)
end

function M.annotationChangesInvalidateReflectedMaterializations()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        [
            "src/main.nupp"
        ] = [[
local models = require("models")
const UserCodec: nupp.reflect.FieldCodec<models.User> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(models.User))
end
return UserCodec.fingerprint
]],
        [
            "src/models.nupp"
        ] = [[
local models = {}
@annotation(targets = {"record"})
local record wire
    name: string
end

@wire(name = "users")
record models.User
    id: integer
end
return models
]],
    })
    local cold, coldStats = {}, {}
    testAssert.equal(project.build(dir, {produced = cold, stats = coldStats}), 0)
    local firstObservation = assert(cold.materializations[1])
    testAssert.equal(firstObservation.schema, 2, "field-codec provider schema")
    testAssert.equal(firstObservation.abis.emitter, 2, "field-codec emitter ABI")
    testAssert.equal(firstObservation.abis.helper, 2, "field-codec helper ABI")
    testAssert.equal(firstObservation.abis.runtimeExpression, 2, "field-codec runtime-expression ABI")
    local first = firstObservation.fingerprint

    local source = read(dir .. "/src/models.nupp")
    write(dir .. "/src/models.nupp", source:gsub('name = "users"', 'name = "accounts"'))
    local changed, changedStats = {}, {}
    testAssert.equal(project.build(dir, {produced = changed, stats = changedStats}), 0)
    testAssert.equal(
        changedStats.checkedModules,
        2,
        "changing exported reflected metadata rechecks its dependent module"
    )
    assert(
        first ~= assert(changed.materializations[1]).fingerprint,
        "annotation values participate in the materialization fingerprint"
    )
    remove(dir)
end

function M.layoutTargetsSeparatePersistentComptimeResults()
    local function manifest(target)
        return (
            [=[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = %q}}
]=]
        ):format(target)
    end

    local dir = tempProject({
        ["nupp.lua"] = manifest("x86_64-unknown-linux-gnu"),
        [
            "src/main.nupp"
        ] = [[
local struct PointerSized
    tag: int8
    pointer: int8*
end
return comptime do return nupp.sizeof(PointerSized) end
]],
    })

    local lp64 = {}
    testAssert.equal(project.build(dir, {stats = lp64}), 0)
    local runtime = compiledRuntimeSources(dir, {"main"})
    testAssert.equal(lp64.checkedModules, 1 + runtime, "the first target checks the project and runtime source")

    local warm = {}
    testAssert.equal(project.build(dir, {stats = warm}), 0)
    testAssert.equal(warm.checkedModules, 0, "the same target reuses its result")

    write(dir .. "/nupp.lua", manifest("i686-unknown-linux-gnu"))
    local ilp32 = {}
    testAssert.equal(project.build(dir, {stats = ilp32}), 0)
    testAssert.equal(compiledRuntimeSources(dir, {"main"}), runtime)
    testAssert.equal(ilp32.checkedModules, 1 + runtime, "changing the target invalidates the old results")
    remove(dir)
end

function M.exportedLayoutChangesInvalidateOnlyTheirReaders()
    local model = [[
local models = {}
struct models.Wire
    tag: int8
    value: int32
end
function models.body(): number return 1 end
return models
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = "x86_64-unknown-linux-gnu"}}
]],
        ["src/main.nupp"] = [[
local models = require("models")
return comptime do return nupp.sizeof(models.Wire) end
]],
        ["src/models.nupp"] = model,
    })

    local cold = {}
    testAssert.equal(project.build(dir, {stats = cold}), 0)
    local runtime = compiledRuntimeSources(dir, {"main", "models"})
    testAssert.equal(cold.checkedModules, 2 + runtime, "the layout reader, declaration and runtime source check cold")

    write(dir .. "/src/models.nupp", model:gsub("return 1", "return 2"))
    local body = {}
    testAssert.equal(project.build(dir, {stats = body}), 0)
    testAssert.equal(body.checkedModules, 1, "a body edit checks only its module")
    testAssert.equal(body.reusedModules, 1 + runtime, "the layout reader and runtime cut off at the interface")

    write(dir .. "/src/models.nupp", model:gsub("value: int32", "value: number"))
    local changed = {}
    testAssert.equal(project.build(dir, {stats = changed}), 0)
    testAssert.equal(changed.checkedModules, 2, "a field layout edit rechecks its reader")
    remove(dir)
end

function M.manifestValidationRejectsInvalidReferencesAndCycles()
    local missing = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {native = {kind = "c", sources = {"native.c"}}},
   build = {entries = {"main"}, dependencies = {"missing"}},
}
]],
    })
    local config, err = project.loadManifest(missing)
    testAssert.equal(config, nil, "unknown target dependency rejects the manifest")
    assert(err:find("references unknown dependency missing", 1, true), err)
    remove(missing)

    local cyclic = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {
      first = {kind = "c", dependencies = {"second"}},
      second = {kind = "c", dependencies = {"first"}},
   },
   build = {entries = {"main"}},
}
]],
    })
    config, err = project.loadManifest(cyclic)
    testAssert.equal(config, nil, "dependency cycles reject the manifest")
    assert(err:find("dependency cycle involving", 1, true), err)
    remove(cyclic)
end

function M.manifestAcceptsSeveralPkgConfigPackages()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c",
   pkgConfig = {"simdjson", "luajit"}}}, build = {entries = {"main"}}}
]]
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    testAssert.equal(table.concat(config.dependencies.native.pkgConfig, ","), "simdjson,luajit")
    remove(valid)

    local invalid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c", pkgConfig = {"simdjson", ""}}},
   build = {entries = {"main"}}}
]]
    })
    config, err = project.loadManifest(invalid)
    testAssert.equal(config, nil, "an empty package name rejects the manifest")
    assert(err:find("pkgConfig%[2%] must be a non%-empty string"), err)
    remove(invalid)
end

function M.manifestValidatesCDependencyLinkage()
    for _, linkage in ipairs({"shared", "static", "both"}) do
        local valid = tempProject({
            [
                "nupp.lua"
            ] = (
                [[
return {dependencies = {native = {kind = "c", linkage = %q}},
   build = {entries = {"main"}}}
]]
            ):format(linkage)
        })
        local config, err = project.loadManifest(valid)
        assert(config, err)
        testAssert.equal(config.dependencies.native.linkage, linkage)
        remove(valid)
    end

    local invalid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c", linkage = "dynamic"}},
   build = {entries = {"main"}}}
]]
    })
    local config, err = project.loadManifest(invalid)
    testAssert.equal(config, nil, "an unknown C linkage rejects the manifest")
    assert(err:find('linkage must be "shared", "static", or "both"', 1, true), err)
    remove(invalid)

    local strayOutput = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {native = {kind = "c", staticOutput = "native.a"}},
   build = {entries = {"main"}}}
]]
    })
    config, err = project.loadManifest(strayOutput)
    testAssert.equal(config, nil, "a static output without static linkage rejects the manifest")
    assert(err:find('staticOutput requires linkage = "static" or "both"', 1, true), err)
    remove(strayOutput)
end

function M.manifestValidatesPrebuiltArtifacts()
    local host = require("nupp.compiler.targetlayout").hostKey()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = (
            [=[
return {
   dependencies = {native = {kind = "c", linkage = "static", artifacts = {
      [%q] = {static = {path = "native.a", sha256 = %q, size = 8}},
   }}},
   build = {kind = "binary", stub = "nupp",
      entries = {"main"}, dependencies = {"native"}},
}
]=]
        ):format(host, ("0"):rep(64))
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    remove(valid)
end

function M.manifestValidatesTypeDependenciesSeparatelyFromTargets()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {
      host = {
         kind = "types",
         format = "luacats",
         source = {
            git = "https://example.invalid/host.git",
            rev = "0123456789012345678901234567890123456789",
         },
         path = "library",
      },
   },
   build = {entries = {"main"}},
}
]],
        ["main.nupp"] = "local value = 1\n"
    })
    assert(project.loadManifest(valid), "a pinned LuaCATS dependency is valid")
    remove(valid)

    local invalid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {
      host = {kind = "types", format = "teal", source = {git = "https://example.invalid/host.git", rev = "short"}},
   },
}
]]
    })
    local _, err = project.loadManifest(invalid)
    assert(err and err:find("format", 1, true), "the importer format is validated")
    remove(invalid)
end

function M.manifestValidatesTheCompileTimeLayoutTarget()
    local valid = tempProject({
        ["nupp.lua"] = [[
return {build = {entries = {"main"},
   layoutTarget = "aarch64-apple-darwin"}}
]]
    })
    local config, err = project.loadManifest(valid)
    assert(config, "a supported layout target is accepted: " .. tostring(err))
    testAssert.equal(config.build.layoutTarget, "aarch64-apple-darwin")
    local described = assert(project.describeTasks(valid, "default"))
    testAssert.equal(
        described.layoutTarget,
        "aarch64-apple-darwin",
        "task discovery reports the effective layout target"
    )
    remove(valid)

    local invalid = tempProject({
        ["nupp.lua"] = [[
return {build = {entries = {"main"}, layoutTarget = "mystery-cpu"}}
]]
    })
    config, err = project.loadManifest(invalid)
    testAssert.equal(config, nil, "an unknown layout target rejects the manifest")
    assert(err:find("layoutTarget names unsupported target mystery-cpu", 1, true), err)
    assert(err:find("x86_64%-unknown%-linux%-gnu"), err)
    remove(invalid)
end

function M.manifestValidatesCrossTargetBinaryPlatforms()
    local validDir = tempProject({
        [
            "nupp.lua"
        ] = [[return {build = {kind = "binary", stub = "nupp",
         entries = {"main"}, platforms = {"x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin", "x86_64-pc-windows-msvc"}}}]],
    })
    local config, err = project.loadManifest(validDir)
    assert(config, err)
    testAssert.equal(#config.build.platforms, 3, "all catalog platforms are retained")
    remove(validDir)

    local cases = {
        {platforms = "{}", message = "must not be empty"},
        {
            platforms = '{"x86_64-unknown-linux-gnu", "x86_64-unknown-linux-gnu"}',
            message = "duplicates x86_64-unknown-linux-gnu",
        },
        {platforms = '{"aarch64-unknown-linux-gnu"}', message = "unsupported binary platform"},
    }
    for _, case in ipairs(cases) do
        local dir = tempProject({
            [
                "nupp.lua"
            ] = (
                'return {build = {kind = "binary", stub = "nupp", entries = {"main"}, platforms = %s}}'
            ):format(case.platforms),
        })
        local rejected, why = project.loadManifest(dir)
        testAssert.equal(rejected, nil, "invalid cross-target manifest is rejected")
        assert(why:find(case.message, 1, true), why)
        remove(dir)
    end
end

function M.browserHostsCannotSelectNativeDistributionPlatforms()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary", stub = "nupp",
            host = "browser", entries = {"main"}, outDir = "out",
            platforms = {"aarch64-apple-darwin"}}}]],
        ["src/main.nupp"] = "return 42\n",
    })
    local rejected, why = project.loadManifest(dir)
    testAssert.equal(rejected, nil, "a browser host cannot use native distribution stubs")
    assert(why:find('platforms selects native binary hosts', 1, true), why)
    write(dir .. "/nupp.lua", read(dir .. "/nupp.lua"):gsub('host = "browser"', 'host = "native"'))
    local accepted, problem = project.loadManifest(dir)
    assert(accepted, problem)
    testAssert.equal(
        project.check(dir, {
            host = "browser"
        }),
        1,
        "a check rejects the resolved host before applying a native layout"
    )

    local root = assert(require("nupp.io.path").currentDirectory()):toString()
    local status, output = process.capture({root .. "/bin/nupp", "build", "--host", "browser"}, {cwd = dir})
    testAssert.equal(status, 1, "the command-line host override is also rejected\n" .. output)
    assert(output:find('platforms selects native binary hosts', 1, true), output)
    assert(not require("nupp.io.files").isDirectory(dir .. "/out"), "rejection writes no build output")
    remove(dir)
end

function M.manifestRestrictsPortablePayloadOutputsToBinaryTargets()
    local validDir = tempProject({
        [
            "nupp.lua"
        ] = [[return {build = {kind = "binary", stub = "host",
         entries = {"main"}, output = "app", payloadOutput = "app.lua"}}]],
    })
    local config, err = project.loadManifest(validDir)
    assert(config, err)
    testAssert.equal(config.build.payloadOutput, "app.lua")
    remove(validDir)

    local invalidDir = tempProject({
        ["nupp.lua"] = [[return {build = {kind = "bundle", entries = {"main"},
         payloadOutput = "app.lua"}}]],
    })
    local rejected, why = project.loadManifest(invalidDir)
    testAssert.equal(rejected, nil, "a bundle cannot claim a separately stamped payload")
    assert(why:find("payloadOutput is only valid for a binary target", 1, true), why)
    remove(invalidDir)
end

function M.crossTargetBuildRefusesSidecarOnlyProvidersBeforeCargoRuns()
    local dir = tempProject({})
    local outputs, err = nativeStage.build(dir, "out", {["native.http"] = true}, "x86_64-pc-windows-msvc")
    testAssert.equal(outputs, nil, "a compiler-host HTTP sidecar is not staged")
    assert(err:find("sidecar-only native feature http", 1, true), err)
    remove(dir)
end

function M.taskDescriptionsUseEffectiveTargetConfiguration()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   build = {
      outDir = "out",
      entries = {"shared.main"},
      default = "other",
      targets = {
         default = {description = "The task named default"},
         other = {entries = {"other.main"}},
      },
   },
}
]],
    })
    local task, err = project.describeTasks(dir, "default")
    assert(task, err)
    testAssert.equal(task.name, "default", "named default task is queried literally")
    testAssert.equal(task.default, false, "query reports the configured default accurately")
    testAssert.equal(task.outDir, "out", "task inherits the output directory")
    testAssert.equal(task.entries[1], "shared.main", "task inherits shared entries")
    remove(dir)
end

-- The generator reads a dozen keys the build's own validation knows nothing
-- about, so a misspelling used to configure nothing and say nothing about it.
function M.aMisspelledDocsKeyIsRejectedWithTheNameItMeant()
    local function reject(target, wanted)
        local dir = tempProject({
            ["nupp.lua"] = "return {include = {\"src\"}, build = {targets = {site = " .. target .. "}}}\n"
        })
        local config, err = project.loadManifest(dir)
        testAssert.equal(config, nil, "a key that configures nothing is refused")
        assert(err:find(wanted, 1, true), wanted .. " not in: " .. tostring(err))
        remove(dir)
    end

    reject('{kind = "docs", sources = {"src"}, titel = "x"}', 'has no key "titel"; did you mean "title"?')
    reject(
        '{kind = "docs", sources = {"src"}, pages = {{titel = "x"}}}',
        'pages[1] has no key "titel"; did you mean "title"?'
    )
    reject(
        '{kind = "docs", sources = {"src"}, pages = {{glob = "docs/**.md", ' .. 'exlude = {"docs/style.md"}}}}',
        'pages[1] has no key "exlude"; did you mean "exclude"?'
    )
    -- A page names what it publishes one way or the other, and one that names
    -- neither a route nor a pattern is a page nothing can place.
    reject('{kind = "docs", sources = {"src"}, pages = {{source = "docs/x.md"}}}', 'pages[1].path must be a string')
    reject('{kind = "docs", sources = {"src"}, pages = {{glob = 1}}}', 'pages[1].glob must be an array')
    -- Nothing near enough to guess at is still named, without one.
    reject('{kind = "docs", sources = {"src"}, wibble = 1}', 'has no key "wibble"')
end

-- Retired keys are not refused by name: each fails as any key nothing reads does.
function M.retiredManifestKeysFailAsUnknownKeys()
    local function reject(manifestSource, wanted)
        local dir = tempProject({["nupp.lua"] = manifestSource})
        local config, err = project.loadManifest(dir)
        testAssert.equal(config, nil, manifestSource)
        assert(err and err:find(wanted, 1, true), wanted .. " not in: " .. tostring(err))
        remove(dir)
    end

    reject('return {include = {"src"}, strict = true}\n', 'nupp.lua has no key "strict"')
    reject(
        'return {include = {"src"}, build = {targets = {app = {kind = "modules", aotCflags = {"-O2"}}}}}\n',
        'has no key "aotCflags"'
    )
    -- One spelling for a tier range: the string form read as an exact tier and meant
    -- a maximum.
    reject(
        'return {include = {"src"}, build = {targets = {app = {kind = "modules", aot = "require", '
        .. 'aotFeatures = "avx2"}}}}\n',
        "aotFeatures must be a table"
    )
    reject(
        'return {include = {"src"}, build = {targets = {app = {kind = "modules", dialect = "luajit"}}}}\n',
        'has no key "dialect"'
    )
    reject(
        'return {include = {"src"}, build = {targets = {site = {kind = "docs", sources = {"src"}, dialect = "luajit"}}}}\n',
        'has no key "dialect"'
    )
    -- A produced path is `output` everywhere a manifest names one.
    reject(
        'return {include = {"src"}, dependencies = {native = {kind = "c", out = "lib/native.so"}}}\n',
        'has no key "out"'
    )
    reject(
        'return {include = {"src"}, dependencies = {native = {kind = "c", bindings = '
        .. '{header = "native.h", out = "src/native.nupp"}}}}\n',
        'has no key "out"'
    )
    reject(
        'return {include = {"src"}, dependencies = {native = {kind = "rust"}}}\n',
        'kind must be "c", "cargo", "luarocks", or "types"'
    )
    reject(
        'return {include = {"src"}, build = {targets = {site = {kind = "docs", sources = {"src"}, all = true}}}}\n',
        'has no key "all"'
    )
end

function M.deliverableTargetsStillRequireAnEntry()
    local cases = {
        bundle = '{kind = "bundle"}',
        binary = '{kind = "binary", stub = "nupp"}',
        component = '{kind = "component", exports = {"app.run"}}',
    }
    for kind, target in pairs(cases) do
        local dir = tempProject({["nupp.lua"] = 'return {include = {"src"}, build = ' .. target .. '}\n',})
        local config, err = project.loadManifest(dir)
        testAssert.equal(config, nil, kind .. " without an entry is refused")
        assert(err and err:find("build.entries is required", 1, true), tostring(err))
        remove(dir)
    end
end

-- `fmt` gets the same treatment as any other manifest table: a typo names
-- itself rather than configuring nothing.
function M.fmtManifestKeyIsValidated()
    local function loadFmt(fmt)
        local dir = tempProject({["nupp.lua"] = 'return {include = {"src"}, fmt = ' .. fmt .. '}\n'})
        local config, err = project.loadManifest(dir)
        remove(dir)
        return config, err
    end

    local config = loadFmt('{methodParens = false}')
    assert(config, "a valid fmt table is accepted")
    testAssert.equal(config.fmt.methodParens, false, "and its value survives")

    local _, err = loadFmt('"off"')
    assert(err and err:find("fmt must be a table", 1, true), err)

    local _, typeErr = loadFmt('{methodParens = "no"}')
    assert(typeErr and typeErr:find("fmt.methodParens must be a boolean", 1, true), typeErr)

    local _, nameErr = loadFmt('{methodParen = false}')
    assert(nameErr and nameErr:find('fmt has no key "methodParen"; did you mean "methodParens"?', 1, true), nameErr)
end

-- A docs target is still a build target, so what any target takes belongs on
-- one too. This project's declares the rocks `nupp doc` renders with.
function M.aDocsTargetKeepsTheKeysEveryTargetTakes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {lunamark = {kind = "luarocks", rock = "lunamark",
      version = "0.6.0-1"}},
   build = {targets = {site = {
      kind = "docs", sources = {"src"}, dependencies = {"lunamark"},
      format = "both", name = "N", github = "https://example.com",
      logo = "l.svg", public = "p", customCss = "c.css",
      includePrivate = true,
      pages = {{path = "", title = "H", layout = "home", source = "i.md",
         redirects = {"old"}}, {glob = {"docs/**.md"}, base = "docs",
         exclude = {"docs/style.md"}}},
   }}},
}
]]
    })
    local config, err = project.loadManifest(dir)
    assert(config, "every documented key is accepted: " .. tostring(err))
    remove(dir)
end

function M.nativeFeatureOverridesAreValidatedAndReported()
    local function load(features)
        local dir = tempProject({
            [
                "nupp.lua"
            ] = [[
return {include = {"src"}, build = {targets = {app = {
   entries = {"main"}, nativeFeatures = ]]
            .. features
            .. [[
}}}}
]]
        })
        local config, err = project.loadManifest(dir)
        local task = config and project.describeTasks(dir, "app") or nil
        remove(dir)

        return config, err, task
    end

    local config, err, task = load("{compression = true, path = true, uuid = false}")
    assert(config, "boolean native feature overrides are accepted: " .. tostring(err))
    testAssert.equal(task.nativeFeatures.compression, true, "task reports forced inclusion")
    testAssert.equal(task.nativeFeatures.path, true, "new native providers can be forced in")
    testAssert.equal(task.nativeFeatures.uuid, false, "new native providers can be forced out")

    local _, unknown = load("{jsoon = true}")
    assert(unknown and unknown:find("nativeFeatures names no feature jsoon", 1, true), tostring(unknown))
    local _, wrongType = load("{compression = 'yes'}")
    assert(
        wrongType and wrongType:find("nativeFeatures.compression must be true or false", 1, true),
        tostring(wrongType)
    )
end

function M.subprocessPreservesEmptyArguments()
    local dir = tempProject({["argv.sh"] = [[printf '%s|%s|%s' "$#" "$1" "$2"]],})
    local status, output = process.capture({"sh", dir .. "/argv.sh", "", "tail"})
    remove(dir)
    testAssert.equal(status, 0, output)
    testAssert.equal(output, "2||tail", "an empty argv entry reaches the child process")
end

function M.nativeFacilitiesSharingAProviderBuildAsOneUnion()
    local originalCapture, originalCopy = process.capture, fs.copyFile
    local originalCompilerRoot = compilerEnv.compilerRoot
    local calls, copies = {}, {}
    -- The driver answers with the path it built, which is the last line it
    -- writes; anything before that is progress.
    process.capture = function(argv)
        calls[#calls + 1] = argv
        return 0, "/built/libnupp_native.dylib\n"
    end
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "."
    end
    local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {["native.path"] = true, ["native.uuid"] = true,})
    process.capture, fs.copyFile = originalCapture, originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.equal(#calls, 1, "one provider union is built once")
    testAssert.equal(#copies, 2, "the shared library and path runtime are staged")
    local command = "\n" .. table.concat(calls[1], "\n") .. "\n"
    assert(command:find("\nnative%-rust\nfilesystem,uuid\n"), "path and UUID select one sorted Rust feature union")
    testAssert.equal(copies[1][1], "/built/libnupp_native.dylib", "the Rust provider union has one source artifact")
    assert(copies[1][2]:find("out/lib/nupp_native", 1, true), "the Rust provider union keeps its stable sidecar name")
end

function M.gpuOverrideSelectsAHostWithTheProviderLinked()
    local originalCapture = process.capture
    local originalCompilerRoot = compilerEnv.compilerRoot
    local calls = {}
    process.capture = function(argv)
        calls[#calls + 1] = argv
        return 0, "/built/nupp-host\n"
    end
    compilerEnv.compilerRoot = function()
        return "."
    end
    local ok, problem = pcall(function()
        for _, enabled in ipairs({false, true}) do
            local effects = nativeStage.resolve({}, {gpu = enabled})
            local host, err = nativeStage.hostStub(".", "out", {stub = "nupp"}, effects)
            testAssert.equal(host, "/built/nupp-host", err)
        end
    end)
    process.capture = originalCapture
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, problem)
    testAssert.equal(#calls, 2, "each feature union selects its own host")
    testAssert.equal(calls[1][#calls[1]], "", "GPU is absent when disabled")
    testAssert.equal(calls[2][#calls[2]], "native-gpu", "forcing GPU changes the host build and cache key")
end

function M.nativeFacilityCanSelectItsProviderDriver()
    local originalCapture, originalCopy = process.capture, fs.copyFile
    local originalCompilerRoot = compilerEnv.compilerRoot
    local calls, copies = {}, {}
    process.capture = function(argv)
        calls[#calls + 1] = argv
        return 0, "/built/libnupp_native.dylib\n"
    end
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "."
    end
    local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {["native.gpu"] = true,})
    process.capture, fs.copyFile = originalCapture, originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.equal(#calls, 1, "the facility selects one provider build")
    local command = "\n" .. table.concat(calls[1], "\n") .. "\n"
    assert(command:find("\nnative%-rust\n"), "the feature's provider driver is passed to the toolchain")
    assert(command:find("\ngpu\n", 1, true), "the selected driver receives the provider feature union")
    testAssert.equal(copies[1][1], "/built/libnupp_native.dylib")
    assert(copies[1][2]:find("out/lib/nupp_native", 1, true), "the Rust provider has an independent sidecar name")
end

function M.aTargetKeepsTheRuntimeModuleItAlreadyBuilt()
    local originalCopy = fs.copyFile
    local originalCompilerRoot = compilerEnv.compilerRoot
    local copies = {}
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "/compiler"
    end
    local output = "/project/out/nupp/suspension.lua"
    local ok, outputs, problem = pcall(nativeStage.build, "/project", "out", {['runtime.suspension'] = true}, nil, {
        [output] = true
    })
    fs.copyFile = originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.equal(#copies, 0, "native staging preserves the target's generated runtime")
    assert(outputs[output], "the preserved runtime remains a staged output")

    copies = {}
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "/compiler"
    end
    ok, outputs, problem = pcall(nativeStage.build, "/project", "out", {['runtime.suspension'] = true})
    fs.copyFile = originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.equal(#copies, 1, "an application still receives the compiler runtime")
    testAssert.equal(copies[1][1], "/compiler/build/nupp/suspension.lua")
    testAssert.equal(copies[1][2], output)
end

-- A docs target with no outDir does not land in the manifest's default
-- directory; the generator has its own, and for markdown it is not even under
-- it. `nupp clean` removes what the task table names, so naming the wrong
-- place left the output behind and took an unrelated directory with it.
function M.aDocsTaskReportsWhereTheGeneratorWillWrite()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {targets = {
      site = {kind = "docs", sources = {"src"}},
      api = {kind = "docs", sources = {"src"}, format = "markdown"},
      chosen = {kind = "docs", sources = {"src"}, outDir = "elsewhere"},
   }},
}
]],
    })
    local site = assert(project.describeTasks(dir, "site"))
    testAssert.equal(site.outDir, "build/docs", "a site target defaults below build")
    local api = assert(project.describeTasks(dir, "api"))
    testAssert.equal(api.outDir, "docs/api.md", "a markdown target defaults to a file")
    local chosen = assert(project.describeTasks(dir, "chosen"))
    testAssert.equal(chosen.outDir, "elsewhere", "an explicit outDir still wins")
    remove(dir)
end

-- `all` and `includePrivate` include different things, and the task table
-- reported the first under the second's name while never mentioning the second.
function M.docsTaskReportsItsPrivacySetting()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {targets = {site = {
      kind = "docs", sources = {"src"}, includePrivate = true,
   }}},
}
]],
    })
    local task = assert(project.describeTasks(dir, "site"))
    testAssert.equal(task.includePrivate, true)
    testAssert.equal(task.all, nil, "there is one privacy setting")
    remove(dir)
end

function M.strictnessFollowsTheFileExtensionThroughTheProject()
    -- The extension decides, and it has to survive the whole path from the file on
    -- disk to the checker: a `.nupp` reports an unknown name, a `.lua` does not.
    local luaDir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
        ["src/main.lua"] = "return unknown_project_value\n",
    })
    local strictDir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
        ["src/main.nupp"] = "return unknown_project_value\n",
    })
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local plain = project.check(luaDir)
    local strict = project.check(strictDir)
    io.stderr:close()
    io.stderr = originalStderr
    os.remove(errorPath)
    testAssert.equal(plain, 0, ".lua permits unknown globals")
    testAssert.equal(strict, 1, ".nupp reports an unknown name")
    remove(luaDir)
    remove(strictDir)
end

function M.manifestBuildDiscoversModulesAndPreservesPaths()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"},
      resources = {"src/app/*.d.nupp",
         {source = "src/schema.nupp", output = "app/data/schema.nupp"}}},
}
]],
        ["src/app/main.nupp"] = "local lib = require('lib.util')\nreturn lib\n",
        ["src/lib/util.nupp"] = "return { answer = 42 }\n",
        ["src/app/data.d.nupp"] = "return { ok: boolean }\n",
        ["src/schema.nupp"] = "return { version = 1 }\n",
    })
    testAssert.equal(project.build(dir), 0)
    -- A library is its source, so its build writes nothing beside the record.
    assert(not exists(dir .. "/out/app/data.d.nupp"), "a library build copies no resources")
    assert(exists(dir .. "/out/.nupp-state.json"), "persistent state is written")
    assert(exists(dir .. "/out/.nupp-complete"), "the completion marker is published")
    assert(
        not exists(dir .. "/out/.nupp-complete.pending"),
        "the stamp it was written to is renamed into place rather than left beside it"
    )
    -- The launcher rebuilds whenever a source is newer than this marker, so the marker
    -- has to date from before the sources were read. Stamped when the build finished it
    -- covered every edit made while the build was running: an edit that landed too late
    -- to be compiled was also too old to ask for another build, and the tree stayed one
    -- edit behind until something unrelated happened to move.
    testAssert.equal(
        os.execute(("test ! '%s/out/.nupp-complete' -nt '%s/out/.nupp-state.json'"):format(dir, dir)),
        0,
        "the completion marker must not be newer than what the build wrote"
    )
    testAssert.equal(project.build(dir), 0, "warm build succeeds")
    write(dir .. "/out/.nupp-state.json", "not json")
    testAssert.equal(project.build(dir), 0, "corrupt state degrades to a cold build")
    remove(dir)
end

-- Advice about a program is not a reason to refuse to compile it. A note and a
-- warning are said and stepped over; only an error withholds the build's output
-- and fails it.
function M.onlyAnErrorStopsAManifestBuild()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"}},
}
]],
        [
            "src/app/main.nupp"
        ] = table.concat(
            {
                "local type Color = 'red' | 'green' | 'blue'",
                "local function name(c: Color): string",
                "    if c == 'red' then",
                "        return 'r'",
                "    end",
                "end",
                "return { name = name }",
            },
            "\n"
        ) .. "\n",
    })
    testAssert.equal(project.build(dir), 0, "a warning does not fail the build")
    assert(exists(dir .. "/out/.nupp-complete"), "a warning does not withhold the build")

    -- the same lint, turned up by the project, does stop it
    write(
        dir .. "/nupp.lua",
        [[
return {
   include = {"src"},
   lints = {["exhaustiveness"] = "error"},
   build = {outDir = "out", entries = {"app.main"}},
}
]]
    )
    remove(dir .. "/out")
    assert(project.build(dir) ~= 0, "raised to an error, it stops the build")
    assert(not exists(dir .. "/out/.nupp-complete"), "and the build is withheld")
    remove(dir)
end

function M.moduleBuildCacheUsesDependencyInterfaces()
    local depV1 = table.concat(
        {"local function answer(): number", "   return 1", "end", "return { answer = answer }",},
        "\n"
    )
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat({"local lib = require('lib')", "local value: number = lib.answer()", "return value",}, "\n"),
        ["src/lib.nupp"] = depV1,
    })

    local cold = {}
    testAssert.equal(project.build(dir, {stats = cold}), 0)
    local runtime = compiledRuntimeSources(dir, {"main", "lib"})
    testAssert.equal(cold.checkedModules, 2 + runtime, "cold build checks the project and runtime closure")

    local warm = {}
    testAssert.equal(project.build(dir, {stats = warm}), 0)
    testAssert.equal(warm.checkedModules, 0, "warm build checks no modules")
    testAssert.equal(warm.generatedModules, 0, "warm build generates no modules")
    testAssert.equal(warm.reusedModules, 2 + runtime, "warm build reuses the project and runtime closure")

    write(dir .. "/src/lib.nupp", depV1:gsub("return 1", "return 2"))
    local bodyEdit = {}
    testAssert.equal(project.build(dir, {stats = bodyEdit}), 0)
    testAssert.equal(bodyEdit.checkedModules, 1, "body edit checks only the changed dependency")
    testAssert.equal(
        bodyEdit.reusedModules,
        1 + runtime,
        "body edit reuses the dependent and runtime after interface cutoff"
    )

    write(
        dir .. "/src/lib.nupp",
        table.concat(
            {
                depV1:gsub("return 1", "return 2"),
                "-- Change the returned module interface without breaking consumers.",
            },
            "\n"
        )
            :gsub("return { answer = answer }", "return { answer = answer, label = 'answer' }")
    )
    local interfaceEdit = {}
    testAssert.equal(project.build(dir, {stats = interfaceEdit}), 0)
    testAssert.equal(interfaceEdit.checkedModules, 2, "interface edit rechecks the dependency and dependent")
    testAssert.equal(
        interfaceEdit.reusedModules,
        runtime,
        "changed interface invalidates the dependent but preserves the runtime"
    )
    remove(dir)
end

function M.moduleBuildCacheIncludesDeprecationMetadata()
    local lib = table.concat({"local M = {}", "function M.answer(): number", "   return 42", "end", "return M",}, "\n")
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = table.concat({"local lib = require('lib')", "return lib.answer()",}, "\n"),
        ["src/lib.nupp"] = lib,
    })

    testAssert.equal(project.check(dir, {stats = {}, diagnostics = {}}), 0)
    write(
        dir .. "/src/lib.nupp",
        lib:gsub("function M.answer", '@deprecated(replacement = "lib.currentAnswer")\nfunction M.answer')
    )
    local stats, diagnostics = {}, {}
    testAssert.equal(project.check(dir, {stats = stats, diagnostics = diagnostics}), 0)
    testAssert.equal(stats.checkedModules, 2, "deprecation metadata invalidates the persistent dependent cache")
    local sawDeprecated = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2513" then
            sawDeprecated = true
        end
    end
    assert(sawDeprecated, "the rebuilt dependent reports the deprecated API")

    remove(dir)
end

function M.warmBuildInvalidatesOnlyReadersOfAChangedProjectType()
    local model = table.concat({"global record ReflectedModel", "   name: string", "end", "return {}",}, "\n")
    local unrelated = table.concat({"global record UnrelatedModel", "   value: number", "end", "return {}",}, "\n")
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/model.nupp"] = model,
        ["src/unrelated.nupp"] = unrelated,
        [
            "src/main.nupp"
        ] = table.concat(
            {
                "const SUMMARY = comptime do",
                "   local info = nupp.reflect(ReflectedModel)",
                "   return info.fields[1].name",
                "end",
                "return SUMMARY",
            },
            "\n"
        ),
    })

    local cold = {}
    testAssert.equal(project.build(dir, {stats = cold}), 0)
    local runtime = compiledRuntimeSources(dir, {"main", "model", "unrelated"})
    testAssert.equal(cold.checkedModules, 3 + runtime, "cold build checks every project module and runtime source")

    local warm = {}
    testAssert.equal(project.build(dir, {stats = warm}), 0)
    testAssert.equal(warm.checkedModules, 0, "unchanged project is warm")

    write(dir .. "/src/unrelated.nupp", unrelated:gsub("value: number", "value: string"))
    local unrelatedEdit = {}
    testAssert.equal(project.build(dir, {stats = unrelatedEdit}), 0)
    testAssert.equal(unrelatedEdit.checkedModules, 1, "unrelated export edit checks only its declaring module")
    testAssert.equal(unrelatedEdit.reusedModules, 2 + runtime, "the reflecting module and runtime remain reusable")

    write(dir .. "/src/model.nupp", model:gsub("name: string", "name: string\n   count: integer"))
    local reflectedEdit = {}
    testAssert.equal(project.build(dir, {stats = reflectedEdit}), 0)
    testAssert.equal(reflectedEdit.checkedModules, 2, "reflected field edit checks its declaration and reader")
    testAssert.equal(reflectedEdit.reusedModules, 1 + runtime, "unrelated module and runtime remain reusable")
    remove(dir)
end

function M.storeKeepsWhatItWasGivenAndForgetsNothingLive()
    local dir = "/tmp/nupp-store-test-" .. tostring(process.mkdirCommand and 1 or 1)
    os.execute("rm -rf '" .. dir .. "'")
    local path = dir .. "/s.buf"

    local first = store.open(path, "stamp-1")
    testAssert.equal(first.get("a"), nil, "an unopened store has nothing in it")
    first.put("a", {n = 1, list = {"x", "y"}})
    first.put("b", {n = 2})
    first.save()

    local second = store.open(path, "stamp-1")
    testAssert.equal(second.get("a").n, 1, "a value survives the round trip")
    testAssert.equal(second.get("a").list[2], "y", "including what is nested in it")
    testAssert.equal(second.get("b").n, 2)
    testAssert.equal(second.stats.hits, 3, "three hits, three lookups")

    -- A different stamp is a different compiler or a different project. There
    -- is no way to tell which of the entries it would have changed, so none of
    -- them are kept.
    local restamped = store.open(path, "stamp-2")
    testAssert.equal(restamped.get("a"), nil, "a restamped store starts empty")

    -- Every way the file can be wrong is a miss, never an error.
    for _, damage in ipairs({"", "garbage", "\0\1\2\3", ("x"):rep(5000)}) do
        write(path, damage)
        local damaged = store.open(path, "stamp-1")
        testAssert.equal(damaged.get("a"), nil, "a damaged store has nothing in it")
        damaged.put("a", {n = 9})
        damaged.save()
        testAssert.equal(store.open(path, "stamp-1").get("a").n, 9, "and is overwritten by the next run")
    end

    -- A store with nowhere to live still works; it just never hits.
    local nowhere = store.open(nil, "stamp-1")
    nowhere.put("a", {n = 1})
    nowhere.save()
    testAssert.equal(nowhere.get("a").n, 1, "within one run it still answers")
    testAssert.equal(store.open(nil, "stamp-1").get("a"), nil, "and never persists")

    -- The single-value store, under the same rules.
    local vpath = dir .. "/v.buf"
    local value = store.openValue(vpath, "stamp-1")
    testAssert.equal(value.value, nil)
    value.set({modules = {m = {sourceHash = "abc"}}})
    value.save()
    testAssert.equal(store.openValue(vpath, "stamp-1").value.modules.m.sourceHash, "abc")
    testAssert.equal(store.openValue(vpath, "stamp-2").value, nil, "a restamped value store is empty")
    write(vpath, "not a buffer")
    testAssert.equal(store.openValue(vpath, "stamp-1").value, nil, "a damaged value store is empty")

    os.execute("rm -rf '" .. dir .. "'")
end

-- `nupp check` reuses on the same terms a build does, and the thing that has
-- to be true for that to be allowed is that reuse still says what checking
-- would have said. A check whose only output is diagnostics cannot get faster
-- by producing fewer of them.
function M.checkReusesUnchangedModulesAndStillReportsThem()
    local libV1 = table.concat(
        {"local function answer(): number", "   return 1", "end", "return { answer = answer }",},
        "\n"
    )
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat({"local lib = require('lib')", "local value: number = lib.answer()", "return value",}, "\n"),
        ["src/lib.nupp"] = libV1,
    })

    local cold = {}
    testAssert.equal(project.check(dir, {stats = cold, diagnostics = {}}), 0)
    testAssert.equal(cold.checkedModules, 2, "a cold check checks the closure")
    testAssert.equal(cold.generatedModules, 0, "a check does not generate module artifacts")

    local warm = {}
    testAssert.equal(project.check(dir, {stats = warm, diagnostics = {}}), 0)
    testAssert.equal(warm.checkedModules, 0, "a warm check checks nothing")
    testAssert.equal(warm.generatedModules, 0, "a warm check does not generate module artifacts")
    testAssert.equal(warm.reusedModules, 2, "a warm check reuses the closure")

    -- A body edit stops at the unchanged interface, exactly as a build does.
    write(dir .. "/src/lib.nupp", libV1:gsub("return 1", "return 2"))
    local bodyEdit = {}
    testAssert.equal(project.check(dir, {stats = bodyEdit, diagnostics = {}}), 0)
    testAssert.equal(bodyEdit.checkedModules, 1, "a body edit checks only the changed module")
    testAssert.equal(bodyEdit.reusedModules, 1, "and reuses the dependent behind the unchanged interface")

    -- Breaking the interface has to reach the dependent even though the
    -- dependent's own bytes did not move.
    write(
        dir .. "/src/lib.nupp",
        table.concat({"local function answer(): string", "   return 'one'", "end", "return { answer = answer }",}, "\n")
    )
    local broken = {}
    assert(project.check(dir, {stats = broken, diagnostics = {}}) ~= 0, "a broken interface fails the check")
    testAssert.equal(broken.checkedModules, 2, "the dependent is rechecked against the changed interface")

    -- The error is still an error on the next run, when the whole project is
    -- unchanged and every module is a candidate for reuse. This is the
    -- failure the whole design has to not have.
    local again = {}
    local diags = {}
    assert(
        project.check(dir, {
            stats = again,
            diagnostics = diags
        }) ~= 0,
        "a failing check still fails when nothing has changed since"
    )
    local errors = 0
    for _, d in ipairs(diags) do
        if d.severity == "error" then
            errors = errors + 1
        end
    end
    assert(errors > 0, "and still says what is wrong, from the record")
    testAssert.equal(again.checkedModules, 0, "without checking anything again")

    remove(dir)
end

-- A call guarantee is body-derived: gaining or losing one moves no interface, so
-- nothing an interface hash covers can reach a reader that observed it. The build
-- records the guarantee as a project dependency of the reader instead, and a warm
-- run has to confirm that record without re-checking the module it names -- asking
-- the query is a full check of that module, which is what made a no-op check of
-- this repository spend twelve seconds in cache validation.
--
-- Confirming it late, against a provider that is itself still being reused, is only
-- sound if a provider that is *not* still reused reaches its readers. Both
-- directions are here, because only one of them fails loudly: a stale refusal is
-- noticed, and a stale acceptance is a wrong answer nobody sees.
function M.warmChecksSeeABodyOnlyGuaranteeChange()
    local allocating = table.concat({"local M = {}", "function M.work(): nil local t = {} end", "return M",}, "\n")
    local quiet = table.concat({"local M = {}", "function M.work(): nil local n = 1 end", "return M",}, "\n")
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = table.concat({"local D = require('dep')", "@noalloc do D.work() end",}, "\n"),
        ["src/dep.nupp"] = allocating,
    })

    assert(project.check(dir, {stats = {}, diagnostics = {}}) ~= 0, "an allocating call is refused in a noalloc region")

    -- Unchanged, so every module is a candidate for reuse and the refusal has to
    -- come back out of the record rather than out of a recheck.
    local warm = {}
    assert(project.check(dir, {stats = warm, diagnostics = {}}) ~= 0, "and is still refused when nothing has changed")
    testAssert.equal(warm.checkedModules, 0, "without rechecking anything")

    -- The provider gains the guarantee. Its interface does not move, and the
    -- reader's own bytes do not move, so the recorded guarantee is the only thing
    -- that can carry the change across.
    write(dir .. "/src/dep.nupp", quiet)
    testAssert.equal(
        project.check(dir, {
            stats = {},
            diagnostics = {}
        }),
        0,
        "the reader accepts once the provider is quiet"
    )

    -- And back the other way, which is the direction that fails silently.
    write(dir .. "/src/dep.nupp", allocating)
    assert(project.check(dir, {stats = {}, diagnostics = {}}) ~= 0, "and refuses again once it allocates again")

    remove(dir)
end

-- A header `cheader` reads is as much the module's input as its source is, so the
-- record a later process reuses has to answer for it. Before it did, an edit to
-- only the header left check and build reusing what the old header said: a warm
-- run accepted a call a cold one refused, and the artifact kept the old cdef.
local function cheaderProject()
    return tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"m"}}}
]],
        [
            "src/m.nupp"
        ] = [[
module m
const C = cheader("probe.h")

export function run(): integer
    return C.probe_add(1, 2)
end
]],
        ["src/probe.h"] = "int probe_add(int a, int b);\n",
    })
end

-- Two include roots each providing `util`, with interfaces a consumer accepts
-- either way. The checker resolved the consumer's `require` through the project
-- index and the build compiled the other file, so both passed and the typed
-- `string` result was an integer at run time. Neither may pass now.
function M.twoRootsProvidingOneModuleAreRefused()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"lib", "src"}, build = {outDir = "out"}}
]],
        ["lib/util.nupp"] = "module util\n\nexport function v(): integer\n    return 42\nend\n",
        ["src/util.nupp"] = "module util\n\nexport function v(): string\n    return \"from-src\"\nend\n",
        ["src/b.nupp"] = [[
module b
const util = require("util")

export function run(): string
    return util.v()
end
]],
    })
    for _, checkOnly in ipairs({true, false}) do
        local diagnostics = {}
        local verb = checkOnly and "check" or "build"
        testAssert.equal(project.build(dir, {checkOnly = checkOnly, diagnostics = diagnostics}), 1, verb .. " refuses")
        local found = false
        for _, diagnostic in ipairs(diagnostics) do
            found = found or (diagnostic.msg or diagnostic.message or ""):find("more than one file", 1, true) ~= nil
        end
        assert(found, verb .. " says two files provide the module")
    end

    remove(dir)
end

function M.aHeaderEditRechecksTheModuleThatReadsIt()
    local dir = cheaderProject()
    testAssert.equal(project.build(dir, {checkOnly = true, stats = {}}), 0, "the header's signature fits the call")
    local warm = {}
    testAssert.equal(project.build(dir, {checkOnly = true, stats = warm}), 0, "and a second check agrees")
    testAssert.equal(warm.checkedModules, 0, "an unchanged header leaves the record reusable")

    -- Renamed rather than re-signed: this process's FFI already holds the first
    -- `probe_add`, and LuaJIT keeps a C declaration once made, so only a cold
    -- process could see its parameters change.
    write(dir .. "/src/probe.h", "int probe_sum(int a, int b);\n")
    local diagnostics, edited = {}, {}
    testAssert.equal(
        project.build(dir, {
            checkOnly = true,
            stats = edited,
            diagnostics = diagnostics
        }),
        1,
        "a header that no longer declares the function refuses the call"
    )
    testAssert.equal(edited.checkedModules, 1, "the header edit rechecked its reader")
    assert(#diagnostics > 0, "and said why")

    write(dir .. "/src/probe.h", "int probe_add(int a, int b);\n")
    testAssert.equal(project.build(dir, {checkOnly = true, stats = {}}), 0, "restoring the header restores the answer")

    remove(dir)
end

function M.aHeaderEditRegeneratesTheModuleThatReadsIt()
    local dir = cheaderProject()
    testAssert.equal(project.build(dir, {stats = {}}), 0)
    local warm = {}
    testAssert.equal(project.build(dir, {stats = warm}), 0)
    testAssert.equal(warm.checkedModules, 0, "an unchanged header leaves the artifact reusable")

    write(dir .. "/src/probe.h", "int probe_add(int a, int b);\nint probe_sub(int a, int b);\n")
    local edited = {}
    testAssert.equal(project.build(dir, {stats = edited}), 0)
    testAssert.equal(edited.checkedModules, 1, "the header edit rebuilt its reader")

    remove(dir)
end

-- Linking a compiler-carried runtime needs its source closure before the checker sees
-- it. A prior module record already names that closure; rediscovering it through a
-- fresh query graph checks the module solely to confirm an otherwise usable cache
-- entry, which made the shared representation declarations dominate every warm command.
function M.warmRuntimeCheckUsesRecordedRuntimeDependencies()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = [[
local random = require("nupp.random")
local time = require("nupp.time")
return random, time
]],
    })

    local cold = {}
    testAssert.equal(project.check(dir, {produced = cold, diagnostics = {}}), 0)
    assert(cold.timing.compiledModules > 0, "the first check establishes the module records")

    local warm = {}
    testAssert.equal(project.check(dir, {produced = warm, diagnostics = {}}), 0)
    testAssert.equal(warm.timing.compiledModules, 0, "the unchanged runtime closure is reused")
    for _, span in ipairs(warm.timing.slowest) do
        assert(
            span.module ~= "nupp.mem.representation.spi",
            "a warm check must not recheck shared representation declarations"
        )
    end

    remove(dir)
end

-- Checking a named file is the project's own check started somewhere smaller,
-- so it has to reuse like one, answer like one, and cost the whole-project
-- check that follows it nothing.
function M.checkOfNamedFilesReusesAndReportsOnlyThem()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat({"local lib = require('lib')", "local value: number = lib.answer()", "return value",}, "\n"),
        [
            "src/lib.nupp"
        ] = table.concat(
            {"local function answer(): number", "   return 1", "end", "return { answer = answer }",},
            "\n"
        ),
        -- Nothing requires this one, and it is wrong.
        ["src/loose.nupp"] = table.concat({"local loose = {}", "local x: number = 'text'", "return loose",}, "\n"),
    })

    -- What the named file requires is checked, because the named file's answer
    -- depends on it. What nothing asked about is not.
    local cold = {}
    local coldDiags = {}
    testAssert.equal(
        project.check(dir, {
            paths = {dir .. "/src/main.nupp"},
            stats = cold,
            diagnostics = coldDiags
        }),
        0,
        "a named file that is well typed passes though the project is not"
    )
    testAssert.equal(cold.checkedModules, 2, "the named file and what it requires")
    testAssert.equal(#coldDiags, 0, "the loose module's error is not this question")

    local warm = {}
    testAssert.equal(project.check(dir, {paths = {dir .. "/src/main.nupp"}, stats = warm, diagnostics = {}}), 0)
    testAssert.equal(warm.checkedModules, 0, "a second narrow check checks nothing")
    testAssert.equal(warm.reusedModules, 2, "and reuses what the first one recorded")

    -- Naming the broken file is how you hear about it.
    local named = {}
    local namedDiags = {}
    assert(
        project.check(dir, {
            paths = {dir .. "/src/loose.nupp"},
            stats = named,
            diagnostics = namedDiags
        }) ~= 0,
        "naming the broken module fails"
    )
    local errors = 0
    for _, d in ipairs(namedDiags) do
        if d.severity == "error" then
            errors = errors + 1
        end
    end
    assert(errors > 0, "and says what is wrong with it")

    -- The narrow runs recorded what they checked and left the rest of the stored
    -- state alone, so the whole-project check that follows starts warm rather
    -- than from nothing.
    local whole = {}
    assert(
        project.check(dir, {
            stats = whole,
            diagnostics = {}
        }) ~= 0,
        "the project still has the loose module's error in it"
    )
    testAssert.equal(whole.checkedModules, 0, "and every module was already recorded by the narrow checks")
    testAssert.equal(whole.reusedModules, 3, "all three of them")

    remove(dir)
end

-- A path the project does not reach is not an error, it is a different
-- question: the caller gets it back to ask on its own terms.
function M.checkOfNamedFilesHandsBackWhatTheProjectDoesNotReach()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "return 1",
        ["src/surface.d.nupp"] = "declare function elsewhere(): integer\n",
    })

    local unchecked = {}
    testAssert.equal(
        project.check(dir, {
            paths = {dir .. "/src/main.nupp", dir .. "/src/surface.d.nupp"},
            unchecked = unchecked,
            diagnostics = {}
        }),
        0
    )
    testAssert.equal(#unchecked, 1, "the declaration file is not a module of the walk")
    testAssert.equal(unchecked[1], dir .. "/src/surface.d.nupp", "and it is named back")

    remove(dir)
end

function M.exportedComptimeTypeFunctionsInvalidateAndPersistSafely()
    local optional = table.concat(
        {
            "local M = {}",
            "@comptime local function AddNil(T: type): type",
            "   return nupp.types.optional(T)",
            "end",
            "@comptime function M.Maybe(T: type): type",
            "   return AddNil(T)",
            "end",
            "return M",
        },
        "\n"
    )
    local main = table.concat(
        {
            "local gen = require('gen')",
            "local direct: gen.Maybe(string) = nil",
            "local function choose<T>(value: T, fallback: gen.Maybe(T)): gen.Maybe(T)",
            "   return fallback",
            "end",
            "local answer: string? = choose('yes', nil)",
            "return answer, direct",
        },
        "\n"
    )
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        ["src/gen.nupp"] = optional,
        ["src/main.nupp"] = main,
    })

    testAssert.equal(
        project.check(dir, {
            stats = {},
            diagnostics = {}
        }),
        0,
        "a consumer executes closed and inferred exported type calls"
    )
    local cache = contentCacheDir(dir, "out") .. "/type-functions.buf"
    assert(exists(cache), "the type-function result store is persisted")

    -- Rechecking a changed consumer admits a validated persisted result. Damage is a
    -- miss, never a different type answer.
    write(dir .. "/src/main.nupp", main .. "\n-- force a consumer check\n")
    testAssert.equal(
        project.check(dir, {
            stats = {},
            diagnostics = {}
        }),
        0,
        "a fresh checker accepts persisted blueprints"
    )
    write(cache, "not a type-function store")
    write(dir .. "/src/main.nupp", main .. "\n-- force another consumer check\n")
    testAssert.equal(
        project.check(dir, {
            stats = {},
            diagnostics = {}
        }),
        0,
        "a damaged result store falls back to evaluation"
    )

    -- The sealed helper closure is part of the exported interface. Changing its
    -- behavior rechecks the unchanged consumer and changes the generated answer.
    write(dir .. "/src/gen.nupp", optional:gsub("return nupp.types.optional%(T%)", "return T"))
    local diagnostics = {}
    assert(
        project.check(dir, {
            stats = {},
            diagnostics = diagnostics
        }) ~= 0,
        "a semantic private-helper edit invalidates the consumer"
    )
    local sawArgumentFailure = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2006" then
            sawArgumentFailure = true
        end
    end
    assert(sawArgumentFailure, "the consumer observes the changed generated type")

    remove(dir)
end

-- A cache is only ever an optimization, so every way of damaging it has to
-- land on the same answer as not having one.
function M.checkSurvivesADamagedCache()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat({"local lib = require('lib')", "local value: string = lib.answer()", "return value",}, "\n"),
        [
            "src/lib.nupp"
        ] = table.concat(
            {"local function answer(): number", "   return 1", "end", "return { answer = answer }",},
            "\n"
        ),
    })

    local function answerOf()
        local diags = {}
        local code = project.check(dir, {stats = {}, diagnostics = diags})
        local parts = {tostring(code)}
        for _, d in ipairs(diags) do
            parts[#parts + 1] = ("%s@%d:%d %s"):format(tostring(d.code), d.line or 0, d.col or 0, tostring(d.msg))
        end

        return table.concat(parts, "\n")
    end

    local cold = answerOf()
    assert(cold:sub(1, 1) ~= "0", "the fixture is meant to have an error in it")
    testAssert.equal(answerOf(), cold, "a warm cache gives the cold answer")

    for _, damage in ipairs({"not a buffer at all", "", "\0\0\0\0"}) do
        write(contentCacheDir(dir, "out") .. "/headers.buf", damage)
        write(dir .. "/out/cache/checks.buf", damage)
        testAssert.equal(answerOf(), cold, "a damaged cache gives the cold answer")
    end

    -- Damage the store cannot see for itself: a value that decodes, under the
    -- right stamp, into something that is not a check state. A build validates
    -- the state it reads back, and a check crashed on these instead.
    local shapes = {
        "a string",
        {},
        {version = 5, modules = 5, dependencies = {}, outputs = {}, targets = {}},
        {version = 5, modules = {main = "a record"}, dependencies = {}, outputs = {}, targets = {}},
        {version = 5, modules = {}, dependencies = {}, outputs = {}, targets = {app = {1}}},
    }

    -- The stamp carries the module compiler, so it is read from the state the last
    -- check wrote rather than spelled here, with the codec the store writes it in.
    local function checkStamp()
        local file = assert(io.open(dir .. "/out/cache/checks.buf", "rb"))
        local codec = rawget(_G, "__nupp_plain_codec") or require("string.buffer")
        local envelope = codec.decode(file:read("*a"))
        file:close()

        return envelope.slots[1].stamp
    end

    for index, shape in ipairs(shapes) do
        local doctored = store.openValue(dir .. "/out/cache/checks.buf", checkStamp())
        doctored.set(shape)
        doctored.save()
        local ok, answer = pcall(answerOf)
        assert(ok, "wrongly shaped check state " .. index .. " crashed the check: " .. tostring(answer))
        testAssert.equal(answer, cold, "wrongly shaped check state " .. index .. " gives the cold answer")
    end

    remove(contentCacheDir(dir, "out"))
    remove(dir .. "/out/cache")
    testAssert.equal(answerOf(), cold, "no cache at all gives the cold answer")
    remove(dir)
end

function M.ownershipContractsInvalidateIncrementalInterfaces()
    local function library(mode)
        return table.concat(
            {"cdef function inspect(" .. mode .. " value: cstring)", "return { inspect = inspect }",},
            "\n"
        )
    end

    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
        ["src/lib.nupp"] = library("borrows"),
    })

    testAssert.equal(project.build(dir), 0)
    write(dir .. "/src/lib.nupp", library("takes"))
    local changed = {}
    testAssert.equal(project.build(dir, {stats = changed}), 0)
    testAssert.equal(changed.checkedModules, 2, "ownership-mode interface changes recheck dependents")
    remove(dir)
end

function M.namedCleanupsInvalidateIncrementalInterfaces()
    local function library(cleanup)
        return table.concat(
            {
                "cdef function create_c(): voidptr",
                "cdef function first_cleanup(takes value: voidptr)",
                "cdef function second_cleanup(takes value: voidptr)",
                "local function create(): affine(voidptr, " .. cleanup .. ")",
                "   return create_c()",
                "end",
                "return { create = create }",
            },
            "\n"
        )
    end

    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
        ["src/lib.nupp"] = library("first_cleanup"),
    })

    testAssert.equal(project.build(dir), 0)
    write(dir .. "/src/lib.nupp", library("second_cleanup"))
    local changed = {}
    testAssert.equal(project.build(dir, {stats = changed}), 0)
    testAssert.equal(changed.checkedModules, 2, "a changed cleanup rechecks dependents")
    remove(dir)
end

function M.cDependencyBuildsSharedLibraryAndBindings()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.equal(project.build(dir), 0)
    assert(exists(dir .. "/out/lib/" .. libraryName("tiny")), "C shared library emitted")
    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(binding:find("module tiny", 1, true), "C binding is a declared module")
    assert(binding:find("export = {", 1, true), "C binding exports its collected declarations")
    assert(binding:find("cdef function tiny_add", 1, true), "typed binding generated")
    write(dir .. "/native/tiny.h", table.concat({"int tiny_add(int a, int b);", "int tiny_sub(int a, int b);",}, "\n"))
    write(
        dir .. "/native/tiny.c",
        table.concat(
            {"int tiny_add(int a, int b) { return a + b; }", "int tiny_sub(int a, int b) { return a - b; }",},
            "\n"
        )
    )
    testAssert.equal(project.build(dir), 0, "changed native input rebuilds")
    assert(
        read(dir .. "/out/generated/tiny.nupp"):find("cdef function tiny_sub", 1, true),
        "header change reimports bindings"
    )
    remove(dir)
end

function M.cDependencyBuildsStaticArchive()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", linkage = "static", sources = {"native/tiny.c"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
        [
            "native/main.c"
        ] = table.concat(
            {"int tiny_add(int a, int b);", "int main(void) { return tiny_add(2, 3) == 5 ? 0 : 1; }",},
            "\n"
        ),
    })
    testAssert.equal(project.build(dir), 0)
    local archive = dir .. "/out/lib/" .. staticLibraryName("tiny")
    assert(exists(archive), "C static archive emitted")
    assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")), "a static dependency does not emit a shared library")

    local executable = dir .. "/native/static-consumer" .. (hostSystem == "windows" and ".exe" or "")
    testAssert.equal(
        process.run({
            "cc",
            dir .. "/native/main.c",
            archive,
            "-o",
            executable
        }),
        0,
        "the emitted archive links into a C executable"
    )
    testAssert.equal(process.run({executable}), 0, "the linked archive supplies its symbols")
    remove(dir)
end

function M.cDependencyBuildsSharedAndStaticArtifactsTogether()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", linkage = "both", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.equal(project.build(dir), 0)
    local shared = dir .. "/out/lib/" .. libraryName("tiny")
    local archive = dir .. "/out/lib/" .. staticLibraryName("tiny")
    assert(exists(shared), "both linkage emits the shared library")
    assert(exists(archive), "both linkage emits the static archive")
    testAssert.equal(answerFrom(dir), "5", "the generated binding loads the shared artifact")

    os.remove(archive)
    testAssert.equal(project.build(dir), 0, "a missing static half is rebuilt")
    assert(exists(archive), "the rebuilt dependency restores its static archive")
    remove(dir)
end

function M.cDependencyUsesTargetIndexedPrebuiltStaticArtifact()
    local producer = tempProject({
        [
            "nupp.lua"
        ] = [[return {dependencies = {tiny = {kind = "c", linkage = "static",
         sources = {"tiny.c"}}}, build = {entries = {"main"}, dependencies = {"tiny"}}}]],
        ["main.nupp"] = "return true\n",
        ["tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.equal(project.build(producer), 0)
    local archive = producer .. "/build/lib/" .. staticLibraryName("tiny")
    local bytes = read(archive)
    local host = assert(require("nupp.compiler.targetlayout").hostKey())
    local consumer = tempProject({
        [
            "nupp.lua"
        ] = (
            [=[
return {
   include = {"src"},
   dependencies = {tiny = {kind = "c", linkage = "static",
      bindings = {header = "native/tiny.h"}, artifacts = {
         [%q] = {static = {path = %q, sha256 = %q, size = %d}},
      }}},
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]=]
        ):format(host, archive, hash.sha256(bytes), #bytes),
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
    })
    testAssert.equal(project.build(consumer), 0, "a verified prebuilt artifact is selected for this target")
    testAssert.equal(
        read(consumer .. "/out/lib/" .. staticLibraryName("tiny")),
        bytes,
        "the selected target artifact is staged byte-for-byte"
    )
    write(archive, ("x"):rep(#bytes))
    testAssert.equal(project.build(consumer), 1, "a digest-valid manifest refuses changed prebuilt bytes")
    remove(consumer)
    remove(producer)
end

function M.binaryFixpointReadsThePlatformNamedHostOutput()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {targets = {dist = {
   kind = "binary", stub = "nupp", output = "out/app", entries = {"main"},
}}}, selfHost = {binary = "dist"}}]],
        ["src/main.nupp"] = "return 1\n",
    })
    local output = dir .. "/out/app.exe"
    local oldBuild, oldRun, oldHostKey = project.build, process.run, buildPlatform.hostKey
    project.build = function(_, opts)
        write(output, "same stamped bytes")
        opts.produced.artifact = output
        return 0
    end
    process.run = function(argv)
        testAssert.equal(argv[1], output .. ".stage1", "fixpoint executes the platform-named stage")
        write(output, "same stamped bytes")
        return 0
    end
    buildPlatform.hostKey = function()
        return "x86_64-pc-windows-msvc"
    end
    local ok, status = pcall(project.binaryFixpoint, dir, {result = {}})
    project.build, process.run, buildPlatform.hostKey = oldBuild, oldRun, oldHostKey
    remove(dir)
    assert(ok, status)
    testAssert.equal(status, 0, "the Windows executable suffix is shared with the build")
end

function M.cDependencyLinksAStaticClosureIntoItsSharedLibrary()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      base = {kind = "c", linkage = "static", sources = {"native/base.c"}},
      core = {kind = "c", linkage = "static", dependencies = {"base"},
         sources = {"native/core.c"}},
      tiny = {kind = "c", dependencies = {"core"}, sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/base.c"] = "int base_add(int a, int b) { return a + b; }\n",
        [
            "native/core.c"
        ] = table.concat(
            {"int base_add(int a, int b);", "int core_add(int a, int b) { return base_add(a, b); }",},
            "\n"
        ),
        [
            "native/tiny.c"
        ] = table.concat(
            {"int core_add(int a, int b);", "int tiny_add(int a, int b) { return core_add(a, b); }",},
            "\n"
        ),
    })
    testAssert.equal(project.build(dir), 0)
    testAssert.equal(answerFrom(dir), "5", "the shared parent contains its transitive static implementation")
    remove(dir)
end

-- A project whose entry actually calls through the binding, so what is being
-- tested is a load rather than the spelling of a string.
local function callingProject()
    return tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
end

-- A C dependency's library is the other thing a build produces and ships, and
-- it used to be named by the path the build wrote: absolute, which runs on one
-- machine, or relative to where the build ran, which runs from one directory.
-- It is now marked the way `@aot` code has always marked its library.
function M.cDependencyNamesItsLibraryRelativeToTheModuleThatLoadsIt()
    local dir = callingProject()
    testAssert.equal(project.build(dir), 0)

    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(
        binding:find('from "@lib/' .. libraryName("tiny") .. '"', 1, true),
        "the binding names the library relative to the output tree: " .. binding
    )
    assert(not binding:find(dir, 1, true), "and the build directory does not appear in it: " .. binding)

    -- The ordinary case first: a project built and run where it was built has to
    -- go on loading, since this changes how every existing one names its library.
    testAssert.equal(answerFrom(dir), "5", "an ordinary C dependency loads where the build left it")
    remove(dir)
end

-- A library the build did not put in the output tree is not part of what
-- travels with it, so it keeps the name it was given. `load` names a library
-- for the platform loader to find, and marking that would send the runtime
-- looking for a file beside a module instead.
function M.aPreexistingLibraryKeepsTheNameItWasGiven()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", load = "m", bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.h"] = "double tiny_scale(double value);\n",
    })
    testAssert.equal(project.build(dir), 0)
    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(binding:find('from "m"', 1, true), "a platform library name is left exactly as it was: " .. binding)
    remove(dir)
end

function M.cDependencyBuildsHeaderOnlyBridges()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", cppflags = {"-DTINY_SCALE=3"}, bindings = {
         header = "native/tiny.h",
         bridge = true,
         macros = {
            TINY_CLAMP = {parameters = {"int32", "int32", "int32"},
               result = "int32"},
            TINY_IGNORE = {parameters = {"int32"}},
         },
      }},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat(
            {
                "local tiny = require('tiny')",
                "local tripled: int32 = tiny.tiny_triple(14)",
                "local clamped: int32 = tiny.TINY_CLAMP(20, 2, 8)",
                "tiny.TINY_IGNORE(clamped)",
                "return tripled",
            },
            "\n"
        ),
        [
            "native/tiny.h"
        ] = [[
#include <stdint.h>
#ifndef TINY_SCALE
#define TINY_SCALE 1
#endif
static inline int32_t tiny_triple(int32_t value) { return value * TINY_SCALE; }
#define TINY_CLAMP(value, low, high) \
   ((value) < (low) ? (low) : ((value) > (high) ? (high) : (value)))
#define TINY_IGNORE(value) ((void)(value))
]],
    })
    testAssert.equal(project.build(dir), 0)
    local library = dir .. "/out/lib/" .. libraryName("tiny")
    assert(exists(library), "header-only bridge shared library emitted")
    assert(exists(dir .. "/out/generated/tiny_bridge.c"), "deterministic bridge source emitted")
    local binding = read(dir .. "/out/generated/tiny.nupp")
    assert(binding:find("local tiny_triple = __nupp_bridge_", 1, true), "inline exported under its logical name")
    assert(binding:find("local TINY_CLAMP = __nupp_bridge_", 1, true), "macro exported under its logical name")
    assert(binding:find("local TINY_IGNORE = __nupp_bridge_", 1, true), "void macro exported under its logical name")

    local triple = binding:match("cdef function (__nupp_bridge_[%da-f]+)%(value: int32%)")
    assert(triple, "physical inline symbol recorded")
    local clamp = binding:match("cdef function (__nupp_bridge_[%da-f]+)%(arg0: int32, arg1: int32, arg2: int32%)")
    assert(clamp, "physical macro symbol recorded")
    testAssert.equal(answerFrom(dir), "42", "bridge compilation receives the dependency's preprocessor flags")
    remove(dir)
end

function M.cDependencyRejectsInvalidMacroBridgeRecipes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", bindings = {
         header = "native/tiny.h",
         macros = {
            TINY_ADD = {parameters = {"int32"}, result = "int32"},
         },
      }},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["native/tiny.h"] = "#define TINY_ADD(a, b) ((a) + (b))\n",
    })
    assert(project.build(dir) ~= 0, "a requested macro with the wrong arity must fail the dependency build")
    assert(not exists(dir .. "/out/generated/tiny.nupp"), "an invalid recipe is not installed as a partial binding")
    remove(dir)
end

function M.cargoDependencyBuildsCdylib()
    requireCargo()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny_rust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tiny_rust"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        [
            "native/Cargo.toml"
        ] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
        ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
    })
    testAssert.equal(project.build(dir), 0)
    assert(exists(dir .. "/out/lib/" .. libraryName("tiny_rust")), "Cargo cdylib copied into output")
    remove(dir)
end

function M.cargoCbindgenBindingsPreserveExplicitOwnership()
    requireCargo()
    local command, cbindgen
    if hostSystem == "windows" then
        command = "cbindgen.cmd"
        -- One redirect per line rather than one around a block: `cmd` ends a
        -- parenthesised block at the first unescaped `)`, and every line here has
        -- one, so the block closed inside the first declaration and the rest went
        -- to the console instead of the file. Leading redirects also keep the
        -- space before `>` out of what is written.
        cbindgen = [[
@echo off
if not "%1"=="--output" exit /b 2
> "%2" echo typedef struct TinyBox { int value; } TinyBox;
>> "%2" echo void tiny_destroy(TinyBox *value);
>> "%2" echo TinyBox *tiny_create(int value);
>> "%2" echo int tiny_drops(void);
]]
    else
        command = "./cbindgen"
        cbindgen = [[#!/bin/sh
if [ "$1" != "--output" ] || [ -z "$2" ]; then exit 2; fi
printf '%s\n' \
  'typedef struct TinyBox { int value; } TinyBox;' \
  'void tiny_destroy(TinyBox *value);' \
  'TinyBox *tiny_create(int value);' \
  'int tiny_drops(void);' > "$2"
]]
    end
    local manifest = (
        [[
return {
   include = {"src"},
   dependencies = {
      tinyrust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false,
         bindings = {
            cbindgen = true,
            command = %q,
            ownership = {
               returns = {tiny_create = "tiny_destroy"},
               takes = {tiny_destroy = {1}},
            },
         },
      },
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tinyrust"}},
}
]]
    ):format(command)
    local dir = tempProject({
        ["nupp.lua"] = manifest,
        [
            "src/main.nupp"
        ] = [[
local tiny = require("tinyrust")
do
   local _box = tiny.tiny_create(41)
end
return tiny.tiny_drops()
]],
        ["native/" .. command:gsub("^%./", "")] = cbindgen,
        [
            "native/Cargo.toml"
        ] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
        [
            "native/src/lib.rs"
        ] = [[
use std::sync::atomic::{AtomicI32, Ordering};

#[repr(C)]
pub struct TinyBox { value: i32 }

static DROPS: AtomicI32 = AtomicI32::new(0);

#[no_mangle]
pub extern "C" fn tiny_create(value: i32) -> Box<TinyBox> {
    Box::new(TinyBox { value })
}

#[no_mangle]
pub extern "C" fn tiny_destroy(value: *mut TinyBox) {
    if !value.is_null() {
        DROPS.fetch_add(1, Ordering::SeqCst);
        unsafe { drop(Box::from_raw(value)); }
    }
}

#[no_mangle]
pub extern "C" fn tiny_drops() -> i32 { DROPS.load(Ordering::SeqCst) }
]],
    })
    if hostSystem ~= "windows" then
        testAssert.equal(os.execute(("chmod +x %q"):format(dir .. "/native/cbindgen")), 0)
    end
    testAssert.equal(project.build(dir), 0)
    assert(exists(dir .. "/out/generated/tinyrust.h"), "the configured cbindgen command wrote its header")
    local binding = read(dir .. "/out/generated/tinyrust.nupp")
    assert(
        binding:find("cdef function tiny_destroy(takes ", 1, true),
        "the configured terminal consumes its pointer: " .. binding
    )
    assert(
        binding:find("affine(TinyBox*, tiny_destroy)", 1, true),
        "the configured constructor returns a non-null affine pointer: " .. binding
    )
    assert(
        binding:find('from "@lib/' .. libraryName("tiny_rust") .. '"', 1, true),
        "the cbindgen import names the copied cdylib relatively: " .. binding
    )
    testAssert.equal(answerFrom(dir), "1", "leaving the returned Box at scope end calls its Rust destructor once")
    remove(dir)
end

-- A crate's cdylib is copied into the same `lib/` a C dependency's library is
-- built into, so it travels with the build and is named the same way.
function M.cargoDependencyNamesItsLibraryRelativeToTheModuleThatLoadsIt()
    requireCargo()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      tinyrust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false,
         bindings = {header = "tiny_rust.h"}},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tinyrust"}},
}
]],
        ["src/main.nupp"] = "local tiny = require('tinyrust')\n" .. "return tiny.tiny_double(21)\n",
        ["native/tiny_rust.h"] = "int tiny_double(int value);\n",
        [
            "native/Cargo.toml"
        ] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
        ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
    })
    testAssert.equal(project.build(dir), 0)

    local binding = read(dir .. "/out/generated/tinyrust.nupp")
    assert(
        binding:find('from "@lib/' .. libraryName("tiny_rust") .. '"', 1, true),
        "the binding names the cdylib relative to the output tree: " .. binding
    )
    assert(not binding:find(dir, 1, true), "and the build directory does not appear in it: " .. binding)

    testAssert.equal(answerFrom(dir), "42", "a Cargo dependency loads where the build left it")
    remove(dir)
end

-- A rock that is already in the source tree, so what is proved here is the
-- provider rather than the network: `luarocks make` builds what is there.
local TINY_ROCKSPEC = [[
package = "tinyrock"
version = "1.0-1"
source = { url = "file://tinyrock.lua" }
description = { summary = "A rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = { type = "builtin", modules = { tinyrock = "tinyrock.lua" } }
]]

local function tinyRockFiles()
    return {
        ["vendor/tinyrock/tinyrock.lua"] = "return {answer = 42}\n",
        ["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC,
        ["src/main.nupp"] = "return true\n",
    }
end

function M.compileDependenciesOptInWithoutChangingOldTypeManifests()
    local legacyDir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {types = {kind = "types", format = "luacats",
 source = {git = "https://example.invalid/types", rev = string.rep("a", 40)}}},
 build = {entries = {"main"}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local legacy = assert(project.loadManifest(legacyDir))
    testAssert.equal(legacy.build.compileDependencies, nil, "omission preserves ambient type dependency compatibility")
    remove(legacyDir)

    local explicitDir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {types = {kind = "types", format = "luacats",
 source = {git = "https://example.invalid/types", rev = string.rep("a", 40)}}},
 build = {entries = {"main"}, compileDependencies = {}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local explicit = assert(project.loadManifest(explicitDir))
    testAssert.equal(
        #explicit.build.compileDependencies,
        0,
        "an explicit empty list opts out of ambient type dependencies"
    )
    remove(explicitDir)
end

function M.aFailingGeneratorReportsWhatItPrinted()
    local rockspec = [[
rockspec_format = "3.0"
package = "providerrock"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Generator fixture." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = { ["provider.codegen"] = "codegen.lua" },
   copy_directories = { "nupp" },
}
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      provider = {kind = "luarocks", path = "vendor/provider",
         rockspec = "vendor/provider/providerrock-1.0-1.rockspec"},
   },
   generators = {api = {using = "provider/codegen", inputs = {"model/*.txt"}}},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["model/value.txt"] = "answer\n",
        ["vendor/provider/providerrock-1.0-1.rockspec"] = rockspec,
        -- Leaves through the exit rather than the worker's own reply, so the
        -- only evidence is what it wrote before going.
        [
            "vendor/provider/codegen.lua"
        ] = [[
return function(request)
   io.stdout:write("codegen: model is on fire\n")
   io.stdout:flush()
   os.exit(3)
end
]],
        [
            "vendor/provider/nupp/capabilities.json"
        ] = [[
{"schema":2,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"}
]}
]],
    })
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local code = project.build(dir)
    io.stderr:close()
    io.stderr = originalStderr
    local reported = read(errorPath) or ""
    os.remove(errorPath)
    testAssert.equal(code, 1, "a generator that dies fails the build")
    assert(
        reported:find("codegen: model is on fire", 1, true),
        "the worker's captured output is reported: " .. reported
    )
    assert(reported:find("generator api failed: worker failed", 1, true), reported)
    assert(not exists(dir .. "/out/generated/api.nupp-staged"), "the staging directory is removed")
    remove(dir)
end

function M.shellEntryPointsRefuseBoundedOptions()
    local ok, err = pcall(process.run, {"true"}, {timeoutMs = 1000})
    assert(
        not ok and tostring(err):find("captureIsolated", 1, true),
        "run refuses a timeout it cannot honor: " .. tostring(err)
    )
    ok, err = pcall(process.capture, {"true"}, {memoryMb = 64})
    assert(
        not ok and tostring(err):find("captureIsolated", 1, true),
        "capture refuses a memory ceiling it cannot honor: " .. tostring(err)
    )
    testAssert.equal(process.run({"true"}, {cwd = "."}), 0, "cwd is still honored")
end

function M.startedSessionsRefusePoliciesTheyCannotService()
    for _, options in ipairs({
        {timeoutMs = 1000},
        {
            pump = function()
            end
        },
        {
            cancelled = function()
                return false
            end
        },
    }) do
        local ok, err = pcall(process.startIsolated, {"true"}, options)
        assert(
            not ok and tostring(err):find("session caller", 1, true),
            "a started session must not silently ignore its policy: " .. tostring(err)
        )
    end
end

function M.generatorDeclarationsAreClosedAndPlainData()
    local unknown = tempProject({
        ["nupp.lua"] = [[
return {generators = {api = {using = "missing/codegen"}},
 build = {entries = {"main"}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local _, unknownErr = project.loadManifest(unknown)
    assert(
        tostring(unknownErr):find("references unknown dependency missing", 1, true),
        "a generator must select a declared provider dependency: " .. tostring(unknownErr)
    )
    remove(unknown)

    local cyclic = tempProject({
        [
            "nupp.lua"
        ] = [[
local options = {}
options.self = options
return {
 dependencies = {provider = {kind = "luarocks", path = "provider"}},
 generators = {api = {using = "provider/codegen", options = options}},
 build = {entries = {"main"}},
}
]],
        ["main.nupp"] = "return true\n",
    })
    local _, cyclicErr = project.loadManifest(cyclic)
    assert(
        tostring(cyclicErr):find("must not contain cycles", 1, true),
        "generator options must be serializable plain data: " .. tostring(cyclicErr)
    )
    remove(cyclic)

    local compile = tempProject({
        ["nupp.lua"] = [[
return {build = {entries = {"main"}, compileDependencies = {"missing"}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local _, compileErr = project.loadManifest(compile)
    assert(
        tostring(compileErr):find("references unknown dependency missing", 1, true),
        "compile dependencies are checked by name: " .. tostring(compileErr)
    )
    remove(compile)
end

function M.docsDoNotInstallUnrunGeneratorTools()
    local dir = tempProject({})
    local config = {
        dependencies = {provider = {kind = "luarocks", path = "not-present"},},
        generators = {api = {using = "provider/codegen"},},
    }
    local built, err = deps.build(dir, "out", config, {}, {kind = "docs", dependencies = {}})
    assert(built, "a docs dependency pass ignores unrun generators: " .. tostring(err))
    testAssert.equal(next(built), nil, "no generator tool is installed for docs")
    remove(dir)
end

function M.canonicalPathsFollowLinksAndKeepMissingOnesObservable()
    local dir = tempProject({["real/file.txt"] = "x\n"})
    local real = fs.canonical(dir .. "/real/file.txt")
    assert(real:sub(1, 1) == "/" or real:match("^%a:/"), "a canonical path is absolute: " .. real)
    assert(read(real) == "x\n", "the canonical path names the same file")
    testAssert.equal(fs.canonical(dir .. "/real/../real/./file.txt"), real, "dot segments are resolved")
    local missing = fs.canonical(dir .. "/real/absent.txt")
    testAssert.equal(missing, fs.absolute(dir .. "/real/absent.txt"), "a missing path keeps its absolute spelling")
    if hostSystem ~= "windows" then
        testAssert.equal(process.run({"ln", "-s", "real", dir .. "/link"}), 0)
        testAssert.equal(fs.canonical(dir .. "/link/file.txt"), real, "a symbolic link is followed")
        local _, printed = process.capture({"realpath", dir .. "/link/file.txt"})
        testAssert.equal(real, (printed:gsub("%s+$", "")), "the answer agrees with realpath")
        testAssert.equal(
            fs.canonical(dir .. "/link/absent.txt"),
            fs.absolute(dir .. "/link/absent.txt"),
            "a missing path behind a link keeps its spelling"
        )
    end
    remove(dir)
end

function M.lexicalRootsRemainAbsolute()
    testAssert.equal(fs.normalize("/"), "/", "the POSIX root survives normalization")
    testAssert.equal(fs.join("ignored", "/"), "/", "a joined POSIX root replaces its left side")
    testAssert.equal(fs.absolute("/"), "/", "the POSIX root does not become the working directory")
    testAssert.equal(fs.dirname("/file"), "/", "a file directly under the POSIX root has the root as its parent")
    testAssert.equal(fs.normalize("C:\\"), "C:/", "a drive root survives normalization")
    testAssert.equal(fs.join("ignored", "C:/"), "C:/", "a joined drive root replaces its left side")
    testAssert.equal(fs.absolute("C:/"), "C:/", "a drive root remains absolute")
    testAssert.equal(fs.dirname("C:/file"), "C:/", "a file directly under a drive root has that root as its parent")
end

function M.fileWalksStopAtSymbolicLinkCycles()
    if hostSystem == "windows" then
        return
    end
    local dir = tempProject({["root/value.txt"] = "value\n"})
    testAssert.equal(process.run({"ln", "-s", ".", dir .. "/root/again"}), 0, "the cycle is created")
    local listed = fs.listFiles(dir .. "/root")
    testAssert.equal(#listed, 1, "a link to an ancestor is not walked again")
    testAssert.equal(listed[1], dir .. "/root/value.txt", "the ordinary file remains visible")
    remove(dir)
end

function M.stagedWritesKeepTheDestinationAfterStreamFailures()
    local loaded = package.loaded["nupp.compiler.fs"]
    local open = io.open
    local dir = tempProject({output = "old\n"})
    local failureAt = "write"
    local ok, failure = pcall(function()
        io.open = function(path, mode)
            if mode ~= "wb" then
                return open(path, mode)
            end
            local closes = 0
            local stream = {}
            function stream:write()
                if failureAt == "write" then
                    return nil, "simulated write failure"
                end

                return self
            end

            function stream:close()
                closes = closes + 1
                if failureAt == "close" and closes == 1 then
                    return nil, "simulated close failure"
                end

                return true
            end

            return stream
        end
        package.loaded["nupp.compiler.fs"] = nil
        local isolated = require("nupp.compiler.fs")
        local wrote, reason = isolated.writeFile(dir .. "/output", "new\n")
        testAssert.equal(wrote, nil, "a failed stream write is reported")
        testAssert.equal(reason, "simulated write failure", "the write failure is retained")
        testAssert.equal(read(dir .. "/output"), "old\n", "a failed stream write publishes nothing")

        failureAt = "close"
        wrote, reason = isolated.writeFile(dir .. "/output", "new\n")
        testAssert.equal(wrote, nil, "a failed stream close is reported")
        testAssert.equal(reason, "simulated close failure", "the close failure is retained")
        testAssert.equal(read(dir .. "/output"), "old\n", "a failed stream close publishes nothing")
    end)
    io.open = open
    package.loaded["nupp.compiler.fs"] = loaded
    remove(dir)
    if not ok then
        error(failure, 0)
    end
end

function M.testCommandBuildsThenRunsArgv()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
   test = {argv = {"sh", "test.sh"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["test.sh"] = "printf yes > test-ran\n",
    })
    testAssert.equal(project.test(dir), 0)
    testAssert.equal(read(dir .. "/test-ran"), "yes")
    assert(exists(dir .. "/out/.nupp-state.json"), "test builds first")
    remove(dir)
end

function M.testCommandDefaultsToBundledRunner()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {
      default = "app",
      targets = {app = {outDir = "out", entries = {"main"}}},
   },
   test = {build = "app"},
}
]],
        ["src/main.nupp"] = "return true\n",
    })
    local originalRun = process.run
    local ran
    process.run = function(argv, options)
        ran = {argv = argv, options = options}
        return 0
    end
    local ok, result = pcall(project.test, dir)
    process.run = originalRun
    assert(ok, result)
    testAssert.equal(result, 0)
    testAssert.equal(ran.argv[2], "test", "the default runner stays under the test command")
    testAssert.equal(ran.argv[3], "--internal-runner", "the default test command is Nupp's bundled runner")
    testAssert.equal(ran.options.cwd, dir, "the default runner starts in the project")
    assert(exists(dir .. "/out/.nupp-state.json"), "the default test command builds first")
    remove(dir)
end

-- Unlike test, a task only builds when it names a target -- most won't, since
-- most of what a task runs (a dev server, a release script) isn't "the code
-- under test" the way a test command's subject always is.
function M.namedTaskRunsItsArgvWithoutBuildingByDefault()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   tasks = {
      greet = {argv = {"sh", "greet.sh"}},
   },
}
]],
        ["greet.sh"] = "printf hi > task-ran\n",
    })
    testAssert.equal(project.runTask(dir, "greet"), 0)
    testAssert.equal(read(dir .. "/task-ran"), "hi")
    assert(not exists(dir .. "/build"), "a task with no build key builds nothing")
    remove(dir)
end

function M.namedTaskRunsFromItsConfiguredWorkingDirectory()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {entries = {"main"}},
   tasks = {
      greet = {cwd = "tools", argv = {"sh", "greet.sh"}},
   },
}
]],
        ["src/main.nupp"] = "return true\n",
        ["tools/greet.sh"] = "printf hi > task-ran\n",
    })
    testAssert.equal(project.runTask(dir, "greet"), 0)
    testAssert.equal(read(dir .. "/tools/task-ran"), "hi")
    assert(not exists(dir .. "/task-ran"), "the task does not run from the outer project root")

    local described = assert(project.describeTasks(dir, "greet"))
    testAssert.equal(described.cwd, "tools", "task discovery reports the configured working directory")
    remove(dir)
end

function M.taskWorkingDirectoryMustBeANonEmptyString()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   build = {entries = {"main"}},
   tasks = {greet = {cwd = "", argv = {"echo", "hi"}}},
}
]],
    })
    local config, err = project.loadManifest(dir)
    testAssert.equal(config, nil, "an empty task working directory rejects the manifest")
    assert(err and err:find("tasks.greet.cwd must be a non-empty string", 1, true), tostring(err))
    remove(dir)
end

function M.namedTaskBuildsFirstWhenItNamesATarget()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", default = "app",
      targets = {app = {entries = {"main"}}}},
   tasks = {
      greet = {build = "app", argv = {"sh", "greet.sh"}},
   },
}
]],
        ["src/main.nupp"] = "return true\n",
        ["greet.sh"] = "printf hi > task-ran\n",
    })
    testAssert.equal(project.runTask(dir, "greet"), 0)
    assert(exists(dir .. "/out/.nupp-state.json"), "a task naming a build target builds first")
    remove(dir)
end

function M.namedTaskAppendsTrailingArgsToItsArgv()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   tasks = {greet = {argv = {"sh", "greet.sh"}}},
}
]],
        ["greet.sh"] = [[
IFS=,
printf '%s' "$*" > task-args
]],
    })
    testAssert.equal(project.runTask(dir, "greet", {"a", "b"}), 0)
    testAssert.equal(read(dir .. "/task-args"), "a,b")
    remove(dir)
end

function M.unknownTaskNameFails()
    local dir = tempProject({["nupp.lua"] = [[
return {include = {"src"}, tasks = {greet = {argv = {"echo", "hi"}}}}
]],})
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local status = project.runTask(dir, "nonexistent")
    io.stderr:close()
    io.stderr = originalStderr
    os.remove(errorPath)
    testAssert.equal(status, 1, "an unconfigured task name fails rather than running nothing quietly")
    remove(dir)
end

function M.pkgConfigFlagsUseShellWordQuotingWithoutRunningAShell()
    local words = assert(buildSyntax.shellWords([[-I"include dir" '-DNAME=two words' plain\ flag "" ab"cd"'ef']]))
    testAssert.equal(
        table.concat(words, "\0"),
        table.concat({"-Iinclude dir", "-DNAME=two words", "plain flag", "", "abcdef"}, "\0")
    )
    testAssert.equal(#assert(buildSyntax.shellWords(" \t\n")), 0)
    local malformed = buildSyntax.shellWords([["unclosed]])
    testAssert.equal(malformed, nil)
end

function M.makeDepfilesPreserveEscapedPathsAndContinuations()
    local paths = assert(buildSyntax.depfile("nupp_header: one.h two\\ three.h \\\n four\\#five.h one.h # ignored\n"))
    testAssert.equal(table.concat(paths, "\0"), table.concat({"one.h", "two three.h", "four#five.h", "one.h"}, "\0"))
    testAssert.equal(buildSyntax.depfile("not a depfile"), nil)
end

function M.buildGlobsTreatDoubleStarAsZeroOrMoreDirectories()
    local component = buildSyntax.glob("src/*/file?.nupp")
    assert(component("src/one/file1.nupp"))
    assert(not component("src/one/two/file1.nupp"))
    assert(not component("src/one/file12.nupp"))
    local directories = buildSyntax.glob("src/**/file.nupp")
    assert(directories("src/file.nupp"))
    assert(directories("src/one/two/file.nupp"))
    assert(not directories("src/one/two/not-file.nupp"))

    local dir = tempProject({
        ["src/root.nupp"] = "return 1\n",
        ["src/nested/child.nupp"] = "return 2\n",
        ["src/nested/child.lua"] = "return 3\n",
    })
    local matches = deps.expandGlob(dir, "src/**/*.nupp")
    table.sort(matches)
    testAssert.equal(#matches, 2)
    testAssert.equal(matches[1], dir .. "/src/nested/child.nupp")
    testAssert.equal(matches[2], dir .. "/src/root.nupp")
    remove(dir)
end

function M.manifestValidatesReloadComponents()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = [[
return {build = {kind = "component", entries = {"main"}, exports = {"main.run"}, reload = true}}
]]
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    testAssert.equal(config.build.reload, true)
    remove(valid)

    local wrongKind = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "bundle", entries = {"main"}, reload = true}}
]]
    })
    config, err = project.loadManifest(wrongKind)
    testAssert.equal(config, nil, "only a component carries the slots a session patches")
    assert(err:find("reload is only valid for a component target", 1, true), err)
    remove(wrongKind)

    local optimized = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "component", entries = {"main"}, reload = true, optimize = 2}}
]]
    })
    config, err = project.loadManifest(optimized)
    testAssert.equal(config, nil, "watch generation is development generation")
    assert(err:find("reload builds at optimize = 0", 1, true), err)
    remove(optimized)

    local compiled = tempProject({
        ["nupp.lua"] = [[
return {build = {kind = "component", entries = {"main"}, reload = true, aot = "require"}}
]]
    })
    config, err = project.loadManifest(compiled)
    testAssert.equal(config, nil, "a patched Lua body is not a rebuilt kernel")
    assert(err:find("reload cannot be combined with aot", 1, true), err)
    remove(compiled)
end

return M
