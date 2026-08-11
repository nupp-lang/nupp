-- Cycles and refinement compatibility.
--
-- A cycle left alone stays an opaque projection, and an opaque projection fits its
-- bound, so directional subtyping would let one through in silence. It has to be
-- observed where the answers are, not where they are used.
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

local M = {}

function M.aDirectCycleReports()
   reports(src(
      "local interface Holds",
      "   associated type Value",
      "end",
      "local record Direct is Holds",
      "   associated type Value = Direct.Value",
      "end",
      "return Direct"), "NUPP2135")
end

-- Two names reaching each other are one cycle, and report once.
function M.anIndirectCycleReportsOnce()
   reports(src(
      "local interface A",
      "   associated type Left",
      "end",
      "local interface B",
      "   associated type Right",
      "end",
      "local record Two is A, B",
      "   associated type Left = Two.Right",
      "   associated type Right = Two.Left",
      "end",
      "return Two"), "NUPP2135")
end

-- A forward reference is ordinary; only the whole graph says whether it closes.
function M.aForwardReferenceThatClosesIsFine()
   clean(src(
      "local interface A",
      "   associated type Left",
      "end",
      "local interface B",
      "   associated type Right",
      "end",
      "local record Fine is A, B",
      "   associated type Left = Fine.Right",
      "   associated type Right = string",
      "end",
      "return Fine"))
end

-- A cyclic default means nothing until somebody takes it.
function M.aCyclicDefaultIsLatentAndSurfacesOnTheImplementor()
   clean(src(
      "local interface Latent",
      "   associated type Value = self.Value",
      "end",
      "return Latent"))
   reports(src(
      "local interface Latent",
      "   associated type Value = self.Value",
      "end",
      "local record Takes is Latent",
      "end",
      "return Takes"), "NUPP2135")
end

-- A fixed equality is the contract's own promise, so its cycle is the contract's.
function M.aFixedCycleReportsOnTheInterface()
   reports(src(
      "local interface Fixed",
      "   associated type Value == Fixed.Value",
      "end",
      "return Fixed"), "NUPP2135")
end

function M.aCycleThroughAGenericInstantiationReports()
   reports(src(
      "local interface Holds",
      "   associated type Value",
      "end",
      "local record Cell<E> is Holds",
      "   associated type Value = self.Value",
      "   held: E",
      "end",
      "return Cell"), "NUPP2135")
end

-- A refinement is a run-time test and an associated type is erased.
function M.aRefinementNeedsASettledAssociatedSurface()
   local shape = src(
      "local interface Shape",
      "   kind: string",
      "end")
   reports(shape .. src(
      "local interface Bare is Shape",
      "   kind: 'bare'",
      "   associated type Item",
      "   matches",
      "      self.kind == 'bare'",
      "   end",
      "end",
      "return Bare"), "NUPP2122")
   reports(shape .. src(
      "local interface Defaulted is Shape",
      "   kind: 'defaulted'",
      "   associated type Item = string",
      "   matches",
      "      self.kind == 'defaulted'",
      "   end",
      "end",
      "return Defaulted"), "NUPP2122")
   clean(shape .. src(
      "local interface Fixed is Shape",
      "   kind: 'fixed'",
      "   associated type Item == string",
      "   matches",
      "      self.kind == 'fixed'",
      "   end",
      "end",
      "return Fixed"))
end

-- Inherited requirements count, and a derived contract may settle them.
function M.aDerivedContractMaySettleWhatItInherited()
   local base = src(
      "local interface Shape",
      "   kind: string",
      "end",
      "local interface Bare is Shape",
      "   associated type Item",
      "end")
   reports(base .. src(
      "local interface Loose is Bare",
      "   kind: 'loose'",
      "   matches",
      "      self.kind == 'loose'",
      "   end",
      "end",
      "return Loose"), "NUPP2122")
   clean(base .. src(
      "local interface Settled is Bare",
      "   kind: 'settled'",
      "   associated type Item == string",
      "   matches",
      "      self.kind == 'settled'",
      "   end",
      "end",
      "return Settled"))
end

-- A cycle is the component, not the path it was entered from. Two members of one
-- cycle, and the two declaration orders, are one fault each way round.
function M.oneCycleIsOneFaultHoweverItIsEntered()
   local contracts = src(
      "local interface A",
      "   associated type Left",
      "end",
      "local interface B",
      "   associated type Right",
      "end")
   reports(contracts .. src(
      "local record Closes is A, B",
      "   associated type Left = Closes.Right",
      "   associated type Right = Closes.Left",
      "end",
      "return Closes"), "NUPP2135")
   reports(contracts .. src(
      "local record Reversed is A, B",
      "   associated type Right = Reversed.Left",
      "   associated type Left = Reversed.Right",
      "end",
      "return Reversed"), "NUPP2135")
   -- three members round one cycle is still one fault
   reports(src(
      "local interface Three",
      "   associated type X",
      "   associated type Y",
      "   associated type Z",
      "end",
      "local record Round is Three",
      "   associated type X = Round.Y",
      "   associated type Y = Round.Z",
      "   associated type Z = Round.X",
      "end",
      "return Round"), "NUPP2135")
end

-- Fixed is not the same as settled. `== any` says nothing a run-time test can check.
function M.aFixedGradualAnswerDoesNotSettleARefinement()
   reports(src(
      "local interface Shape",
      "   kind: string",
      "end",
      "local interface Gradual is Shape",
      "   kind: 'gradual'",
      "   associated type Item == any",
      "   matches",
      "      self.kind == 'gradual'",
      "   end",
      "end",
      "return Gradual"), "NUPP2122")
end

return M
