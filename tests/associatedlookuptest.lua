-- The one semantic answer about a projection.
--
-- Requirements carry identity because a name cannot tell "one contract reached
-- twice through a diamond" from "two contracts that chose the same name", and those
-- differ in whether one answer is owed or two, and in what it has to satisfy.
local T = require("nupp.compiler.types")
local associated = require("nupp.compiler.associated")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Distinguishable on purpose. Two empty interfaces satisfy each other, so a bound
-- built from them proves nothing about whether every bound was checked.
local NAMED = T.nominal("Named", "interface")
NAMED.byname = {name = T.string}
local COUNTED = T.nominal("Counted", "interface")
COUNTED.byname = {count = T.integer}

-- A declaration. `requires` is a list of {name, bound}; `answers` maps a name to
-- {type, isDefault}; `is` lists the contracts it takes.
local function decl(name, spec)
   local n = T.nominal(name, spec.kind or "interface")
   n.selfType = T.typevar("self", name .. ":self")
   n.supertypes = spec.is or {}
   if spec.requires then
      n.associatedRequirements = {}
      for j, one in ipairs(spec.requires) do
         n.associatedRequirements[j] = {
            name = one[1], bound = one[2], definition = one[3],
         }
      end
   end
   if spec.answers then
      n.associatedAnswers = {}
      for member, entry in pairs(spec.answers) do
         n.associatedAnswers[member] = entry
      end
   end
   return n
end

local function shownBound(result)
   return result.bound and T.tostring(result.bound) or "none"
end

-- Interned members sort by id, so their spelling depends on creation order.
local function boundHas(result, tag, ...)
   local bound = result.bound
   assert(bound, "no bound at all")
   assertEq(bound.tag, tag, "bound shape")
   local present = {}
   for _, member in ipairs(bound.members) do
      present[member] = true
   end
   for _, wanted in ipairs({...}) do
      assert(present[wanted],
         T.tostring(wanted) .. " missing from " .. T.tostring(bound))
   end
   assertEq(#bound.members, select("#", ...), "member count")
end

local M = {}

function M.requirementsCollectDirectlyAndTransitively()
   local base = decl("Base", {requires = {{"Item"}}})
   local middle = decl("Middle", {is = {base}})
   local leaf = decl("Leaf", {is = {middle}})
   assertEq(#associated.lookup(base, "Item").requirements, 1, "direct")
   assertEq(#associated.lookup(middle, "Item").requirements, 1, "one hop")
   local found = associated.lookup(leaf, "Item")
   assertEq(#found.requirements, 1, "two hops")
   assertEq(found.requirements[1].from, base, "reported from the contract that stated it")
end

-- One requirement reached by two paths is one requirement, so one answer settles it.
function M.aDiamondDeduplicatesByRequirementIdentity()
   local top = decl("Top", {requires = {{"Item"}}})
   local left = decl("Left", {is = {top}})
   local right = decl("Right", {is = {top}})
   local bottom = decl("Bottom", {is = {left, right}})
   assertEq(#associated.lookup(bottom, "Item").requirements, 1,
      "the same requirement counted twice")
end

-- Two contracts that happen to choose one name are two requirements.
function M.independentContractsWithOneNameCoalesce()
   local a = decl("A", {requires = {{"Item", NAMED}}})
   local b = decl("B", {requires = {{"Item", COUNTED}}})
   local taker = decl("Taker", {is = {a, b}})
   local found = associated.lookup(taker, "Item")
   assertEq(#found.requirements, 2, "two contracts, two requirements")
   boundHas(found, "intersection", NAMED, COUNTED)
end

function M.anAnswerIsCheckedAgainstEveryBound()
   local a = decl("A2", {requires = {{"Item", NAMED}}})
   local b = decl("B2", {requires = {{"Item", COUNTED}}})
   local both = T.intersection({NAMED, COUNTED})
   local good = decl("Good", {is = {a, b}, answers = {Item = {type = both}}})
   assertEq(associated.lookup(good, "Item").reason, nil, "an answer fitting both")
   local half = decl("Half", {is = {a, b}, answers = {Item = {type = NAMED}}})
   assertEq(associated.lookup(half, "Item").reason, "unfit",
      "an answer satisfying one contract and not the other")
end

function M.aSingleDefaultIsInherited()
   local source = decl("Source", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, isDefault = true}},
   })
   local taker = decl("Taker2", {is = {source}})
   local found = associated.lookup(taker, "Item")
   assertEq(found.reason, nil)
   assertEq(T.tostring(found.resolved), "string")
end

function M.distinctDefaultsConflict()
   local a = decl("A3", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, isDefault = true}},
   })
   local b = decl("B3", {
      requires = {{"Item"}},
      answers = {Item = {type = T.integer, isDefault = true}},
   })
   local taker = decl("Taker3", {is = {a, b}})
   assertEq(associated.lookup(taker, "Item").reason, "conflict")
   -- Writing the answer settles it.
   local written = decl("Written", {is = {a, b}, answers = {Item = {type = T.string}}})
   assertEq(associated.lookup(written, "Item").reason, nil)
   assertEq(T.tostring(associated.lookup(written, "Item").resolved), "string")
end

-- Two interfaces defaulting `= self` agree once each is read as the implementor.
function M.twoSelfDefaultsConvergeOnOneImplementor()
   local a = decl("A4", {requires = {{"Item"}}})
   a.associatedAnswers = {
      Item = {type = a.selfType, selfBinder = a.selfType, isDefault = true},
   }
   local b = decl("B4", {requires = {{"Item"}}})
   b.associatedAnswers = {
      Item = {type = b.selfType, selfBinder = b.selfType, isDefault = true},
   }
   local taker = decl("Taker4", {kind = "record", is = {a, b}})
   local found = associated.lookup(taker, "Item")
   assertEq(found.reason, nil, "two `= self` defaults are one answer")
   assertEq(found.resolved, taker, "and the answer is the implementor")
end

function M.aSameDefaultThroughADiamondCountsOnce()
   local top = decl("Top2", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, isDefault = true}},
   })
   local left = decl("Left2", {is = {top}})
   local right = decl("Right2", {is = {top}})
   local bottom = decl("Bottom2", {is = {left, right}})
   local found = associated.lookup(bottom, "Item")
   assertEq(found.reason, nil, "one default reached twice read as a conflict")
   assertEq(#found.defaults, 1)
end

function M.anIntersectionHeadCoalescesEveryConstituent()
   local a = decl("A5", {requires = {{"Item", NAMED}}})
   local b = decl("B5", {requires = {{"Item", COUNTED}}})
   local found = associated.lookup(T.intersection({a, b}), "Item")
   assertEq(#found.requirements, 2)
   boundHas(found, "intersection", NAMED, COUNTED)
end

function M.aUnionHeadNeedsEveryAlternativeToDeclareIt()
   local a = decl("A6", {requires = {{"Item", NAMED}}})
   local b = decl("B6", {requires = {{"Item", COUNTED}}})
   local bare = decl("Bare", {})
   local found = associated.lookup(T.union({a, b}), "Item")
   assertEq(found.reason, "missing", "a union answers nothing of its own")
   boundHas(found, "union", NAMED, COUNTED)
   assertEq(associated.lookup(T.union({a, bare}), "Item").reason, "incomplete")
end

function M.anUnprojectableHeadIsRefused()
   local unbounded = T.typevar("T", "lookup-test:unbounded")
   assertEq(associated.lookup(unbounded, "Item").reason, "unprojectable")
   assertEq(associated.lookup(T.string, "Item").reason, "unprojectable")
   assertEq(associated.lookup(T.shape({}, {}, nil), "Item").reason, "unprojectable")
   -- A bound with no such requirement is projectable-but-unknown, which is a
   -- different fact and a different message.
   local bounded = T.typevar("B", "lookup-test:bounded")
   bounded.bound = decl("Bounded", {requires = {{"Item"}}})
   assertEq(associated.lookup(bounded, "Item").reason, "missing")
   assertEq(associated.lookup(bounded, "Other").reason, "unknown")
end

-- `any` is the gradual case, and only reachable by materializing a projection that
-- was valid where it was written.
function M.aGradualHeadIsNotAReason()
   local found = associated.lookup(T.any, "Item")
   assertEq(found.gradual, true)
   assertEq(found.reason, nil)
end

function M.aChainedProjectionValidatesAgainstTheFirstBound()
   local inner = decl("Inner", {requires = {{"Item"}}, answers = {Item = {type = NAMED}}})
   local outer = decl("Outer", {requires = {{"Step", inner}}})
   local binder = T.typevar("T", "lookup-test:chain")
   binder.bound = outer
   -- `T.Step` is bounded by Inner, so `T.Step.Item` is the Item of Inner.
   local first = T.projection(binder, "Step")
   assertEq(associated.lookup(first, "Item").reason, nil)
   assertEq(T.tostring(associated.lookup(first, "Item").resolved), "Named")
   -- A name Inner does not state is unknown rather than unprojectable.
   assertEq(associated.lookup(first, "Missing").reason, "unknown")
end

function M.boundsFollowGenericInstantiation()
   local generics = require("nupp.compiler.generics")
   local param = T.typevar("E", "lookup-test:generic")
   local holder = decl("Holder", {requires = {{"Item", param}}})
   holder.typeParams = {param}
   local ofNamed = generics.instantiate(holder, {[param] = NAMED})
   assertEq(shownBound(associated.lookup(ofNamed, "Item")), "Named",
      "the bound did not follow the instantiation")
   local good = T.nominal("Good2", "record")
   good.supertypes = {ofNamed}
   good.associatedAnswers = {Item = {type = NAMED}}
   assertEq(associated.lookup(good, "Item").reason, nil)
   local bad = T.nominal("Bad2", "record")
   bad.supertypes = {ofNamed}
   bad.associatedAnswers = {Item = {type = T.string}}
   assertEq(associated.lookup(bad, "Item").reason, "unfit")
end

return M
