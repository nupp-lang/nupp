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
-- many external toolchain processes the policy started -- and the bytes of the
-- object files themselves, because a count is a claim the compiler makes about
-- itself and the bytes are not.
--
-- One project, built and rebuilt through a sequence of states, rather than one
-- project per assertion: each build costs a C compiler run and the states are
-- consecutive by nature. The scenario names each transition as it makes it, so
-- a failure says which rebuild was wrong.

local test = require("assert")
local json = require("nupp.codec.json")

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

@aot(vectorize = true)
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
local function build(dir)
    local cache = dir .. "/build/test-cache"
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_CACHE_DIR=%q NO_COLOR= '%s' build --target native --format json 2>/dev/null"
            ):format(dir, cache, NUPP)
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
        found[line] = assert(read(line), "unreadable object " .. line)
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
    assert(coldFacts.compiledObjects >= SOURCES, "a cold build compiles every unit: " .. coldFacts.compiledObjects)
    test.equal(coldFacts.compiledObjects, coldFacts.units, "every emitted unit becomes an object")
    test.equal(coldFacts.linked, true, "a cold build links")
    assert(coldFacts.externalCommands > coldFacts.compiledObjects, "a cold build runs a compiler and a linker")
    local coldObjects = objects(dir)
    test.equal(#names(coldObjects), coldFacts.units, "one object file per unit")
    local library = assert(
        read(
            dir .. "/build/native/lib/libnative_aot.dylib"
        ) or read(dir .. "/build/native/lib/libnative_aot.so") or read(dir .. "/build/native/lib/native_aot.dll"),
        "no linked library"
    )

    -- Nothing changed, so nothing may be produced and nothing may be started.
    -- The second half is the one worth having: an unchanged build that quietly
    -- asked a compiler its version costs most of what an unchanged build costs.
    local unchanged = build(dir)
    local stillFacts = unchanged.timing.aot
    test.equal(stillFacts.externalCommands, 0, "an unchanged build starts no external toolchain process")
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
    local mine = objectsOf(coldObjects, "k2")
    test.equal(
        editFacts.compiledObjects,
        count(mine),
        "editing one unit compiles that unit's target-tier objects and no others"
    )
    test.equal(editFacts.reusedObjects, editFacts.units - count(mine), "every other object is reused")
    test.equal(editFacts.linked, true, "the library is relinked once")
    test.equal(
        editFacts.externalCommands,
        editFacts.compiledObjects + 1,
        "one compiler run per dirty object and one link"
    )
    local editedObjects = objects(dir)
    local moved = changed(coldObjects, editedObjects)
    test.equal(
        table.concat(names(moved), " "),
        table.concat(names(mine), " "),
        "only the edited unit's objects were rewritten"
    )
    local relinked = assert(
        read(
            dir .. "/build/native/lib/libnative_aot.dylib"
        ) or read(dir .. "/build/native/lib/libnative_aot.so") or read(dir .. "/build/native/lib/native_aot.dll")
    )
    assert(relinked ~= library, "the relinked library differs from the one before the edit")

    -- The record is evidence and not authority. An object that is gone is
    -- compiled again however well its key matches, and only that one is.
    local victim = names(objectsOf(editedObjects, "k1"))[1]
    assert(victim, "no k1 object to remove")
    os.remove(victim)
    local repaired = build(dir)
    test.equal(repaired.timing.aot.compiledObjects, 1, "a missing object is compiled again")
    test.equal(repaired.timing.aot.reusedObjects, repaired.timing.aot.units - 1, "and nothing else is")
    test.equal(read(victim), editedObjects[victim], "the object compiled again is the object that was there")

    -- Back to a settled state, so the fixture ends the way it started: nothing
    -- to do and nothing started to find that out.
    local settled = build(dir)
    test.equal(settled.timing.aot.externalCommands, 0, "the repaired project settles again")
end

--- A project flag the last build did not use recompiles every object.
---
--- Flags are not in the unit key, because the C does not change when they do.
--- They are in the object key, because the object does. A build that kept
--- objects across a flag change would ship a library compiled two ways.
function M.changedFlagsRecompileEveryObject()
    local dir = project()
    local first = build(dir)
    test.equal(first.timing.aot.reusedObjects, 0)
    local settled = build(dir)
    test.equal(settled.timing.aot.reusedObjects, settled.timing.aot.units, "the fixture starts settled")

    local manifest = assert(read(dir .. "/nupp.lua"))
    write(
        dir .. "/nupp.lua",
        (manifest:gsub('aot = "require",', 'aot = "require", aotCflags = {"-DNUPP_AOT_TEST=1"},'))
    )
    local reflagged = build(dir)
    test.equal(reflagged.timing.aot.reusedObjects, 0, "a flag the objects were not compiled with recompiles them")
    test.equal(reflagged.timing.aot.compiledObjects, reflagged.timing.aot.units)
    test.equal(reflagged.timing.aot.linked, true, "and the library is linked again")
end

--- What an object key covers, asserted on the key rather than through a build.
---
--- A build can only show that two keys differed by recompiling, which needs two
--- of whatever differed installed on the machine. These are the dimensions the
--- key claims to cover, checked directly.
function M.objectKeysCoverWhatChangesTheirBytes()
    local aot = require("nupp.compiler.build.aot")
    local clang = {command = "cc", version = "clang 17", dialect = "clang"}
    local newer = {command = "cc", version = "clang 18", dialect = "clang"}
    local base = aot.objectKey("unit", "baseline", clang, {"-O3"})

    test.equal(aot.objectKey("unit", "baseline", clang, {"-O3"}), base, "the same inputs give the same key")
    assert(aot.objectKey("other", "baseline", clang, {"-O3"}) ~= base, "the unit is in the key")
    assert(aot.objectKey("unit", "avx2", clang, {"-O3"}) ~= base, "the target tier is in the key")
    assert(aot.objectKey("unit", "baseline", newer, {"-O3"}) ~= base, "the compiler's identity is in the key")
    assert(aot.objectKey("unit", "baseline", clang, {"-O2"}) ~= base, "the flags are in the key")
    assert(aot.objectKey("unit", "baseline", clang, {"-O3", "-g"}) ~= base, "and so is one more of them")
end

--- What lets a build believe a recorded compiler identity without asking again.
---
--- The signature has to move when the file it names does, because everything
--- keyed on the recorded version text is only as good as this is. It names a
--- path rather than running anything, so it can be asked about an ordinary file.
function M.aToolSignatureFollowsTheFileItNames()
    local aot = require("nupp.compiler.build.aot")
    local path = os.tmpname()
    write(path, "one")
    local first = aot.toolSignature(path)
    write(path, "one and a half")
    local grown = aot.toolSignature(path)
    assert(first ~= grown, "a compiler replaced with a file of another length is seen")
    write(path, "one")
    test.equal(aot.toolSignature(path), first, "and restoring it restores the signature")

    local elsewhere = os.tmpname()
    write(elsewhere, "one")
    assert(aot.toolSignature(elsewhere) ~= first, "the same bytes at another path are another compiler")
    os.remove(path)
    os.remove(elsewhere)

    local missing = aot.toolSignature("/nonexistent/compiler-that-is-not-there")
    assert(missing ~= first, "a compiler that is not there matches nothing that is")
    test.equal(
        aot.toolSignature("/nonexistent/compiler-that-is-not-there"),
        missing,
        "and says the same thing every time it is asked"
    )
end

return M
