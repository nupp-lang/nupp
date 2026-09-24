-- The cached prelude has to be the checked prelude.
--
-- Every command builds an environment, and building one used to mean checking the
-- three prelude declaration files from source. That is most of what a small
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
    test.equal(second.dialect, first.dialect, "for the same dialect")
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
        assert(
            loadfile(ROOT .. "/editors/playground/tools/generate-prelude-image.lua")
        )(bundle, output, "image", "luajit")
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
end

return M
