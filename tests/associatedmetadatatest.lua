-- Associated metadata through generic instantiation.
--
-- An answer is not just a type. `= self` means whatever answered, so the binder it
-- was written under travels with it and is rebound where the projection reduces;
-- an answer written in terms of the declaration's own parameters has to follow the
-- instantiation instead. Both, without special casing either.
local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.generics")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- A generic declaration with one parameter and whatever metadata the case needs.
local function declaring(name, params, spec)
   local n = T.nominal(name, spec.kind or "record")
   n.typeParams = params
   n.selfType = T.typevar("self", name .. ":self")
   if spec.order then
      n.associatedRequirements = {}
      for j, member in ipairs(spec.order) do
         n.associatedRequirements[j] = {
            name = member,
            bound = spec.bounds and spec.bounds[member] or nil,
         }
      end
   end
   n.associatedAnswers = spec.answers
   return n
end

local function shown(t)
   return T.tostring(generics.normalize(t).type)
end

local M = {}

-- `Cell<T>.Value = T` follows the argument.
function M.aGenericAnswerFollowsTheInstantiation()
   local param = T.typevar("T", "meta-test:cell")
   local cell = declaring("Cell", {param}, {
      order = {"Value"},
      answers = {Value = {type = param}},
   })
   local ofString = generics.instantiate(cell, {[param] = T.string})
   assertEq(shown(T.projection(ofString, "Value")), "string")
   local ofInteger = generics.instantiate(cell, {[param] = T.integer})
   assertEq(shown(T.projection(ofInteger, "Value")), "integer")
end

-- An answer mentioning a binder the instantiation knows nothing about keeps it.
-- Materializing here would quietly turn it into `any`.
function M.anUnrelatedBinderInAnAnswerSurvives()
   local param = T.typevar("T", "meta-test:pair-own")
   local other = T.typevar("E", "meta-test:pair-other")
   local pair = declaring("Pair", {param}, {
      order = {"Value"},
      answers = {Value = {type = T.func({other}, {param})}},
   })
   local ofString = generics.instantiate(pair, {[param] = T.string})
   assertEq(shown(T.projection(ofString, "Value")), "function(E): string")
end

-- `= self` reduces to the declaration actually projected, which for an
-- instantiation is that instantiation rather than the declaration it came from.
function M.selfAnswersWithTheInstantiatedNominal()
   local param = T.typevar("T", "meta-test:holder")
   local holder = declaring("Holder", {param}, {order = {"Value"}})
   holder.associatedAnswers = {
      Value = {type = holder.selfType, selfBinder = holder.selfType},
   }
   local ofString = generics.instantiate(holder, {[param] = T.string})
   local reduced = generics.normalize(T.projection(ofString, "Value")).type
   assertEq(reduced, ofString, "self answered with something other than the receiver")
   assert(reduced ~= holder, "self answered with the origin declaration")
   assert(reduced ~= T.any, "self answered with any")
   assertEq(T.tostring(reduced), "Holder<string>")
end

-- An inherited default keeps the binder it was written under, so a later
-- implementor reads it as itself. This is the copy-down the withdrawn attempt got
-- wrong by dropping the binder.
--
-- The interface itself stays opaque. Its default is a fallback for implementors, and
-- one of them may answer otherwise, so a value known only as the interface cannot be
-- said to answer it.
function M.anInheritedDefaultRebindsToItsImplementor()
   local source = declaring("Source", {}, {kind = "interface", order = {"Value"}})
   local default = {
      type = source.selfType,
      selfBinder = source.selfType,
      kind = "default",
   }
   source.associatedAnswers = {Value = default}
   assertEq(shown(T.projection(source, "Value")), "Source.Value",
      "an interface resolved its own default")
   -- Copying it to a concrete implementor is what makes it an answer, and the binder
   -- rebinds there.
   local taker = T.nominal("Taker", "record")
   taker.associatedAnswers = {Value = default}
   local reduced = generics.normalize(T.projection(taker, "Value")).type
   assertEq(reduced, taker, "the default did not rebind to the implementor")
   assert(reduced ~= source, "the default stayed with the interface")
end

-- The same rule, stated directly: an override must not be shadowed by the default a
-- value's interface declares.
function M.anInterfaceNeverExposesADefaultAnImplementorOverrides()
   local iface = declaring("I", {}, {kind = "interface", order = {"Item"}})
   iface.associatedAnswers = {Item = {type = T.string, kind = "default"}}
   local impl = T.nominal("R", "record")
   impl.supertypes = {iface}
   impl.associatedAnswers = {Item = {type = T.integer}}
   assertEq(shown(T.projection(iface, "Item")), "I.Item",
      "a value typed as the interface exposed the default")
   assertEq(shown(T.projection(impl, "Item")), "integer",
      "the implementor's own answer")
end

function M.everyPieceOfMetadataSurvivesInstantiation()
   local param = T.typevar("T", "meta-test:full")
   local named = T.nominal("Named", "interface")
   local site = {file = "m.nupp", line = 12}
   local full = declaring("Full", {param}, {
      order = {"Value", "Error"},
      bounds = {Value = named},
      answers = {
         Value = {type = param, definition = site},
         Error = {type = T.string, kind = "default", definition = site},
      },
   })
   local instance = generics.instantiate(full, {[param] = T.integer})
   local order = {}
   for j, requirement in ipairs(instance.associatedRequirements) do
      order[j] = requirement.name
   end
   assertEq(table.concat(order, ","), "Value,Error", "order")
   assertEq(instance.associatedRequirements[1].bound, named, "bound")
   assertEq(T.tostring(instance.associatedAnswers.Value.type), "integer", "answer")
   assertEq(instance.associatedAnswers.Error.kind, "default", "provenance")
   assertEq(instance.associatedAnswers.Value.definition, site, "definition")
   assertEq(instance.associatedAnswers.Error.definition, site, "definition")
   -- The origin is untouched by having been instantiated.
   assertEq(T.tostring(full.associatedAnswers.Value.type), "T", "the origin moved")
end

-- The answer is reachable through the instantiation and reduces all the way.
function M.aProjectionThroughAnInstantiatedAnswerNormalizesFully()
   local param = T.typevar("T", "meta-test:chain")
   local inner = declaring("Inner", {param}, {
      order = {"Value"},
      answers = {Value = {type = param}},
   })
   local ofString = generics.instantiate(inner, {[param] = T.string})
   local outer = T.nominal("Outer", "record")
   outer.associatedAnswers = {Value = {type = T.projection(ofString, "Value")}}
   assertEq(shown(T.projection(outer, "Value")), "string")
   assertEq(shown(T.array(T.projection(outer, "Value"))), "{string}")
end

function M.instantiationIsMemoizedWithItsMetadata()
   local param = T.typevar("T", "meta-test:memo")
   local cell = declaring("Cell2", {param}, {
      order = {"Value"},
      answers = {Value = {type = param}},
   })
   local once = generics.instantiate(cell, {[param] = T.string})
   local twice = generics.instantiate(cell, {[param] = T.string})
   assertEq(once, twice, "two instantiations of one application")
   assertEq(once.associatedAnswers.Value.type, twice.associatedAnswers.Value.type)
   assertEq(shown(T.projection(twice, "Value")), "string")
end

-- A parameter the instantiation left out is genuinely unknown, and only there is
-- `any` the right answer.
function M.aMissingArgumentMaterializesInTheAnswer()
   local param = T.typevar("T", "meta-test:missing")
   local cell = declaring("Cell3", {param}, {
      order = {"Value"},
      answers = {Value = {type = param}},
   })
   local bare = generics.instantiate(cell, {})
   assertEq(shown(T.projection(bare, "Value")), "any")
end

return M
