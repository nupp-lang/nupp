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
