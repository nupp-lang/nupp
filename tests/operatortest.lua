local testAssert = require("nupp.test")
-- Nil-coalescing and compound assignment: semantics, not just syntax.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function run(src, tolerate)
   local result = parser.parse(src, "test.g.nupp")
   testAssert.equal(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = {}
   for _, d in ipairs(check.check(result, "test.g.nupp", env)) do
      if d.code ~= tolerate then diags[#diags + 1] = d end
   end
   testAssert.equal(#diags, 0, "check: " .. (diags[1] and diags[1].msg or ""))
   local code, genDiags = gen.generate(result, "test")
   testAssert.equal(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@optest")
   if not chunk then
      error("does not load: " .. tostring(err) .. "\n" .. code, 2)
   end
   return chunk()
end

local function diagsOf(src)
   local result = parser.parse(src, "test.g.nupp")
   testAssert.equal(#result.errors, 0, "syntax errors")
   local out = {}
   for j, d in ipairs(check.check(result, "test.g.nupp", env)) do out[j] = d.code end
   return table.concat(out, " ")
end

local M = {}

-- The integer answer for `%` and `//` is documented as a promise about the
-- divisor: `7 % 0` is nan at run time, and the checker does not follow a
-- divisor back to a value, so `index % count` stays the integer it is.
function M.integralRemainderAndFloorQuotientStayIntegral()
   testAssert.equal(diagsOf("local a: integer = 7\nlocal n: integer = 2\nlocal m: integer = a % n\nlocal q: integer = a // n"), "")
   testAssert.equal(run("local a: integer = 7\nlocal z: integer = 0\nlocal m: integer = a % z\nreturn m ~= m"), true)
end

function M.nilCoalescingPrefersTheLeft()
   testAssert.equal(run("return 1 ?? 2"), 1)
   testAssert.equal(run("local a = nil\nreturn a ?? 'fallback'"), "fallback")
   -- false is a value, not an absence: `or` gets this wrong, `??` must not
   testAssert.equal(run("return false ?? 'wrong'"), false)
   testAssert.equal(run("local t = {}\nreturn t.missing ?? 'gone'"), "gone")
end

function M.nilCoalescingIsLazyAndEvaluatesTheLeftOnce()
   testAssert.equal(run([[
local calls = 0
local function side() calls = calls + 1 return 'x' end
local _ = side() ?? 'unused'
return calls]]), 1)
   testAssert.equal(run([[
local hits = 0
local function boom() hits = hits + 1 return 0 end
local _ = 'present' ?? boom()
return hits]]), 0)
end

function M.nilCoalescingTypesDropNil()
   -- the result cannot be nil once a fallback is supplied
   testAssert.equal(diagsOf("local a: number?\nlocal b: number = a ?? 0"), "")
   testAssert.equal(diagsOf("local a: number?\nlocal b: number = a"), "NUPP2001")
end

function M.compoundArithmetic()
   testAssert.equal(run("local a = 1\na += 2\nreturn a"), 3)
   testAssert.equal(run("local a = 10\na -= 4\nreturn a"), 6)
   testAssert.equal(run("local a = 3\na *= 4\nreturn a"), 12)
   testAssert.equal(run("local a = 12\na /= 4\nreturn a"), 3)
   testAssert.equal(run("local a = 7\na //= 2\nreturn a"), 3)
   testAssert.equal(run("local a = 7\na %= 4\nreturn a"), 3)
   testAssert.equal(run("local s = 'a'\ns ..= 'b'\nreturn s"), "ab")
end

function M.compoundBitOperations()
   testAssert.equal(run("local a = 5\na &= 3\nreturn a"), 1)
   testAssert.equal(run("local a = 5\na |= 2\nreturn a"), 7)
   testAssert.equal(run("local a = 1\na <<= 4\nreturn a"), 16)
   testAssert.equal(run("local a = 256\na >>= 4\nreturn a"), 16)
   testAssert.equal(run("local a = -8\na ~>>= 1\nreturn a"), -4)
end

function M.compoundNilCoalescingAssign()
   testAssert.equal(run("local a = nil\na ??= 5\nreturn a"), 5)
   testAssert.equal(run("local a = 1\na ??= 5\nreturn a"), 1)
   -- false is present, so it is kept
   testAssert.equal(run("local a = false\na ??= 5\nreturn a"), false)
end

function M.compoundAssignmentOnFields()
   testAssert.equal(run("local t = {x = 1}\nt.x += 2\nreturn t.x"), 3)
   testAssert.equal(run("local t = {[1] = 5}\nt[1] *= 3\nreturn t[1]"), 15)
   testAssert.equal(run("local t = {n = nil}\nt.n ??= 7\nreturn t.n"), 7)
   testAssert.equal(run("local t = {s = 'a'}\nt.s ..= 'b'\nreturn t.s"), "ab")
end

function M.compoundAssignmentEvaluatesThePrefixOnce()
   -- obj.field += v must not re-run whatever produced obj
   testAssert.equal(run([[
local calls = 0
local box = {n = 1}
local function get() calls = calls + 1 return box end
get().n += 10
return calls]]), 1)
   testAssert.equal(run([[
local box = {n = 1}
local calls = 0
local function get() calls = calls + 1 return box end
get().n += 10
return box.n]]), 11)
   -- and the key of an indexed target is evaluated once too
   testAssert.equal(run([[
local keys = 0
local t = {[1] = 1}
local function key() keys = keys + 1 return 1 end
t[key()] += 5
return keys]]), 1)
end

function M.compoundAssignmentIsChecked()
   testAssert.equal(diagsOf("local s = 'text'\ns += 1"), "NUPP2003")
   testAssert.equal(diagsOf("local n: number = 1\nn ??= 'text'"), "NUPP2001")
   testAssert.equal(diagsOf("local t = {}\nt.x += 1"), "")
end

function M.inequalityIsUntouched()
   -- `~=` stays the inequality operator in every expression position; only a
   -- statement reads it as xor-assign, and Lua has no assignment expression
   -- for the two readings to meet in.
   testAssert.equal(run("return 1 ~= 2"), true)
   testAssert.equal(run("local a = 1\nlocal b = 2\nreturn a ~= b"), true)
   testAssert.equal(run("local a = 1\nreturn (a ~= 2) and 'ne' or 'eq'"), "ne")
end

function M.compoundExclusiveOr()
   testAssert.equal(run("local a = 5\na ~= 3\nreturn a"), 6)
   testAssert.equal(run("local t = {x = 5}\nt.x ~= 3\nreturn t.x"), 6)
   testAssert.equal(run([[
local calls = 0
local box = {n = 5}
local function get() calls = calls + 1 return box end
get().n ~= 3
return calls]]), 1)
end

-- The customary spellings are always linted, so these run past that one code.
local CUSTOMARY = "NUPP2504"

function M.customaryOperatorsMeanTheClassicOnes()
   testAssert.equal(run("return 1 < 2 && 2 < 3", CUSTOMARY), true)
   testAssert.equal(run("return false || 'fallback'", CUSTOMARY), "fallback")
   testAssert.equal(run("return !false", CUSTOMARY), true)
   testAssert.equal(run("return 1 != 2", CUSTOMARY), true)
   -- short-circuiting is the classic behaviour, not a re-implementation
   testAssert.equal(run([[
local hits = 0
local function boom() hits = hits + 1 return true end
local _ = false && boom()
local _ = true || boom()
return hits]], CUSTOMARY), 0)
   -- and they mix freely with the words they spell
   testAssert.equal(run("return (1 < 2 and 3 > 2) == (1 < 2 && 3 > 2)", CUSTOMARY), true)
end

function M.customaryOperatorsAreLinted()
   -- the lint is the only thing that notices; the meaning is unchanged
   testAssert.equal(diagsOf("local a = true\nlocal b = !a"), "NUPP2504")
   testAssert.equal(diagsOf("local a = true\nlocal b = a && a"), "NUPP2504")
   testAssert.equal(diagsOf("local a = true\nlocal b = a || a"), "NUPP2504")
   testAssert.equal(diagsOf("local a = 1\nlocal b = a != 2"), "NUPP2504")
   testAssert.equal(diagsOf("local a = true\nlocal b = not a"), "")
   -- and a statement can wave it away
   testAssert.equal(diagsOf('local a = true\n@allow("customary-operator")\nlocal b = !a'),
      "")
   testAssert.equal(diagsOf("local a = true\n@allow(NUPP2504)\nlocal b = !a"), "")
end

function M.emptyPipesAreBothOperatorAndParameterList()
   testAssert.equal(run("local f = || -> 7\nreturn f()"), 7)
   testAssert.equal(run("local a = nil\nreturn a || 'or'", CUSTOMARY), "or")
   -- one token, two readings, decided by position: the first `||` is `or`
   -- because an operand precedes it, the second is an empty parameter list
   testAssert.equal(run("local f = false || || -> 'inner'\nreturn type(f)", CUSTOMARY),
      "function")
end

function M.safeMethodCalls()
   -- `?.:` checks the receiver
   testAssert.equal(run("local t = nil\nreturn t?.:m()"), nil)
   testAssert.equal(run([[
local t = {}
function t:m() return 'called' end
return t?.:m()]]), "called")
   -- `:m?.()` checks the method
   testAssert.equal(run("local t = {}\nreturn t:m?.()"), nil)
   testAssert.equal(run([[
local t = {}
function t:m(n) return n + self.base end
t.base = 10
return t:m?.(5)]]), 15)
   -- both, and the receiver is evaluated once
   testAssert.equal(run([[
local calls = 0
local box = {}
function box:m() return 'ok' end
local function get() calls = calls + 1 return box end
local _ = get()?.:m?.()
return calls]]), 1)
   -- a suppressed call does not evaluate its arguments
   testAssert.equal(run([[
local hits = 0
local function boom() hits = hits + 1 return 1 end
local t = nil
local _ = t?.:m(boom())
return hits]]), 0)
end

function M.safeNavigationAssignmentTargets()
   testAssert.equal(run("local t = {}\nt?.x = 1\nreturn t.x"), 1)
   testAssert.equal(run("local t = nil\nt?.x = 1\nreturn t"), nil)
   testAssert.equal(run("local t = {}\nt?.['k'] = 2\nreturn t.k"), 2)
   testAssert.equal(run("local t = {x = 1}\nt?.x += 4\nreturn t.x"), 5)
   testAssert.equal(run("local t = nil\nt?.x += 4\nreturn t"), nil)
   testAssert.equal(run("local t = {}\nt?.x ??= 9\nreturn t.x"), 9)
   -- the value of a suppressed assignment is never evaluated
   testAssert.equal(run([[
local hits = 0
local function boom() hits = hits + 1 return 1 end
local t = nil
t?.x = boom()
return hits]]), 0)
end

return M
