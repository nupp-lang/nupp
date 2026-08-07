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
   assertClean(TASK .. "\nlocal t: Task\nlocal s: string = t:describe()")
   assertEq(diagsOf(TASK .. "\nlocal t: Task\nlocal n: number = t:describe()"),
      "NUPP2001:8")
   assertEq(diagsOf(TASK .. "\nlocal t: Task\nt:describe(1)"), "NUPP2007:8")
   assertEq(diagsOf(TASK .. "\nlocal t: Task\nt:nosuch()"), "NUPP2004:8")
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
      "local t = Task{title = 'ok'}",
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
      "local v = Vec2{x = 3, y = 4}",
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
      "local p = P{n = 21}",
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
      "local b = m.Box{}",
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
