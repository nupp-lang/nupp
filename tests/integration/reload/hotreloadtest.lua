local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.project.env")
local gen = require("nupp.compiler.lua.gen")
local optimize = require("nupp.compiler.lua.optimize")
local hot = require("nupp.runtime.hotreload")
local hotSession = require("nupp.tools.hotsession")

-- One environment for the whole suite.
--
-- Every case checks against an environment built exactly this way, and
-- building one means checking the prelude from source. Per case that was
-- most of what this suite cost; the cases share it the way the other
-- checker suites do.
local sharedEnv = envMod.new(".")

local function checked(source, filename)
    filename = filename or "hot.nupp"
    local result = parser.parse(source, filename)
    testAssert.eq(#result.errors, 0, "hot source parses")
    local diagnostics = check.check(result, filename, sharedEnv)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code:match("^NUPP[123]") then
            error(("hot source did not check: %s: %s"):format(diagnostic.code, diagnostic.msg), 2)
        end
    end

    return result
end

local function generate(source, mode, module)
    local result = checked(source)
    local code, diagnostics, _, _, metadata = gen.generate(result, "hot.nupp", nil, {
        mode = mode,
        module = module or "hot",
        baseGeneration = mode == "patch" and hot.generation() or nil,
    })
    testAssert.eq(#diagnostics, 0, mode .. " generation diagnostics")
    assert(metadata and metadata.mode == mode, mode .. " metadata")
    local chunk, reason = loadstring(code, "@hot-generated")
    assert(chunk, tostring(reason) .. "\n---\n" .. code)

    return code, chunk, metadata
end

local function initial(source, module)
    hot.resetForTesting()
    local _, chunk, metadata = generate(source, "initial", module)
    local value = chunk()
    hot.seal(metadata.module)

    return value, metadata
end

local M = {}

local function temporaryProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    for name, source in pairs(files) do
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(source)
        handle:close()
    end

    return dir
end

local function write(path, source)
    local handle = assert(io.open(path, "wb"))
    handle:write(source)
    handle:close()
end

local function loadedCompilerSession(dir, path)
    local session = hotSession.new(dir, {cache = false})
    local initialBuild = session:initial({path})
    if initialBuild.kind ~= "initial" then
        local messages = {}
        for _, diagnostic in ipairs(initialBuild.diagnostics or {}) do
            messages[#messages + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
        error("initial hot build failed: " .. table.concat(messages, "; "), 2)
    end
    session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)

    return session
end

function M.thePublicReloadNamespaceKeepsItsWatchContract()
    checked(
        [[
local generation: integer = debug.reload.generation()
local outcome: debug.ReloadPoll = debug.reload.poll()
local kind: string = outcome.kind
local previous: integer? = outcome.basegeneration
assert(previous == nil or previous >= 0)
assert(generation >= 0 and kind ~= "")
assert(debug.getinfo(1) ~= nil)
]]
    )
    local retired = parser.parse("local outcome = nupp.hotreload.poll()\n", "retired_reload.nupp")
    local diagnostics = check.check(retired, "retired_reload.nupp", sharedEnv)
    local rejected = false
    for _, diagnostic in ipairs(diagnostics) do
        rejected = rejected or diagnostic.code == "NUPP2004"
    end
    assert(rejected, "the retired public namespace is not a compatibility alias")
    checked(
        [[
local debug = {reload = {generation = function(): string return "local" end}}
local generation: string = debug.reload.generation()
assert(generation == "local")
]]
    )
end

function M.normalGenerationRemainsByteIdentical()
    local result = checked("local function f(n: integer): integer return n + 1 end\nreturn f")
    local ordinary = assert(gen.generate(result, "ordinary.nupp"))
    local explicit = assert(gen.generate(result, "ordinary.nupp", nil, nil))
    testAssert.eq(explicit, ordinary, "absent watch request changes normal output")
    assert(not ordinary:find("__nuppHot", 1, true), "normal output contains hot runtime")
end

function M.normalOptimizationLevelsContainNoHotReloadMetadata()
    local source = table.concat(
        {
            "cdef function hot_plain(value: int32): int32",
            "local function f(n: int32): int32 return math.i32.add(hot_plain(n), 1) end",
            "return f",
        },
        "\n"
    )
    for level = 0, 2 do
        local left = checked(source, "ordinary.nupp")
        local right = checked(source, "ordinary.nupp")
        if level > 0 then
            optimize.run(left, {level = level})
            optimize.run(right, {level = level})
        end
        local ordinary = assert(gen.generate(left, "ordinary.nupp"))
        local explicit = assert(gen.generate(right, "ordinary.nupp", nil, nil))
        testAssert.eq(explicit, ordinary, "absent watch request changes -O" .. level .. " output")
        assert(not ordinary:find("__nuppHot", 1, true), "-O" .. level .. " contains hot runtime")
        assert(not ordinary:find("provider-file", 1, true), "-O" .. level .. " contains provider metadata")
        assert(not ordinary:find("cUses", 1, true), "-O" .. level .. " contains C-use metadata")
    end
end

function M.retainedFunctionUsesPatchedBodyAndCapturedCell()
    local before = table.concat(
        {
            "local value: integer = 1",
            "local function advance(by: integer): integer",
            "   value = value + by",
            "   return value",
            "end",
            "return {advance = advance}",
        },
        "\n"
    )
    local api = initial(before, "capture")
    local retained = api.advance
    testAssert.eq(retained(1), 2, "initial implementation")

    local after = table.concat(
        {
            "local value: integer = 999",
            "local function advance(by: integer): integer",
            "   value = value + by * 2",
            "   return value",
            "end",
            "return {advance = advance}",
        },
        "\n"
    )
    local patch = generate(after, "patch", "capture")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    testAssert.eq(hot.commit(prepared), 2, "committed generation")
    testAssert.eq(api.advance, retained, "public function identity")
    testAssert.eq(retained(1), 4, "patched implementation shares old value cell")
end

-- Lua numbers upvalues by order of first reference, so a patched body that
-- references its captures in a different order carries the same names at
-- different indices. The second patch is the one that would join through a
-- stale index map recorded before the first commit.
function M.secondPatchJoinsCapturesByNameNotStaleIndex()
    local function source(firstNamed)
        local selector = firstNamed and "first" or "second"
        local matched = firstNamed and "first" or "second"
        local other = firstNamed and "second" or "first"
        return table.concat(
            {
                "local first: integer = 10",
                "local second: integer = 20",
                "local function read(which: string): integer",
                "   if which == '" .. selector .. "' then",
                "      return " .. matched,
                "   end",
                "   return " .. other,
                "end",
                "return {read = read}",
            },
            "\n"
        )
    end

    local api = initial(source(true), "reorder")
    testAssert.eq(api.read("first"), 10, "initial first cell")
    testAssert.eq(api.read("second"), 20, "initial second cell")

    local function commitPatch(body, label)
        local patch = generate(body, "patch", "reorder")
        local prepared, reason = hot.stage(patch, hot.generation())
        assert(prepared, reason)
        assert(hot.commit(prepared), label)
    end

    -- References `second` first, reversing the upvalue numbering.
    commitPatch(source(false), "reordered patch commits")
    testAssert.eq(api.read("first"), 10, "first cell after a reordered patch")
    testAssert.eq(api.read("second"), 20, "second cell after a reordered patch")

    -- Back to the initial order: this join must use the live implementation's
    -- numbering rather than the initial generation's.
    commitPatch(source(true), "restored patch commits")
    testAssert.eq(api.read("first"), 10, "first cell after the second patch")
    testAssert.eq(api.read("second"), 20, "second cell after the second patch")
end

function M.managedCellsKeepPolicyAndUseThePatchedCleanupSlot()
    local function source(multiplier)
        return table.concat(
            {
                "local cleaned: integer = 0",
                "local record Item value: integer end",
                "local function closeItem(takes item: Item): nil",
                "   cleaned = cleaned + item.value * " .. tostring(multiplier),
                "end",
                "local function openItem(): affine(Item, closeItem)",
                "   return new Item(value = 3)",
                "end",
                "local function make(): managed(affine(Item, closeItem))",
                "   return own.manage(openItem())",
                "end",
                "local function count(): integer return cleaned end",
                "return {make = make, count = count}",
            },
            "\n"
        )
    end

    local api = initial(source(1), "dynamic-policy")
    local cell = api.make()
    local patch = generate(source(2), "patch", "dynamic-policy")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    testAssert.eq(hot.commit(prepared), 2, "dynamic policy patch committed")
    cell:close()
    testAssert.eq(api.count(), 6, "live cell resolves cleanup through the patched slot")
end

function M.liveDynamicPoliciesRejectAnIncompatiblePatchTransactionally()
    local function source(openName)
        return table.concat(
            {
                "local M = {}",
                "local cleaned: integer = 0",
                "local record Item value: integer end",
                "local function closeA(takes item: Item): nil cleaned = cleaned + item.value end",
                "local function closeB(takes item: Item): nil cleaned = cleaned + item.value * 10 end",
                "function M.openA(): affine(Item, closeA) return new Item(value = 2) end",
                "function M.openB(): affine(Item, closeB) return new Item(value = 2) end",
                "function M.make(): managed(unknown)",
                "   return own.manage(M." .. openName .. "()) as managed(unknown)",
                "end",
                "function M.count(): integer return cleaned end",
                "return M",
            },
            "\n"
        )
    end

    local api = initial(source("openA"), "dynamic-transition")
    local cell = api.make()
    local patch = generate(source("openB"), "patch", "dynamic-transition")
    local prepared, reason = hot.stage(patch, hot.generation())
    testAssert.eq(prepared, nil, "a live policy blocks incompatible replacement")
    assert(reason and reason:find("live managed-cell policy changed", 1, true), tostring(reason))
    testAssert.eq(hot.generation(), 1, "rejected policy transition leaves the generation unchanged")
    cell:close()
    testAssert.eq(api.count(), 2, "rejection neither migrates nor cleans the cell")
end

function M.commitFlushesJitAfterPublishing()
    local before = "local function value(): integer return 1 end\nreturn value"
    local retained = initial(before, "jit-flush")
    local patch = generate(before:gsub("return 1", "return 2"), "patch", "jit-flush")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    local original = jit.flush
    local flushes = 0
    jit.flush = function()
        flushes = flushes + 1
    end
    local ok, generation, commitError = pcall(hot.commit, prepared)
    jit.flush = original
    assert(ok, generation)
    testAssert.eq(generation, 2, commitError)
    testAssert.eq(flushes, 1, "commit flushes stale JIT traces exactly once")
    testAssert.eq(retained(), 2, "the flushed generation was published")
end

function M.rejectedCaptureChangeLeavesOldGenerationRunning()
    local before = table.concat(
        {"local value: integer = 3", "local function read(): integer", "   return value", "end", "return read",},
        "\n"
    )
    local retained = initial(before, "reject")

    local after = table.concat(
        {
            "local value: integer = 3",
            "local other: integer = 4",
            "local function read(): integer",
            "   return value + other",
            "end",
            "return read",
        },
        "\n"
    )
    local patch = generate(after, "patch", "reject")
    local prepared, reason = hot.stage(patch, hot.generation())
    testAssert.eq(prepared, nil, "capture-changing patch is rejected")
    assert(reason and reason:find("captured bindings changed", 1, true), tostring(reason))
    testAssert.eq(hot.generation(), 1, "rejection does not publish generation")
    testAssert.eq(retained(), 3, "old implementation remains callable")
end

function M.selfRecursionUsesNewPrivateImplementation()
    local before = table.concat(
        {
            "local function sum(n: integer): number",
            "   if n == 0 then return 0 end",
            "   return n + sum(n - 1)",
            "end",
            "return sum",
        },
        "\n"
    )
    local retained = initial(before, "recursive")
    testAssert.eq(retained(3), 6, "initial recursion")

    local after = table.concat(
        {
            "local function sum(n: integer): number",
            "   if n == 0 then return 1 end",
            "   return n + sum(n - 1)",
            "end",
            "return sum",
        },
        "\n"
    )
    local patch = generate(after, "patch", "recursive")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    assert(hot.commit(prepared))
    testAssert.eq(retained(3), 7, "replacement self recursion stays on replacement")
end

function M.mutualRecursionUsesTheNewestPartnerSlot()
    local before = table.concat(
        {
            "local M = {}",
            "function M.odd(n: integer): boolean",
            "   if n == 0 then return false end",
            "   return M.even(n - 1)",
            "end",
            "function M.even(n: integer): boolean",
            "   if n == 0 then return true end",
            "   return M.odd(n - 1)",
            "end",
            "return M",
        },
        "\n"
    )
    local api = initial(before, "mutual")
    local after = before:gsub("if n == 0 then return false end", "if n == 0 then return true end")
    local patch = generate(after, "patch", "mutual")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    assert(hot.commit(prepared))
    testAssert.eq(api.even(1), true, "unchanged partner dispatches through patched odd slot")
end

function M.inlineRecordMethodKeepsItsPublicIdentity()
    local before = table.concat(
        {
            "local record Counter",
            "   value: integer",
            "   function add(self, by: integer): integer",
            "      return self.value + by",
            "   end",
            "end",
            "return Counter",
        },
        "\n"
    )
    local Counter = initial(before, "inline")
    local retained = Counter.add
    local instance = setmetatable({value = 3}, Counter)
    testAssert.eq(retained(instance, 2), 5)
    local after = before:gsub("self.value %+ by", "self.value + by * 2")
    local patch = generate(after, "patch", "inline")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    assert(hot.commit(prepared))
    testAssert.eq(Counter.add, retained, "record method identity")
    testAssert.eq(retained(instance, 2), 7, "record method replacement")
end

function M.structMethodDispatchesThroughAStableSlot()
    local before = table.concat(
        {
            "local struct Counter",
            "   value: int32",
            "end",
            "function Counter:add(by: integer): number",
            "   return self.value + by",
            "end",
            "local item = new Counter(3)",
            "local function call(): number return item:add(2) end",
            "return call",
        },
        "\n"
    )
    local call = initial(before, "struct-method")
    testAssert.eq(call(), 5)
    local after = before:gsub("self.value %+ by", "self.value + by * 2")
    local patch = generate(after, "patch", "struct-method")
    local prepared, reason = hot.stage(patch, hot.generation())
    assert(prepared, reason)
    assert(hot.commit(prepared))
    testAssert.eq(call(), 7, "struct metatype method replacement")
end

function M.activeCallFinishesOnTheImplementationItEntered()
    local before = table.concat(
        {
            "local function value(commit: function(): nil): integer",
            "   commit()",
            "   return 1",
            "end",
            "return value",
        },
        "\n"
    )
    local retained = initial(before, "active")
    local after = before:gsub("return 1", "return 2")
    local patch = generate(after, "patch", "active")
    local didCommit = false
    local oldResult = retained(function()
        local prepared, reason = hot.stage(patch, hot.generation())
        assert(prepared, reason)
        assert(hot.commit(prepared))
        didCommit = true
    end)
    assert(didCommit)
    testAssert.eq(oldResult, 1, "active closure remains old")
    testAssert.eq(
        retained(function()
        end),
        2,
        "future dispatch enters replacement"
    )
end

function M.failedMultiFunctionStagePublishesNothing()
    local before = table.concat(
        {
            "local function first(): integer return 1 end",
            "local function second(): integer return 2 end",
            "return {first = first, second = second}",
        },
        "\n"
    )
    local api = initial(before, "atomic")
    local after = table.concat(
        {
            "local captured: integer = 4",
            "local function first(): integer return 10 end",
            "local function second(): integer return 2 + captured end",
            "return {first = first, second = second}",
        },
        "\n"
    )
    local patch = generate(after, "patch", "atomic")
    local prepared, reason = hot.stage(patch, hot.generation())
    testAssert.eq(prepared, nil)
    assert(reason and reason:find("captured bindings changed", 1, true), tostring(reason))
    testAssert.eq(api.first(), 1, "earlier valid candidate was not published")
    testAssert.eq(api.second(), 2, "failing candidate was not published")
end

function M.tailTrampolinePreservesErrorAttribution()
    local source = table.concat(
        {
            "local function fail(): nil",
            "   error('boom', 2)",
            "end",
            "local function call(): nil fail() end",
            "return call",
        },
        "\n"
    )
    local result = checked(source, "stack.nupp")
    local ordinary = assert(gen.generate(result, "stack.nupp"))
    local normalChunk = assert(loadstring(ordinary, "@stack.nupp"))
    local normal = normalChunk()
    local normalOK, normalReason = pcall(normal)
    testAssert.eq(normalOK, false)

    hot.resetForTesting()
    local watchCode, diagnostics, _, _, metadata = gen.generate(result, "stack.nupp", nil, {
        mode = "initial",
        module = "stack",
    })
    testAssert.eq(#diagnostics, 0)
    local watch = assert(loadstring(watchCode, "@stack.nupp"))()
    hot.seal(metadata.module)
    local watchOK, watchReason = pcall(watch)
    testAssert.eq(watchOK, false)
    testAssert.eq(tostring(watchReason), tostring(normalReason), "error(level) source attribution")
end

function M.slotArrayMatchesTheNormalLocalBoundary()
    local function source(count)
        local lines = {}
        for index = 1, count do
            lines[#lines + 1] = ("local function f%d() return %d end"):format(index, index)
        end
        lines[#lines + 1] = ("return f%d"):format(count)

        return table.concat(lines, "\n")
    end

    local boundary
    for count = 180, 200 do
        local parsed = parser.parse(source(count), "locals.nupp")
        local code, diagnostics = gen.generate(parsed, "locals.nupp")
        if #diagnostics == 0 and loadstring(code, "@normal-locals") then
            boundary = count
        else
            break
        end
    end
    assert(boundary, "normal generator has no accepted boundary fixture")
    for _, count in ipairs({boundary, boundary + 1}) do
        local parsed = parser.parse(source(count), "locals.nupp")
        local normal, normalDiagnostics = gen.generate(parsed, "locals.nupp")
        local watch, watchDiagnostics = gen.generate(parsed, "locals.nupp", nil, {mode = "initial", module = "locals",})
        local normalLoads = #normalDiagnostics == 0 and loadstring(normal, "@normal-locals") ~= nil
        local watchLoads = #watchDiagnostics == 0 and loadstring(watch, "@watch-locals") ~= nil
        testAssert.eq(watchLoads, normalLoads, "watch and normal local ceiling at " .. count)
    end
end

function M.sessionAdvancesOnlyAfterCommitAcknowledgement()
    local before = table.concat(
        {
            "local value: integer = 1",
            "local function changed(by: integer): integer",
            "   value = value + by",
            "   return value",
            "end",
            "local function untouched(): integer return 9 end",
            "return {changed = changed, untouched = untouched}",
        },
        "\n"
    )
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    hot.resetForTesting()
    local session = hotSession.new(dir, {cache = false})
    local initialBuild = session:initial({path})
    testAssert.eq(initialBuild.kind, "initial")
    local entry = assert(loadstring(initialBuild.entryCode, "@" .. path))
    local api = entry()
    hot.seal(initialBuild.entryManifest.module)
    session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)

    local after = before:gsub("value = value %+ by", "value = value + by * 2")
    write(path, after)
    session:diskChanged(path, 2)
    local prepared = session:prepare({path})
    testAssert.eq(prepared.kind, "prepared")
    assert(prepared.patch:find("changed", 1, true), "changed implementation is emitted")
    assert(not prepared.patch:find("untouched", 1, true), "unchanged implementation is omitted")
    testAssert.eq(session.generation, 1, "prepare does not advance compiler baseline")
    local staged, reason = hot.stage(prepared.patch, prepared.baseGeneration)
    assert(staged, reason)
    testAssert.eq(hot.commit(staged), 2)
    session:committed(2)
    testAssert.eq(api.changed(1), 3, "session patch reached retained function")
end

function M.sessionSkipsUnloadedChangedModules()
    local dir = temporaryProject({
        ["main.nupp"] = "local function main(): integer return 1 end\nreturn main",
        ["later.nupp"] = "local function later(): integer return 1 end\nreturn later",
    })
    local mainPath = dir .. "/main.nupp"
    local laterPath = dir .. "/later.nupp"
    hot.resetForTesting()
    local session = hotSession.new(dir, {cache = false})
    local initialBuild = session:initial({mainPath})
    assert(loadstring(initialBuild.entryCode, "@" .. mainPath))()
    hot.seal(initialBuild.entryManifest.module)
    session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)
    write(laterPath, "local function later(): integer return 2 end\nreturn later")
    session:diskChanged(laterPath, 2)
    local result = session:prepare({laterPath})
    testAssert.eq(result.kind, "no-change", "unloaded module has no running slots to patch")
end

function M.sessionReportsStructuralChangesAsRestartRequired()
    local before = "local function value(): integer return 1 end\nreturn value"
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    hot.resetForTesting()
    local session = hotSession.new(dir, {cache = false})
    local initialBuild = session:initial({path})
    assert(loadstring(initialBuild.entryCode, "@" .. path))()
    hot.seal(initialBuild.entryManifest.module)
    session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)
    write(path, "local added: integer = 2\n" .. before)
    session:diskChanged(path, 2)
    local result = session:prepare({path})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.diagnostics[1].code, "NUPP5001")
    testAssert.eq(result.reason.kind, "source-structure")
    testAssert.eq(result.reason.dependency, "main")
    testAssert.eq(result.reason.path, path)
end

function M.sessionRestartsBeforeAChangedSoALayoutCanReachLiveStorage()
    local before = table.concat(
        {
            "local soa = require('nupp.soa')",
            "local ffi = require('ffi')",
            "local struct Particle",
            "   x: float",
            "   y: float",
            "end",
            "local function fingerprint(): string",
            "   return soa.layoutof(ffi.typeof<Particle>()).fingerprint",
            "end",
            "return fingerprint",
        },
        "\n"
    )
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)

    write(path, before:gsub("y: float", "y: int32"))
    session:diskChanged(path, 2)
    local result = session:prepare({path})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.diagnostics[1].code, "NUPP5001")
end

function M.sessionRechecksLoadedModulesAfterDeclarationChanges()
    local dir = temporaryProject({
        ["globals.nupp"] = "global type Watched = number\n",
        [
            "main.nupp"
        ] = table.concat(
            {"local function add(value: Watched): number", "   return value + 1", "end", "return add",},
            "\n"
        ),
    })
    local mainPath = dir .. "/main.nupp"
    local globalsPath = dir .. "/globals.nupp"
    local session = loadedCompilerSession(dir, mainPath)

    write(globalsPath, "global type Watched = string\n")
    session:diskChanged(globalsPath, 2)
    local result = session:prepare({globalsPath})
    testAssert.eq(result.kind, "diagnostics", "dependent is type-checked before patching")
    assert(result.diagnostics[1].code:match("^NUPP[123]"), "expected a fatal type diagnostic")
end

function M.sessionRejectsSemanticSignatureChangesWithTheSameSpelling()
    local dir = temporaryProject({
        ["globals.nupp"] = "global type Watched = int32\n",
        [
            "main.nupp"
        ] = table.concat(
            {"local function identity(value: Watched): Watched", "   return value", "end", "return identity",},
            "\n"
        ),
    })
    local mainPath = dir .. "/main.nupp"
    local globalsPath = dir .. "/globals.nupp"
    local session = loadedCompilerSession(dir, mainPath)

    write(globalsPath, "global type Watched = int64\n")
    session:diskChanged(globalsPath, 2)
    local result = session:prepare({globalsPath})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.diagnostics[1].code, "NUPP5001")
    testAssert.eq(result.reason.kind, "project-declaration")
    testAssert.eq(result.reason.dependency, "Watched")
    testAssert.eq(result.reason.path, globalsPath)
    testAssert.eq(result.reason.consumer, "main")
    assert(result.diagnostics[1].msg:find(globalsPath, 1, true), result.diagnostics[1].msg)
    assert(result.diagnostics[1].msg:find("required by main", 1, true), result.diagnostics[1].msg)
end

function M.sessionRechecksCallableFactsWithoutTreatingThemAsAbi()
    for _, guarded in ipairs({false, true}) do
        local body = "return dependency.identity(value)"
        if guarded then
            body = "@noalloc do " .. body .. " end"
        end
        local dir = temporaryProject({
            [
                "dependency.nupp"
            ] = "local M = {}\nfunction M.identity(value: integer): integer return value end\nreturn M",
            [
                "main.nupp"
            ] = "local dependency = require('dependency')\nlocal function work(value: integer): integer "
            .. body
            .. " end\nreturn work",
        })
        local path = dir .. "/dependency.nupp"
        local session = loadedCompilerSession(dir, dir .. "/main.nupp")
        write(
            path,
            "local M = {}\nfunction M.identity(value: integer): integer local allocated = {value}; return value end\nreturn M"
        )
        session:diskChanged(path, 2)
        local result = session:prepare({path})
        testAssert.eq(result.kind, guarded and "diagnostics" or "no-change")
        if guarded then
            local found = false
            for _, diagnostic in ipairs(result.diagnostics) do
                found = found or diagnostic.code == "NUPP2710"
            end
            assert(found, "changed inferred effects revalidate loaded caller guards")
        end
    end
end

function M.sessionNamesTheImportedModuleWhoseInterfaceChanged()
    local dir = temporaryProject({
        [
            "dependency.nupp"
        ] = table.concat(
            {"local M = {}", "function M.identity(value: int32): int32 return value end", "return M",},
            "\n"
        ),
        ["main.nupp"] = "local dependency = require('dependency')\nreturn dependency.identity\n",
    })
    local mainPath = dir .. "/main.nupp"
    local dependencyPath = dir .. "/dependency.nupp"
    local session = loadedCompilerSession(dir, mainPath)

    write(
        dependencyPath,
        table.concat({"local M = {}", "function M.identity(value: int64): int64 return value end", "return M",}, "\n")
    )
    session:diskChanged(dependencyPath, 2)
    local result = session:prepare({dependencyPath})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "module-interface")
    testAssert.eq(result.reason.dependency, "dependency")
    testAssert.eq(result.reason.path, dependencyPath)
    testAssert.eq(result.reason.consumer, "main")
    assert(result.diagnostics[1].msg:find("module interface dependency", 1, true), result.diagnostics[1].msg)
    assert(result.diagnostics[1].msg:find(dependencyPath, 1, true), result.diagnostics[1].msg)
end

-- An `@comptime export type` flip reaches the session as a project declaration
-- before its fingerprint is consulted, so the digest itself is what is held to
-- the build's: the session names the build's own function, and these are the
-- two inputs the session's copy of it used to leave out.
function M.interfaceFingerprintIsTheBuildsOwn()
    local buildModules = require("nupp.tools.build.modules")
    local exports = {typeDefs = {Field = {}}, valueDefs = {}}
    local plain = buildModules.interfaceHash(nil, exports, nil)
    testAssert.eq(buildModules.interfaceHash(nil, exports, nil), plain, "the digest is a function of its inputs")
    exports.typeDefs.Field.comptimeOnly = true
    local comptimeOnly = buildModules.interfaceHash(nil, exports, nil)
    assert(comptimeOnly ~= plain, "an alias becoming comptime-only changes the interface")
    assert(
        buildModules.interfaceHash(nil, exports, "abc") ~= comptimeOnly,
        "an external declaration's source is part of its interface"
    )
end

function M.sessionRejectsChangedCLayoutsBeforePatching()
    local dir = temporaryProject({
        [
            "native.nupp"
        ] = table.concat({"cdef struct hot_point", "   value: int32", "end", "return {hot_point = hot_point}",}, "\n"),
        ["main.nupp"] = table.concat({"local native = require('native')", "return native.hot_point",}, "\n"),
    })
    local mainPath = dir .. "/main.nupp"
    local nativePath = dir .. "/native.nupp"
    local session = loadedCompilerSession(dir, mainPath)

    write(
        nativePath,
        table.concat({"cdef struct hot_point", "   value: int64", "end", "return {hot_point = hot_point}",}, "\n")
    )
    session:diskChanged(nativePath, 2)
    local result = session:prepare({nativePath})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.diagnostics[1].code, "NUPP5001")
    testAssert.eq(result.reason.kind, "c-declaration")
    testAssert.eq(result.reason.dependency, "hot_point")
    testAssert.eq(result.reason.path, nativePath)
    testAssert.eq(result.reason.consumer, "main")
    assert(result.diagnostics[1].msg:find("C declarations in module hot_point", 1, true), result.diagnostics[1].msg)
    assert(result.diagnostics[1].msg:find(nativePath, 1, true), result.diagnostics[1].msg)
end

function M.sessionKeysCDeclarationsIndependentOfOrder()
    local before = table.concat(
        {
            "cdef function hot_first(value: int32): int32",
            "cdef function hot_second(value: int32): int32",
            "local function value(n: int32): int32 return hot_first(n) end",
            "return value",
        },
        "\n"
    )
    local after = table.concat(
        {
            "cdef function hot_second(value: int32): int32",
            "cdef function hot_first(value: int32): int32",
            "local function value(n: int32): int32 return hot_first(n) end",
            "return value",
        },
        "\n"
    )
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)

    write(path, after)
    session:diskChanged(path, 2)
    testAssert.eq(session:prepare({path}).kind, "no-change", "declaration order is not part of keyed C ABI semantics")
end

function M.sessionKeysCFunctionsByDecodedLibraryAndSymbol()
    local before = table.concat(
        {
            "cdef function hot_library_value(): int32 from 'hot-one'",
            "local function value(): int32 return 1 end",
            "return value",
        },
        "\n"
    )
    local equivalent = before:gsub("'hot%-one'", '"hot-one"')
    local changed = equivalent:gsub('"hot%-one"', '"hot-two"')
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)

    write(path, equivalent)
    session:diskChanged(path, 2)
    testAssert.eq(session:prepare({path}).kind, "no-change", "equivalent library literal spelling changes C identity")

    write(path, changed)
    session:diskChanged(path, 3)
    local result = session:prepare({path})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "c-declaration")
    testAssert.eq(result.reason.dependency, "hot_library_value")
end

function M.sessionRejectsNewCUseMissingFromTheRunningModule()
    local before = table.concat({"local function value(n: int32): int32 return n end", "return value",}, "\n")
    local after = table.concat(
        {
            "local function value(n: int32): int32",
            "   cdef function hot_late(value: int32): int32",
            "   return hot_late(n)",
            "end",
            "return value",
        },
        "\n"
    )
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)

    write(path, after)
    session:diskChanged(path, 2)
    local result = session:prepare({path})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "c-declaration")
    testAssert.eq(result.reason.dependency, "hot_late")
end

function M.sessionKeepsRawFfiDeclarationsOnTheConservativeFallback()
    local before = table.concat(
        {
            "local ffi = require('ffi')",
            "local function declare(): nil",
            "   ffi.cdef('int hot_raw(int value);')",
            "end",
            "return declare",
        },
        "\n"
    )
    local after = before:gsub("int hot_raw", "long hot_raw")
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)

    write(path, after)
    session:diskChanged(path, 2)
    local result = session:prepare({path})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "c-declaration")
    testAssert.eq(result.reason.identity, "<module-wide C fallback>")
end

function M.sessionTracksDeriveProviderFilesystemInputs()
    local source = table.concat(
        {
            "local M = {}",
            "interface M.Labelled",
            "   label: function(self): string",
            "end",
            "function M.labelValue(value: string): string return value end",
            "@comptime function M.derive(info: types.derive.Info): types.derive.Result<M.Labelled>",
            "   local label = types.derive.file('schema.txt')",
            "   return types.derive.implement{methods = {",
            "      label = types.derive.forward{helper = types.derive.helper(M, 'labelValue'), arguments = {types.derive.constant(label)}},",
            "   }}",
            "end",
            "@derive(M.derive)",
            "record M.Value",
            "   value: integer",
            "end",
            "return M",
        },
        "\n"
    )
    local dir = temporaryProject({["schema.txt"] = "version one", ["main.nupp"] = source})
    local path = dir .. "/main.nupp"
    local inputPath = require("nupp.compiler.fs").canonical(dir .. "/schema.txt")
    local session = loadedCompilerSession(dir, path)
    local observed = false
    for _, input in ipairs(session:watchedInputs()) do
        if input.path == inputPath and input.kind == "provider-file" then
            observed = true
        end
    end
    assert(observed, "provider filesystem input joins the dynamic watch set")

    write(inputPath, "version two")
    session:diskChanged(inputPath, 2)
    local result = session:prepare({inputPath})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "provider-input")
    testAssert.eq(result.reason.dependency, "schema.txt")
    testAssert.eq(result.reason.path, inputPath)
end

function M.deriveProviderFilesystemInputsRequireLiteralPaths()
    local source = table.concat(
        {
            "local M = {}",
            "interface M.Contract",
            "   value: function(self): string",
            "end",
            "function M.value(): string return 'value' end",
            "@comptime function M.derive(info: types.derive.Info): types.derive.Result<M.Contract>",
            "   local path = 'schema.txt'",
            "   local schema = types.derive.file(path)",
            "   return types.derive.implement{methods = {value = types.derive.forward{helper = types.derive.helper(M, 'value'), arguments = {}}}}",
            "end",
            "@derive(M.derive)",
            "record M.Value end",
            "return M",
        },
        "\n"
    )
    local dir = temporaryProject({["schema.txt"] = "value", ["main.nupp"] = source})
    local session = hotSession.new(dir, {cache = false})
    local result = session:initial({dir .. "/main.nupp"})
    testAssert.eq(result.kind, "diagnostics")
    testAssert.eq(result.diagnostics[1].code, "NUPP2810")
    assert(result.diagnostics[1].msg:find("string literal", 1, true), result.diagnostics[1].msg)
end

function M.deriveProviderFilesystemInputsStayInsideTheProject()
    local source = table.concat(
        {
            "local M = {}",
            "interface M.Contract",
            "   value: function(self): string",
            "end",
            "function M.value(): string return 'value' end",
            "@comptime function M.derive(info: types.derive.Info): types.derive.Result<M.Contract>",
            "   local schema = types.derive.file('../outside.txt')",
            "   return types.derive.implement{methods = {value = types.derive.forward{helper = types.derive.helper(M, 'value'), arguments = {}}}}",
            "end",
            "@derive(M.derive)",
            "record M.Value end",
            "return M",
        },
        "\n"
    )
    local dir = temporaryProject({["main.nupp"] = source})
    local session = hotSession.new(dir, {cache = false})
    local result = session:initial({dir .. "/main.nupp"})
    testAssert.eq(result.kind, "diagnostics")
    local escaped
    for _, diagnostic in ipairs(result.diagnostics) do
        if diagnostic.code == "NUPP2810" and diagnostic.msg:find("escapes the project root", 1, true) then
            escaped = diagnostic
        end
    end
    assert(escaped, "project-escaping derive.file did not report NUPP2810")
end

function M.sessionNamesTheAffineCaptureThatRequiresRestart()
    local before = table.concat(
        {
            "local record Resource",
            "   value: integer",
            "end",
            "local function closeResource(takes resource: Resource): nil end",
            "local function openResource(): affine(Resource, closeResource)",
            "   return new Resource(value = 7)",
            "end",
            "local resource = openResource()",
            "local function read(): integer takes (resource)",
            "   return resource.value",
            "end",
            "return read()",
        },
        "\n"
    )
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)

    write(path, before:gsub("return resource.value", "return resource.value + 1"))
    session:diskChanged(path, 2)
    local result = session:prepare({path})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "affine-capture")
    testAssert.eq(result.reason.capture, "resource")
    assert(result.diagnostics[1].msg:find("capture resource", 1, true), result.diagnostics[1].msg)
    assert(result.diagnostics[1].msg:find("main/module/local/read", 1, true), result.diagnostics[1].msg)
end

function M.sessionIgnoresUnrelatedDeclarationChanges()
    local dir = temporaryProject({
        ["globals.nupp"] = table.concat({"global type Watched = number", "global type Unused = number",}, "\n"),
        ["main.nupp"] = "local value: Watched = 1\nreturn value\n",
    })
    local mainPath = dir .. "/main.nupp"
    local globalsPath = dir .. "/globals.nupp"
    local session = loadedCompilerSession(dir, mainPath)

    write(globalsPath, table.concat({"global type Watched = number", "global type Unused = string",}, "\n"))
    session:diskChanged(globalsPath, 2)
    local result = session:prepare({globalsPath})
    testAssert.eq(result.kind, "no-change", "unobserved declarations stop at the query boundary")
end

function M.sessionObservesHeaderSemanticsAndIgnoresComments()
    local dir = temporaryProject({
        ["api.h"] = "int hot_header_value(void);\n",
        [
            "main.nupp"
        ] = table.concat(
            {
                "local api = cheader('api.h')",
                "local function value(): integer return api.hot_header_value() end",
                "return value",
            },
            "\n"
        ),
    })
    local sourcePath = dir .. "/main.nupp"
    local headerPath = dir .. "/api.h"
    local session = loadedCompilerSession(dir, sourcePath)
    local watched = {}
    for _, input in ipairs(session:watchedInputs()) do
        watched[input.path] = input.kind
    end
    local absoluteHeader = require("nupp.compiler.fs").canonical(headerPath)
    testAssert.eq(watched[absoluteHeader], "header", "direct header joins the watch set")

    write(headerPath, "/* spelling only */\nint hot_header_value(void);\n")
    session:diskChanged(absoluteHeader, 2)
    testAssert.eq(
        session:prepare({
            absoluteHeader
        }).kind,
        "no-change",
        "comment-only header edit has the same declarations"
    )

    write(headerPath, "long hot_header_value(void);\n")
    session:diskChanged(absoluteHeader, 2)
    local changed = session:prepare({absoluteHeader})
    testAssert.eq(changed.kind, "restart-required")
    testAssert.eq(changed.reason.kind, "header-abi")
    testAssert.eq(changed.reason.path, absoluteHeader)
    assert(changed.diagnostics[1].msg:find("api.h", 1, true), changed.diagnostics[1].msg)
end

function M.sessionTracksPreprocessedHeaderClosure()
    if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").suite.skip("cc is unavailable")
    end
    local dir = temporaryProject({
        ["nested.h"] = "typedef int hot_nested_value;\n",
        ["api.h"] = '#include "nested.h"\nhot_nested_value hot_nested(void);\n',
        [
            "main.nupp"
        ] = table.concat(
            {
                "local api = cheader('api.h', nil, 'preprocess')",
                "local function value(): integer return api.hot_nested() end",
                "return value",
            },
            "\n"
        ),
    })
    local sourcePath = dir .. "/main.nupp"
    local nestedPath = require("nupp.compiler.fs").canonical(dir .. "/nested.h")
    local session = loadedCompilerSession(dir, sourcePath)
    local found = false
    for _, input in ipairs(session:watchedInputs()) do
        if input.path == nestedPath then
            found = true
        end
    end
    assert(found, "nested preprocessor input joins the watch set")
    write(nestedPath, "typedef long hot_nested_value;\n")
    session:diskChanged(nestedPath, 2)
    local result = session:prepare({nestedPath})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "header-abi")
end

function M.sessionPinsAndObservesMappedNativeArtifacts()
    local dir = temporaryProject({
        ["libmini.bin"] = "generation one",
        ["nupp.lua"] = "return { hotreload = { libraries = { mini = 'libmini.bin' } } }\n",
        [
            "main.nupp"
        ] = table.concat(
            {
                "cdef function hot_mini_value(): int32 from 'mini'",
                "local function value(): number return hot_mini_value() end",
                "return value",
            },
            "\n"
        ),
    })
    local sourcePath = dir .. "/main.nupp"
    local artifactPath = require("nupp.compiler.fs").absolute(dir .. "/libmini.bin")
    local session = hotSession.new(dir, {cache = false})
    local built = session:initial({sourcePath})
    testAssert.eq(built.kind, "initial")
    session:loaded(built.entryManifest.module, 1, built.entryManifest)
    -- The spelling generation pins, asked of the session rather than written again
    -- here: a project directory reached through a link or a short name resolves to
    -- something other than its own absolute spelling, and on Windows most temporary
    -- directories are short names. The edits below stay on the configured spelling,
    -- which is what a change is reported against.
    local pinnedPath = nil
    for _, input in ipairs(session:watchedInputs()) do
        if input.kind == "native-artifact" then
            pinnedPath = input.path
        end
    end
    assert(pinnedPath, "mapped artifact joins the watch set")
    assert(built.entryCode:find(pinnedPath, 1, true), "watch generation loads the artifact it pins")
    write(artifactPath, "generation two")
    session:diskChanged(artifactPath, 2)
    local result = session:prepare({artifactPath})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "native-artifact")
    testAssert.eq(result.reason.path, artifactPath)
    assert(os.remove(artifactPath))
    session:diskChanged(artifactPath, 3)
    local missing = session:prepare({artifactPath})
    testAssert.eq(missing.kind, "restart-required")
    testAssert.eq(missing.reason.kind, "native-artifact")
end

function M.sessionReportsUnmappedNativeIdentityOnce()
    local dir = temporaryProject({
        ["main.nupp"] = "cdef function hot_unverified(): int32 from 'bare'\nreturn hot_unverified\n",
    })
    local path = dir .. "/main.nupp"
    local session = hotSession.new(dir, {cache = false})
    local built = session:initial({path})
    local first = session:loaded(built.entryManifest.module, 1, built.entryManifest)
    testAssert.eq(first.unverifiedLibraries[1], "bare")
end

function M.headerWatchPathsCollapseDuplicateSpellingsButKeepConsumers()
    local dir = temporaryProject({
        ["api.h"] = "int hot_duplicate(void);\n",
        [
            "main.nupp"
        ] = table.concat(
            {
                "local first = cheader('api.h')",
                "local second = cheader('./api.h')",
                "local function value(): number return first.hot_duplicate() + second.hot_duplicate() end",
                "return value",
            },
            "\n"
        ),
    })
    local session = loadedCompilerSession(dir, dir .. "/main.nupp")
    local headerPath = require("nupp.compiler.fs").canonical(dir .. "/api.h")
    local watchedCount = 0
    for _, input in ipairs(session:watchedInputs()) do
        if input.path == headerPath then
            watchedCount = watchedCount + 1
        end
    end
    testAssert.eq(watchedCount, 1, "canonical header path is polled once")
    local manifest = session.running.main
    local consumers = 0
    for _, input in pairs(manifest.abi.inputs) do
        if input.kind == "header" and input.sourcePath == headerPath then
            consumers = consumers + 1
        end
    end
    testAssert.eq(consumers, 2, "each cheader site retains its consumer record")
end

function M.deletedHeaderRejectsWithoutLosingTheRunningManifest()
    local dir = temporaryProject({
        ["api.h"] = "int hot_deleted(void);\n",
        ["main.nupp"] = "local api = cheader('api.h')\nreturn api.hot_deleted\n",
    })
    local path = dir .. "/main.nupp"
    local headerPath = require("nupp.compiler.fs").canonical(dir .. "/api.h")
    local session = loadedCompilerSession(dir, path)
    assert(os.remove(headerPath))
    session:diskChanged(headerPath, 3)
    local result = session:prepare({headerPath})
    testAssert.eq(result.kind, "diagnostics")
    testAssert.eq(result.diagnostics[1].code, "NUPP2302")
    local retained = false
    for _, input in ipairs(session:watchedInputs()) do
        if input.path == headerPath then
            retained = true
        end
    end
    assert(retained, "the missing retained input remains watched")
end

function M.unloadedModuleDoesNotObserveItsHeader()
    local dir = temporaryProject({
        ["later.h"] = "int hot_later(void);\n",
        ["later.nupp"] = "local api = cheader('later.h')\nreturn api.hot_later\n",
        ["main.nupp"] = "local function main(): integer return 1 end\nreturn main\n",
    })
    local session = loadedCompilerSession(dir, dir .. "/main.nupp")
    local headerPath = require("nupp.compiler.fs").canonical(dir .. "/later.h")
    for _, input in ipairs(session:watchedInputs()) do
        assert(input.path ~= headerPath, "an unloaded module must not contribute external inputs")
    end
end

function M.mappedFfiLoadChangesOnlyWatchGeneration()
    local source = "local ffi = require('ffi')\nreturn ffi.load('mini')\n"
    local result = checked(source)
    local ordinary = assert(gen.generate(result, "ffi-load.nupp"))
    local mapped = "/tmp/nupp-exact-mini-library"
    local watched = assert(
        gen.generate(result, "ffi-load.nupp", nil, {
            mode = "initial",
            module = "ffi-load",
            libraries = {mini = mapped},
        })
    )
    assert(ordinary:find("'mini'", 1, true), ordinary)
    assert(not ordinary:find(mapped, 1, true), ordinary)
    assert(watched:find(mapped, 1, true), watched)
end

function M.mappedNativeSymlinkRetargetRequiresRestart()
    if package.config:sub(1, 1) == "\\" then
        return require("assert").suite.skip("symbolic-link fixture is POSIX-only")
    end
    local dir = temporaryProject({
        ["one.bin"] = "identical bytes",
        ["two.bin"] = "identical bytes",
        ["nupp.lua"] = "return { hotreload = { libraries = { mini = 'current.bin' } } }\n",
        ["main.nupp"] = "cdef function hot_symlink(): int32 from 'mini'\nreturn hot_symlink\n",
    })
    testAssert.eq(os.execute(("ln -s '%s/one.bin' '%s/current.bin'"):format(dir, dir)), 0)
    local session = hotSession.new(dir, {cache = false})
    local built = session:initial({dir .. "/main.nupp"})
    local firstTarget = require("nupp.compiler.fs").absolute(dir .. "/one.bin")
    assert(built.entryCode:find(firstTarget, 1, true), "watch generation pins the resolved target")
    session:loaded(built.entryManifest.module, 1, built.entryManifest)
    assert(os.remove(dir .. "/current.bin"))
    testAssert.eq(os.execute(("ln -s '%s/two.bin' '%s/current.bin'"):format(dir, dir)), 0)
    local link = require("nupp.compiler.fs").absolute(dir .. "/current.bin")
    session:diskChanged(link, 2)
    local result = session:prepare({link})
    testAssert.eq(result.kind, "restart-required")
    testAssert.eq(result.reason.kind, "native-artifact")
end

function M.headerDependencyClosureGrowsAndShrinksAfterNoChange()
    if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").suite.skip("cc is unavailable")
    end
    local withInclude = '#include "nested.h"\nint hot_closure(void);\n'
    local dir = temporaryProject({
        ["nested.h"] = "/* contributes no declarations */\n",
        ["api.h"] = withInclude,
        ["main.nupp"] = "local api = cheader('api.h', nil, 'preprocess')\nreturn api.hot_closure\n",
    })
    local sourcePath = dir .. "/main.nupp"
    local fs = require("nupp.compiler.fs")
    local apiPath = fs.canonical(dir .. "/api.h")
    local nestedPath = fs.canonical(dir .. "/nested.h")
    local session = loadedCompilerSession(dir, sourcePath)

    local function isWatched(path)
        for _, input in ipairs(session:watchedInputs()) do
            if input.path == path then
                return true
            end
        end

        return false
    end

    assert(isWatched(nestedPath), "initial include is watched")
    write(apiPath, "int hot_closure(void);\n")
    session:diskChanged(apiPath, 2)
    testAssert.eq(session:prepare({apiPath}).kind, "no-change")
    assert(not isWatched(nestedPath), "removed include leaves the dynamic watch set")
    write(apiPath, withInclude)
    session:diskChanged(apiPath, 2)
    testAssert.eq(session:prepare({apiPath}).kind, "no-change")
    assert(isWatched(nestedPath), "new include joins the dynamic watch set")
end

-- The host-driven surface: what `nupp.tools.hostreload` answers is what the C
-- functions behind it return, so these cases are the reload verdicts a host sees.

local hostreloadModule = require("nupp.tools.hostreload")

local function hostProject(source)
    hot.resetForTesting()
    local dir = temporaryProject({["main.nupp"] = source})
    local session, failure = hostreloadModule.open("main.nupp", dir)
    assert(session, tostring(failure))

    return session, dir, dir .. "/main.nupp"
end

function M.watchInstallsOnlyThePublicDebugReloadTable()
    local session = hostProject("return {}\n")
    assert(type(debug.reload) == "table", "watch installs the public reload table")
    assert(type(debug.reload.generation) == "function" and type(debug.reload.poll) == "function")
    assert(nupp.hotreload == nil, "watch does not install the retired public namespace")
    testAssert.eq(debug.reload.generation(), 1)
    testAssert.eq(debug.reload.poll().kind, "no-change")
    session.close(true)
end

function M.publicPollDoesNotPublishPrivateTransactionFields()
    local session, _, path = hostProject("local function update(): integer return 41 end\nreturn {update = update}\n")
    local unchanged = debug.reload.poll()
    testAssert.eq(unchanged.kind, "no-change")
    testAssert.eq(unchanged.baseGeneration, nil)
    testAssert.eq(unchanged.basegeneration, nil)

    write(path, "local function update(): integer return 42 end\nreturn {update = update}\n")
    local committed = debug.reload.poll()
    testAssert.eq(committed.kind, "prepared")
    testAssert.eq(committed.generation, 2)
    testAssert.eq(committed.baseGeneration, nil, "the public result does not expose private transaction metadata")
    testAssert.eq(committed.basegeneration, nil, "the optional field remains absent for the current producer")
    session.close(true)
end

function M.hostSessionCommitsAnEditThroughARetainedMember()
    local session, _, path = hostProject("local function update(): integer return 41 end\nreturn {update = update}\n")
    local update = session.member("update")
    testAssert.eq(update(), 41, "the member answers before the edit")
    write(path, "local function update(): integer return 42 end\nreturn {update = update}\n")
    local verdict, generation, message = session.poll()
    session.close(true)
    testAssert.eq(verdict, "committed")
    testAssert.eq(generation, 2)
    testAssert.eq(message, nil)
    testAssert.eq(update(), 42, "the retained member reaches the new body")
end

function M.hostSessionReportsNoChangeWhenNothingMoved()
    local session = hostProject("local function update(): integer return 1 end\nreturn {update = update}\n")
    local verdict, generation = session.poll()
    session.close(true)
    testAssert.eq(verdict, "no-change")
    testAssert.eq(generation, 1)
end

function M.hostSessionRejectionKeepsTheRunningGeneration()
    local session, _, path = hostProject("local function update(): integer return 1 end\nreturn {update = update}\n")
    local update = session.member("update")
    write(path, "local function update(): integer return \"two\" end\nreturn {update = update}\n")
    local verdict, generation, message = session.poll()
    session.close(true)
    testAssert.eq(verdict, "rejected")
    testAssert.eq(generation, 1, "the running generation is what stays running")
    assert(message and message:find("NUPP", 1, true), "the refusal names its diagnostic: " .. tostring(message))
    testAssert.eq(update(), 1, "the member still answers from the generation that checked")
end

function M.hostSessionReportsStructuralChangesAsRestartRequired()
    local session, _, path = hostProject("local function update(): integer return 1 end\nreturn {update = update}\n")
    write(
        path,
        "local added: integer = 2\nlocal function update(): integer return added end\nreturn {update = update}\n"
    )
    local verdict, generation, message = session.poll()
    session.close(true)
    testAssert.eq(verdict, "restart-required")
    testAssert.eq(generation, 1)
    assert(message and message:find("NUPP5001", 1, true), "the restart names its diagnostic: " .. tostring(message))
end

function M.hostSessionRefusesAnEntryThatDoesNotCheck()
    hot.resetForTesting()
    local dir = temporaryProject({
        ["main.nupp"] = "local function update(): integer return \"one\" end\nreturn update\n"
    })
    local session, failure = hostreloadModule.open("main.nupp", dir)
    testAssert.eq(session, nil, "an entry that does not check opens nothing")
    assert(failure and failure:find("NUPP", 1, true), "the failure names its diagnostic: " .. tostring(failure))
end

function M.hostSessionRefusesASecondSessionAndReopensAfterClose()
    local session, dir = hostProject("local function update(): integer return 1 end\nreturn {update = update}\n")
    local update = session.member("update")
    local second, why = hostreloadModule.open("main.nupp", dir)
    testAssert.eq(second, nil, "one registry means one session")
    assert(why and why:find("already open", 1, true), tostring(why))
    session.close(true)
    local reopened, failure = hostreloadModule.open("main.nupp", dir)
    assert(reopened, tostring(failure))
    testAssert.eq(update(), 1, "the closed session's values keep working")
    reopened.close(true)
end

function M.hostSessionNamesAnEntryItCannotRead()
    hot.resetForTesting()
    local dir = temporaryProject({})
    local session, failure = hostreloadModule.open("absent.nupp", dir)
    testAssert.eq(session, nil)
    assert(
        failure and failure:find("NUPP0001", 1, true),
        "an unreadable entry reports a diagnostic: " .. tostring(failure)
    )
end

function M.aPatchDoesNotDisturbTheLoadedModuleTable()
    -- A patch runs the module's top level again to build candidates over the same
    -- cells. It is not a module load: writing `package.loaded` there would unload the
    -- running module, and the next `require` would register its slots a second time.
    local source = "module patched\n\nlocal patched = {}\n\n"
        .. "function patched.answer(): integer return 1 end\n\nexport = patched\n"
    local dir = temporaryProject({["patched.nupp"] = source})
    local path = dir .. "/patched.nupp"
    hot.resetForTesting()
    package.loaded.patched = nil
    local session = hotSession.new(dir, {cache = false})
    local built = assert(session:compile(path, "initial", "patched"))
    local api = assert(loadstring(built.code, "@" .. path))("patched")
    hot.seal("patched")
    session:loaded("patched", 1, built.manifest)
    testAssert.eq(package.loaded.patched, api, "the initial load publishes the module")

    write(path, (source:gsub("return 1", "return 2")))
    session:diskChanged(path, 2)
    local prepared = session:prepare({path})
    testAssert.eq(prepared.kind, "prepared")
    assert(not prepared.patch:match([[package%.loaded[%w%._%[%]"']*%s*=]]), "a patch does not write the loaded table")
    local staged, reason = hot.stage(prepared.patch, prepared.baseGeneration)
    assert(staged, reason)
    testAssert.eq(package.loaded.patched, api, "staging leaves the running module loaded")
    testAssert.eq(hot.commit(staged), 2)
    session:committed(2)
    testAssert.eq(package.loaded.patched, api, "committing leaves the running module loaded")
    testAssert.eq(require("patched"), api, "requiring it again is the same table, not a second load")
    testAssert.eq(api.answer(), 2, "and it answers from the committed generation")
    package.loaded.patched = nil
end

return M
