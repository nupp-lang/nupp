-- Record and struct members, and multi-value return expansion.
local parser = require("nupp.parser")
local check = require("nupp.check")
local gen = require("nupp.gen")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagsOf(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test", env)) do
      out[j] = d.code .. ":" .. d.line
   end
   return table.concat(out, " ")
end

local function assertClean(src)
   assertEq(diagsOf(src), "", "expected clean:\n" .. src)
end

local function run(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test", env)
   assertEq(#diags, 0, "check: " .. (diags[1] and diags[1].msg or ""))
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@methodtest")
   if not chunk then
      error("generated code does not load: " .. tostring(err) .. "\n" .. code, 2)
   end
   return chunk()
end

local TASK = table.concat({
   "local record Task",
   "    title: string",
   "end",
   "function Task:describe(): string",
   "    return self.title",
   "end",
}, "\n")

local M = {}

function M.recordMethodsTypeAtCallSites()
   assertClean(TASK .. "\nlocal t: Task = new Task {}\nlocal s: string = t:describe()")
   assertEq(diagsOf(TASK .. "\nlocal t: Task = new Task {}\nlocal n: number = t:describe()"),
      "NUPP2001:8")
   assertEq(diagsOf(TASK .. "\nlocal t: Task = new Task {}\nt:describe(1)"), "NUPP2007:8")
   assertEq(diagsOf(TASK .. "\nlocal t: Task = new Task {}\nt:nosuch()"), "NUPP2004:8")
end

function M.selfIsBoundInsideMethods()
   assertClean(TASK)
   -- self carries the record's fields
   assertEq(diagsOf(table.concat({
      "local record R",
      "    n: number",
      "end",
      "function R:bad(): number",
      "    return self.nope",
      "end",
   }, "\n")), "NUPP2004:5")
end

function M.dottedMembersTakeNoReceiver()
   assertClean(table.concat({
      "local record R",
      "    n: number",
      "end",
      "function R.make(v: number): R",
      "    return {n = v} as R",
      "end",
      "local r: R = R.make(1)",
   }, "\n"))
end

function M.recordMethodsRunAtRuntime()
   assertEq(run(TASK .. table.concat({
      "",
      "local t = new Task {title = 'ok'}",
      "return t:describe()",
   }, "\n")), "ok")
end

function M.structMethodsDispatchThroughMetatype()
   local src = table.concat({
      "local struct Vec2",
      "    x: float",
      "    y: float",
      "end",
      "function Vec2:len(): number",
      "    return (self.x * self.x + self.y * self.y) ^ 0.5",
      "end",
      "local v = new Vec2 {x = 3, y = 4}",
      "return v:len()",
   }, "\n")
   assertClean(src)
   assertEq(run(src), 5)
   -- the constructor still works after metatype
   assertEq(run(table.concat({
      "local struct P",
      "    n: float",
      "end",
      "function P:twice(): number",
      "    return self.n * 2",
      "end",
      "local p = new P {n = 21}",
      "return p:twice()",
   }, "\n")), 42)
end

function M.multiValueReturnsExpandAcrossTargets()
   local two = table.concat({
      "local function two(): number, string",
      "    return 1, 'two'",
      "end",
   }, "\n")
   assertClean(two .. "\nlocal a, b = two()\nlocal n: number = a\nlocal s: string = b")
   assertEq(diagsOf(two .. "\nlocal a, b = two()\nlocal bad: number = b"),
      "NUPP2001:5")
   -- only the trailing expression expands
   assertClean(two .. "\nlocal x, y, z = 0, two()\nlocal n: number = y")
   assertEq(diagsOf(two .. "\nlocal x, y, z = 0, two()\nlocal bad: number = z"),
      "NUPP2001:5")
end

-- Only a call expands. Inferring anything else may still have left a call's
-- results behind — a function expression whose body calls something does — and
-- taking those for the expression's own type gave a function the type of
-- whatever it last called.
function M.onlyACallExpandsAcrossTargets()
   local two = table.concat({
      "local function two(): number, string",
      "    return 1, 'two'",
      "end",
   }, "\n")
   -- the value is the function, not what its body returns
   assertClean(two .. "\n" .. table.concat({
      "local f: function(): (number, string) = two",
      "local a, b = f()",
      "local n: number = a",
   }, "\n"))
   -- a function expression assigned to a declared field, whose body both
   -- recurses and returns a multi-value call
   assertClean(table.concat({
      "local m = {}",
      "record m.Box",
      "    one: function(n: string?): string?",
      "    two: function(n: string?): (string?, any)",
      "end",
      "local b = new m.Box {}",
      "b.one = function(n)",
      "    if n == 'x' then return b.one(n) end",
      "    return b.two(n)",
      "end",
      "b.two = function(n)",
      "    return n, nil",
      "end",
      "return m",
   }, "\n"))
end

-- `new` is the construction, for both kinds of declaration. It lowers to the
-- stamp and the ctype call themselves, so what it costs at run time is nothing.
function M.newConstructsRecordsAndStructs()
   assertEq(run(table.concat({
      "local record Account",
      "    name: string",
      "    balance: number",
      "    function deposit(credit: number)",
      "        self.balance = self.balance + credit",
      "    end",
      "end",
      "local struct V2",
      "    x: float",
      "    y: float",
      "end",
      "local a = new Account {name = 'Hina', balance = 500}",
      "local named = new V2 {x = 3.0, y = 4.0}",
      "local positional = new V2(1.0, 2.0)",
      "a:deposit(20)",
      "return a.balance + named.x + named.y + positional.x + positional.y",
   }, "\n")), 530)
end

-- The keyword is contextual: `new` is a name everywhere a name can stand, and
-- only a name following it on the same line makes it a construction.
function M.newStaysAnOrdinaryNameElsewhere()
   assertEq(run(table.concat({
      "local record R",
      "    n: integer",
      "end",
      "local function id(x: any): any return x end",
      "local new = id",
      "local held = new",
      "id(R)",
      "local built = new R {n = 5}",
      "return built.n + (held == id and 1 or 0)",
   }, "\n")), 6)
end

-- What `new` names is a type, so an operand that is not one is answered as a
-- type rather than through whatever value stands under the name. An interface
-- binds no value at all, so going through the value would say `any`.
function M.newRefusesWhatCannotBeConstructed()
   assertEq(diagsOf(table.concat({
      "local interface I",
      "    n: integer",
      "end",
      "local iface = new I()",
   }, "\n")), "NUPP2206:4")
   assertEq(diagsOf("local prim = new string()"), "NUPP2206:1")
   assertEq(diagsOf(table.concat({
      "local enum Color",
      "    'red'",
      "end",
      "local c = new Color()",
   }, "\n")), "NUPP2206:4")
end

-- A refinement is what `is` compiles to. The values here were never built by
-- this program, which is the case a stamped metatable cannot answer: a table
-- off a decoder, or anything an untyped library handed back.
function M.whereRefinementsDecideIsAtRuntime()
   assertEq(run(table.concat({
      "local interface Shape",
      "   kind: string",
      "end",
      "local record Circle is Shape where self.kind == 'circle'",
      "   kind: string",
      "   radius: number",
      "end",
      "local record Square is Shape where self.kind == 'square'",
      "   kind: string",
      "   side: number",
      "end",
      "local function area(s: Shape): number",
      "   if s is Circle then return 3 * s.radius * s.radius end",
      "   if s is Square then return s.side * s.side end",
      "   return 0",
      "end",
      "local decoded: Shape = {kind = 'circle', radius = 2} as Shape",
      "local other: Shape = {kind = 'square', side = 3} as Shape",
      "return area(decoded) + area(other)",
   }, "\n")), 21)
end

-- An interface has no runtime table to stamp, so `is` on one was NUPP3001 and
-- could not be compiled at all. A refinement is the answer it can give.
function M.whereRefinementsGiveAnInterfaceARuntimeIdentity()
   assertEq(run(table.concat({
      "local interface Tagged where type(self.tag) == 'string'",
      "   tag: string",
      "end",
      "local function describe(v: any): string",
      "   if v is Tagged then return 'tagged ' .. v.tag end",
      "   return 'untagged'",
      "end",
      "return describe({tag = 'x'}) .. '/' .. describe(42)",
   }, "\n")), "tagged x/untagged")
end

-- A refinement may read the subject more than once, so a subject that is not a
-- name is evaluated once and handed to the test.
function M.aComputedSubjectIsEvaluatedOnce()
   assertEq(run(table.concat({
      "local interface Tagged where self.tag == 'x'",
      "   tag: string",
      "end",
      "local calls = 0",
      "local function make(): any",
      "   calls = calls + 1",
      "   return {tag = 'x'}",
      "end",
      "local hit = make() is Tagged",
      "return (hit and 10 or 0) + calls",
   }, "\n")), 11)
end

-- A constructor is the whole reason `new` is worth having over a literal: a
-- literal may leave a declared field out, and a constructor may not.
function M.constructorsRunAndFillEveryField()
   assertEq(run(table.concat({
      "local record Account",
      "    name: string",
      "    balance: number",
      "    constructor(name: string, opening: number)",
      "        self.name = name",
      "        self.balance = opening",
      "    end",
      "    function deposit(credit: number)",
      "        self.balance = self.balance + credit",
      "    end",
      "end",
      "local a = new Account('Hina', 500)",
      "a:deposit(20)",
      "return a.balance",
   }, "\n")), 520)
   -- the instance is a real one: `is` still answers through the metatable
   assertEq(run(table.concat({
      "local record R",
      "    n: integer",
      "    constructor(v: integer)",
      "        self.n = v",
      "    end",
      "end",
      "local r = new R(7)",
      "return (r is R) and r.n or 0",
   }, "\n")), 7)
end

function M.constructorsRefuseWhatTheyCannotGuarantee()
   -- a field that cannot hold nil has to be filled
   assertEq(diagsOf(table.concat({
      "local record A",
      "    name: string",
      "    balance: number",
      "    constructor(n: string)",
      "        self.name = n",
      "    end",
      "end",
   }, "\n")), "NUPP2208:4")
   -- an optional one need not be
   assertClean(table.concat({
      "local record B",
      "    name: string",
      "    note: string?",
      "    constructor(n: string)",
      "        self.name = n",
      "    end",
      "end",
   }, "\n"))
   -- an interface builds nothing
   assertEq(diagsOf(table.concat({
      "local interface I",
      "    n: integer",
      "    constructor(v: integer)",
      "        self.n = v",
      "    end",
      "end",
   }, "\n")), "NUPP2208:3")
   -- and one constructor, until overloads arrive with intersections
   assertEq(diagsOf(table.concat({
      "local record T",
      "    n: integer",
      "    constructor(v: integer)",
      "        self.n = v",
      "    end",
      "    constructor(v: string)",
      "        self.n = #v",
      "    end",
      "end",
   }, "\n")), "NUPP2208:6")
end

-- Declaring a constructor closes the literal form. Leaving it open beside one
-- would let every invariant the constructor establishes be walked around.
function M.aConstructorClosesTheLiteralForm()
   local decl = table.concat({
      "local record A",
      "    n: integer",
      "    constructor(v: integer)",
      "        self.n = v",
      "    end",
      "end",
   }, "\n")
   assertEq(diagsOf(decl .. "\nlocal a = new A {n = 1}"), "NUPP2208:7")
   assertClean(decl .. "\nlocal a = new A(1)")
   -- `constructor` is contextual: a field may still be called one
   assertClean(table.concat({
      "local record C",
      "    constructor: string",
      "end",
      "local c = new C {constructor = 'x'}",
   }, "\n"))
end

function M.multiValueReturnsInAssignments()
   local two = table.concat({
      "local function two(): number, string",
      "    return 1, 'two'",
      "end",
      "local a: number = 0",
      "local b: string = ''",
   }, "\n")
   assertClean(two .. "\na, b = two()")
   assertEq(diagsOf(two .. "\nb, a = two()"), "NUPP2001:6 NUPP2001:6")
end

return M
