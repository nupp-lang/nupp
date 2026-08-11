-- The one semantic answer about a projection.
--
-- Requirements carry identity because a name cannot tell "one contract reached
-- twice through a diamond" from "two contracts that chose the same name", and those
-- differ in whether one answer is owed or two, and in what it has to satisfy.
local T = require("nupp.compiler.types")
local associated = require("nupp.compiler.associated")
local generics = require("nupp.compiler.generics")

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
-- {type, kind}; `is` lists the contracts it takes.
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

-- An answering site. Only a declaration values are built as resolves an answer, so
-- every case about what a projection stands for uses one of these.
local function impl(name, spec)
   spec.kind = "record"
   return decl(name, spec)
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

-- Fitness is the caller's question: the core lookup is relation-free so that
-- `relations` can consume it, and `relations.associatedLookup` is where the verdict
-- comes back with `unfit` filled in.
function M.anAnswerIsCheckedAgainstEveryBound()
   local relations = require("nupp.compiler.relations")
   local a = decl("A2", {requires = {{"Item", NAMED}}})
   local b = decl("B2", {requires = {{"Item", COUNTED}}})
   local both = T.intersection({NAMED, COUNTED})
   local good = impl("Good", {is = {a, b}, answers = {Item = {type = both}}})
   assertEq(relations.associatedLookup(good, "Item").reason, nil, "an answer fitting both")
   local half = impl("Half", {is = {a, b}, answers = {Item = {type = NAMED}}})
   assertEq(relations.associatedLookup(half, "Item").reason, "unfit",
      "an answer satisfying one contract and not the other")
   assertEq(associated.lookup(half, "Item").reason, nil,
      "the core decided fitness, which would be the cycle")
end

function M.aSingleDefaultIsInherited()
   local source = decl("Source", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, kind = "default"}},
   })
   local taker = impl("Taker2", {is = {source}})
   local found = associated.lookup(taker, "Item")
   assertEq(found.reason, nil)
   assertEq(T.tostring(found.resolved), "string")
end

function M.distinctDefaultsConflict()
   local a = decl("A3", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, kind = "default"}},
   })
   local b = decl("B3", {
      requires = {{"Item"}},
      answers = {Item = {type = T.integer, kind = "default"}},
   })
   local taker = impl("Taker3", {is = {a, b}})
   assertEq(associated.lookup(taker, "Item").reason, "conflict")
   -- Writing the answer settles it.
   local written = impl("Written", {is = {a, b}, answers = {Item = {type = T.string}}})
   assertEq(associated.lookup(written, "Item").reason, nil)
   assertEq(T.tostring(associated.lookup(written, "Item").resolved), "string")
end

-- Two interfaces defaulting `= self` agree once each is read as the implementor.
function M.twoSelfDefaultsConvergeOnOneImplementor()
   local a = decl("A4", {requires = {{"Item"}}})
   a.associatedAnswers = {
      Item = {type = a.selfType, selfBinder = a.selfType, kind = "default"},
   }
   local b = decl("B4", {requires = {{"Item"}}})
   b.associatedAnswers = {
      Item = {type = b.selfType, selfBinder = b.selfType, kind = "default"},
   }
   local taker = impl("Taker4", {is = {a, b}})
   local found = associated.lookup(taker, "Item")
   assertEq(found.reason, nil, "two `= self` defaults are one answer")
   assertEq(found.resolved, taker, "and the answer is the implementor")
end

function M.aSameDefaultThroughADiamondCountsOnce()
   local top = decl("Top2", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, kind = "default"}},
   })
   local left = decl("Left2", {is = {top}})
   local right = decl("Right2", {is = {top}})
   local bottom = impl("Bottom2", {is = {left, right}})
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
   assertEq(found.reason, nil, "two contracts that both state it")
   boundHas(found, "union", NAMED, COUNTED)
   assertEq(found.resolved, nil, "neither alternative answers, so nothing resolves")
   assertEq(associated.lookup(T.union({a, bare}), "Item").reason, "incomplete")
end

-- The answer distributes: each alternative already knows what it answers, so
-- refusing to say would discard what is known for every value the union can hold.
function M.aUnionAnswerDistributesAcrossItsAlternatives()
   local contract = decl("Holds", {requires = {{"Item"}}})
   local left = impl("Left3", {is = {contract}, answers = {Item = {type = T.string}}})
   local right = impl("Right3", {is = {contract}, answers = {Item = {type = T.integer}}})
   local found = associated.lookup(T.union({left, right}), "Item")
   assertEq(found.reason, nil)
   assertEq(T.tostring(found.resolved), "integer | string")
   -- and the normalizer agrees
   assertEq(T.tostring(generics.normalize(T.projection(T.union({left, right}), "Item")).type),
      "integer | string")
end

-- One alternative that cannot answer decides the union, because the value could be
-- that one.
function M.aUnionIsOnlyAsSettledAsItsWeakestAlternative()
   local contract = decl("Holds2", {requires = {{"Item"}}})
   local answered = impl("Answered", {is = {contract}, answers = {Item = {type = T.string}}})
   local unanswered = impl("Unanswered", {is = {contract}})
   assertEq(associated.lookup(T.union({answered, unanswered}), "Item").reason, "missing")
   -- An opaque alternative is not a failure, but it does leave the union opaque.
   local opaque = decl("Opaque", {requires = {{"Item"}}})
   local mixed = associated.lookup(T.union({answered, opaque}), "Item")
   assertEq(mixed.reason, nil)
   assertEq(mixed.resolved, nil, "an opaque alternative resolved anyway")
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
   local through = associated.lookup(bounded, "Item")
   assertEq(through.reason, nil, "a bounded binder can be projected")
   assertEq(through.resolved, nil, "and stays opaque, since the bound is a contract")
   assertEq(associated.lookup(bounded, "Other").reason, "unknown")
   -- A concrete declaration owing an answer and giving none is the missing case.
   local owing = impl("Owing", {is = {bounded.bound}})
   assertEq(associated.lookup(owing, "Item").reason, "missing")
end

-- `any` is the gradual case, and only reachable by materializing a projection that
-- was valid where it was written.
function M.aGradualHeadIsNotAReason()
   local found = associated.lookup(T.any, "Item")
   assertEq(found.gradual, true)
   assertEq(found.reason, nil)
end

function M.aChainedProjectionValidatesAgainstTheFirstBound()
   local inner = impl("Inner", {requires = {{"Item"}}, answers = {Item = {type = NAMED}}})
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
   local relations = require("nupp.compiler.relations")
   local bad = T.nominal("Bad2", "record")
   bad.supertypes = {ofNamed}
   bad.associatedAnswers = {Item = {type = T.string}}
   assertEq(relations.associatedLookup(bad, "Item").reason, "unfit")
end

-- The normalizer reduces projections and the query answers about them, and they
-- cannot both be the authority. `generics` may not require `associated` -- that
-- would close the require graph -- so the two implement the same rules separately,
-- and this pins them together.
function M.theNormalizerAndTheQueryAgree()
   local contract = decl("Agreed", {requires = {{"Item"}}})
   local answered = impl("AgreedRecord", {is = {contract}, answers = {Item = {type = T.string}}})
   local defaulted = decl("AgreedDefault", {
      requires = {{"Item"}},
      answers = {Item = {type = T.string, kind = "default"}},
   })
   local inheriting = impl("AgreedTaker", {is = {defaulted}})
   inheriting.associatedAnswers = {Item = defaulted.associatedAnswers.Item}
   local binder = T.typevar("T", "agree-test:binder")
   binder.bound = contract
   local heads = {
      answered,
      contract,
      defaulted,
      inheriting,
      binder,
      T.union({answered, answered}),
      T.string,
      T.any,
   }
   for _, head in ipairs(heads) do
      local found = associated.lookup(head, "Item")
      local reduced = generics.normalize(T.projection(head, "Item")).type
      if found.resolved then
         assertEq(reduced, found.resolved,
            "the query resolved " .. T.tostring(head) .. ".Item and the normalizer did not")
      elseif found.gradual then
         assertEq(reduced, T.any, "a gradual head reduced to something else")
      else
         assertEq(reduced.tag, "projection",
            "the normalizer reduced " .. T.tostring(head) .. ".Item and the query did not")
      end
   end
end

return M
