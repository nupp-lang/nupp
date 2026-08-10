-- Conformance to an interface that carries associated requirements.
--
-- Members can be satisfied by shape, but an answer needs somewhere to live and a
-- structural value has nowhere. So an interface is nominal at that part, and the
-- rule has to sit in the subtyping relation -- enforcing it only in generic call
-- checking would let `local x: I = value` accept a value that answers nothing.
local T = require("nupp.compiler.types")
local relations = require("nupp.compiler.relations")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local NAMED = T.nominal("Named", "interface")
NAMED.byname = {name = T.string}

-- `interface Holder  count: integer  associated type Item [is bound] end`
local function contract(name, bound)
   local n = T.nominal(name, "interface")
   n.byname = {count = T.integer}
   n.selfType = T.typevar("self", name .. ":self")
   n.associatedRequirements = {{name = "Item", bound = bound}}
   return n
end

local function implementing(name, of, answer)
   local n = T.nominal(name, "record")
   n.byname = {count = T.integer}
   n.supertypes = {of}
   if answer then
      n.associatedAnswers = {Item = answer}
   end
   return n
end

local function fits(a, b)
   local ok = relations.isA(a, b)
   return ok and true or false
end

local M = {}

-- The case the whole layer exists for.
function M.aStructuralValueCannotSatisfyAnAssociatedInterface()
   local holder = contract("Holder")
   local shaped = T.shape({{name = "count", read = T.integer, write = T.integer}}, {}, nil)
   assertEq(fits(shaped, holder), false, "a shape answered an associated type")
   -- A record carrying every member but declaring no contract is the same case: it
   -- has the fields and no answering site.
   local lookalike = T.nominal("Lookalike", "record")
   lookalike.byname = {count = T.integer}
   assertEq(fits(lookalike, holder), false, "a structural record answered one")
   -- and the members alone still satisfy an ordinary interface
   local plain = T.nominal("Plain", "interface")
   plain.byname = {count = T.integer}
   assertEq(fits(shaped, plain), true, "an ordinary interface stopped being structural")
end

function M.aConcreteRecordWithAFittingAnswerSatisfiesIt()
   local holder = contract("Holder2", NAMED)
   local good = implementing("Good", holder, {type = NAMED})
   assertEq(fits(good, holder), true)
end

function M.aMissingOrUnfitAnswerDoesNot()
   local holder = contract("Holder3", NAMED)
   assertEq(fits(implementing("Silent", holder, nil), holder), false, "missing")
   assertEq(fits(implementing("Wrong", holder, {type = T.string}), holder), false, "unfit")
end

function M.conflictingDefaultsDoNotSatisfyIt()
   local a = contract("A", nil)
   a.associatedAnswers = {Item = {type = T.string, isDefault = true}}
   local b = contract("B", nil)
   b.associatedAnswers = {Item = {type = T.integer, isDefault = true}}
   local silent = T.nominal("Taker", "record")
   silent.byname = {count = T.integer}
   silent.supertypes = {a, b}
   assertEq(fits(silent, a), false, "two contracts defaulting differently")
   -- Writing the answer settles it. A second declaration rather than a mutation,
   -- because `isA` caches by identity pair and would hand back the first verdict.
   local written = T.nominal("TakerWritten", "record")
   written.byname = {count = T.integer}
   written.supertypes = {a, b}
   written.associatedAnswers = {Item = {type = T.string}}
   assertEq(fits(written, a), true)
end

function M.aCopiedDefaultSatisfiesIt()
   local holder = contract("Holder4")
   local default = {type = T.string, isDefault = true}
   holder.associatedAnswers = {Item = default}
   local taker = implementing("Inheritor", holder, default)
   assertEq(fits(taker, holder), true, "a default copied down did not answer")
   -- The interface itself still satisfies its own contract, answering nothing.
   assertEq(fits(holder, holder), true)
end

function M.anInterfaceSatisfiesOneByDeclaringIt()
   local holder = contract("Holder5")
   local wider = T.nominal("Wider", "interface")
   wider.byname = {count = T.integer}
   wider.supertypes = {holder}
   assertEq(fits(wider, holder), true, "an interface taking the contract")
   -- One that merely has the same members does not: it answers nothing and promises
   -- nothing about its implementors.
   local unrelated = T.nominal("Unrelated", "interface")
   unrelated.byname = {count = T.integer}
   assertEq(fits(unrelated, holder), false)
end

function M.gradualStaysGradual()
   local holder = contract("Holder6")
   assertEq(fits(T.any, holder), true, "any stopped being gradual")
end

function M.aBoundedBinderSatisfiesItsOwnBound()
   local holder = contract("Holder7")
   local binder = T.typevar("T", "conformance-test:bounded")
   binder.bound = holder
   assertEq(fits(binder, holder), true,
      "a binder bounded by the interface does not satisfy it")
end

function M.everyMemberOfAUnionMustSatisfyIt()
   local holder = contract("Holder8", NAMED)
   local good = implementing("Good2", holder, {type = NAMED})
   local other = implementing("Good3", holder, {type = NAMED})
   local silent = implementing("Silent2", holder, nil)
   assertEq(fits(T.union({good, other}), holder), true)
   assertEq(fits(T.union({good, silent}), holder), false,
      "a union satisfied it with an alternative that answers nothing")
end

return M
