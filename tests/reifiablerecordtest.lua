local parser = require("nupp.parser")
local check = require("nupp.check")
local envMod = require("nupp.env")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Every NUPP2509 the source produces. The level is set rather than left at the
-- registry default so that a case reads the same if the default is reconsidered.
local function lint(src, level)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", envMod.new("."),
      {lints = {["reifiable-record"] = level or "warning"}})
   local found = {}
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2509" then found[#found + 1] = diag end
   end
   return found, diags
end

-- A record the suggestion fires on must also compile once the keyword is changed,
-- which is the only thing that makes the advice worth giving. Rather than trust the
-- whitelist, rewrite the source and check that nothing is reported.
local function assertSuggested(src, label)
   local found = lint(src)
   assertEq(#found, 1, (label or "expected one suggestion") .. "\n" .. src)
   assertEq(found[1].lint, "reifiable-record", "lint name")
   local asStruct = src:gsub("record ", "struct ", 1)
   local result = parser.parse(asStruct, "test")
   assertEq(#result.errors, 0, "the suggested source does not parse\n" .. asStruct)
   local diags = check.check(result, "test.g.nupp", envMod.new("."), {})
   for _, diag in ipairs(diags) do
      if diag.severity == "error" then
         error(("the suggestion does not compile: %s: %s\n%s")
            :format(diag.code, diag.msg, asStruct))
      end
   end
   return found[1]
end

local function assertSilent(src, label)
   local found = lint(src)
   assertEq(#found, 0, (label or "expected no suggestion") .. "\n" .. src)
end

local test = {}

function test.everyFieldReifiesSoStructIsAvailable()
   local d = assertSuggested([[
local record Vec2
    x: float
    y: float
end
]])
   assertEq(d.severity, "warning", "reported at the configured level")
   assertEq(d.line, 1, "reported on the declaration")
   assertEq(d.msg:find("Vec2", 1, true) ~= nil, true, "names the record")
   assertEq(d.help ~= nil, true, "says what the change costs")
end

function test.everyReifiablePrimitiveCounts()
   assertSuggested([[
local record Wide
    a: int8
    b: uint16
    c: int32
    d: int64
    e: float
    f: number
    g: boolean
end
]])
end

function test.aPointerFieldReifies()
   assertSuggested([[
local struct Cell
    v: int32
end

local record Holder
    cell: Cell*
    nilable: Cell*?
end
]])
end

function test.aStructFieldReifies()
   assertSuggested([[
local struct Inner
    v: int32
end

local record Outer
    inner: Inner
    n: int32
end
]])
end

function test.anOwnedPointerFieldIsSilent()
   -- The pointer under it reifies, but the obligation wrapped around it does not:
   -- a struct field written `owned<widget*>` is NUPP2201. The two halves agree,
   -- which is the property worth holding -- what a struct refuses is exactly what
   -- is never suggested.
   assertSilent([[
cdef struct widget
    value: int32
end

cdef function widget_free(takes value: widget*)

local record Holder
    handle: owned<widget*>
    n: int32
end
]])
end

function test.methodsAndConstructorsDoNotArgueAgainstIt()
   assertSuggested([[
local record Point
    x: float
    y: float

    constructor(x: float, y: float)
        self.x = x
        self.y = y
    end

    function sum(self): float
        return self.x + self.y
    end
end
]])
end

function test.aGcFieldIsSilent()
   assertSilent([[
local record Named
    name: string
    n: int32
end
]], "a string field cannot live in C memory")
   assertSilent([[
local record Bag
    items: {integer}
end
]], "a table field cannot live in C memory")
end

function test.aRecordReferenceIsSilent()
   -- The value, not a pointer to it: reifying would mean inlining a GC-managed
   -- table into C memory, which is what NUPP2201 refuses. `Inner` holds a string
   -- so that the only candidate under test is `Outer`.
   assertSilent([[
local record Inner
    label: string
end

local record Outer
    inner: Inner
end
]])
end

function test.noFieldsIsSilent()
   assertSilent([[
local record Empty
end
]], "an empty record is not a struct waiting to happen")
   assertSilent([[
local record OnlyMethods
    function f(self): integer
        return 1
    end
end
]], "a record with no fields at all")
end

function test.whatAStructRefusesIsSilent()
   -- An indexer and an array part are written before the fields: a field followed
   -- by `[` reads as a C array type instead.
   assertSilent([[
local record Indexed
    [string]: integer
    n: int32
end
]], "a struct has no indexer")
   assertSilent([[
local record Sequence
    {integer}
    n: int32
end
]], "a struct has no Lua array part")
   assertSilent([[
local record Meta
    n: int32
    metamethod __tostring: function(self): string
end
]], "a struct cannot declare a metamethod")
   -- `Inner` holds a string so that the only candidate under test is `Outer`. A
   -- nested declaration is legal inside a record and may itself be a struct, so a
   -- reifiable `Inner` would rightly be suggested on its own account.
   assertSilent([[
local record Outer
    n: int32

    record Inner
        label: string
    end
end
]], "a struct body holds fields only")
   assertSilent([[
local record Capable
    readonly n: int32
end
]], "a struct cannot install a property")
end

function test.genericsAndSupertypesAreSilent()
   assertSilent([[
local record Box<T>
    n: int32
end
]], "a generic record")
   assertSilent([[
local interface Shape
    n: int32
end

local record Circle is Shape
    n: int32
end
]], "a record declaring a supertype")
end

function test.aStructSaysNothingAboutItself()
   assertSilent([[
local struct Vec2
    x: float
    y: float
end
]], "the suggestion is a record's alone")
end

function test.offUntilAProjectAsks()
   local src = [[
local record Vec2
    x: float
    y: float
end
]]
   for _, diag in ipairs(check.check(parser.parse(src, "test.g.nupp"), "test",
      envMod.new("."), {})) do
      assertEq(diag.code ~= "NUPP2509", true,
         "a performance suggestion is met by asking, not by being told")
   end
   -- Whether a record is worth reifying depends on how many are built and where,
   -- which no declaration states, so the class is asked for as a class.
   local on = check.check(parser.parse(src, "test.g.nupp"), "test", envMod.new("."),
      {lints = {performance = "note"}})
   local found = nil
   for _, diag in ipairs(on) do
      if diag.code == "NUPP2509" then found = diag end
   end
   assertEq(found ~= nil, true, "the category turns it on")
   assertEq(found.severity, "note", "at the level the category asked for")
end

function test.allowSuppressesIt()
   local found = lint([[
@allow("reifiable-record")
local record Vec2
    x: float
    y: float
end
]])
   assertEq(#found, 0, "an @allow silences it")
end

function test.theSuggestionCanBeApplied()
   -- A suggestion nobody can act on is a suggestion nobody acts on. The edit is
   -- the one token that matters, and applying it has to produce a program that
   -- compiles -- which is what assertSuggested already proves separately.
   local d = assertSuggested([[
local record Vec2
    x: float
    y: float
end
]])
   assertEq(d.fixes ~= nil and #d.fixes == 1, true, "exactly one fix is offered")
   local fix = d.fixes[1]
   assertEq(fix.title, "change `record` to `struct`", "and it says what it does")
   assertEq(#fix.edits, 1, "one edit")
   assertEq(fix.edits[1].newText, "struct", "replacing the keyword")
   assertEq(fix.edits[1].length, #"record", "and only the keyword")
end

function test.theEditLandsOnTheKeywordNotAField()
   -- `record` is contextual, so a field may be called one. The scan stops at the
   -- declaration name, which the keyword always precedes.
   local d = assertSuggested([[
local record Holder
    record: int32
    n: int32
end
]])
   local edit = d.fixes[1].edits[1]
   local src = [[
local record Holder
    record: int32
    n: int32
end
]]
   -- Offsets are 1-based, as everywhere else in the toolchain.
   local applied = src:sub(1, edit.offset - 1) .. edit.newText
      .. src:sub(edit.offset + edit.length)
   assert(applied:find("^local struct Holder"),
      "the keyword was replaced, not the field:\n" .. applied)
   assert(applied:find("record: int32", 1, true),
      "the field called record survives:\n" .. applied)
end

return test
