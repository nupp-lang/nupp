-- What a second ahead-of-time build is allowed to do.
--
-- The claims here are about process creation and about which files were
-- rewritten, so they are made against a real project built by the real binary
-- more than once. Nothing about them is visible from inside the compiler: a
-- build that recompiled every object and produced the same library would pass
-- every artifact assertion the rest of the suite makes.
--
-- Two things are asserted about every rebuild. The counts `build --json`
-- publishes -- how many objects were reused, how many were compiled, and how
-- many external processes the policy started, which for a code generator and
-- linker running in process is always none -- and the bytes of the object files
-- themselves, because a count is a claim the compiler makes about itself and
-- the bytes are not.
--
-- One project, built and rebuilt through a sequence of states, rather than one
-- project per assertion: each build costs a code generator run and the states
-- are consecutive by nature. The scenario names each transition as it makes it, so
-- a failure says which rebuild was wrong.

local test = require("assert")
local json = require("nupp.codec.json")
local process = require("nupp.compiler.process")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end

local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function read(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()

    return text
end

local function write(path, text)
    local handle = assert(io.open(path, "wb"), "cannot write " .. path)
    handle:write(text)
    handle:close()
end

local function kernel(index)
    return (
        [[
module k%d

local span = require("nupp.mem.span")

@aot
local function scale%d(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>, factor: number): nil
    if #out ~= #input then
        error("length mismatch", 2)
    end
    for i = 1, #out do
        out[i] = input[i] * factor + %d.0
    end
end

export = {scale = scale%d}
]]
    ):format(index, index, index, index)
end

local SOURCES = 3

local function project()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local entries = {}
    for index = 1, SOURCES do
        write(dir .. "/src/k" .. index .. ".nupp", kernel(index))
        entries[#entries + 1] = ('"k%d"'):format(index)
    end
    write(
        dir .. "/nupp.lua",
        (
            [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {%s}, outDir = "build/native", aot = "require",
   }}},
}
]]
        ):format(table.concat(entries, ", "))
    )

    return dir
end

-- Its own content cache, for the reason `aotbuildtest` gives: a shard-wide one
-- makes an artifact-reuse assertion depend on whichever unrelated project the
-- worker happened to build first.
--
-- `env` is prepended to the command, for a build under another code generator
-- selection.
local function build(dir, env)
    local cache = dir .. "/build/test-cache"
    local pipe = assert(
        io.popen(
            (
                "cd %q && %s NUPP_CACHE_DIR=%q NO_COLOR= '%s' build --target native --remarks-out --format json 2>/dev/null"
            ):format(dir, env or "", cache, NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local ok, report = pcall(json.decode, out)
    assert(ok and type(report) == "table", "no JSON report from the build:\n" .. out)
    assert(report.ok, "the build failed:\n" .. out)
    assert(type(report.timing) == "table" and type(report.timing.aot) == "table", "no aot timing facts:\n" .. out)

    return report
end

-- Every object the policy produced, by path, so a rebuild can be asked which
-- of them it left alone.
local function objects(dir)
    local found = {}
    local pipe = assert(io.popen(("find %q -name '*.o' 2>/dev/null"):format(dir .. "/build/native/aot")))
    for line in pipe:lines() do
        -- Git Bash's `find` spells a Windows drive as `/c/`, while LuaJIT's
        -- `io.open` passes paths to the Windows C runtime rather than MSYS.
        -- Use the native spelling as the comparison key too: the test later
        -- removes one of these paths and reads it again after the rebuild.
        local path = line
        if package.config:sub(1, 1) == "\\" then
            path = path:gsub("^/([A-Za-z])/", "%1:/")
        end
        -- A Windows library also links the compiler's own glue, built once
        -- beside the units; it is not a unit's object.
        if not path:match("/luabind%.[^/]*%.o$") then
            found[path] = assert(read(path), "unreadable object " .. path)
        end
    end
    pipe:close()

    return found
end

local function names(map)
    local list = {}
    for path in pairs(map) do
        list[#list + 1] = path
    end
    table.sort(list)

    return list
end

-- Which objects came from one source. On x86-64 that is one per feature tier,
-- because a multiversioned library carries the same body compiled several ways;
-- elsewhere it is one. Read off the file names rather than assumed, so the
-- assertion means the same thing on every architecture.
local function objectsOf(map, stem)
    local matched = {}
    for path in pairs(map) do
        if path:match("/" .. stem .. "%.[^/]*%.o$") then
            matched[path] = true
        end
    end

    return matched
end

local function changed(before, after)
    local moved = {}
    for path, bytes in pairs(after) do
        if before[path] ~= bytes then
            moved[path] = true
        end
    end

    return moved
end

local function count(set)
    local total = 0
    for _ in pairs(set) do
        total = total + 1
    end

    return total
end

--- One project through cold, unchanged, one-unit-edit and damaged-artifact
--- rebuilds, asserting what each was allowed to do.
function M.rebuildsOnlyWhatChanged()
    local dir = project()

    local cold = build(dir)
    local coldFacts = cold.timing.aot
    test.equal(coldFacts.reusedObjects, 0, "a cold build reuses nothing")
    test.equal(coldFacts.checkedSources, SOURCES, "a cold build checks every AOT source")
    assert(coldFacts.loweredPrograms >= SOURCES, "a cold build lowers every AOT program")
    test.equal(coldFacts.optimizedPrograms, coldFacts.loweredPrograms, "every lowered program is optimized")
    assert(coldFacts.emittedUnits >= SOURCES, "every AOT source emits at least one unit")
    assert(coldFacts.emittedUnits <= coldFacts.units, "compiler-owned units are counted separately")
    assert(coldFacts.compiledObjects >= SOURCES, "a cold build compiles every unit: " .. coldFacts.compiledObjects)
    test.equal(coldFacts.compiledObjects, coldFacts.units, "every emitted unit becomes an object")
    test.equal(coldFacts.linked, true, "a cold build links")
    -- LLVM compiles and lld links in process.
    test.equal(coldFacts.externalCommands, 0, "a cold build runs no external command")
    local remarks = json.decode(assert(read(dir .. "/build/remarks.json")))
    local aotNotes = 0
    for _, note in ipairs(remarks.remarks or {}) do
        if note.code == "AOT-LOOP" then
            aotNotes = aotNotes + 1
            assert(note.range.start.line > 1, "AOT notes use the authored loop position")
            local source = assert(read(dir .. "/" .. note.file))
            assert(
                source:sub(note.range.start.offset, note.range.start.offset + 2) == "for",
                "AOT note range starts at its loop"
            )
        end
    end
    test.equal(aotNotes, SOURCES, "each source contributes one AOT loop remark")
    local coldObjects = objects(dir)
    test.equal(#names(coldObjects), coldFacts.units, "one object file per unit")
    local library = assert(
        read(dir .. "/build/native/lib/libnative_aot.dylib")
        or read(dir .. "/build/native/lib/libnative_aot.so")
        or read(dir .. "/build/native/lib/native_aot.dll"),
        "no linked library"
    )

    -- Nothing changed, so nothing may be produced and nothing may be started.
    local unchanged = build(dir)
    local stillFacts = unchanged.timing.aot
    test.equal(stillFacts.externalCommands, 0, "an unchanged build starts no external toolchain process")
    test.equal(stillFacts.checkedSources, 0, "an unchanged build checks no AOT source")
    test.equal(stillFacts.loweredPrograms, 0, "an unchanged build lowers no AOT program")
    test.equal(stillFacts.optimizedPrograms, 0, "an unchanged build optimizes no AOT program")
    test.equal(stillFacts.emittedUnits, 0, "an unchanged build emits no AOT unit")
    test.equal(stillFacts.compiledObjects, 0, "an unchanged build compiles nothing")
    test.equal(stillFacts.reusedObjects, stillFacts.units, "an unchanged build reuses every object")
    test.equal(stillFacts.linked, false, "an unchanged build links nothing")
    test.equal(#names(changed(coldObjects, objects(dir))), 0, "an unchanged build rewrites no object")

    -- One body edited. Only that source's objects may be compiled -- one per
    -- feature tier where the target has several -- and the library relinked.
    local edited = read(dir .. "/src/k2.nupp"):gsub("factor %+ 2%.0", "factor + 9.0")
    write(dir .. "/src/k2.nupp", edited)
    local afterEdit = build(dir)
    local editFacts = afterEdit.timing.aot
    assert(editFacts.checkedSources >= SOURCES, "a source edit invalidates the pre-emission fingerprint")
    assert(editFacts.loweredPrograms >= SOURCES, "a source edit reruns AOT lowering")
    local mine = objectsOf(coldObjects, "k2")
    test.equal(
        editFacts.compiledObjects,
        count(mine),
        "editing one unit compiles that unit's target-tier objects and no others"
    )
    test.equal(editFacts.reusedObjects, editFacts.units - count(mine), "every other object is reused")
    test.equal(editFacts.linked, true, "the library is relinked once")
    test.equal(editFacts.externalCommands, 0, "compiling and relinking start no external process")
    local editedObjects = objects(dir)
    local moved = changed(coldObjects, editedObjects)
    test.equal(
        table.concat(names(moved), " "),
        table.concat(names(mine), " "),
        "only the edited unit's objects were rewritten"
    )
    local relinked = assert(
        read(dir .. "/build/native/lib/libnative_aot.dylib")
        or read(dir .. "/build/native/lib/libnative_aot.so")
        or read(dir .. "/build/native/lib/native_aot.dll")
    )
    assert(relinked ~= library, "the relinked library differs from the one before the edit")

    -- The record is evidence and not authority. An object that is gone is
    -- compiled again however well its key matches, and only that one is.
    local victim = names(objectsOf(editedObjects, "k1"))[1]
    assert(victim, "no k1 object to remove")
    os.remove(victim)
    local repaired = build(dir)
    assert(repaired.timing.aot.checkedSources >= SOURCES, "a missing artifact refuses the AOT replay")
    test.equal(repaired.timing.aot.compiledObjects, 1, "a missing object is compiled again")
    test.equal(repaired.timing.aot.reusedObjects, repaired.timing.aot.units - 1, "and nothing else is")
    test.equal(read(victim), editedObjects[victim], "the object compiled again is the object that was there")

    -- Back to a settled state, so the fixture ends the way it started: nothing
    -- to do and nothing started to find that out.
    local settled = build(dir)
    test.equal(settled.timing.aot.externalCommands, 0, "the repaired project settles again")
end

--- The policy accounts for its own time under names a reader can act on.
---
--- The timeline is one activity at a time, so these are parts of the whole
--- rather than a separate measurement, and a name that is not one of these is a
--- bucket nothing documents.
function M.theTimelineNamesTheAheadOfTimePhases()
    local known = {
        ["aot"] = true,
        ["aot:lookup"] = true,
        ["aot:check"] = true,
        ["aot:lower"] = true,
        ["aot:optimize"] = true,
        ["aot:emit"] = true,
        ["aot:reuse"] = true,
        ["aot:compile"] = true,
        ["aot:link"] = true,
    }
    local dir = project()
    local cold = build(dir)
    local seen = {}
    for _, span in ipairs(cold.timing.phases) do
        if span.name:sub(1, 3) == "aot" then
            assert(known[span.name], "undocumented phase " .. span.name)
            seen[span.name] = true
        end
    end
    -- The two a cold build always spends measurable time in: finding the
    -- bodies and compiling what it emitted. Linking is not among them: lld in
    -- process links a fixture this small in under a millisecond, below what
    -- the timeline reports.
    assert(seen["aot:check"], "checking the policy's own sources is named")
    assert(seen["aot:compile"], "running the code generator is named")

    -- And an unchanged build spends none of it, which is the same claim the
    -- counts make, read off the timeline instead.
    local unchanged = build(dir)
    for _, span in ipairs(unchanged.timing.phases) do
        assert(span.name ~= "aot:check", "an unchanged build checks no AOT source")
        assert(span.name ~= "aot:lower", "an unchanged build lowers no AOT program")
        assert(span.name ~= "aot:optimize", "an unchanged build optimizes no AOT program")
        assert(span.name ~= "aot:emit", "an unchanged build emits no AOT unit")
        assert(span.name ~= "aot:compile", "an unchanged build has no compilation to report")
        assert(span.name ~= "aot:link", "and nothing to link")
    end
end

--- The pre-emission key covers source bytes and every project-level semantic
--- record supplied before the checker runs. This is tested directly so every
--- component can be varied without requiring several installed toolchains or
--- dependency providers merely to observe a cache miss.
function M.preEmissionInputsInvalidateIndependently()
    local aot = require("nupp.tools.build.aot")
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    write(dir .. "/src/main.nupp", "module main\nlocal imported = require(\"support\")\nexport = imported\n")
    write(dir .. "/src/support.nupp", "module support\nexport = {value = 1}\n")

    local semantic = {
        compiler = "compiler-a",
        compilerResources = "compiler-resources-a",
        moduleCompiler = "module-compiler-a",
        config = "config-a",
        dependencies = "dependencies-a",
        generators = "generators-a",
        spi = "spi-a",
        target = "native",
        platform = "host",
    }
    local sources = {dir .. "/src/main.nupp", dir .. "/src/support.nupp"}
    local base = aot.inputFingerprint(sources, semantic)
    test.equal(aot.inputFingerprint(sources, semantic), base, "identical inputs retain one fingerprint")

    local fields = {
        "compiler",
        "compilerResources",
        "moduleCompiler",
        "config",
        "dependencies",
        "generators",
        "spi",
        "target",
        "platform",
    }
    for _, field in ipairs(fields) do
        local changed = {}
        for name, value in pairs(semantic) do
            changed[name] = value
        end
        changed[field] = tostring(changed[field]) .. "-changed"
        assert(aot.inputFingerprint(sources, changed) ~= base, field .. " invalidates the fingerprint")
    end

    write(dir .. "/src/support.nupp", "module support\nexport = {value = 2}\n")
    assert(aot.inputFingerprint(sources, semantic) ~= base, "an imported body invalidates the pre-emission fingerprint")

    write(dir .. "/src/plain.lua", "return {value = 1}\n")
    local mixed = {sources[1], sources[2], dir .. "/src/plain.lua"}
    local luaBase = aot.inputFingerprint(mixed, semantic)
    write(dir .. "/src/plain.lua", "return {value = 2}\n")
    assert(
        aot.inputFingerprint(mixed, semantic) ~= luaBase,
        "a Lua graph source invalidates the pre-emission fingerprint"
    )

    write(dir .. "/src/interface.d.nupp", "module interface\nexport type Value = number\n")
    local envMod = require("nupp.compiler.project.env")
    local declared = envMod.listSourceFilesFor({memoryOnly = false}, dir, {"src"}, dir .. "/build", true)
    local declarationBase = aot.inputFingerprint(declared, semantic)
    write(dir .. "/src/interface.d.nupp", "module interface\nexport type Value = string\n")
    assert(
        aot.inputFingerprint(declared, semantic) ~= declarationBase,
        "an authored declaration invalidates the pre-emission fingerprint"
    )

    assert(os.execute("mkdir -p '" .. dir .. "/build'") == 0)
    write(dir .. "/root.nupp", "module root\nexport = true\n")
    write(dir .. "/build/generated.nupp", "module generated\nexport = false\n")
    local implicit = envMod.listSourceFilesFor({memoryOnly = false}, dir, {}, dir .. "/build", false)
    local foundRoot, foundBuild = false, false
    for _, path in ipairs(implicit) do
        foundRoot = foundRoot or path:match("root%.nupp$") ~= nil
        foundBuild = foundBuild or path:match("build/generated%.nupp$") ~= nil
    end
    assert(foundRoot, "an omitted include list fingerprints the project root")
    assert(not foundBuild, "an implicit root does not fingerprint generated build output")
end

--- A replay is admitted only for the code generator this build selects.
function M.replayRequiresTheCurrentCodeGenerator()
    local aot = require("nupp.tools.build.aot")
    local aotllvm = require("nupp.tools.build.aotllvm")
    local policy = aot.toolchainPolicy("require", nil)
    test.equal(policy.desiredCommand, "<llvm>", "the in-process code generator is the only command")
    test.equal(policy.codegen, aotllvm.selection(), "the policy names the code generator selection")

    local remembered = {command = "<llvm>", signature = "", version = aotllvm.version(), dialect = "llvm"}
    local byC = {command = "clang", signature = "", version = "clang 18", dialect = "clang"}
    for _, name in ipairs({"require", "require-wasm", "emit-wasm"}) do
        assert(aot.replayCommandMatches(name, remembered, "<llvm>"), name .. ": the remembered code generator matches")
        assert(not aot.replayCommandMatches(name, byC, "<llvm>"), name .. ": a build a C compiler produced is not replayed")
        assert(
            not aot.replayCommandMatches(name, nil, "<llvm>"),
            name .. ": a build with nothing remembered is not replayed"
        )
    end
    assert(aot.replayCommandMatches("off", nil, nil), "a policy that compiles nothing selects no code generator")
end

--- The code generator selection is part of the key asked before any source is
--- checked: a build under other facts, or another LLVM, lowers again.
function M.preEmissionInputsIncludeTheCodeGeneratorSelection()
    local aot = require("nupp.tools.build.aot")
    local semantic = {sources = "same", toolchainPolicy = aot.toolchainPolicy("require", "x86_64-unknown-linux-gnu")}
    local base = aot.inputFingerprint({}, semantic)
    test.equal(aot.inputFingerprint({}, semantic), base, "one selection keeps one fingerprint")
    for _, field in ipairs({"policy", "target", "codegen"}) do
        local changed = {}
        for name, value in pairs(semantic.toolchainPolicy) do
            changed[name] = value
        end
        changed[field] = tostring(changed[field]) .. "-changed"
        assert(
            aot.inputFingerprint({}, {sources = "same", toolchainPolicy = changed}) ~= base,
            field .. " invalidates pre-emission replay"
        )
    end
end

function M.constSpecializedProjectsTakeTheSoundColdPath()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    write(
        dir .. "/nupp.lua",
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"constkernel"}, outDir = "build/native", aot = "require",
   }}},
}
]]
    )
    write(
        dir .. "/src/constkernel.nupp",
        [[
module constkernel

@aot
local function doubled<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do
        answer = answer * 2.0
    end
    return answer
end

local function doubled3(value: number): number
    return doubled(value, 3)
end

export = {doubled = doubled, doubled3 = doubled3}
]]
    )

    local cold = build(dir)
    assert(cold.timing.aot.loweredPrograms > 0, "the fixture contains a compiled const specialization")
    local generated = assert(read(dir .. "/build/native/constkernel.lua"))
    local unchanged = build(dir)
    assert(
        unchanged.timing.aot.checkedSources > 0,
        "a live const selection refuses pre-emission replay instead of changing the module build"
    )
    test.equal(read(dir .. "/build/native/constkernel.lua"), generated, "cold and unchanged const dispatch agree")
    local status, output = process.capture(
        {
            "luajit",
            "-e",
            'package.path="build/native/?.lua;"..package.path; local m=require("constkernel"); '
            .. 'assert(m.doubled3(5.0)==40.0); assert(m.doubled(5.0,3)==40.0)',
        },
        {cwd = dir}
    )
    test.equal(status, 0, "the unchanged const dispatcher remains correct: " .. output)
end

function M.replayEvidenceDistinguishesWasmMetadataFromFiles()
    local aot = require("nupp.tools.build.aot")
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/aot'") == 0)
    local unit = dir .. "/aot/kernel.ll"
    local manifest = dir .. "/aot/units.json"
    local linkManifest = dir .. "/aot/link.json"
    write(unit, "unit")
    write(manifest, "units")
    write(linkManifest, "link")
    local bridge = {entries = {{call = "kernel", layouts = {},},},}
    local aotllvm = require("nupp.tools.build.aotllvm")
    local snapshot = aot.captureReplay("emit-wasm", {
        emitted = {
            {
                source = "kernel.nupp",
                tier = "simd128",
                cacheKey = "kernel\0simd128",
                output = unit,
                key = "key",
                registrar = "nupp_wasm_register_u1234",
                bridge = bridge,
                unit = "u1234",
                backend = "llvm",
            },
        },
        manifest = manifest,
        dispatch = {},
        specializedBodies = 0,
        remembered = {command = "<llvm>", signature = "", version = aotllvm.version(), dialect = "llvm"},
    })
    assert(
        snapshot.payload.files.nupp_wasm_register_u1234 == nil,
        "a registrar symbol is metadata rather than a path to validate"
    )
    test.equal(snapshot.payload.emitted[1].bridge, bridge, "independent Wasm bridge metadata survives capture")
    assert(aot.replay(snapshot, "clang") == nil, "another code generator refuses replay")
    local restored = assert(aot.replay(snapshot, "<llvm>"), "intact replay evidence restores the result")
    test.equal(restored.emitted[1].bridge, bridge, "independent Wasm bridge metadata survives replay")
    os.remove(linkManifest)
    assert(aot.replay(snapshot, "<llvm>") == nil, "a missing static link manifest refuses replay")
end

--- A code generator selection the last build did not use recompiles every
--- source's objects.
---
--- The facts the lowering states change the IR, so they are in the unit key
--- and through it the object key. A build that kept objects across a change of
--- facts would ship a library lowered two ways.
function M.changedFactsRecompileEveryObject()
    local dir = project()
    local first = build(dir)
    test.equal(first.timing.aot.reusedObjects, 0)
    local coldObjects = objects(dir)
    local settled = build(dir)
    test.equal(settled.timing.aot.reusedObjects, settled.timing.aot.units, "the fixture starts settled")

    local refacted = build(dir, "NUPP_AOT_FACTS=none")
    local facts = refacted.timing.aot
    assert(facts.checkedSources >= SOURCES, "the fact selection invalidates the pre-emission fingerprint")
    local mine = 0
    for index = 1, SOURCES do
        mine = mine + count(objectsOf(coldObjects, "k" .. index))
    end
    test.equal(facts.compiledObjects, mine, "every source's objects are compiled again")
    test.equal(facts.reusedObjects, facts.units - mine, "and only compiler-owned units are reused")
    test.equal(facts.linked, true, "and the library is linked again")

    local back = build(dir)
    assert(back.timing.aot.checkedSources >= SOURCES, "returning to every fact lowers again")
    test.equal(back.timing.aot.compiledObjects, mine, "and compiles every source's objects again")
end

--- What an object key covers, asserted on the key rather than through a build.
---
--- A build can only show that two keys differed by recompiling, which needs two
--- of whatever differed installed on the machine. These are the dimensions the
--- key claims to cover, checked directly.
function M.numericLoopRuntimeIsPartOfTheArtifactKey()
    local aot = require("nupp.tools.build.aot")
    local targets = require("nupp.compiler.aot.target")
    local original = targets.numericForRuntime
    local ok, failure = pcall(function()
        local selected = assert(targets.select("x86_64-unknown-linux-gnu", "baseline"))
        targets.numericForRuntime = function()
            return "luajit-single"
        end
        local single = aot.key("same verified source", selected)
        targets.numericForRuntime = function()
            return "luajit-dual"
        end
        assert(
            aot.key("same verified source", selected) ~= single,
            "changing only the local LuaJIT number mode invalidates the compiled artifact"
        )
    end)
    targets.numericForRuntime = original
    assert(ok, failure)
end

function M.wasmNumericLoopsUseTheLuaJitArtifactKey()
    local aot = require("nupp.tools.build.aot")
    local targets = require("nupp.compiler.aot.target")
    local triple = "wasm32-unknown-emscripten"
    local source = "same verified Wasm source"
    for _, tier in ipairs({"scalar", "simd128"}) do
        local guest = assert(targets.select(triple, tier, "luajit"))
        local unspecified = assert(targets.select(triple, tier))
        test.equal(targets.numericForRuntime(guest), "luajit-single")
        test.equal(targets.numericForRuntime(unspecified), "luajit-single", "direct Wasm AOT uses the LuaJIT runtime")
        test.equal(aot.key(source, guest), aot.key(source, unspecified))
    end
    local tiers = assert(targets.buildTiers(triple, {minimum = "scalar", maximum = "simd128"}, "luajit"))
    test.equal(#tiers, 2)
    for _, selected in ipairs(tiers) do
        test.equal(
            targets.numericForRuntime(selected),
            "luajit-single",
            "every project tier retains the guest's numeric-loop contract"
        )
        local explicit = assert(targets.select(triple, selected.tier, "luajit"))
        test.equal(aot.key(source, selected), aot.key(source, explicit))
    end
end

function M.objectKeysCoverWhatChangesTheirBytes()
    local aot = require("nupp.tools.build.aot")
    local aotllvm = require("nupp.tools.build.aotllvm")
    local llvm = {command = "<llvm>", version = "llvm 20", dialect = "llvm"}
    local newer = {command = "<llvm>", version = "llvm 21", dialect = "llvm"}
    local triple = "x86_64-unknown-linux-gnu"
    local baseline = aotllvm.flags(triple, "baseline")
    local avx2 = aotllvm.flags(triple, "avx2")
    assert(table.concat(baseline, " ") ~= table.concat(avx2, " "), "each tier compiles with its own options")
    local base = aot.objectKey("unit", "baseline", llvm, baseline)

    test.equal(aot.objectKey("unit", "baseline", llvm, baseline), base, "the same inputs give the same key")
    assert(aot.objectKey("other", "baseline", llvm, baseline) ~= base, "the unit is in the key")
    assert(aot.objectKey("unit", "avx2", llvm, baseline) ~= base, "the target tier is in the key")
    assert(aot.objectKey("unit", "baseline", newer, baseline) ~= base, "the code generator's identity is in the key")
    assert(aot.objectKey("unit", "baseline", llvm, avx2) ~= base, "the options are in the key")
    local more = {}
    for index, flag in ipairs(baseline) do
        more[index] = flag
    end
    more[#more + 1] = "extra=1"
    assert(aot.objectKey("unit", "baseline", llvm, more) ~= base, "and so is one more of them")
end

return M
