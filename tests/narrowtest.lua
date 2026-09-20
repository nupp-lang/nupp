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

function M.orDropsAFalseLeftOperand()
   -- `cond and nil or x` is the Lua spelling of a conditional; its left side can
   -- only be nil or false, neither of which `or` yields.
   assertClean("local i = 2\nlocal v: string = i == 2 and nil or 's'")
   assertClean("local i = 2\nlocal w: string = (i == 2 and false) or 's'")
   assertClean("local f: false | nil = nil\nlocal s: string = f or 's'")
   assertEq((diagsOf("local b: boolean = true\nlocal s: string = b or 's'")), "NUPP2001:2")
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

function M.isTestsAnAliasOfAPrimitiveByItsResolvedType()
   assertClean(table.concat({
      "local type Text = string",
      "local type Count = integer",
      "local x: any",
      "if x is Text then",
      "elseif x is Count then",
      "end",
   }, "\n"))
end

-- A test whose subject and target share no value answers false on every run, so the
-- branch it guards is one nothing reaches. `is` sits at the comparison level and `not`
-- binds tighter, which makes `not v is T` one of the ways to write one.
function M.isRefusesATestNoValueCouldPass()
   assertEq((diagsOf(table.concat({
      "local record Box",
      "   value: integer",
      "end",
      "local function settled(v: Box | string): boolean return not v is Box end",
   }, "\n"))), "NUPP2147:4")
   assertEq((diagsOf(table.concat({
      "local record Circle",
      "   radius: number",
      "end",
      "local record Square",
      "   side: number",
      "end",
      "local function test(shape: Circle): boolean return shape is Square end",
   }, "\n"))), "NUPP2147:7")
   assertEq((diagsOf(table.concat({
      "local function test(count: integer): boolean return count is string end",
   }, "\n"))), "NUPP2147:1")
end

-- And leaves alone every test whose answer is not settled: a downcast, an alternative
-- of the union the subject already is, a gradual subject, an unsubstituted binder, and
-- a target whose runtime test is coarser than the type written.
function M.isLeavesATestItCannotRuleOut()
   assertClean(table.concat({
      "local interface Named",
      "   name: string",
      "end",
      "local record Circle",
      "   name: string",
      "   radius: number",
      "end",
      "local record Square",
      "   name: string",
      "   side: number",
      "end",
      "local function downcast(v: Named): boolean return v is Circle end",
      "local function alternative(v: Circle | Square): boolean return v is Circle end",
      "local function gradual(v: any): boolean return v is Circle end",
      "local function binder<T>(v: T): boolean return v is string end",
      "local function coarse(v: {integer}): boolean return v is table end",
      "local function optional(v: string?): boolean return v is nil end",
      "local function grouped(v: Circle | Square): boolean return not (v is Circle) end",
      "print(downcast, alternative, gradual, binder, coarse, optional, grouped)",
   }, "\n"))
end

function M.isStillRefusesATypeWithNoRuntimeIdentity()
   assertEq((diagsOf(table.concat({
      "local type Pair = {a: string, b: string}",
      "local x: any",
      "if x is Pair then",
      "end",
   }, "\n"))), "NUPP3001:3")
end

-- `cond and value or fallback` reaches the fallback only when the conjunction was
-- falsy, and when the second conjunct is something no run can find falsy that leaves
-- the first as the only way there. The fallback then knows what the test ruled out,
-- which is the difference between this reading as `string` and as the union it
-- started from.
function M.aConjunctionThatCannotBeFalsyOnTheRightNarrowsItsFallback()
   assertClean(table.concat({
      "local record Wrapped",
      "   text: string",
      "end",
      "local value: Wrapped | string = 'plain'",
      "local through: string = value is Wrapped and value.text or value",
      "local literal: string = value is Wrapped and 'wrapped' or value",
      "local built: string = value is Wrapped and `w:${value.text}` or value",
   }, "\n"))
end

-- And leaves it alone when the second conjunct could have been the one that failed:
-- an optional field says nothing about the test beside it.
function M.aConjunctionWithAFalsyRightSideLeavesItsFallbackAlone()
   assertEq((diagsOf(table.concat({
      "local record Wrapped",
      "   text: string?",
      "end",
      "local value: Wrapped | string = 'plain'",
      "local through: string = value is Wrapped and value.text or value",
   }, "\n"))), "NUPP2001:5")
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
