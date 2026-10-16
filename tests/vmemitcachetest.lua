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
                ("%s: the cached emit differs from an emit from nothing at line %d:\n  scratch: %s\n  cached:  %s")
                    :format(
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
            assert(actual[opcode] == position, ("%s operand %d of %s is not relocated by the linker"):format(
                what,
                position,
                opcode
            ))
        end
        for opcode, position in pairs(actual) do
            assert(expected[opcode] == position, ("the linker relocates %s operand %d of %s, which the loader does not"):format(
                what,
                position,
                opcode
            ))
        end
    end
    same(functions, relink.FUNCTION_OPERANDS, "function")
    same(shapes, relink.SHAPE_OPERANDS, "shape")
end

return M
