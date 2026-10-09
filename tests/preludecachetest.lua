-- The cached prelude has to be the checked prelude.
--
-- Every command builds an environment, and building one used to mean checking the
-- three prelude sources. That is most of what a small
-- command costs, so the answer is kept -- and a kept answer that is not quite the
-- computed one is the worst kind of bug, because nothing reports it and every
-- later answer is built on it.
--
-- So the two are compared directly: an environment that was forbidden the cache
-- against one that used it, root by root.
local test = require("assert")
local envMod = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function project()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write('return {include = {"."}}\n')
    manifest:close()

    return dir
end

local function names(table_)
    local out = {}
    for name in pairs(table_ or {}) do
        out[#out + 1] = tostring(name)
    end
    table.sort(out)

    return table.concat(out, " ")
end

--- Every code the checker reports for one source in one environment.
local function codes(env, source)
    local parsed = parser.parse(source, "prelude-cache.g.nupp")
    test.equal(#parsed.errors, 0, "the sample parses")
    local out = {}
    for _, diagnostic in ipairs(check.check(parsed, "prelude-cache.g.nupp", env)) do
        out[#out + 1] = diagnostic.code
    end

    return table.concat(out, " ")
end

local SAMPLES = {
    -- Reaches the string library, which is a prelude root of its own.
    "local n = ('abc'):len()\nreturn n\n",
    -- Reaches a prelude interface by name.
    "local c: nupp.Closeable? = nil\nreturn c\n",
    -- And one the checker has to reject, so agreement is not agreement on silence.
    "local n: integer = 'not a number'\nreturn n\n",
}

-- The order here is the whole test.
--
-- Interning is process-wide: `intern` finds what an earlier environment put in
-- the arena and hands it back. So an environment built after a bootstrapped one
-- reuses that one's types whatever it was told to do, and comparing the two that
-- way round compares a thing with itself. The cached environment is built first,
-- and the bootstrapped one after it, so what the cache restored is what the
-- comparison is about.
--
-- This is also why a process that mixes the two is the case to distrust: see
-- `theSuiteThisCannotSpeakFor` below.
function M.aCachedPreludeAnswersLikeAFreshlyCheckedOne()
    local dir = project()
    -- Allowed the cache: the first fills it, the second reads it back.
    envMod.new(dir)
    local cached = envMod.new(dir)
    -- Forbidden it, so it checks the prelude from source.
    local fresh = envMod.new(dir, {cache = false})

    test.equal(cached.preludeRuntime, fresh.preludeRuntime, "the generated prelude runtime is the same source")
    test.equal(names(cached.globals), names(fresh.globals), "the same globals")
    test.equal(names(cached.globalTypes), names(fresh.globalTypes), "the same global types")
    test.equal(names(cached.globalTypeDefs), names(fresh.globalTypeDefs), "the same declaration sites")
    test.equal(
        names(cached.preludeComptimeFunctions),
        names(fresh.preludeComptimeFunctions),
        "the same comptime helpers"
    )
    test.equal(names(cached.annotations.byname), names(fresh.annotations.byname), "the same built-in annotations")
    assert(cached.stringLib ~= nil, "the string library survives")
    test.equal(names(cached.stringLib.fields), names(fresh.stringLib.fields), "with the same members")

    for _, source in ipairs(SAMPLES) do
        test.equal(codes(cached, source), codes(fresh, source), "the same diagnostics for:\n" .. source)
    end

    -- Two environments must not share the tables they are about to add
    -- declarations to, or one project's globals would appear in another's.
    assert(cached.globals ~= fresh.globals, "environments own their own globals")
    local second = envMod.new(dir)
    assert(second.globals ~= cached.globals, "two cached environments own their own globals")
    os.execute("rm -rf '" .. dir .. "'")
end

-- Trivia is the one part of the graph that is not plain data: it is an arena of
-- comments and whitespace, and it is where a prelude doc comment lives. Rebuilt
-- from its source and its records rather than dropped.
function M.theCachedPreludeKeepsItsTrivia()
    local dir = project()
    envMod.new(dir)
    local cached = envMod.new(dir)
    local fresh = envMod.new(dir, {cache = false})

    local function anyArena(env)
        local seen, pending = {}, {env.globalTypeDefs, env.globalTypes, env.globals}
        local at = 1
        while at <= #pending do
            local owner = pending[at]
            if type(owner) == "table" and not seen[owner] then
                seen[owner] = true
                if owner.trivia ~= nil then
                    return owner.trivia
                end
                for key, value in pairs(owner) do
                    if key ~= "trivia" then
                        pending[#pending + 1] = key
                        pending[#pending + 1] = value
                    end
                end
            end
            at = at + 1
        end

        return nil
    end

    local one, other = anyArena(fresh), anyArena(cached)
    assert(one ~= nil, "the checked prelude carries trivia to compare against")
    assert(other ~= nil, "the cached prelude carries trivia")
    test.equal(other.source, one.source, "the arena keeps the source it indexes")
    test.equal(other.count, one.count, "and every record in it")
    local kind, offset, length, line, col = other:record(1)
    local wantKind, wantOffset, wantLength, wantLine, wantCol = one:record(1)
    test.equal(kind, wantKind)
    test.equal(offset, wantOffset)
    test.equal(length, wantLength)
    test.equal(line, wantLine)
    test.equal(col, wantCol)
    os.execute("rm -rf '" .. dir .. "'")
end

-- The point of writing it down: the next command, in the next process.
function M.theNextCommandReadsWhatThisOneWrote()
    local dir = project()
    local sample = assert(io.open(dir .. "/sample.g.nupp", "wb"))
    sample:write("local n = ('abc'):len()\nreturn n\n")
    sample:close()

    local function run()
        local pipe = assert(io.popen(("cd '%s' && '%s/bin/nupp' check --json sample.g.nupp 2>&1"):format(dir, ROOT)))
        local out = pipe:read("*a")
        pipe:close()
        return out
    end

    local json = require("testjson")
    local first = json.decode(run())
    -- Wherever the stores live. A shard is handed NUPP_CACHE_DIR so every project
    -- it builds shares one warm store, and the prelude goes in beside the rest of
    -- them rather than under the project being checked.
    local storeDir = os.getenv("NUPP_CACHE_DIR") or (dir .. "/build/cache")
    local written = io.open(storeDir .. "/prelude.buf", "rb")
    assert(written, "the first command wrote the prelude down, in " .. storeDir)
    written:close()

    -- What is compared is the answer, not the bytes: a JSON object writes its
    -- members in whatever order it holds them, and that order is not the point.
    local second = json.decode(run())
    test.equal(second.ok, first.ok, "and the second answers the same")
    test.equal(#second.diagnostics, #first.diagnostics, "with the same diagnostics")
    test.equal(second.compat, first.compat, "under the same profile")
    os.execute("rm -rf '" .. dir .. "'")
end

-- Every environment declares its own nominals, stored prelude or not.
--
-- This is the invariant a stored prelude is easiest to break. Interning is
-- process-wide and a nominal's identity is not, so an environment handed the
-- first one's keys gets the first one's types -- which point at the first one's
-- nominals, while the rest of it points at its own copies. One environment with
-- two objects for one nominal type-checks differently: `ownershiptest` stopped
-- being able to see an owned value being dropped, sixty cases after the one that
-- caused it.
--
-- So only the first environment in a process may read a stored prelude. A second
-- one checks the prelude and declares nominals of its own, which is what this
-- watches for.
function M.everyEnvironmentDeclaresItsOwnNominals()
    local types = require("nupp.compiler.types")
    local dir = project()
    local first = types.identity().nominal
    envMod.new(dir)
    local afterOne = types.identity().nominal
    envMod.new(dir)
    local afterTwo = types.identity().nominal
    assert(afterOne > first, "an environment declares the prelude's nominals")
    assert(afterTwo > afterOne, "and a second environment declares its own rather than sharing them")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A stored prelude is true only of the type identity it was written from.
--
-- An arena key spells a type by its parts' serials, and serials are issued per
-- process. So an image restored over an arena that already holds other types
-- under those serials gives two objects one id, and every key built from that id
-- afterwards finds whichever the arena met first. The test runner's process lanes
-- made exactly that arena: after each suite they unload the modules it loaded,
-- which takes `nupp.compiler.project.env` and keeps `nupp.compiler.types`, so the
-- next suite's first environment read the stored prelude over the last suite's
-- checked one. `nupp.peg.compile` then answered a `Peg<...any>` that was not the
-- `Peg<...any>` it was annotated with, and `examplestest` failed on whichever
-- machine put the two suites in one lane.
function M.aStoredPreludeIsNotRestoredOverAnotherIdentity()
    local saved = {}
    for name, value in pairs(package.loaded) do
        saved[name] = value
    end

    -- What a lane does between suites: every compiler module is loaded afresh,
    -- except the one that owns type identity.
    local function unloadAllButTypes()
        for name in pairs(package.loaded) do
            if type(name) == "string" and name:match("^nupp%.") and name ~= "nupp.compiler.types" then
                package.loaded[name] = nil
            end
        end
    end

    local function restore()
        for name in pairs(package.loaded) do
            if saved[name] == nil then
                package.loaded[name] = nil
            end
        end
        for name, value in pairs(saved) do
            package.loaded[name] = value
        end
    end

    local dir = project()
    local store = dir .. "/store"
    local ok, problem = pcall(function()
        -- The first writes the image, the second is a first environment again and
        -- finds it.
        unloadAllButTypes()
        require("nupp.compiler.project.env").new(dir, {cacheDir = store})
        unloadAllButTypes()
        local env = require("nupp.compiler.project.env").new(dir, {cacheDir = store})

        local types = require("nupp.compiler.types")
        local byId, shared = {}, {}
        for bucket, entries in pairs(types.identity().arenas) do
            for key, value in pairs(entries) do
                local id = type(value) == "table" and value.id or nil
                if id ~= nil and byId[id] ~= nil and byId[id] ~= value then
                    shared[#shared + 1] = bucket .. " " .. key .. " = " .. tostring(id)
                end
                if id ~= nil then
                    byId[id] = value
                end
            end
        end
        table.sort(shared)
        test.equal(
            #shared,
            0,
            "no two interned types share an id:\n  " .. table.concat(shared, "\n  ", 1, math.min(#shared, 10))
        )

        local source = "local function loadMatcher(configuration: string): nupp.peg.Peg<...any>\n"
            .. "    return nupp.peg.compile(configuration)\n"
            .. "end\n"
            .. "return loadMatcher\n"
        local parsed = require("nupp.compiler.syntax.parser").parse(source, "prelude-identity.nupp")
        local found = {}
        for _, diagnostic in ipairs(require("nupp.compiler.check").check(parsed, "prelude-identity.nupp", env)) do
            found[#found + 1] = tostring(diagnostic.code) .. " " .. tostring(diagnostic.msg)
        end
        test.equal(table.concat(found, "\n"), "", "a nominal the prelude declares is one type")
    end)
    restore()
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, problem)
end

-- The same, the other way round and across processes: an image written by a
-- process that had interned types of its own before the prelude, read by one
-- that had not. The reader's serials for its own first types are the writer's
-- for something else, and the image arrives carrying both.
function M.aStoredPreludeFromAnotherIdentityIsNotRestored()
    local dir = project()
    local store = dir .. "/store"
    local script = dir .. "/identity.lua"
    local file = assert(io.open(script, "wb"))
    file:write(
        [[
local project, store, extra = arg[1], arg[2], tonumber(arg[3])
local types = require("nupp.compiler.types")
for index = 1, extra do
    types.union({types.literal("before the prelude " .. index), types.string})
end
require("nupp.compiler.project.env").new(project, {cacheDir = store})
local byId, shared = {}, 0
for _, entries in pairs(types.identity().arenas) do
    for _, value in pairs(entries) do
        local id = type(value) == "table" and value.id or nil
        if id ~= nil and byId[id] ~= nil and byId[id] ~= value then
            shared = shared + 1
        end
        if id ~= nil then
            byId[id] = value
        end
    end
end
print("shared ids: " .. shared)
]]
    )
    file:close()

    local function run(extra)
        local pipe = assert(
            io.popen(
                (
                    "NUPP_COMPILER_ROOT='%s' LUA_PATH='%s' luajit '%s' '%s' '%s' %d 2>&1"
                ):format(ROOT, package.path, script, dir, store, extra)
            )
        )
        local out = pipe:read("*a")
        pipe:close()

        return out
    end

    local written = run(5)
    test.equal(written:match("shared ids: %d+"), "shared ids: 0", "the writer's own arena is consistent:\n" .. written)
    local read = run(0)
    os.execute("rm -rf '" .. dir .. "'")
    test.equal(read:match("shared ids: %d+"), "shared ids: 0", "no two interned types share an id:\n" .. read)
end

-- Exercise the image writer and reader together with values the real prelude
-- need not happen to contain, especially binary strings and IEEE negative zero.
local function imageFixture()
    local text = string.rep("dictionary\0\255", 30)
    local shared = {text = text, serial = 17}
    shared.self = shared
    setmetatable(shared, {description = "fixture metatable", owner = shared})

    return {
        annotationsByName = {},
        featureEffects = {},
        globalTypeDefs = {},
        globalTypes = {},
        preludeComptimeFunctions = {},
        stringLib = shared,
        preludeRuntime = text,
        globals = {
            left = shared,
            right = shared,
            byTable = {[shared] = shared},
            binary = text,
            empty = "",
            yes = true,
            no = false,
            zero = 0,
            negativeZero = -1 / math.huge,
            negative = -16385,
            boundary = 9007199254740991,
            negativeBoundary = -9007199254740991,
            fraction = 1.25,
            nan = 0 / 0,
            positiveInfinity = math.huge,
            negativeInfinity = -math.huge,
        },
    }, {arenas = {types = {["compact-fixture"] = shared}}, serial = 127, capability = 128, nominal = 16384}
end

local function writeImageFixture(roots, identity)
    local image = require("nupp.compiler.project.preludeimage")
    local types = require("nupp.compiler.types")
    local oldNew, oldIdentity = image.new, types.identity
    local bundle, output = os.tmpname(), os.tmpname()
    local file = assert(io.open(bundle, "wb"));
    file:write("return true\n");
    file:close()
    image.new = function()
        return roots
    end
    types.identity = function()
        return identity
    end
    local data
    local ok, why = pcall(function()
        assert(loadfile(ROOT .. "/editors/playground/tools/generate-prelude-image.lua"))(bundle, output, "image")
        local written = assert(io.open(output, "rb"))
        data = written:read("*a");
        written:close()
    end)
    image.new, types.identity = oldNew, oldIdentity
    os.remove(bundle);
    os.remove(output)
    assert(ok, why)

    return data
end

local function readImageFixture(data, operation)
    local image = require("nupp.compiler.project.preludeimage")
    local bundled = require("nupp.compiler.bundled")
    local original = bundled.source
    bundled.source = function(path)
        if path == "/preludeimage.bin" then
            return data
        end
        return original(path)
    end
    local ok, result = pcall(operation or image.new)
    bundled.source = original
    if not ok then
        error(result, 0)
    end

    return result
end

function M.portableImageKeepsBinaryNumericAndGraphIdentity()
    local roots, identity = imageFixture()
    local data = writeImageFixture(roots, identity)
    local types = require("nupp.compiler.types")
    local oldInterned, oldAdopt, oldResume = types.interned, types.adopt, types.resumeIdentity
    local adopted, resumed
    types.interned = function()
        return nil
    end
    types.adopt = function(bucket, key, value)
        test.equal(bucket, "types");
        test.equal(key, "compact-fixture")
        adopted = value
    end
    types.resumeIdentity = function(value)
        resumed = value
    end
    local ok, decoded = pcall(readImageFixture, data)
    types.interned, types.adopt, types.resumeIdentity = oldInterned, oldAdopt, oldResume
    assert(ok, decoded)
    local values = decoded.globals
    test.equal(values.binary, roots.globals.binary)
    test.equal(decoded.preludeRuntime, values.binary)
    test.equal(values.empty, "")
    assert(values.yes == true and values.no == false)
    assert(1 / values.zero == math.huge and 1 / values.negativeZero == -math.huge)
    test.equal(values.negative, -16385)
    test.equal(values.boundary, 9007199254740991)
    test.equal(values.negativeBoundary, -9007199254740991)
    test.equal(values.fraction, 1.25)
    assert(values.nan ~= values.nan and values.positiveInfinity == math.huge and values.negativeInfinity == -math.huge)
    assert(values.left == values.right and values.left == decoded.stringLib and values.left == adopted)
    assert(values.left.self == values.left and values.byTable[values.left] == values.left)
    assert(getmetatable(values.left).owner == values.left)
    test.equal(resumed.serial, identity.serial)
    test.equal(resumed.capability, identity.capability)
    test.equal(resumed.nominal, identity.nominal)
    local roundtripIdentity = {
        arenas = {types = {["compact-fixture"] = values.left}},
        serial = resumed.serial,
        capability = resumed.capability,
        nominal = resumed.nominal
    }
    test.equal(
        writeImageFixture(decoded, roundtripIdentity),
        data,
        "dictionary ordering and every graph value survive re-encoding"
    )
end

function M.portableImageDoesNotOverwriteAlreadyInternedTables()
    local roots, identity = imageFixture()
    local data = writeImageFixture(roots, identity)
    local types = require("nupp.compiler.types")
    local oldInterned, oldAdopt, oldResume = types.interned, types.adopt, types.resumeIdentity
    local liveMeta = {preserved = true}
    local live = setmetatable({preserved = true}, liveMeta)
    types.interned = function(bucket, key)
        if bucket == "types" and key == "compact-fixture" then
            return live
        end
    end
    types.adopt = function()
        error("existing intern must not be adopted again")
    end
    types.resumeIdentity = function()
    end
    local ok, decoded = pcall(readImageFixture, data)
    types.interned, types.adopt, types.resumeIdentity = oldInterned, oldAdopt, oldResume
    assert(ok, decoded)
    assert(decoded.globals.left == live and decoded.stringLib == live)
    assert(live.preserved and live.text == nil and live.self == nil)
    assert(getmetatable(live) == liveMeta)
end

function M.portableImageExcludesRuntimeWitnessCachesOnly()
    local roots, identity = imageFixture()
    local expected = writeImageFixture(roots, identity)
    require("nupp.compiler.runtime.reflect").install(_G.nupp)
    local reflect = assert(_G.nupp.__reflect)
    local owner = roots.globals.left
    owner[assert(reflect.targetsKey)] = {
        owner = owner,
        executable = function()
        end
    }
    owner[assert(reflect.infoKey)] = {
        owner = owner,
        executable = function()
        end
    }
    test.equal(writeImageFixture(roots, identity), expected)
    -- An unrelated anonymous key is still an invalid image. The exclusion is
    -- by the runtime's exact private keys, not by the shape of user data.
    owner[{}] = true
    assert(not pcall(writeImageFixture, roots, identity))
end

function M.portableImageRejectsMalformedCompactData()
    local magic = "NUPP-PRELUDE-3\n"
    -- No tables/dictionary/interns, followed by zero counters and eight nil roots.
    local empty = magic .. string.rep("\0", 6) .. string.rep("z", 8)
    readImageFixture(empty)
    local cases = {
        "NUPP-PRELUDE-2\n",
        magic .. "\128", -- truncated varint
        magic .. string.rep("\255", 8), -- overflowing varint
        magic .. "\0\1\4a", -- truncated dictionary string
        magic .. string.rep("\0", 6) .. "d\1" .. string.rep("z", 7),
        magic .. string.rep("\0", 6) .. "r\1" .. string.rep("z", 7),
        empty:sub(1, -2),
        empty .. "trailing",
    }
    for _, data in ipairs(cases) do
        local ok = pcall(readImageFixture, data)
        assert(not ok, "malformed compact prelude must be refused")
    end

    local invalidInterns = {
        {magic .. "\1\0\1\1s\7missings\1x", "unknown interned arena"},
        {magic .. "\2\0\2\1s\5typess\1x\2s\5typess\1x", "duplicate interned key"},
    }
    for _, case in ipairs(invalidInterns) do
        local ok, why = pcall(readImageFixture, case[1])
        assert(not ok and tostring(why):find(case[2], 1, true), tostring(why))
    end

    -- A complete graph followed by junk used to be adopted before the trailing
    -- bytes were noticed, poisoning the process even though loading failed.
    local internedThenTrailing = magic .. "\1\0\1\1s\5typess\1x" .. string.rep(
        "\0",
        5
    ) .. string.rep("z", 8) .. "trailing"
    local types = require("nupp.compiler.types")
    local oldInterned, oldAdopt, oldResume = types.interned, types.adopt, types.resumeIdentity
    local adopted, resumed = false, false
    types.interned = function()
        return nil
    end
    types.adopt = function()
        adopted = true
    end
    types.resumeIdentity = function()
        resumed = true
    end
    local ok = pcall(readImageFixture, internedThenTrailing)
    types.interned, types.adopt, types.resumeIdentity = oldInterned, oldAdopt, oldResume
    assert(not ok, "trailing compact prelude data must be refused")
    assert(not adopted and not resumed, "a refused compact prelude changed type identity")
end

-- Written from the arena as it stands, so the origin is not what refuses it.
local function emptyNativeImage()
    local cache = require("nupp.compiler.project.preludecache")
    local origin = cache.origin()
    assert(cache.seal(origin), "the arena has not moved since its origin was taken")
    return {
        format = 3,
        origin = origin,
        counts = {},
        cells = {},
        tags = {},
        externs = {},
        metas = {},
        metaExterns = {},
        arenas = {},
        triviaOf = {},
        internedAs = {},
        identity = {serial = 0, capability = 0, nominal = 0},
        roots = {0, 0, 0, 0, 0, 0, 0},
        runtime = "",
    }
end

function M.nativeCacheRejectsMalformedPlainData()
    local cache = require("nupp.compiler.project.preludecache")
    local valid = emptyNativeImage()
    assert(cache.decode(valid) ~= nil, "the empty fixture is a valid cache image")

    local cases = {
        function(image)
            image.externs = "not an array"
        end,
        function(image)
            image.counts = {0.5}
            image.cells = {true}
            image.tags = {0}
        end,
        function(image)
            image.counts = {1}
            image.cells = {"key", {}}
            image.tags = {0, 0}
            image.roots[1] = 1
        end,
        function(image)
            image.counts = {0}
            image.arenas = {{source = " ", records = {1, 1, 1, 1}}}
            image.triviaOf = {[1] = 1}
            image.roots[1] = 1
        end,
        function(image)
            image.counts = {0}
            image.metas = {[2] = 1}
        end,
        function(image)
            image.identity.serial = math.huge
        end,
        -- Written from an arena that had issued something this one has not.
        function(image)
            image.origin.serial = image.origin.serial + 1
        end,
        function(image)
            image.origin.digest = string.rep("0", #image.origin.digest)
        end,
        function(image)
            image.origin = nil
        end,
    }
    for index, damage in ipairs(cases) do
        local image = emptyNativeImage()
        damage(image)
        local ok, decoded = pcall(cache.decode, image)
        assert(ok, "malformed native image " .. index .. " raised: " .. tostring(decoded))
        test.equal(decoded, nil, "malformed native image " .. index .. " is a cache miss")
    end
end

function M.nativeCacheValidatesEveryRootBeforeAdoptingTypes()
    local cache = require("nupp.compiler.project.preludecache")
    local types = require("nupp.compiler.types")
    local image = emptyNativeImage()
    image.counts = {0}
    image.internedAs = {[1] = {"types", "late-invalid-root-fixture"}}
    image.roots = {1, 0, 0, 0, 0, 0}

    local oldInterned, oldAdopt, oldResume = types.interned, types.adopt, types.resumeIdentity
    local adopted, resumed = false, false
    types.interned = function()
        return nil
    end
    types.adopt = function()
        adopted = true
    end
    types.resumeIdentity = function()
        resumed = true
    end
    local ok, decoded = pcall(cache.decode, image)
    types.interned, types.adopt, types.resumeIdentity = oldInterned, oldAdopt, oldResume
    assert(ok, decoded)
    test.equal(decoded, nil, "an incomplete root list is refused")
    assert(not adopted and not resumed, "a refused native image changed type identity")
end

return M
