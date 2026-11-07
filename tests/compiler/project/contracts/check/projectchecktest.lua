local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local store = fixture.store
local write = fixture.write
local read = fixture.read
local tempProject = fixture.tempProject
local remove = fixture.remove
local answerFrom = fixture.answerFrom
local cheaderProject = fixture.cheaderProject

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.storeKeepsWhatItWasGivenAndForgetsNothingLive()
    local dir = "/tmp/nupp-store-test-" .. tostring(process.mkdirCommand and 1 or 1)
    os.execute("rm -rf '" .. dir .. "'")
    local path = dir .. "/s.buf"

    local first = store.open(path, "stamp-1")
    testAssert.eq(first.get("a"), nil, "an unopened store has nothing in it")
    first.put("a", {n = 1, list = {"x", "y"}})
    first.put("b", {n = 2})
    first.save()

    local second = store.open(path, "stamp-1")
    testAssert.eq(second.get("a").n, 1, "a value survives the round trip")
    testAssert.eq(second.get("a").list[2], "y", "including what is nested in it")
    testAssert.eq(second.get("b").n, 2)
    testAssert.eq(second.stats.hits, 3, "three hits, three lookups")

    -- A different stamp is a different compiler or a different project. There
    -- is no way to tell which of the entries it would have changed, so none of
    -- them are kept.
    local restamped = store.open(path, "stamp-2")
    testAssert.eq(restamped.get("a"), nil, "a restamped store starts empty")

    -- Every way the file can be wrong is a miss, never an error.
    for _, damage in ipairs({"", "garbage", "\0\1\2\3", ("x"):rep(5000)}) do
        write(path, damage)
        local damaged = store.open(path, "stamp-1")
        testAssert.eq(damaged.get("a"), nil, "a damaged store has nothing in it")
        damaged.put("a", {n = 9})
        damaged.save()
        testAssert.eq(store.open(path, "stamp-1").get("a").n, 9, "and is overwritten by the next run")
    end

    -- A store with nowhere to live still works; it just never hits.
    local nowhere = store.open(nil, "stamp-1")
    nowhere.put("a", {n = 1})
    nowhere.save()
    testAssert.eq(nowhere.get("a").n, 1, "within one run it still answers")
    testAssert.eq(store.open(nil, "stamp-1").get("a"), nil, "and never persists")

    -- The single-value store, under the same rules.
    local vpath = dir .. "/v.buf"
    local value = store.openValue(vpath, "stamp-1")
    testAssert.eq(value.value, nil)
    value.set({modules = {m = {sourceHash = "abc"}}})
    value.save()
    testAssert.eq(store.openValue(vpath, "stamp-1").value.modules.m.sourceHash, "abc")
    testAssert.eq(store.openValue(vpath, "stamp-2").value, nil, "a restamped value store is empty")
    write(vpath, "not a buffer")
    testAssert.eq(store.openValue(vpath, "stamp-1").value, nil, "a damaged value store is empty")

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
    testAssert.eq(project.check(dir, {stats = cold, diagnostics = {}}), 0)
    testAssert.eq(cold.checkedModules, 2, "a cold check checks the closure")
    testAssert.eq(cold.generatedModules, 0, "a check does not generate module artifacts")

    local warm = {}
    testAssert.eq(project.check(dir, {stats = warm, diagnostics = {}}), 0)
    testAssert.eq(warm.checkedModules, 0, "a warm check checks nothing")
    testAssert.eq(warm.generatedModules, 0, "a warm check does not generate module artifacts")
    testAssert.eq(warm.reusedModules, 2, "a warm check reuses the closure")

    -- A body edit stops at the unchanged interface, exactly as a build does.
    write(dir .. "/src/lib.nupp", libV1:gsub("return 1", "return 2"))
    local bodyEdit = {}
    testAssert.eq(project.check(dir, {stats = bodyEdit, diagnostics = {}}), 0)
    testAssert.eq(bodyEdit.checkedModules, 1, "a body edit checks only the changed module")
    testAssert.eq(bodyEdit.reusedModules, 1, "and reuses the dependent behind the unchanged interface")

    -- Breaking the interface has to reach the dependent even though the
    -- dependent's own bytes did not move.
    write(
        dir .. "/src/lib.nupp",
        table.concat({"local function answer(): string", "   return 'one'", "end", "return { answer = answer }",}, "\n")
    )
    local broken = {}
    assert(project.check(dir, {stats = broken, diagnostics = {}}) ~= 0, "a broken interface fails the check")
    testAssert.eq(broken.checkedModules, 2, "the dependent is rechecked against the changed interface")

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
    testAssert.eq(again.checkedModules, 0, "without checking anything again")

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
    testAssert.eq(warm.checkedModules, 0, "without rechecking anything")

    -- The provider gains the guarantee. Its interface does not move, and the
    -- reader's own bytes do not move, so the recorded guarantee is the only thing
    -- that can carry the change across.
    write(dir .. "/src/dep.nupp", quiet)
    testAssert.eq(
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
        testAssert.eq(project.build(dir, {checkOnly = checkOnly, diagnostics = diagnostics}), 1, verb .. " refuses")
        local found = false
        for _, diagnostic in ipairs(diagnostics) do
            found = found or (diagnostic.msg or diagnostic.message or ""):find("more than one file", 1, true) ~= nil
        end
        assert(found, verb .. " says two files provide the module")
    end

    remove(dir)
end

-- A const-specialized body is emitted with the function's declaration, so what a
-- declaring module's artifact holds depends on its callers' constant arguments as
-- well as on its own source. An edit to only a caller leaves the declaring
-- module's source hash where it was; its specialization hash is what says the
-- artifact is owed again, and a reuse that ignored it left the caller naming a
-- body its declaration never emitted.

function M.aHeaderEditRechecksTheModuleThatReadsIt()
    local dir = cheaderProject()
    testAssert.eq(project.build(dir, {checkOnly = true, stats = {}}), 0, "the header's signature fits the call")
    local warm = {}
    testAssert.eq(project.build(dir, {checkOnly = true, stats = warm}), 0, "and a second check agrees")
    testAssert.eq(warm.checkedModules, 0, "an unchanged header leaves the record reusable")

    -- Renamed rather than re-signed: this process's FFI already holds the first
    -- `probe_add`, and LuaJIT keeps a C declaration once made, so only a cold
    -- process could see its parameters change.
    write(dir .. "/src/probe.h", "int probe_sum(int a, int b);\n")
    local diagnostics, edited = {}, {}
    testAssert.eq(
        project.build(dir, {
            checkOnly = true,
            stats = edited,
            diagnostics = diagnostics
        }),
        1,
        "a header that no longer declares the function refuses the call"
    )
    testAssert.eq(edited.checkedModules, 1, "the header edit rechecked its reader")
    assert(#diagnostics > 0, "and said why")

    write(dir .. "/src/probe.h", "int probe_add(int a, int b);\n")
    testAssert.eq(project.build(dir, {checkOnly = true, stats = {}}), 0, "restoring the header restores the answer")

    remove(dir)
end

function M.aHeaderEditRegeneratesTheModuleThatReadsIt()
    local dir = cheaderProject()
    testAssert.eq(project.build(dir, {stats = {}}), 0)
    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "an unchanged header leaves the artifact reusable")

    write(dir .. "/src/probe.h", "int probe_add(int a, int b);\nint probe_sub(int a, int b);\n")
    local edited = {}
    testAssert.eq(project.build(dir, {stats = edited}), 0)
    testAssert.eq(edited.checkedModules, 1, "the header edit rebuilt its reader")

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
        ["src/main.nupp"] = [[
local random = math.Xoshiro128
local time = require("coroutine")
return random, time
]],
    })

    local cold = {}
    testAssert.eq(project.check(dir, {produced = cold, diagnostics = {}}), 0)
    assert(cold.timing.compiledModules > 0, "the first check establishes the module records")

    local warm = {}
    testAssert.eq(project.check(dir, {produced = warm, diagnostics = {}}), 0)
    testAssert.eq(warm.timing.compiledModules, 0, "the unchanged runtime closure is reused")
    for _, span in ipairs(warm.timing.slowest) do
        assert(
            span.module ~= "nupp.runtime.contracts",
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
    testAssert.eq(
        project.check(dir, {
            paths = {dir .. "/src/main.nupp"},
            stats = cold,
            diagnostics = coldDiags
        }),
        0,
        "a named file that is well typed passes though the project is not"
    )
    testAssert.eq(cold.checkedModules, 2, "the named file and what it requires")
    testAssert.eq(#coldDiags, 0, "the loose module's error is not this question")

    local warm = {}
    testAssert.eq(project.check(dir, {paths = {dir .. "/src/main.nupp"}, stats = warm, diagnostics = {}}), 0)
    testAssert.eq(warm.checkedModules, 0, "a second narrow check checks nothing")
    testAssert.eq(warm.reusedModules, 2, "and reuses what the first one recorded")

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
    testAssert.eq(whole.checkedModules, 0, "and every module was already recorded by the narrow checks")
    testAssert.eq(whole.reusedModules, 3, "all three of them")

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
    testAssert.eq(
        project.check(dir, {
            paths = {dir .. "/src/main.nupp", dir .. "/src/surface.d.nupp"},
            unchecked = unchecked,
            diagnostics = {}
        }),
        0
    )
    testAssert.eq(#unchecked, 1, "the declaration file is not a module of the walk")
    testAssert.eq(unchecked[1], dir .. "/src/surface.d.nupp", "and it is named back")

    remove(dir)
end

return M
