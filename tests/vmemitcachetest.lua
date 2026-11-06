-- The per-module reuse a VM image emit makes of the one before it.
--
-- `nupp.tools.vm.emitcache` hands `nupp.compiler.vm.relink` the lowering an
-- earlier emit kept for each module whose check would come out the same, and the
-- linker replays it into this emit's numbering. The one property that matters is
-- that nobody can tell: an emit that reused anything writes the bytes an emit
-- from nothing writes. Every case here compares against one, after the kinds of
-- edit that move what a module's lowering depends on -- its own body, the body
-- of a module everything imports, an exported record, and the function and shape
-- numbering of everything lowered before it.
local project = require("nupp.tools.vm.project")
local emitcache = require("nupp.tools.vm.emitcache")

local function write(path, text)
    local sub = path:match("^(.*)/[^/]+$")
    if sub then
        assert(os.execute("mkdir -p '" .. sub .. "'") == 0)
    end
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local SHAPES = [[
module shapes

local shapes = {}

record shapes.Point
    x: number
    y: number
end

record shapes.Box<T>
    value: T
end

function shapes.make(x: number, y: number): shapes.Point
    return new shapes.Point(x = x, y = y)
end

function shapes.length(p: shapes.Point): number
    return p.x + p.y
end

function shapes.box(value: number): shapes.Box<number>
    return new shapes.Box<number>(value = value)
end

export = shapes
]]

local A = [[
module a

local shapes = require("shapes")

local a = {}

local record Step
    at: shapes.Point
    next: Step?
end

function a.walk(n: number): number
    local first = new Step(at = shapes.make(n, 1), next = nil)
    local second = new Step(at = shapes.make(1, n), next = first)
    local total = 0
    local step: Step? = second
    while step do
        total = total + shapes.length(step.at)
        step = step.next
    end
    local add = function(x: number): number
        return x + total
    end
    return add(shapes.box(n).value)
end

export = a
]]

local B = [[
module b

local shapes = require("shapes")

local b = {}

function b.pair(n: number): number
    local point = {left = n, right = n * 2}
    local scale = function(p: shapes.Point): number
        return shapes.length(p) * point.left + point.right
    end
    return scale(shapes.make(n, n))
end

export = b
]]

local LEAF = [[
module leaf

local a = require("a")
local b = require("b")

local leaf = {}

function leaf.run(): number
    return a.walk(3) + b.pair(4)
end

export = leaf
]]

local MAIN = [[
module main

local leaf = require("leaf")
local shapes = require("shapes")

local main = {}

function main.start(): number
    local p = shapes.make(1, 2)
    return leaf.run() + p.x
end

export = main
]]

local function tempProject()
    local dir = os.tmpname()
    os.remove(dir)
    write(dir .. "/src/shapes.nupp", SHAPES)
    write(dir .. "/src/a.nupp", A)
    write(dir .. "/src/b.nupp", B)
    write(dir .. "/src/leaf.nupp", LEAF)
    write(dir .. "/src/main.nupp", MAIN)

    return dir
end

local function remove(dir)
    os.execute("rm -rf '" .. dir .. "'")
end

-- An emit from nothing, and one through the cache: they must be the same bytes.
local function scratch(dir)
    return project.emit(dir, "main", "", "src")
end

local function cached(dir)
    local image = project.emitCached(dir, "main", "", "src", dir .. "/cache")
    return image, emitcache.last.stats
end

local function same(expected, actual, what)
    if expected == actual then
        return
    end
    local line = 1
    for i = 1, math.max(#expected, #actual) do
        local e, a = expected:sub(i, i), actual:sub(i, i)
        if e ~= a then
            local from = expected:sub(1, i):match(".*\n()") or 1
            error(
                (
                    "%s: the cached emit differs from an emit from nothing at line %d:\n  scratch: %s\n  cached:  %s"
                ):format(
                    what,
                    line,
                    expected:sub(from, (expected:find("\n", i, true) or #expected + 1) - 1),
                    actual:sub(from, (actual:find("\n", i, true) or #actual + 1) - 1)
                ),
                2
            )
        end
        if e == "\n" then
            line = line + 1
        end
    end
end

local M = {}

function M.aCompletedEnvironmentCheckIsLoweredOnlyOnce()
    local check = require("nupp.compiler.check")
    local original = check.check
    local counts = {}
    check.check = function(parsed, path, env, options)
        if path:match("/src/shapes%.nupp$") then
            counts[#counts + 1] = options and options.moduleName or false
        end
        return original(parsed, path, env, options)
    end
    local dir = tempProject()
    local ok, problem = pcall(function()
        local image, stats = cached(dir)
        assert(stats.adopted > 0, "no completed environment check was used by lowering")
        assert(#counts == 1 and counts[1] == "shapes", "shapes was checked again for lowering")
        check.check = original
        same(scratch(dir), image, "one check")
    end)
    check.check = original
    remove(dir)
    assert(ok, problem)
end

function M.adoptionRefusesIncompleteOrDifferentSourceChecks()
    local envMod = require("nupp.compiler.project.env")
    local fs = require("nupp.compiler.fs")
    local dir = tempProject()
    local config = {include = {"src"}}
    local env = envMod.new(dir, {cache = false, config = config})
    local session = emitcache.open(dir .. "/cache", env, config)
    local ok, problem = pcall(function()
        assert(envMod.resolveModule(env, "shapes"))
        local path = fs.normalize(dir .. "/src/shapes.nupp")
        local record = assert(env.loadedPaths[path])
        assert(session.checkedTree("shapes", dir .. "/src/b.nupp") == nil, "a different file was adopted")
        record.inProgress = true
        assert(session.checkedTree("shapes", path) == nil, "an incomplete check was adopted")
        record.inProgress = false
        record.compatDiagnostics = {{severity = "error"}}
        assert(session.checkedTree("shapes", path) == nil, "a check with errors was adopted")
        record.compatDiagnostics = {}
        write(path, SHAPES .. "\n")
        assert(session.checkedTree("shapes", path) == nil, "a check of different bytes was adopted")
        write(path, SHAPES)
        local tree = session.checkedTree("shapes", path)
        assert(tree == record.result.root, "a completed source-identical tree was not adopted")
        assert(session.checkedTree("shapes", path) == nil, "a tree already given to lowering was adopted again")
    end)
    session.abandon()
    remove(dir)
    assert(ok, problem)
end

function M.aRequireCycleIsCheckedAgainAfterItsInterfacesComplete()
    local envMod = require("nupp.compiler.project.env")
    local dir = tempProject()
    write(
        dir .. "/src/cyclea.nupp",
        [[
module cyclea
local b = require("cycleb")
export function value(): number return b.value() end
]]
    )
    write(
        dir .. "/src/cycleb.nupp",
        [[
module cycleb
local a = require("cyclea")
export function value(): number return 1 end
export function again(): number return a.value() end
]]
    )
    local config = {include = {"src"}}
    local env = envMod.new(dir, {cache = false, config = config})
    local session = emitcache.open(dir .. "/cache", env, config)
    local ok, problem = pcall(function()
        assert(envMod.resolveModule(env, "cyclea"))
        assert(session.checkedTree("cycleb", dir .. "/src/cycleb.nupp") == nil, "the recursive edge was adopted")
        assert(session.checkedTree("cyclea", dir .. "/src/cyclea.nupp") == nil, "a reader of that edge was adopted")
    end)
    session.abandon()
    remove(dir)
    assert(ok, problem)
end

function M.independentEmitsReplayThroughOneFinalNumbering()
    local dir = tempProject()
    project.emitCached(dir, "leaf", "", "src", dir .. "/left")
    project.emitCached(dir, "b", "", "src", dir .. "/right")
    local original = os.getenv
    os.getenv = function(name)
        if name == "NUPP_VM_EMIT_IMPORTS" then
            return dir .. "/left;" .. dir .. "/right"
        end
        return original(name)
    end
    local ok, problem = pcall(function()
        local image, stats = cached(dir)
        assert(stats.replayed >= 4, "independent fragments were not replayed: " .. stats.replayed)
        os.getenv = original
        same(scratch(dir), image, "independent emit imports")
        local warm, warmStats = cached(dir)
        same(image, warm, "promoted imports")
        assert(warmStats.lowered == 0, "the final cache depended on worker directories")
    end)
    os.getenv = original
    remove(dir)
    assert(ok, problem)
end

function M.borrowedInterfacesPreservePreludeCleanupTypeIdentity()
    local dir = tempProject()
    write(
        dir .. "/src/handles.nupp",
        [[
module handles
local handles = {}
export type Handle = io.File
function handles.identity(value: io.File): io.File
    return value
end
export = handles
]]
    )
    write(
        dir .. "/src/consumer.nupp",
        [[
module consumer
local handles = require("handles")
local consumer = {}
consumer.identity = handles.identity
export type Owned = affine(handles.Handle, __nuppCloseFile)
export = consumer
]]
    )
    write(dir .. "/src/left.nupp", [[
module left
local handles = require("handles")
export = handles
]])
    local original = os.getenv
    local ok, problem = pcall(function()
        local expected = project.emit(dir, "consumer", "", "src")
        project.emitCached(dir, "left", "", "src", dir .. "/left")
        os.getenv = function(name)
            return name == "NUPP_VM_EMIT_IMPORTS" and dir .. "/left" or original(name)
        end
        local image = project.emitCached(dir, "consumer", "", "src", dir .. "/final")
        assert(emitcache.last.stats.restored > 0, "the borrowed interface was not restored")
        same(expected, image, "prelude cleanup type")
    end)
    os.getenv = original
    remove(dir)
    assert(ok, problem)
end

function M.aCachedEmitWritesWhatAnEmitFromNothingWrites()
    local dir = tempProject()
    local expected = scratch(dir)
    local cold, coldStats = cached(dir)
    same(expected, cold, "cold")
    -- The project's five, and the VM library modules they reach.
    assert(coldStats.replayed == 0 and coldStats.lowered >= 5, "a cold cache lowers everything")
    assert(coldStats.kept == coldStats.lowered, "and keeps every module, kept " .. coldStats.kept)

    local warm, warmStats = cached(dir)
    same(expected, warm, "warm")
    assert(warmStats.lowered == 0, "an unchanged project lowers nothing, lowered " .. warmStats.lowered)
    assert(warmStats.replayed == coldStats.lowered, "and replays every module")
    assert(warmStats.checked == 0, "nor checks one, checked " .. warmStats.checked)
    remove(dir)
end

function M.aLeafEditLowersOnlyTheLeaf()
    local dir = tempProject()
    local _, cold = cached(dir)
    write(dir .. "/src/leaf.nupp", (LEAF:gsub("a%.walk%(3%)", "a.walk(5) * 2")))
    local image, stats = cached(dir)
    same(scratch(dir), image, "leaf edit")
    assert(stats.lowered == 1, "only the leaf is lowered, lowered " .. stats.lowered)
    assert(stats.replayed == cold.lowered - 1, "the rest are replayed")
    -- What the leaf requires was restored from the interfaces kept for it rather
    -- than checked: the one module checked is the leaf, for its interface.
    assert(stats.restored > 0, "nothing the leaf requires was restored")
    assert(stats.checked == 1, "checking the leaf checked " .. stats.checked .. " modules")
    remove(dir)
end

-- What a cutoff is for: every module requires `shapes`, and editing a function's
-- body leaves the interface they were checked against as it was.
function M.aBodyEditToAWidelyImportedModuleStopsAtItsInterface()
    local dir = tempProject()
    cached(dir)
    write(dir .. "/src/shapes.nupp", (SHAPES:gsub("return p%.x %+ p%.y", "return p.y + p.x + 0")))
    local image, stats = cached(dir)
    same(scratch(dir), image, "body edit")
    assert(stats.lowered == 1, "only the edited module is lowered, lowered " .. stats.lowered)
    assert(stats.checked == 1, "the edited module alone is checked, checked " .. stats.checked)
    remove(dir)
end

-- A record's fields are its slots, and every module that reads one reads it by slot
-- index: adding a field has to reach every module using the record.
function M.anExportedRecordEditReachesItsImporters()
    local dir = tempProject()
    cached(dir)
    local edited = SHAPES:gsub("    x: number\n    y: number\n", "    tag: string\n    x: number\n    y: number\n")
        :gsub("new shapes%.Point%(x = x, y = y%)", 'new shapes.Point(tag = "p", x = x, y = y)')
    write(dir .. "/src/shapes.nupp", edited)
    local image, stats = cached(dir)
    same(scratch(dir), image, "record edit")
    assert(stats.lowered >= 4, "the record's readers are lowered again, lowered " .. stats.lowered)
    remove(dir)
end

-- A function's signature alone is not its interface: callers consume the
-- allocation guarantee too, so a same-signature body edit must invalidate them.
function M.aCallableFactChangeReachesItsImporters()
    local interfaceimage = require("nupp.compiler.project.interfaceimage")
    local original = interfaceimage.encode
    local observed = {}
    local dir = tempProject()
    interfaceimage.encode = function(semantics, options)
        local image, problem = original(semantics, options)
        if image and semantics.shapes then
            local facts = image.modules[1].callGuarantees.length
            observed[#observed + 1] = facts.noAllocate == true
        end

        return image, problem
    end
    local ok, problem = pcall(function()
        cached(dir)
        assert(observed[1] == true, "the original function does not allocate")
        local edited = SHAPES:gsub("return p%.x %+ p%.y", "local pair = {p.x, p.y}\n    return pair[1] + pair[2]")
        write(dir .. "/src/shapes.nupp", edited)
        local image, stats = cached(dir)
        same(scratch(dir), image, "callable effect edit")
        assert(observed[#observed] == false, "the edited function allocates")
        assert(stats.lowered >= 4, "the callable fact's readers are lowered again, lowered " .. stats.lowered)
    end)
    interfaceimage.encode = original
    remove(dir)
    if not ok then
        error(problem, 0)
    end
end

-- Lowered first, `shapes` decides where every later module's functions and shapes
-- are numbered from. Growing it with a record and functions of its own moves all
-- of them without changing what it exports, and the replays relocate. (Called
-- from an exported function instead, the record would change what that function
-- guarantees -- it would allocate -- which its callers' checks can read.)
function M.renumberingEverythingAfterAnEditStillReplays()
    local dir = tempProject()
    local _, cold = cached(dir)
    local edited = SHAPES:gsub(
        "function shapes%.length",
        "local record Extra\n    note: string\nend\n\nlocal function extra(): Extra\n"
        .. '    local make = function(): Extra\n        return new Extra(note = "x")\n    end\n'
        .. "    return make()\nend\n\nlocal EXTRA = extra()\n\nfunction shapes.length"
    )
    write(dir .. "/src/shapes.nupp", edited)
    local image, stats = cached(dir)
    same(scratch(dir), image, "renumbered")
    assert(stats.lowered == 1, "only the grown module is lowered, lowered " .. stats.lowered)
    assert(stats.replayed == cold.lowered - 1, "everything after it was replayed")
    remove(dir)
end

-- Runs `run` with `fingerprint[field]` replaced by what `answer` makes of it:
-- how a case stands in for an emit by another compiler generation.
local function withFingerprint(field, answer, run)
    local fingerprint = require("nupp.compiler.project.fingerprint")
    local original = fingerprint[field]
    fingerprint[field] = answer(original)
    local ok, image, stats = pcall(run)
    fingerprint[field] = original
    assert(ok, image)

    return image, stats
end

local function otherLoweringCode(original)
    return function(...)
        return original(...) .. "+an edited lowering"
    end
end

local function otherInterpreter()
    return function()
        return "another interpreter"
    end
end

-- A generation whose lowering code differs, or whose interpreter does, lowers
-- from nothing: what another generation lowered is never replayed. The one that
-- filled the cache still finds all of it, unchanged sources being the hit.
function M.anotherGenerationsLoweringIsNeverReplayed()
    local dir = tempProject()
    local expected = scratch(dir)
    local _, cold = cached(dir)

    local function emit()
        return cached(dir)
    end

    local image, stats = withFingerprint("subsystemFingerprint", otherLoweringCode, emit)
    same(expected, image, "other lowering code")
    assert(stats.replayed == 0, "another compiler's lowering was replayed: " .. stats.replayed)
    assert(stats.lowered == cold.lowered, "and not everything was lowered again: " .. stats.lowered)

    image, stats = cached(dir)
    same(expected, image, "the first compiler again")
    assert(stats.lowered == 0 and stats.replayed == cold.lowered, "the first compiler lost what it kept")

    image, stats = withFingerprint("runtimeIdentity", otherInterpreter, emit)
    same(expected, image, "another interpreter")
    assert(stats.replayed == 0, "another interpreter's lowering was replayed: " .. stats.replayed)
    remove(dir)
end

-- Anything wrong with what was kept costs a lowering and nothing else.
function M.aDamagedFragmentIsLoweredAgain()
    local dir = tempProject()
    local expected = scratch(dir)
    cached(dir)
    local file = dir .. "/cache/modules/a.buf"
    local text = assert(read(file), "a fragment was kept for a")
    write(file, text:sub(1, math.floor(#text / 2)))
    local image, stats = cached(dir)
    same(expected, image, "damaged")
    assert(stats.lowered >= 1, "the damaged module was lowered")
    remove(dir)
end

-- What a kept function names that the rest of the image numbers is found by
-- opcode: the operands the VM's image loader relocates. An opcode the loader
-- relocates and the linker does not know would be replayed with another
-- emit's number in it, so the two lists are held to each other here.
function M.relinkRelocatesWhatTheImageLoaderRelocates()
    local relink = require("nupp.compiler.vm.relink")
    local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local loader = assert(read(HERE .. "/../native/crates/vm/src/image.rs"), "the image loader is readable")
    local functions, shapes = {}, {}
    local cases = {}
    for at, opcode in loader:gmatch('()"(%w+)" => Op::') do
        cases[#cases + 1] = {at = at, opcode = opcode}
    end
    for i, case in ipairs(cases) do
        local finish = cases[i + 1] and cases[i + 1].at or #loader
        local text = loader:sub(case.at, finish):match("^[^\n]*")
        local fid = text:match("base %+ a%((%d+)%)")
        local shape = text:match("shape_ids%[a%((%d+)%)")
        if fid then
            functions[case.opcode] = tonumber(fid)
        end
        if shape then
            shapes[case.opcode] = tonumber(shape)
        end
    end
    assert(next(functions) and next(shapes), "found no relocated operands; the loader's spelling moved")

    local function same(expected, actual, what)
        for opcode, position in pairs(expected) do
            assert(
                actual[opcode] == position,
                ("%s operand %d of %s is not relocated by the linker"):format(what, position, opcode)
            )
        end
        for opcode, position in pairs(actual) do
            assert(
                expected[opcode] == position,
                ("the linker relocates %s operand %d of %s, which the loader does not"):format(what, position, opcode)
            )
        end
    end

    same(functions, relink.FUNCTION_OPERANDS, "function")
    same(shapes, relink.SHAPE_OPERANDS, "shape")
end

local PHYSICAL = [[
module physical
local physical = {}
struct physical.Packet
    offset: uint32
    ready: boolean : 1
    link: uint8*?
end
struct physical.Other
    offset: uint32
    ready: boolean : 1
    link: uint8*?
end
export = physical
]]

local PHYSICAL_MAIN = [[
module main
local physical = require("physical")
local main = {}
function main.isPacket(value: any): boolean
    return value is physical.Packet
end
function main.isOther(value: any): boolean
    return value is physical.Other
end
function main.start(): boolean
    local packet = new physical.Packet(0, false, nil)
    if not main.isPacket(packet) or main.isOther(packet) then
        return false
    end
    if packet.offset ~= 0 or packet.ready or packet.link ~= nil then
        return false
    end
    packet.offset = 7
    packet.ready = true
    return packet.offset == 7 and packet.ready and packet.link == nil
end
export = main
]]

local physicalSerial = 0

local function physicalProject()
    physicalSerial = physicalSerial + 1
    local provider = "vmemitcachephysical" .. physicalSerial
    local entry = "vmemitcacheentry" .. physicalSerial
    local source = PHYSICAL_MAIN:gsub("module main", "module " .. entry, 1)
        :gsub('require%("physical"%)', 'require("' .. provider .. '")')
    local dir = tempProject()
    write(dir .. "/src/" .. provider .. ".nupp", (PHYSICAL:gsub("module physical", "module " .. provider, 1)))
    write(dir .. "/src/" .. entry .. ".nupp", source)
    write(
        dir .. "/nupp.lua",
        (
            "return {include = {\"src\"}, build = {entries = {%q}, layoutTarget = %q}}\n"
        ):format(entry, require("nupp.compiler.targetlayout").hostKey())
    )

    return dir, entry, provider, source
end

local function physicalScratch(dir, entry)
    return project.emit(dir, entry, "", nil)
end

local function physicalCached(dir, entry)
    local image = project.emitCached(dir, entry, "", nil, dir .. "/cache")
    return image, emitcache.last.stats
end

local function runPhysicalImage(image, what)
    local loadImage = rawget(_G, "__nupp_load_image")
    if loadImage then
        local chunk = assert(loadImage(image))
        assert(chunk().start() == true, what .. ": physical identity, fields, and metadata survive")
    end
end

function M.physicalStructIdentityAndMetadataSurviveCacheReplay()
    local dir, entry, _, source = physicalProject()
    local expected = physicalScratch(dir, entry)
    local cold, coldStats = physicalCached(dir, entry)
    same(expected, cold, "physical cold")
    assert(coldStats.replayed == 0 and coldStats.lowered >= 2, "the cold cache lowers the physical modules")
    assert(coldStats.kept == coldStats.lowered, "the physical modules can be kept")
    runPhysicalImage(cold, "physical cold")

    local warm, warmStats = physicalCached(dir, entry)
    same(expected, warm, "physical warm")
    assert(warmStats.lowered == 0, "the unchanged physical project lowers nothing")
    assert(warmStats.replayed == coldStats.lowered, "the physical modules are replayed")
    assert(warmStats.checked == 0, "the warm physical interfaces are restored")
    runPhysicalImage(warm, "physical warm")

    -- Re-lower the consumer against restored provider interfaces and registry data.
    write(dir .. "/src/" .. entry .. ".nupp", (source:gsub("packet.offset = 7", "packet.offset = (7)")))
    local edited, stats = physicalCached(dir, entry)
    same(physicalScratch(dir, entry), edited, "physical consumer edit")
    assert(stats.lowered == 1, "only the physical consumer is lowered again")
    assert(stats.replayed == coldStats.lowered - 1, "its provider is replayed")
    assert(stats.restored > 0, "the consumer reads restored interfaces")
    runPhysicalImage(edited, "physical consumer edit")
    remove(dir)
end

-- Full-graph replay can find the provider's shape before the consumer asks for
-- it. A separately lowered consumer must reconstruct its foreign physical shape.
function M.anIsolatedPhysicalConsumerReplaysForeignShapeMetadata()
    local compile = require("nupp.tools.cli.compile")
    local envMod = require("nupp.compiler.project.env")
    local lower = require("nupp.compiler.vm.lower")
    local targetLayout = require("nupp.compiler.targetlayout")
    local dir, entry, providerName = physicalProject()
    local path = dir .. "/src/" .. entry .. ".nupp"
    local kept = {}
    local keptCount = 0
    local reuse = {
        fragment = function(name)
            return kept[name]
        end,
        keep = function(name, fragment)
            kept[name] = fragment
            keptCount = keptCount + 1
        end,
    }

    local function isolated(reuseCache)
        local env = envMod.new(dir, {cacheDir = dir .. "/isolated-check"})
        local diagnostics = {}
        local result = compile.check(path, env, {moduleName = entry}, diagnostics)
        assert(result, tostring(diagnostics[1] and diagnostics[1].msg))
        result.root.vmModuleExports = result.moduleExports
        envMod.persist(env)

        return lower.emit(
            entry,
            {},
            function(name)
                return name == entry and path or nil
            end,
            function()
                return result.root
            end,
            nil,
            nil,
            targetLayout.hostKey(),
            nil,
            reuseCache
        )
    end

    local expected = isolated(nil)
    local cold = isolated(reuse)
    assert(kept[entry], "the isolated consumer kept a fragment")
    same(expected, cold, "isolated physical cold")
    local coldKeptCount = keptCount
    local warm = isolated(reuse)
    same(expected, warm, "isolated physical warm")
    assert(keptCount == coldKeptCount, "the isolated consumer replayed instead of lowering again")
    assert(not warm:find("\nmodule " .. providerName .. " ", 1, true), "the provider is outside the consumer image")

    -- Runtime execution needs the physical declarations already registered, as
    -- when the dynamic module loader supplies a separately compiled consumer.
    local loadImage = rawget(_G, "__nupp_load_image")
    if loadImage then
        local provider = assert(loadImage(project.emit(dir, providerName, "", nil)))()
        assert(provider.Packet and provider.Other, "the provider returns both physical type witnesses")
        local prior = package.loaded[providerName]
        package.loaded[providerName] = provider
        local ok, problem = pcall(function()
            runPhysicalImage(cold, "isolated physical cold")
            runPhysicalImage(warm, "isolated physical warm")
        end)
        package.loaded[providerName] = prior
        assert(ok, problem)
    end
    remove(dir)
end

return M
