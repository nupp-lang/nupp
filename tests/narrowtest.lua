local parser = require("nupp.compiler.parser")
local check = require("fragment")
local narrowing = require("nupp.compiler.narrowing")
local T = require("nupp.compiler.types")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagsOf(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp")
   local out = {}
   for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
   return table.concat(out, " "), diags
end

local function assertClean(src)
   local got, diags = diagsOf(src)
   assertEq(got, "", "expected clean check for:\n" .. src
      .. (diags[1] and ("\nfirst: " .. diags[1].msg) or ""))
end

local M = {}

function M.subtractingAnExhaustiveUnionLeavesNever()
   local values = T.union({T.number, T.string})
   assertEq(narrowing.subtract(values, values), T.never)
end

function M.narrowingRetainsExplicitOpaqueOwnership()
   local source = T.affine(T.optional(T.string), nil, true)
   local narrowed = narrowing.subtract(source, T.nil_)
   assertEq(narrowed.transferOnly, true, "narrowing erased explicit transfer-only affinity")
   assertEq(T.tostring(narrowed), "affine(string)")
end

function M.nilCheckNarrowing()
   assertClean(table.concat({
      "local s: string?",
      "if s ~= nil then",
      "   local t: string = s",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "local s: string?",
      "if s == nil then",
      "else",
      "   local t: string = s",
      "end",
   }, "\n"))
   -- without the check it still errors
   assertEq((diagsOf("local s: string?\nlocal t: string = s")),
      "NUPP2001:2")
end

function M.truthinessNarrowing()
   assertClean(table.concat({
      "local s: string?",
      "if s then",
      "   local t: string = s",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "local s: string?",
      "if not s then",
      "else",
      "   local t: string = s",
      "end",
   }, "\n"))
end

function M.isNarrowing()
   assertClean(table.concat({
      "local v: number | string",
      "if v is string then",
      "   local s: string = v",
      "else",
      "   local n: number = v",
      "end",
   }, "\n"))
end

function M.elseifAccumulatesElseFacts()
   assertClean(table.concat({
      "local v: number | string | nil",
      "if v is string then",
      "   local s: string = v",
      "elseif v is number then",
      "   local n: number = v",
      "else",
      "   local z: nil = v",
      "end",
   }, "\n"))
end

function M.guardClauseNarrowing()
   assertClean(table.concat({
      "local function f(s: string?): string",
      "   if not s then return 'default' end",
      "   return s",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "local function f(s: string?): string",
      "   if s == nil then error('nope') end",
      "   return s",
      "end",
   }, "\n"))
end

function M.andOrRhsNarrowing()
   -- the previously-deferred idiom now checks
   assertClean("local s: string?\nlocal t: string = s and s .. '!' or 'none'")
   assertClean("local n: number?\nlocal m: number = n and n + 1 or 0")
end

function M.andConditionFacts()
   assertClean(table.concat({
      "local a: string?",
      "local b: number?",
      "if a and b then",
      "   local s: string = a",
      "   local n: number = b",
      "end",
   }, "\n"))
end

function M.whileNarrowing()
   assertClean(table.concat({
      "local head: {x: number}?",
      "while head do",
      "   local n: number = head.x",
      "   head = nil",
      "end",
   }, "\n"))
end

function M.ternaryNarrowing()
   assertClean("local s: string?\nlocal t: string = s ~= nil ? s : 'd'")
end

function M.genericsInstantiation()
   assertClean(table.concat({
      "local id: function<T>(x: T): T",
      "local n: number = id(42)",
      "local s: string = id('hi')",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local id: function<T>(x: T): T",
      "local n: number = id('hi')",
   }, "\n"))), "NUPP2001:2")
   assertClean(table.concat({
      "local first: function<V>(xs: {V}): V",
      "local n: number = first({1, 2, 3})",
   }, "\n"))
end

-- Every caller of analyzeCond infers the condition first, so a condition the
-- narrowing pass looked at a second time reported its problems twice.
function M.conditionIsCheckedOnce()
   assertEq((diagsOf(table.concat({
      "local function f(s: string): boolean",
      "   return #s > 0",
      "end",
      "local function g(s: number): number",
      "   if f(s) then",
      "      return 1",
      "   end",
      "   return f(s) and 1 or 2",
      "end",
   }, "\n"))), "NUPP2006:5 NUPP2006:8")
   assertEq((diagsOf(table.concat({
      "local x: any",
      "if x is Unknowable then",
      "end",
   }, "\n"))), "NUPP2101:2 NUPP3001:2")
end

function M.genericMapIteration()
   assertClean(table.concat({
      "local pairs2: function<K, V>(t: {[K]: V}): function(): (K, V)",
      "local m: {[string]: number} = {}",
      "for k, v in pairs2(m) do",
      "   local s: string = k",
      "   local n: number = v",
      "end",
   }, "\n"))
end

return M
