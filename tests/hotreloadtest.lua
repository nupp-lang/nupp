-- Hot reload on the VM: the compiler session that matches a changed module's
-- functions to the running ones, the runtime's body patch (`vm.hotPatch`), and
-- `nupp run --watch` around both. Session cases run on any host, since they only
-- check and lower; the cases that load and patch code need the VM, and the
-- command cases need a launcher whose CLI runs on it.

local testAssert = require("nupp.test")
local hotSession = require("nupp.tools.hotsession")

local loadImage = rawget(_G, "__nupp_load_image")
local hotPatch = rawget(_G, "__nupp_hot_patch")

local M = {}

local function temporaryProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    for name, source in pairs(files) do
        local parent = (dir .. "/" .. name):match("^(.*)/")
        assert(os.execute("mkdir -p '" .. parent .. "'"))
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

local function readFile(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()

    return text
end

local function loadedCompilerSession(dir, path)
    local session = hotSession.new(dir, {cache = false})
    local initialBuild = session:initial({path})
    if initialBuild.kind ~= "initial" then
        local messages = {}
        for _, diagnostic in ipairs(initialBuild.diagnostics or {}) do
            messages[#messages + 1] = tostring(diagnostic.code) .. ": " .. tostring(diagnostic.msg)
        end
        error("initial hot build failed: " .. table.concat(messages, "; "), 2)
    end
    session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)

    return session
end

-- A one-module program running on this VM under a session: what its chunk
-- returned, and the state `commit` and `edit` work on.
local function running(source, module)
    if not loadImage or not hotPatch then
        return nil, require("assert").skip("loading and patching code needs the VM")
    end
    module = module or "main"
    local dir = temporaryProject({[module .. ".nupp"] = source})
    local path = dir .. "/" .. module .. ".nupp"
    local session = hotSession.new(dir, {cache = false})
    local initialBuild = session:initial({path})
    testAssert.equal(initialBuild.kind, "initial", "initial build")
    local chunk = assert(loadImage(initialBuild.entryCode))
    local value = chunk()
    session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)

    return value, {session = session, path = path, dir = dir, module = initialBuild.entryManifest.module}
end

-- Writes a new version of the module and prepares it.
local function edit(state, source)
    write(state.path, source)
    state.session:diskChanged(state.path, 2)

    return state.session:prepare({state.path})
end

-- Prepares and commits a new version, the way `poll` does.
local function commit(state, source)
    local prepared = edit(state, source)
    if prepared.kind ~= "prepared" then
        error("expected a prepared patch, got " .. tostring(prepared.kind) .. ": "
            .. tostring(prepared.diagnostics and prepared.diagnostics[1] and prepared.diagnostics[1].msg), 2)
    end
    for _, patch in ipairs(prepared.patches) do
        assert(hotPatch(patch, true))
    end
    local report
    for _, patch in ipairs(prepared.patches) do
        report = assert(hotPatch(patch))
    end
    state.session:committed(prepared.generation)

    return report, prepared
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
    local api, state = running(before)
    if not api then
        return
    end
    local retained = api.advance
    testAssert.equal(retained(1), 2, "initial implementation")
    local report = commit(state, (before:gsub("value = value %+ by", "value = value + by * 2")))
    testAssert.equal(report.changed, 1, "one body changed")
    testAssert.equal(api.advance, retained, "public function identity")
    testAssert.equal(retained(1), 4, "patched implementation shares old value cell")
    testAssert.equal(state.session.generation, 2, "committed generation")
end

function M.anonymousClosuresArePatchIdentities()
    local before = table.concat(
        {
            "local handlers: {function(): integer} = {}",
            "local function register(handler: function(): integer): nil",
            "   handlers[#handlers + 1] = handler",
            "end",
            "register(function(): integer return 1 end)",
            "local function make(): function(): integer",
            "   return function(): integer return 10 end",
            "end",
            "return {handlers = handlers, made = make()}",
        },
        "\n"
    )
    local api, state = running(before)
    if not api then
        return
    end
    testAssert.equal(api.handlers[1](), 1)
    testAssert.equal(api.made(), 10)
    local after = before:gsub("return 1 end%)", "return 2 end)"):gsub("return 10 end", "return 20 end")
    local report = commit(state, after)
    testAssert.equal(report.changed, 2, "both closures changed")
    testAssert.equal(api.handlers[1](), 2, "a registered top-level closure takes its new body")
    testAssert.equal(api.made(), 20, "a closure made before the commit takes its new body")
end

function M.aChangedBodyMayAddAClosure()
    local before = table.concat(
        {
            "local function compute(): integer",
            "   return 1",
            "end",
            "return compute",
        },
        "\n"
    )
    local compute, state = running(before)
    if not compute then
        return
    end
    local after = table.concat(
        {
            "local function compute(): integer",
            "   local twice = function(n: integer): integer return n * 2 end",
            "   return twice(21)",
            "end",
            "return compute",
        },
        "\n"
    )
    local report = commit(state, after)
    testAssert.equal(report.added, 1, "the new closure is added")
    testAssert.equal(compute(), 42)
end

function M.rejectedCaptureChangeLeavesOldGenerationRunning()
    local before = table.concat(
        {"local value: integer = 3", "local function read(): integer", "   return value", "end", "return read",},
        "\n"
    )
    local retained, state = running(before)
    if not retained then
        return
    end
    local result = edit(
        state,
        table.concat(
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
    )
    testAssert.equal(result.kind, "restart-required", "capture-changing edit is refused")
    testAssert.equal(result.diagnostics[1].code, "NUPP5001")
    testAssert.equal(state.session.generation, 1, "refusal does not publish a generation")
    testAssert.equal(retained(), 3, "old implementation remains callable")
end

function M.sessionRefusesSignatureDeclarationAndLayoutChanges()
    -- Nothing here is exported, so each refusal is the session's own rather than a
    -- changed module interface.
    local before = table.concat(
        {
            "local record Point",
            "   x: number",
            "end",
            "local function size(p: Point): number",
            "   return p.x",
            "end",
            "local function measure(): number",
            "   return size(new Point(x = 1))",
            "end",
            "print(measure())",
        },
        "\n"
    )
    local cases = {
        {
            (before:gsub("p: Point%): number", "p: Point, scale: number): number"):gsub("size%(new Point%(x = 1%)%)", "size(new Point(x = 1), 2)")),
            "callable-abi",
            "callable signature changed: size",
        },
        {before .. "\nlocal function extra(): integer return 1 end", "reloadable-declaration", "reloadable declaration was added: extra"},
        {(before:gsub("   x: number", "   x: number\n   y: number?")), "record-layout", "record layout changed in main"},
    }
    for _, case in ipairs(cases) do
        local dir = temporaryProject({["main.nupp"] = before})
        local path = dir .. "/main.nupp"
        local session = loadedCompilerSession(dir, path)
        write(path, case[1])
        session:diskChanged(path, 2)
        local result = session:prepare({path})
        testAssert.equal(result.kind, "restart-required", case[3])
        testAssert.equal(result.reason.kind, case[2], case[3])
        assert(result.diagnostics[1].msg:find(case[3], 1, true), result.diagnostics[1].msg)
    end
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
    local retained, state = running(before)
    if not retained then
        return
    end
    testAssert.equal(retained(3), 6, "initial recursion")
    commit(state, (before:gsub("then return 0 end", "then return 1 end")))
    testAssert.equal(retained(3), 7, "replacement self recursion stays on replacement")
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
    local api, state = running(before)
    if not api then
        return
    end
    commit(state, (before:gsub("if n == 0 then return false end", "if n == 0 then return true end")))
    testAssert.equal(api.even(1), true, "unchanged partner calls the patched odd")
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
            "local function make(value: integer): Counter return new Counter(value = value) end",
            "return {Counter = Counter, make = make}",
        },
        "\n"
    )
    local api, state = running(before)
    if not api then
        return
    end
    local instance = api.make(3)
    local retained = instance.add
    testAssert.equal(instance:add(2), 5)
    commit(state, (before:gsub("self.value %+ by", "self.value + by * 2")))
    testAssert.equal(instance.add, retained, "record method identity")
    testAssert.equal(instance:add(2), 7, "record method replacement")
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
    local retained, state = running(before)
    if not retained then
        return
    end
    local report = nil
    local oldResult = retained(function()
        report = commit(state, (before:gsub("return 1", "return 2")))
    end)
    assert(report, "the callback committed")
    testAssert.equal(report.retained, 1, "the running activation is retained")
    testAssert.equal(oldResult, 1, "active call finishes on the body it entered")
    testAssert.equal(
        retained(function()
        end),
        2,
        "future calls enter the replacement"
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
    local api, state = running(before)
    if not api then
        return
    end
    local result = edit(
        state,
        table.concat(
            {
                "local captured: integer = 4",
                "local function first(): integer return 10 end",
                "local function second(): integer return 2 + captured end",
                "return {first = first, second = second}",
            },
            "\n"
        )
    )
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(api.first(), 1, "earlier valid candidate was not published")
    testAssert.equal(api.second(), 2, "failing candidate was not published")
end

function M.theRuntimeRefusesWhatTheSessionMissed()
    local before = "local function value(): integer return 1 end\nreturn value"
    local retained, state = running(before)
    if not retained then
        return
    end
    local prepared = edit(state, (before:gsub("return 1", "return 2")))
    testAssert.equal(prepared.kind, "prepared")
    -- The same patch against a module this VM never loaded.
    local stray = prepared.patches[1]:gsub("^patch %S+", "patch nupp-hot-never-loaded")
    local accepted, reason = hotPatch(stray, true)
    testAssert.equal(accepted, nil)
    assert(tostring(reason):find("is not loaded", 1, true), tostring(reason))
    testAssert.equal(retained(), 1, "a refused patch changes nothing")
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
    local session = loadedCompilerSession(dir, path)
    write(path, (before:gsub("value = value %+ by", "value = value + by * 2")))
    session:diskChanged(path, 2)
    local prepared = session:prepare({path})
    testAssert.equal(prepared.kind, "prepared")
    testAssert.equal(#prepared.patches, 1, "one module changed")
    assert(prepared.patches[1]:find("^patch main\nmap 0 1 2\n"), prepared.patches[1]:sub(1, 80))
    testAssert.equal(session.generation, 1, "prepare does not advance compiler baseline")
    session:committed(2)
    testAssert.equal(session.generation, 2)
end

function M.movedLinesAreNoChange()
    local before = "local function value(): integer\n   return 1\nend\nreturn value"
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)
    write(path, "-- a comment\n\n" .. before)
    session:diskChanged(path, 2)
    testAssert.equal(session:prepare({path}).kind, "no-change")
end

function M.sessionSkipsUnloadedChangedModules()
    local dir = temporaryProject({
        ["main.nupp"] = "local function main(): integer return 1 end\nreturn main",
        ["later.nupp"] = "local function later(): integer return 1 end\nreturn later",
    })
    local mainPath = dir .. "/main.nupp"
    local laterPath = dir .. "/later.nupp"
    local session = loadedCompilerSession(dir, mainPath)
    write(laterPath, "local function later(): integer return 2 end\nreturn later")
    session:diskChanged(laterPath, 2)
    local result = session:prepare({laterPath})
    testAssert.equal(result.kind, "no-change", "an unloaded module has no running code to patch")
end

function M.sessionReportsStructuralChangesAsRestartRequired()
    local before = "local function value(): integer return 1 end\nreturn value"
    local dir = temporaryProject({["main.nupp"] = before})
    local path = dir .. "/main.nupp"
    local session = loadedCompilerSession(dir, path)
    write(path, "local added: integer = 2\n" .. before)
    session:diskChanged(path, 2)
    local result = session:prepare({path})
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.diagnostics[1].code, "NUPP5001")
    testAssert.equal(result.reason.kind, "source-structure")
    testAssert.equal(result.reason.dependency, "main")
    testAssert.equal(result.reason.path, path)
end

function M.sessionRestartsBeforeAChangedSoALayoutCanReachLiveStorage()
    local before = table.concat(
        {
            "local soa = require('nupp.mem.soa')",
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.diagnostics[1].code, "NUPP5001")
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
    testAssert.equal(result.kind, "diagnostics", "dependent is type-checked before patching")
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.diagnostics[1].code, "NUPP5001")
    testAssert.equal(result.reason.kind, "project-declaration")
    testAssert.equal(result.reason.dependency, "Watched")
    testAssert.equal(result.reason.path, globalsPath)
    testAssert.equal(result.reason.consumer, "main")
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
        testAssert.equal(result.kind, guarded and "diagnostics" or "no-change")
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "module-interface")
    testAssert.equal(result.reason.dependency, "dependency")
    testAssert.equal(result.reason.path, dependencyPath)
    testAssert.equal(result.reason.consumer, "main")
    assert(result.diagnostics[1].msg:find("module interface dependency", 1, true), result.diagnostics[1].msg)
    assert(result.diagnostics[1].msg:find(dependencyPath, 1, true), result.diagnostics[1].msg)
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.diagnostics[1].code, "NUPP5001")
    testAssert.equal(result.reason.kind, "c-declaration")
    testAssert.equal(result.reason.dependency, "hot_point")
    testAssert.equal(result.reason.path, nativePath)
    testAssert.equal(result.reason.consumer, "main")
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
    -- Order is not part of the keyed C comparison. On the VM a top-level
    -- declaration is also a statement the module's top level runs, so moving one
    -- is still a top-level change.
    local result = session:prepare({path})
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "source-structure", "declaration order is not part of keyed C ABI semantics")
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
    testAssert.equal(
        session:prepare({
            path
        }).kind,
        "no-change",
        "equivalent library literal spelling changes C identity"
    )

    write(path, changed)
    session:diskChanged(path, 3)
    local result = session:prepare({path})
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "c-declaration")
    testAssert.equal(result.reason.dependency, "hot_library_value")
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "c-declaration")
    testAssert.equal(result.reason.dependency, "hot_late")
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "c-declaration")
    testAssert.equal(result.reason.identity, "<module-wide C fallback>")
end

function M.sessionTracksDeriveProviderFilesystemInputs()
    local source = table.concat(
        {
            "local M = {}",
            "interface M.Labelled",
            "   label: function(self): string",
            "end",
            "function M.labelValue(value: string): string return value end",
            "@comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Labelled>",
            "   local label = nupp.derive.file('schema.txt')",
            "   return nupp.derive.implement{methods = {",
            "      label = nupp.derive.forward{helper = nupp.derive.helper(M, 'labelValue'), arguments = {nupp.derive.constant(label)}},",
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "provider-input")
    testAssert.equal(result.reason.dependency, "schema.txt")
    testAssert.equal(result.reason.path, inputPath)
end

function M.deriveProviderFilesystemInputsRequireLiteralPaths()
    local source = table.concat(
        {
            "local M = {}",
            "interface M.Contract",
            "   value: function(self): string",
            "end",
            "function M.value(): string return 'value' end",
            "@comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Contract>",
            "   local path = 'schema.txt'",
            "   local schema = nupp.derive.file(path)",
            "   return nupp.derive.implement{methods = {value = nupp.derive.forward{helper = nupp.derive.helper(M, 'value'), arguments = {}}}}",
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
    testAssert.equal(result.kind, "diagnostics")
    testAssert.equal(result.diagnostics[1].code, "NUPP2810")
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
            "@comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Contract>",
            "   local schema = nupp.derive.file('../outside.txt')",
            "   return nupp.derive.implement{methods = {value = nupp.derive.forward{helper = nupp.derive.helper(M, 'value'), arguments = {}}}}",
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
    testAssert.equal(result.kind, "diagnostics")
    local escaped
    for _, diagnostic in ipairs(result.diagnostics) do
        if diagnostic.code == "NUPP2810" and diagnostic.msg:find("escapes the project root", 1, true) then
            escaped = diagnostic
        end
    end
    assert(escaped, "project-escaping derive.file did not report NUPP2810")
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
    testAssert.equal(result.kind, "no-change", "unobserved declarations stop at the query boundary")
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
    testAssert.equal(watched[absoluteHeader], "header", "direct header joins the watch set")

    write(headerPath, "/* spelling only */\nint hot_header_value(void);\n")
    session:diskChanged(absoluteHeader, 2)
    testAssert.equal(
        session:prepare({
            absoluteHeader
        }).kind,
        "no-change",
        "comment-only header edit has the same declarations"
    )

    write(headerPath, "long hot_header_value(void);\n")
    session:diskChanged(absoluteHeader, 2)
    local changed = session:prepare({absoluteHeader})
    testAssert.equal(changed.kind, "restart-required")
    testAssert.equal(changed.reason.kind, "header-abi")
    testAssert.equal(changed.reason.path, absoluteHeader)
    assert(changed.diagnostics[1].msg:find("api.h", 1, true), changed.diagnostics[1].msg)
end

function M.sessionTracksPreprocessedHeaderClosure()
    if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").skip("cc is unavailable")
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "header-abi")
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
    testAssert.equal(built.kind, "initial")
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
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "native-artifact")
    testAssert.equal(result.reason.path, artifactPath)
    assert(os.remove(artifactPath))
    session:diskChanged(artifactPath, 3)
    local missing = session:prepare({artifactPath})
    testAssert.equal(missing.kind, "restart-required")
    testAssert.equal(missing.reason.kind, "native-artifact")
end

function M.sessionReportsUnmappedNativeIdentityOnce()
    local dir = temporaryProject({
        ["main.nupp"] = "cdef function hot_unverified(): int32 from 'bare'\nreturn hot_unverified\n",
    })
    local path = dir .. "/main.nupp"
    local session = hotSession.new(dir, {cache = false})
    local built = session:initial({path})
    local first = session:loaded(built.entryManifest.module, 1, built.entryManifest)
    testAssert.equal(first.unverifiedLibraries[1], "bare")
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
    testAssert.equal(watchedCount, 1, "canonical header path is polled once")
    local manifest = session.running.main
    local consumers = 0
    for _, input in pairs(manifest.abi.inputs) do
        if input.kind == "header" and input.sourcePath == headerPath then
            consumers = consumers + 1
        end
    end
    testAssert.equal(consumers, 2, "each cheader site retains its consumer record")
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
    testAssert.equal(result.kind, "diagnostics")
    testAssert.equal(result.diagnostics[1].code, "NUPP2302")
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

function M.mappedNativeSymlinkRetargetRequiresRestart()
    if package.config:sub(1, 1) == "\\" then
        return require("assert").skip("symbolic-link fixture is POSIX-only")
    end
    local dir = temporaryProject({
        ["one.bin"] = "identical bytes",
        ["two.bin"] = "identical bytes",
        ["nupp.lua"] = "return { hotreload = { libraries = { mini = 'current.bin' } } }\n",
        ["main.nupp"] = "cdef function hot_symlink(): int32 from 'mini'\nreturn hot_symlink\n",
    })
    testAssert.equal(os.execute(("ln -s '%s/one.bin' '%s/current.bin'"):format(dir, dir)), 0)
    local session = hotSession.new(dir, {cache = false})
    local built = session:initial({dir .. "/main.nupp"})
    local firstTarget = require("nupp.compiler.fs").absolute(dir .. "/one.bin")
    assert(built.entryCode:find(firstTarget, 1, true), "watch generation pins the resolved target")
    session:loaded(built.entryManifest.module, 1, built.entryManifest)
    assert(os.remove(dir .. "/current.bin"))
    testAssert.equal(os.execute(("ln -s '%s/two.bin' '%s/current.bin'"):format(dir, dir)), 0)
    local link = require("nupp.compiler.fs").absolute(dir .. "/current.bin")
    session:diskChanged(link, 2)
    local result = session:prepare({link})
    testAssert.equal(result.kind, "restart-required")
    testAssert.equal(result.reason.kind, "native-artifact")
end

function M.headerDependencyClosureGrowsAndShrinksAfterNoChange()
    if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").skip("cc is unavailable")
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
    testAssert.equal(session:prepare({apiPath}).kind, "no-change")
    assert(not isWatched(nestedPath), "removed include leaves the dynamic watch set")
    write(apiPath, withInclude)
    session:diskChanged(apiPath, 2)
    testAssert.equal(session:prepare({apiPath}).kind, "no-change")
    assert(isWatched(nestedPath), "new include joins the dynamic watch set")
end

-- `nupp run --watch` itself, through the launcher. The launcher runs the VM CLI
-- when one is installed or named by `NUPP_VM_CLI_IMAGE`; otherwise it refuses
-- `--watch`, and these cases have nothing to run.
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local ROOT = HERE:sub(1, 1) == "/" and (HERE .. "/..") or ((os.getenv("PWD") or ".") .. "/" .. HERE .. "/..")

local function watchCommand()
    local installed = io.open(ROOT .. "/.nupp/vm-cli/current", "rb")
    if installed then
        installed:close()
    end
    if not installed and not os.getenv("NUPP_VM_CLI_IMAGE") then
        return nil
    end

    return ROOT .. "/bin/nupp"
end

local function withProject(files, callback)
    local dir = temporaryProject(files)
    local ok, result = pcall(callback, dir)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(result, 0)
    end

    return result
end

local WRITER = [[
return function(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end
]]

function M.cliWatchCommitsAndKeepsTheLastGoodGeneration()
    local nupp = watchCommand()
    if not nupp then
        return require("assert").skip("--watch runs on the VM CLI, and none is installed")
    end
    local function watched(body)
        return table.concat(
            {"local M = {}", "function M.value(): integer", "   " .. body, "end", "return M", "",},
            "\n"
        )
    end

    local versionTwo = string.format("%q", watched("return 2"))
    local rejected = string.format("%q", watched("return 'bad'"))
    local structural = string.format("%q", "local marker: integer = 1\n" .. watched("return 3"))
    withProject(
        {
            ["nupp.lua"] = "return { include = { 'src' } }\n",
            ["writer.lua"] = WRITER,
            ["src/watched.nupp"] = watched("return 1"),
            [
                "main.nupp"
            ] = table.concat(
                {
                    "local watched = require('watched')",
                    "local write = require('writer')",
                    "nupp.hotreload.poll()",
                    "print(watched.value())",
                    "write('src/watched.nupp', " .. versionTwo .. ")",
                    "nupp.hotreload.poll()",
                    "print(watched.value())",
                    "write('src/watched.nupp', " .. rejected .. ")",
                    "nupp.hotreload.poll()",
                    "print(watched.value())",
                    "write('src/watched.nupp', " .. structural .. ")",
                    "nupp.hotreload.poll()",
                    "print(watched.value())",
                    "",
                },
                "\n"
            ),
        },
        function(dir)
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = ("cd '%s' && '%s' run --watch main.nupp > '%s' 2> '%s'"):format(dir, nupp, output, errors)
            local status = os.execute(command)
            local stderr = readFile(errors)
            testAssert.equal(status, 0, "nupp run --watch exit status: " .. stderr)
            testAssert.equal(readFile(output), "1\n2\n2\n2\n", "watch generation output")
            assert(stderr:find("committed hot generation 2", 1, true), stderr)
            assert(stderr:find("NUPP2002", 1, true), stderr)
            assert(stderr:find("generation 2 remains running", 1, true), stderr)
            assert(stderr:find("NUPP5001", 1, true), stderr)
            assert(stderr:find("top-level structure changed in watched", 1, true), stderr)
        end
    )
end

-- The loop that polls is itself edited: its running call stays on the body it
-- entered, while the function it calls changes underneath it.
function M.cliWatchPatchesUnderARunningLoop()
    local nupp = watchCommand()
    if not nupp then
        return require("assert").skip("--watch runs on the VM CLI, and none is installed")
    end
    local function program(message, nextVersion)
        return table.concat(
            {
                "local write = require('writer')",
                "local function message(): string",
                "   return '" .. message .. "'",
                "end",
                "local function main(): nil",
                "   for round = 1, 2 do",
                "      nupp.hotreload.poll()",
                "      print(message())",
                "      if round == 1 then",
                "         write('main.nupp', " .. nextVersion .. ")",
                "      end",
                "   end",
                "end",
                "main()",
                "",
            },
            "\n"
        )
    end
    -- The program writes its own next version, in which only the bodies differ.
    local second = program("version two", "''")
    local first = program("version one", string.format("%q", second))
    withProject({["writer.lua"] = WRITER, ["main.nupp"] = first}, function(dir)
        local output = dir .. "/output.txt"
        local errors = dir .. "/errors.txt"
        local command = ("cd '%s' && '%s' run --watch main.nupp > '%s' 2> '%s'"):format(dir, nupp, output, errors)
        local status = os.execute(command)
        local stderr = readFile(errors)
        testAssert.equal(status, 0, "nupp run --watch exit status: " .. stderr)
        testAssert.equal(readFile(output), "version one\nversion two\n", "the edited body runs without a restart")
        assert(stderr:find("committed hot generation 2", 1, true), stderr)
    end)
end

function M.cliWatchRejectsOptimizedGeneration()
    local nupp = watchCommand() or (ROOT .. "/bin/nupp")
    withProject({["main.nupp"] = "print(1)\n"}, function(dir)
        local output = dir .. "/output.txt"
        local command = ("cd '%s' && '%s' run --watch -O1 main.nupp > '%s' 2>&1"):format(dir, nupp, output)
        local status = os.execute(command)
        assert(status ~= 0, "optimized watch command must fail")
        assert(readFile(output):find("--watch supports -O0 only", 1, true), readFile(output))
    end)
end

function M.cliWatchRequiresRestartForMappedNativeReplacement()
    local nupp = watchCommand()
    if not nupp then
        return require("assert").skip("--watch runs on the VM CLI, and none is installed")
    end
    local windows = package.config:sub(1, 1) == "\\"
    if windows or os.execute("cc --version >/dev/null 2>&1") ~= 0 then
        return require("assert").skip("a POSIX C compiler is unavailable")
    end
    local darwin = io.popen("uname -s"):read("*l") == "Darwin"
    withProject(
        {
            ["first.c"] = "int hot_native_value(void) { return 1; }\n",
            ["second.c"] = "int hot_native_value(void) { return 2; }\n",
            ["replace.lua"] = "return function(from, to) assert(os.rename(from, to)) end\n",
        },
        function(dir)
            local extension = darwin and ".dylib" or ".so"
            local current = "libmini" .. extension
            local replacement = "libmini-next" .. extension
            local flags = darwin and "-dynamiclib" or "-shared -fPIC"
            assert(os.execute(("cc %s -o '%s/%s' '%s/first.c'"):format(flags, dir, current, dir)), "compile first library")
            assert(
                os.execute(("cc %s -o '%s/%s' '%s/second.c'"):format(flags, dir, replacement, dir)),
                "compile replacement library"
            )
            write(dir .. "/nupp.lua", ("return { hotreload = { libraries = { mini = %q } } }\n"):format(current))
            write(
                dir .. "/main.nupp",
                table.concat(
                    {
                        "cdef function hot_native_value(): int32 from 'mini'",
                        "local replace = require('replace')",
                        "nupp.hotreload.poll()",
                        "print(hot_native_value())",
                        ("replace(%q, %q)"):format(replacement, current),
                        "print(nupp.hotreload.poll().kind)",
                        "",
                    },
                    "\n"
                )
            )
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = ("cd '%s' && '%s' run --watch main.nupp > '%s' 2> '%s'"):format(dir, nupp, output, errors)
            local status = os.execute(command)
            local stderr = readFile(errors)
            testAssert.equal(status, 0, "native watch exit status: " .. stderr)
            testAssert.equal(readFile(output), "1\nrestart-required\n")
            assert(stderr:find("native artifact for mini at", 1, true), stderr)
        end
    )
end

return M
