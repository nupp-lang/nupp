-- Completion over associated types: an associated name is a type member -- never a
-- runtime one, since it is erased.
local T = require("nupp.compiler.types")
local complete = require("nupp.compiler.lsp.complete")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

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
