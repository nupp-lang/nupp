-- Completion over associated types.
--
-- Set algebra, because a head may be more than one contract at once, and an
-- associated name is a type member -- never a runtime one, since it is erased.
local T = require("nupp.compiler.types")
local complete = require("nupp.compiler.lsp.complete")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function names(t)
   local out = {}
   for name in pairs(complete.associatedNamesOf(t)) do
      out[#out + 1] = name
   end
   table.sort(out)
   return table.concat(out, ",")
end

local function contract(name, list)
   local c = T.nominal(name, "interface")
   c.selfType = T.typevar("self", name .. ":self")
   c.associatedRequirements = {}
   for j, member in ipairs(list) do
      c.associatedRequirements[j] = {name = member}
   end
   return c
end

local M = {}

-- A value of an intersection satisfies every contract, so every name is reachable.
function M.anIntersectionUnionsTheNames()
   local left, right = contract("Left", {"Item", "Extra"}), contract("Right", {"Item"})
   assertEq(names(T.intersection({left, right})), "Extra,Item")
end

-- A value of a union is one alternative, so a name the others do not state means
-- nothing for it.
function M.aUnionIntersectsTheNames()
   local left, right = contract("Left2", {"Item", "Extra"}), contract("Right2", {"Item"})
   assertEq(names(T.union({left, right})), "Item")
end

-- One name to type either way; what differs is how many declarations are behind it.
function M.oneCandidateCarriesEveryContributingIdentity()
   local left, right = contract("Left3", {"Item"}), contract("Right3", {"Item"})
   local coalesced = complete.associatedNamesOf(T.intersection({left, right}))
   assertEq(names(T.intersection({left, right})), "Item")
   assertEq(#coalesced.Item, 2, "two contracts contributed one candidate")

   local top = contract("Top3", {"Leaf"})
   local a, b = T.nominal("A3", "interface"), T.nominal("B3", "interface")
   a.supertypes, b.supertypes = {top}, {top}
   local diamond = complete.associatedNamesOf(T.intersection({a, b}))
   assertEq(#diamond.Leaf, 1, "a diamond is one requirement")
end

function M.aBoundedBinderOffersItsBoundsNames()
   local holds = contract("Holds4", {"Item"})
   local binder = T.typevar("T", "complete-test:bounded")
   binder.bound = holds
   assertEq(names(binder), "Item")
   local bare = T.typevar("U", "complete-test:bare")
   assertEq(names(bare), "")
end

-- An associated type is erased, so it is never a runtime member.
function M.runtimeCompletionNeverOffersAnAssociatedName()
   local rec = T.nominal("R4", "record")
   rec.byname = {field = T.string}
   rec.associatedAnswers = {Item = {type = T.string, kind = "answer"}}
   local out = {}
   for name in pairs(complete.membersOf(rec)) do
      out[#out + 1] = name
   end
   table.sort(out)
   assertEq(table.concat(out, ","), "field")
end

-- Members reached through an opaque projection come from its bound, and are read as
-- the projection: a `self`-returning member shows `T.Item`, not the contract.
function M.membersThroughAnOpaqueProjectionKeepTheProjectionAsReceiver()
   local cloneable = T.nominal("Cloneable4", "interface")
   cloneable.selfType = T.typevar("self", "Cloneable4:self")
   cloneable.byname = {clone = T.func({cloneable.selfType}, {cloneable.selfType})}
   local holds = T.nominal("Copies4", "interface")
   holds.selfType = T.typevar("self", "Copies4:self")
   holds.associatedRequirements = {{name = "Item", bound = cloneable}}
   local binder = T.typevar("T", "complete-test:receiver")
   binder.bound = holds
   local projection = T.projection(binder, "Item")
   local members = complete.membersOf(projection)
   assert(members.clone, "the bound's members were not offered")
   assertEq(T.tostring(members.clone.type), "function(T.Item): T.Item",
      "the bound was shown instead of the projection")
end

return M
