-- Reified positions, and the gradual-projection lint.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function codes(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(parsed, "test.g.nupp", env)) do
      out[j] = d.code
   end
   return table.concat(out, " ")
end

local function src(...)
   return table.concat({...}, "\n") .. "\n"
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function reports(source, want)
   assertEq(codes(source), want, "for:\n" .. source)
end

local HOLDS = src(
   "local interface Holds",
   "   associated type Unit",
   "end",
   "local interface Fixes",
   "   associated type Unit == float",
   "end")

local M = {}

function M.aConcreteOrFixedAnswerIsReifiable()
   clean(HOLDS .. src(
      "local record Concrete is Holds",
      "   associated type Unit = float",
      "end",
      "local struct FromConcrete",
      "   x: Concrete.Unit",
      "end",
      "local struct FromFixed",
      "   x: Fixes.Unit",
      "end",
      "local struct Nested",
      "   xs: Concrete.Unit[4]",
      "end",
      "return FromConcrete, FromFixed, Nested"))
end

function M.anOpaqueProjectionIsNotReifiable()
   reports(HOLDS .. src(
      "local struct FromOpaque<T is Holds>",
      "   x: T.Unit",
      "end",
      "return FromOpaque"), "NUPP2201")
end

-- A pointer does not need its pointee laid out, so the recursion is the existing one
-- rather than a blanket walk for projections.
function M.aPointerDoesNotAskAboutItsPointee()
   clean(HOLDS .. src(
      "local record Concrete is Holds",
      "   associated type Unit = float",
      "end",
      "local struct Held",
      "   x: float",
      "end",
      "local struct ThroughPointer",
      "   p: Held*",
      "end",
      "return ThroughPointer"))
end

-- A cycle is one fault. The reified position must not add a second complaint.
function M.aCyclicProjectionInAReifiedPositionReportsOnce()
   reports(src(
      "local interface Holds",
      "   associated type Unit",
      "end",
      "local record Loop is Holds",
      "   associated type Unit = self.Unit",
      "end",
      "local struct Uses",
      "   x: Loop.Unit",
      "end",
      "return Uses"), "NUPP2135")
end

-- One warning per call and name, however many times it occurs across both packs.
function M.aGradualCallWarnsOnce()
   reports(src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local function both<T is Holds>(a: T.Item, b: T.Item): T.Item",
      "   return a",
      "end",
      "local erased = both(nil as any, nil as any)",
      "return erased"), "NUPP2511")
end

-- An answer somebody wrote as `any` is not an erased projection.
function M.anAnswerWrittenAsAnyDoesNotWarn()
   clean(src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local record Untyped is Holds",
      "   associated type Item = any",
      "end",
      "local function held<T is Holds>(x: T): T.Item",
      "   return nil as any",
      "end",
      "local fine = held(new Untyped {})",
      "return fine"))
end

function M.theWarningCanBeSuppressed()
   clean(src(
      "local interface Holds",
      "   associated type Item",
      "end",
      "local function both<T is Holds>(a: T.Item, b: T.Item): T.Item",
      "   return a",
      "end",
      "@allow('gradual-projection')",
      "local quiet = both(nil as any, nil as any)",
      "return quiet"))
end

-- The negative the lint exists for: a wrong result cannot pass in silence. It is
-- either rejected, or the erasure that let it through is reported.
function M.aWrongResultCannotPassSilently()
   local world = src(
      "local interface Component",
      "   componentId: integer",
      "   associated type Value = self",
      "end",
      "local record Health is Component",
      "   componentId: integer",
      "   associated type Value = number",
      "end",
      "local record Archetype",
      "   function get<C is Component>(self, component: C): {C.Value}",
      "      return nil as any",
      "   end",
      "end",
      "local arch = new Archetype {}")
   -- concrete: rejected outright
   reports(world .. src(
      "local health = new Health {componentId = 1}",
      "local wrong: {string} = arch:get(health)",
      "return wrong"), "NUPP2001")
   -- erased: accepted, but the lint says the check stopped meaning anything
   reports(world .. src(
      "local wrong: {string} = arch:get(nil as any)",
      "return wrong"), "NUPP2511")
end

return M
