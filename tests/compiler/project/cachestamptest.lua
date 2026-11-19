-- What a stored answer is stamped with, and where it is stored.
--
-- Two facts hold the caches up, and neither shows itself in an answer: a stamp that
-- covers the code the entry came from and no more, and a key that is the same key for
-- callers asking the same question. Getting either wrong costs no correctness -- a miss
-- recomputes -- so nothing else in the suite notices, and the project quietly reparses
-- itself on every command. These are the tests that notice.
local cache = require("nupp.tools.build.cache")
local envMod = require("nupp.compiler.project.env")
local stable = require("nupp.compiler.stable")
-- The codec the store writes with: the VM's plain codec where the host has one.
local codec = require("helpers.plaincodec")

local HERE = require("helpers.paths").absoluteTests
local ROOT = assert(HERE:match("^(.*)/[^/]+$"), "tests directory has no parent")
local NUPP = ROOT .. "/bin/nupp"
local fingerprint = require("nupp.compiler.project.fingerprint")

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        local sub = name:match("^(.*)/[^/]+$")
        if sub then
            assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
        end
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(text)
        file:close()
    end

    return dir
end

local function exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end

    return false
end

local M = {}

function M.damagedBuildStateIsAnEmptyCacheRatherThanAnException()
    local dir = tempProject({})
    local path = dir .. "/state.json"
    for _, text in ipairs({
        [[{"version":6,"modules":"bad","dependencies":{},"outputs":{},"targets":{}}]],
        [[{"version":6,"modules":{"m":"bad"},"dependencies":{},"outputs":{},"targets":{}}]],
        [[{"version":6,"modules":{},"dependencies":{},"outputs":{},"targets":{"app":[null,"x"]}}]],
    }) do
        local file = assert(io.open(path, "wb"))
        file:write(text)
        file:close()
        local ok, state = pcall(cache.loadState, path)
        assert(ok, tostring(state))
        assert(next(state.modules) == nil and next(state.targets) == nil, "damaged state must be discarded")
    end
    os.execute("rm -rf '" .. dir .. "'")
end

function M.stableTextDoesNotDependOnCollidingKeyInsertionOrder()
    local numberFirst, stringFirst = {}, {}
    numberFirst[2], numberFirst["2"] = "number", "string"
    stringFirst["2"], stringFirst[2] = "string", "number"
    local expected = [[{"2"="string",2="number"}]]
    assert(stable(numberFirst) == expected, stable(numberFirst))
    assert(stable(stringFirst) == expected, stable(stringFirst))
end

-- Falling back is always allowed. It costs work and changes no answer, which is what
-- makes it the right thing to do about a question this cannot answer.
function M.anUnreadableSubsystemFallsBackToTheWholeCompiler()
    assert(
        fingerprint.subsystemFingerprint({
            "nupp.compiler.no.such.module"
        }) == fingerprint.graphFingerprint(),
        "an unknown module has to leave the stamp covering everything"
    )
end

-- Most single flipped bytes in an encoded store still decode, and a hit is never
-- rewritten. Unsealed, one damaged byte in `checks.buf` misquoted a diagnostic on every
-- run and one in `headers.buf` crashed every check, until the file was deleted by hand.
function M.aStoreWhoseBodyWasDamagedAnswersNothing()
    local store = require("nupp.compiler.project.store")
    local dir = tempProject({})
    local message = "cannot initialize wrong: string is not a integer"

    local function damage(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        local at = assert(text:find(message, 1, true), "the message is stored as written")
        local flipped = string.char(bit.bxor(text:byte(at + 7), 1))
        text = text:sub(1, at + 6) .. flipped .. text:sub(at + 8)
        -- The binary codec still decodes this, which is what the seal is for; the VM's
        -- plain codec checks its own payload and refuses it outright. Either way
        -- the store has to answer nothing.
        assert(text:sub(1, 8) == "NUPPSAV1" or pcall(codec.decode, text), "the damage still decodes")
        file = assert(io.open(path, "wb"))
        file:write(text)
        file:close()
    end

    local valuePath = dir .. "/value.buf"
    local value = store.openValue(valuePath, "stamp")
    value.set({msg = message})
    value.save()
    assert(store.openValue(valuePath, "stamp").value.msg == message, "an intact value is read back")
    damage(valuePath)
    assert(store.openValue(valuePath, "stamp").value == nil, "a damaged value was believed")

    local keyedPath = dir .. "/keyed.buf"
    local keyed = store.open(keyedPath, "stamp")
    keyed.put("key", {msg = message})
    keyed.save()
    assert(store.open(keyedPath, "stamp").get("key").msg == message, "an intact entry is read back")
    damage(keyedPath)
    assert(store.open(keyedPath, "stamp").get("key") == nil, "a damaged entry was believed")
    os.execute("rm -rf '" .. dir .. "'")
end

-- Two compilers used on one project -- `bin/nupp` and the binary it builds -- stamp
-- their caches differently. Each used to find the other's stamp, discard the file and
-- write its own, so alternating them rechecked the whole project every time. A file
-- now keeps a body for each of the last two stamps.
function M.twoCompilersKeepEachOthersEntries()
    local store = require("nupp.compiler.project.store")
    local dir = tempProject({})
    local path = dir .. "/checks.buf"

    local first = store.openValue(path, "tree")
    first.set({by = "tree"})
    first.save()
    local second = store.openValue(path, "bundle")
    assert(second.value == nil, "another compiler's body is not this one's")
    second.set({by = "bundle"})
    second.save()
    assert(store.openValue(path, "tree").value.by == "tree", "the first compiler's record was evicted")
    assert(store.openValue(path, "bundle").value.by == "bundle", "the second compiler's record was lost")

    local keyed = store.open(dir .. "/keyed.buf", "tree")
    keyed.put("key", "tree")
    keyed.save()
    local other = store.open(dir .. "/keyed.buf", "bundle")
    other.put("key", "bundle")
    other.save()
    assert(store.open(dir .. "/keyed.buf", "tree").get("key") == "tree", "a keyed store evicted too")

    local third = store.openValue(path, "stage0")
    third.set({by = "stage0"})
    third.save()
    assert(store.openValue(path, "tree").value == nil, "the file keeps two stamps, not every one")
    assert(store.openValue(path, "bundle").value.by == "bundle", "the newer of the others is kept")
    os.execute("rm -rf '" .. dir .. "'")
end

-- The codec refuses a value that reaches a function, and one such entry used to fail
-- the whole save: `type-functions.buf` was never written, so every command evaluated
-- every type function again. An entry that cannot be stored is left out instead.
function M.anEntryThatCannotBeStoredDoesNotCostTheOthers()
    local store = require("nupp.compiler.project.store")
    local dir = tempProject({})
    local path = dir .. "/keyed.buf"
    local keyed = store.open(path, "stamp")
    keyed.put("kept", {value = 1})
    keyed.put("refused", {
        value = function()
        end
    })
    keyed.put("also kept", "text")
    keyed.save()
    assert(keyed.stats.dropped == 1, "the refused entry is counted")
    local reopened = store.open(path, "stamp")
    assert(reopened.get("kept").value == 1, "an entry beside a refused one was lost")
    assert(reopened.get("also kept") == "text", "an entry after a refused one was lost")
    assert(reopened.get("refused") == nil, "a refused entry was stored")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A module is checked against the carried declarations as much as against the
-- checker, and they are not modules, so the subsystem stamp never reached them. An
-- edit to `lua.d.nupp` then left every module's stored diagnostics believed while a
-- fresh file checked clean, until `checks.buf` was deleted by hand.
function M.theModuleStampMovesWhenACarriedDeclarationChanges()
    local list = function()
        return {"/decls/lua.d.nupp", "/decls/prelude.d.nupp"}
    end

    local function reader(sort)
        return function(path)
            if path == "/decls/lua.d.nupp" then
                return "sort: " .. sort
            end
            return "prelude"
        end
    end

    local before, after = reader("function(a, b)"), reader("function(a: T, b: T)")
    local declared = fingerprint.declarationFingerprint(nil, list, before)
    assert(
        declared == fingerprint.declarationFingerprint(nil, list, before),
        "the same declarations have to stamp the same"
    )
    assert(
        declared ~= fingerprint.declarationFingerprint(nil, list, after),
        "an edited declaration left the declaration stamp where it was"
    )
    assert(
        cache.moduleCompilerFingerprint(
            nil,
            nil,
            list,
            before
        ) ~= cache.moduleCompilerFingerprint(nil, nil, list, after),
        "the module stamp does not reach the declarations"
    )
    assert(
        cache.moduleCompilerFingerprint(nil, nil, list, before) ~= fingerprint.subsystemFingerprint({
            "nupp.tools.build.modules"
        }),
        "the module stamp is the code alone"
    )
    assert(
        fingerprint.declarationFingerprint() ~= fingerprint.declarationFingerprint(nil, function()
            return {}
        end),
        "the compiler's own declarations were not read"
    )
end

-- A build adds its generated directory to the include roots and nothing else does.
-- Keyed on the roots, that made every header a build stored a header a check missed.
function M.twoEnvironmentsAgreeOnAHeaderKeyWhenTheModuleNameAgrees()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/m.nupp"] = "local m = {}\nreturn m\n",
    })
    local plain = envMod.new(dir)
    local building = envMod.new(dir, {config = {include = {"src", "build/generated"}}})
    local path = dir .. "/src/m.nupp"
    local text = "local m = {}\nreturn m\n"
    assert(
        envMod.headerKey(plain, path, text) == envMod.headerKey(building, path, text),
        "a root that changes no module name must not change the key"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- The prelude is the compiler's own source and is checked before the project has been
-- looked at. Answering its lookups from the project made every environment -- one per
-- case in the suites that check fragments -- read and index every file in the project.
function M.makingAnEnvironmentDoesNotReadTheProject()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/m.nupp"] = "local m = {}\nreturn m\n",
    })
    local env = envMod.new(dir)
    assert(env.projectIndex == nil, "the prelude bootstrap built the project index")
    assert(env.bootstrapping == nil, "the bootstrap flag outlived the bootstrap")
    local index = envMod.ensureProjectIndex(env)
    assert(env.projectIndex ~= nil and index == env.projectIndex, "and asking for it still builds it")
    os.execute("rm -rf '" .. dir .. "'")
end

-- Every environment in a process shares the headers it worked out, keyed by content:
-- a test that made one per case at the repository's root otherwise parsed every file
-- in it again each time. A file edited between two environments is a new key, so the
-- second one reads the edit, and an unchanged one is not parsed a second time.
function M.environmentsInOneProcessShareHeadersByContent()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/m.nupp"] = "export function before(): integer return 1 end\n",
        ["src/other.nupp"] = "export function unchanged(): integer return 2 end\n",
    })
    local parser = require("nupp.compiler.syntax.parser")
    local first = envMod.ensureProjectIndex(envMod.new(dir, {cache = false}))
    assert(first.byName.before and not first.byName.after, "the first index reads the file as it was")

    local file = assert(io.open(dir .. "/src/m.nupp", "wb"))
    file:write("export function after(): integer return 1 end\n")
    file:close()
    local env = envMod.new(dir, {cache = false})
    local original = parser.parse
    local parsed = {}
    parser.parse = function(text, path, ...)
        parsed[#parsed + 1] = path
        return original(text, path, ...)
    end
    local ok, second = pcall(envMod.ensureProjectIndex, env)
    parser.parse = original
    assert(ok, tostring(second))
    assert(second.byName.after and not second.byName.before, "the edit reached the next environment")
    assert(#parsed == 1 and parsed[1]:match("/src/m%.nupp$"), "only the edited file was parsed again")
    os.execute("rm -rf '" .. dir .. "'")
end

-- Environments that keep no stores check the prelude once per process and share it,
-- so they agree about what a prelude type is: each declared its own `io.File`, and a
-- type one of them handed another was not the receiver's `io.File`. Each still
-- declares into maps of its own.
function M.environmentsThatKeepNoStoresShareOnePrelude()
    local dir = tempProject({["nupp.lua"] = 'return { include = { "src" } }\n'})
    local first = envMod.new(dir, {cache = false})
    local second = envMod.new(dir, {cache = false})
    assert(first.globalTypes["io.File"] ~= nil, "the prelude declares no io.File")
    assert(
        second.globalTypes["io.File"] == first.globalTypes["io.File"],
        "two environments that keep no stores declare io.File apart"
    )
    assert(second.globalTypes ~= first.globalTypes, "two environments declare types into one map")
    assert(second.globals ~= first.globals, "two environments declare values into one map")
    assert(second.globals.types ~= first.globals.types, "two environments write one entry of the prelude's")
    os.execute("rm -rf '" .. dir .. "'")
end

-- Environments that keep no stores share the modules they check when everything a
-- check reads is the same: a suite making one per case otherwise checked every runtime
-- module its fixture required again in each. An edit to a project file is a new
-- family, so the module is checked again and answers with the edit.
function M.environmentsThatKeepNoStoresShareCheckedModules()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/dep.nupp"] = "module dep\n\nexport function value(): integer return 1 end\n",
    })
    local checkMod = require("nupp.compiler.check")
    local function resolve()
        local env = envMod.new(dir, {cache = false})
        local original = checkMod.check
        local checks = 0
        checkMod.check = function(parsed, path, ...)
            if tostring(path):match("/src/dep%.nupp$") then
                checks = checks + 1
            end
            return original(parsed, path, ...)
        end
        local ok, exports = pcall(envMod.resolveModuleExports, env, "dep")
        checkMod.check = original
        assert(ok, tostring(exports))
        return checks, exports
    end

    local firstChecks, first = resolve()
    assert(firstChecks == 1, "the first environment checks the module")
    local secondChecks, second = resolve()
    assert(secondChecks == 0, "the second environment checked it again")
    assert(second == first, "and shares the first one's answer")

    local file = assert(io.open(dir .. "/src/dep.nupp", "wb"))
    file:write("module dep\n\nexport function value(): string return 'one' end\n")
    file:close()
    local thirdChecks, third = resolve()
    assert(thirdChecks == 1 and third ~= first, "an edited module is checked again")
    assert(
        tostring(third.values.value) ~= tostring(first.values.value),
        "and answers with the edit: " .. tostring(third.values.value)
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- Counts the checks of each module in `names` while `run` uses an environment.
local function counting(names, run)
    local checkMod = require("nupp.compiler.check")
    local original = checkMod.check
    local counts = {}
    for _, name in ipairs(names) do
        counts[name] = 0
    end
    checkMod.check = function(parsed, path, ...)
        local name = tostring(path):match("/src/([%w_]+)%.nupp$")
        if name and counts[name] then
            counts[name] = counts[name] + 1
        end
        return original(parsed, path, ...)
    end
    local ok, answer = pcall(run)
    checkMod.check = original
    assert(ok, tostring(answer))

    return counts, answer
end

-- Whether `target` is reachable from `root` through tables' keys, values and
-- metatables.
local function reaches(root, target)
    local seen, pending = {}, {root}
    while #pending > 0 do
        local value = table.remove(pending)
        if value == target then
            return true
        end
        if type(value) == "table" and not seen[value] then
            seen[value] = true
            for key, item in next, value do
                pending[#pending + 1] = key
                pending[#pending + 1] = item
            end
            local meta = getmetatable(value)
            if type(meta) == "table" then
                pending[#pending + 1] = meta
            end
        end
    end

    return false
end

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()

    return text
end

-- A module one environment checked holds that environment's prelude types, and they
-- are the receiving environment's own. Before environments shared a prelude, a
-- cleanup declared against one environment's `io.File` did not apply to a value of
-- another's, and a warm VM emit wrote different bytes for it (vmemitcachetest's
-- prelude identity cases).
function M.aSharedModuleHoldsTheReceivingEnvironmentsPreludeTypes()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/handles.nupp"] = [[
module handles
local handles = {}
export type Handle = io.File
function handles.identity(value: io.File): io.File
    return value
end
export = handles
]],
    })
    local first = envMod.new(dir, {cache = false})
    local firstExports = assert(envMod.resolveModuleExports(first, "handles"))
    local second = envMod.new(dir, {cache = false})
    local counts, secondExports = counting({"handles"}, function()
        return assert(envMod.resolveModuleExports(second, "handles"))
    end)
    assert(counts.handles == 0, "the second environment checked the module again")
    assert(secondExports == firstExports, "the second environment does not share the first one's check")
    assert(
        reaches(secondExports.types.Handle, second.globalTypes["io.File"]),
        "the shared module's io.File is not the receiving environment's own"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- A shared check lends its interface, never its tree. Lowering rewrites the tree it
-- is given and a member asking for the module's check may lower it, so the member
-- checks the module itself; the record each member holds is its own to write.
function M.aSharedCheckLendsItsInterfaceButNotItsTree()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/dep.nupp"] = "module dep\n\nexport function value(): integer return 1 end\n",
    })
    local first = envMod.new(dir, {cache = false})
    assert(envMod.resolveModule(first, "dep"))
    local path = assert(envMod.findModulePath(first, "dep"))
    local key = require("nupp.compiler.fs").normalize(path)
    local owned = assert(first.loadedPaths[key])
    local tree = assert(owned.result and owned.result.root, "the checking environment keeps no tree")

    local second = envMod.new(dir, {cache = false})
    local counts = counting({"dep"}, function()
        assert(envMod.resolveModule(second, "dep"))
    end)
    assert(counts.dep == 0, "the second environment checked the module again")
    local lent = assert(second.loadedPaths[key])
    assert(lent ~= owned, "the receiving environment holds the first one's record")
    assert(lent.exports == owned.exports, "the receiving environment does not hold the shared interface")
    assert(lent.result == nil, "a lent record carries another environment's tree")

    local rechecked
    counts = counting({"dep"}, function()
        rechecked = envMod.checkModuleSource(second, path, readAll(path), {moduleName = "dep"})
    end)
    assert(counts.dep == 1, "asked for the module's check, the member did not check it")
    assert(rechecked.root ~= tree, "the member was handed another environment's tree")
    assert(first.loadedPaths[key] == owned and owned.result.root == tree, "the first record changed")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A check that read a cyclic dependency's interface before that dependency was
-- complete is one its own environment would make again, so no other shares it.
function M.aCheckThatReadAnIncompleteCycleIsNotShared()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/cyclea.nupp"] = [[
module cyclea
local b = require("cycleb")
export function value(): number return b.value() end
]],
        ["src/cycleb.nupp"] = [[
module cycleb
local a = require("cyclea")
export function value(): number return 1 end
export function again(): number return a.value() end
]],
    })
    local first = envMod.new(dir, {cache = false})
    assert(envMod.resolveModule(first, "cyclea"))
    local second = envMod.new(dir, {cache = false})
    local counts = counting({"cyclea", "cycleb"}, function()
        assert(envMod.resolveModule(second, "cycleb"))
    end)
    assert(counts.cycleb == 1, "a check that read an incomplete cycle was shared")
    assert(counts.cyclea == 0, "the cycle's complete module was not shared")
    os.execute("rm -rf '" .. dir .. "'")
end

-- What a family shares is the check alone. Nothing reachable from a shared module's
-- interface -- a comptime function it exports, a constant one computed -- is the
-- environment that checked it, or anything that environment keeps.
function M.aSharedInterfaceReachesNothingOfTheEnvironmentThatMadeIt()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/twice.nupp"] = [[
module twice
local twice = {}
@comptime function twice.of(n: integer): integer
    return n * 2
end
export = twice
]],
        ["src/user.nupp"] = [[
module user
local twice = require("twice")
const FOUR = twice.of(2)
export function value(): integer return FOUR end
]],
    })
    local first = envMod.new(dir, {cache = false})
    assert(envMod.resolveModule(first, "user"))
    local second = envMod.new(dir, {cache = false})
    local counts = counting({"twice", "user"}, function()
        assert(envMod.resolveModule(second, "user"))
        assert(envMod.resolveModule(second, "twice"))
    end)
    assert(counts.twice == 0 and counts.user == 0, "the second environment checked the modules again")
    for _, name in ipairs({"twice", "user"}) do
        local record = assert(second.loaded[name])
        local interface = {record.exports, record.type, record.compatDiagnostics, record.annotationDefinitions}
        for what, kept in pairs({
            environment = first,
            loaded = first.loaded,
            loadedPaths = first.loadedPaths,
            globals = first.globals,
            annotations = first.annotations,
        }) do
            assert(not reaches(interface, kept), name .. "'s shared interface reaches the first environment's " .. what)
        end
    end
    os.execute("rm -rf '" .. dir .. "'")
end

-- Content-keyed stores move; the build state does not.
function M.namedCacheDirectoryHoldsTheStoresThatAnswerAboutContent()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" }, build = { entries = { "m" } } }\n',
        ["src/m.nupp"] = "local m = {}\nreturn m\n",
    })
    local shared = tempProject({})
    local status = os.execute(("cd '%s' && NUPP_CACHE_DIR='%s' '%s' check > /dev/null 2>&1"):format(dir, shared, NUPP))
    assert(status == 0, "the check itself has to pass")
    assert(exists(shared .. "/headers.buf"), "headers were not stored where NUPP_CACHE_DIR named")
    assert(
        not exists(dir .. "/build/cache/headers.buf"),
        "headers were also stored in the project, which is the directory being replaced"
    )
    assert(
        exists(dir .. "/build/cache/checks.buf"),
        "the check state is keyed by module name and stays with the project"
    )
    os.execute("rm -rf '" .. dir .. "' '" .. shared .. "'")
end

-- Which compiler wrote a stored check result is asked once, of the state as a whole,
-- and a run asked about named files hands on the records it never visited. Those two
-- facts used to disagree: the carried records were the last compiler's while the state
-- they were written into was stamped with this one, so a narrow check run after the
-- checker changed left every module it had not visited marked as current. The next
-- whole-project check believed all of them and reported the previous checker's
-- messages, and deleting `checks.buf` by hand was the only way out.
--
-- `checks/1` is `CHECK_STATE_STAMP` in nupp.tools.build.project, where the store
-- is opened.
function M.aNarrowCheckDoesNotHandOnAnotherCompilersRecordsAsItsOwn()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/one.nupp"] = "local one = {}\nreturn one\n",
        ["src/two.nupp"] = "local two = {}\nreturn two\n",
    })

    local function check(what)
        local pipe = assert(io.popen(("cd '%s' && '%s' check %s 2>&1"):format(dir, NUPP, what or "")))
        local output = pipe:read("*a")
        local passed = pipe:close() and true or false
        return passed, output
    end

    local store = require("nupp.compiler.project.store")
    local path = dir .. "/build/cache/checks.buf"

    -- The stamp carries the module compiler that wrote the record, so it is read out
    -- of the file rather than spelled here: the newest body is this compiler's.
    local function stamp()
        local file = assert(io.open(path, "rb"))
        local envelope = codec.decode(file:read("*a"))
        file:close()
        return envelope.slots[1].stamp
    end

    local function stored()
        return store.openValue(path, stamp()).value
    end

    local passed, output = check()
    assert(passed, "the project itself has to check clean: " .. output)
    local state = assert(stored(), "the check wrote no state under the stamp this reads")
    assert(state.modules.one and state.modules.two, "both modules were recorded")

    -- The state another compiler would have left behind: its own records, under a stamp
    -- that is not this compiler's. `two` is given something to say that this compiler,
    -- checking the same source, never would.
    state.moduleCompilerHash = "written by a compiler that is not this one"
    state.modules.two.diags = {
        {
            code = "NUPP2129",
            severity = "error",
            msg = "a record the running compiler did not write",
            filename = "src/two.nupp",
            line = 1,
            col = 1,
            offset = 0,
            length = 5,
        }
    }
    local doctored = store.openValue(path, stamp())
    doctored.set(state)
    doctored.save()

    passed, output = check("src/one.nupp")
    assert(passed, "a narrow check of a clean file passes: " .. output)
    local narrowed = assert(stored(), "the narrow check wrote no state")
    assert(narrowed.modules.one, "the file it was asked about is recorded")
    assert(not narrowed.modules.two, "a record this compiler could not reuse was handed on as one it had written")

    passed, output = check()
    assert(
        not output:find("did not write", 1, true),
        "the whole-project check replayed the other compiler's record: " .. output
    )
    assert(passed, "and so a project that checks clean was reported failing: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
