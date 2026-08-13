-- Projection normalization.
--
-- `types.projection` builds and interns and nothing else; reducing one is
-- `generics.normalize`, which runs to a fixed point. Keeping those apart is the
-- point: a constructor that reduced one hop looks like normalization and is not,
-- which is how an earlier attempt shipped a projection that went gradual.
local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.generics")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- A declaration answering `Item` with `answer`. Answers live apart from
-- `nestedTypes` so a private alias can never be mistaken for one.
local function answering(name, answers, aliases)
   local n = T.nominal(name, "record")
   n.associatedAnswers = {}
   for member, answer in pairs(answers or {}) do
      n.associatedAnswers[member] = {type = answer}
   end
   for alias, held in pairs(aliases or {}) do
      n.nestedTypes[alias] = held
   end
   return n
end

local function shown(t)
   return T.tostring(generics.normalize(t).type)
end

local M = {}

function M.oneHopReduces()
   local lines = answering("Lines", {Item = T.string})
   assertEq(shown(T.projection(lines, "Item")), "string")
end

function M.manyHopsReduceToAFixedPoint()
   local inner = answering("Inner", {Item = T.integer})
   local middle = answering("Middle", {Item = T.projection(inner, "Item")})
   local outer = answering("Outer", {Item = T.projection(middle, "Item")})
   assertEq(shown(T.projection(outer, "Item")), "integer")
end

function M.reductionReachesInsideEveryStructure()
   local lines = answering("Lines", {Item = T.string})
   local item = T.projection(lines, "Item")
   assertEq(shown(T.array(item)), "{string}")
   assertEq(shown(T.union({item, T.integer})), "integer | string")
   assertEq(shown(T.func({item}, {item})), "function(string): string")
   assertEq(shown(T.indexer(T.integer, item)), "{readonly [integer]: string}")
   local pack = T.pack({item}, nil, {"plain"})
   assertEq(T.tostringPack(generics.normalizePack(pack).pack), "(string)")
end

function M.explicitOpaqueOwnershipSurvivesGenericTypeTransforms()
   local binder = T.typevar("T", "normalize-test:owned-opaque")
   local source = T.owned(binder, nil, true)
   local rebound = generics.rebind(source, {[binder] = T.optional(T.string)})
   assertEq(rebound.opaque, true, "rebinding erased explicit opaque ownership")
   assertEq(T.tostring(rebound), "Owned<string?, opaque>")

   local normalized = generics.normalize(rebound).type
   assertEq(normalized.opaque, true, "normalization erased explicit opaque ownership")
   assertEq(T.tostring(normalized), "Owned<string?, opaque>")
end

-- Substituting the head is what makes a projection reducible; the two stay
-- separate operations, and rebinding alone must not reduce.
function M.rebindingTheHeadThenNormalizingReduces()
   local lines = answering("Lines", {Item = T.string})
   local binder = T.typevar("C", "normalize-test:head")
   local open = T.projection(binder, "Item")
   assertEq(T.tostring(open), "C.Item")
   assertEq(T.tostring(generics.normalize(open).type), "C.Item",
      "an opaque projection is already a normal form")
   local bound = generics.rebind(open, {[binder] = lines})
   assertEq(T.tostring(bound), "Lines.Item",
      "rebinding substitutes the head and does not reduce")
   assertEq(T.tostring(generics.normalize(bound).type), "string")
end

function M.anOpaqueHeadStaysAProjection()
   local binder = T.typevar("T", "normalize-test:opaque")
   local result = generics.normalize(T.projection(binder, "Item"))
   assertEq(T.tostring(result.type), "T.Item")
   assertEq(result.cycle, nil, "an opaque projection is not a cycle")
   assertEq(#result.gradual, 0, "and it is not gradual either")
end

-- A declaration answering nothing of that name is opaque too, not an error and
-- not `any`.
function M.anUnansweredNameStaysAProjection()
   local bare = answering("Bare", {})
   assertEq(shown(T.projection(bare, "Item")), "Bare.Item")
end

function M.aGradualHeadReducesToAnyAndSaysSo()
   local binder = T.typevar("C", "normalize-test:gradual")
   local open = T.projection(binder, "Item")
   local materialized = generics.materialize(open, {})
   assertEq(T.tostring(materialized), "any.Item",
      "materializing the head does not reduce the projection")
   local result = generics.normalize(materialized)
   assertEq(T.tostring(result.type), "any")
   assertEq(#result.gradual, 1, "the gradual reduction went unrecorded")
   assertEq(result.gradual[1], "Item")
end

function M.aDirectCycleIsReportedAndNotFollowed()
   local loop = T.nominal("Loop", "record")
   loop.associatedAnswers = {Item = {type = T.projection(loop, "Item")}}
   local result = generics.normalize(T.projection(loop, "Item"))
   assert(result.cycle, "a direct cycle went unreported")
   assertEq(table.concat(result.cycle, " -> "), "Loop.Item -> Loop.Item")
   assertEq(T.tostring(result.type), "Loop.Item",
      "a cycle must not collapse to any")
end

function M.aTwoNodeCycleIsReported()
   local a = T.nominal("A", "record")
   local b = T.nominal("B", "record")
   a.associatedAnswers = {Item = {type = T.projection(b, "Item")}}
   b.associatedAnswers = {Item = {type = T.projection(a, "Item")}}
   local result = generics.normalize(T.projection(a, "Item"))
   assert(result.cycle, "a two-node cycle went unreported")
   assertEq(table.concat(result.cycle, " -> "), "A.Item -> B.Item -> A.Item")
   assertEq(T.tostring(result.type), "A.Item")
end

-- The reason answers are stored apart from `nestedTypes`.
function M.aNestedAliasOfTheSameNameDoesNotAnswer()
   local shape = answering("Shape", {}, {Unit = T.number})
   assertEq(T.tostring(shape.nestedTypes.Unit), "number", "the alias is there")
   assertEq(shown(T.projection(shape, "Unit")), "Shape.Unit",
      "a private alias answered a contract it knows nothing about")
end

function M.normalizingIsIdempotent()
   local inner = answering("Inner", {Item = T.integer})
   local outer = answering("Outer", {Item = T.projection(inner, "Item")})
   local binder = T.typevar("T", "normalize-test:idempotent")
   for _, subject in ipairs({
      T.projection(outer, "Item"),
      T.array(T.projection(binder, "Item")),
      T.func({T.projection(outer, "Item")}, {T.projection(binder, "Item")}),
      T.string,
   }) do
      local once = generics.normalize(subject).type
      local twice = generics.normalize(once).type
      assertEq(twice, once, "normalizing twice changed " .. T.tostring(subject))
   end
end

-- The wrapper tags. Each is a member of the type union, so a projection can sit
-- inside one, and each needs its own branch in the walker to be rebuilt: a tag with
-- no branch is returned whole and its contents never reduce.
function M.reductionReachesInsideTheWrapperTags()
   local lines = answering("Lines", {Item = T.string})
   local item = T.projection(lines, "Item")
   assertEq(shown(T.carray(item, 4)), "string[4]")
   assertEq(shown(T.carray(item, nil)), "string[?]")
   assertEq(shown(T.constOf(item)), "const string")
   assertEq(shown(T.ctype(item)), "ctype<string>")
   assertEq(shown(T.ptr(item)), "string*")
   -- and nested, so a wrapper around a wrapper is rebuilt too
   assertEq(shown(T.constOf(T.carray(item, 2))), "const string[2]")
end

function M.theWrapperTagsStayOpaqueWhenTheHeadIs()
   local binder = T.typevar("T", "normalize-test:wrappers")
   local item = T.projection(binder, "Item")
   assertEq(shown(T.carray(item, 4)), "T.Item[4]")
   assertEq(shown(T.constOf(item)), "const T.Item")
   assertEq(shown(T.ctype(item)), "ctype<T.Item>")
end

-- The cycle is sliced by the identity a projection was keyed under, not by what it
-- displays. Two declarations may share a displayed name; keying the slice on the
-- label would report a loop that runs through the wrong one.
function M.aCycleIsSlicedByIdentityNotByName()
   local outer = T.nominal("Same", "record")
   local inner = T.nominal("Same", "record")
   local tail = T.nominal("Tail", "record")
   assert(outer ~= inner, "two declarations, one displayed name")
   outer.associatedAnswers = {Item = {type = T.projection(inner, "Item")}}
   inner.associatedAnswers = {Item = {type = T.projection(tail, "Item")}}
   tail.associatedAnswers = {Item = {type = T.projection(inner, "Item")}}
   local result = generics.normalize(T.projection(outer, "Item"))
   assert(result.cycle, "the cycle went unreported")
   -- The loop is inner -> tail -> inner. It does not start at `outer`, even though
   -- `outer` displays the same label as `inner`.
   assertEq(table.concat(result.cycle, " -> "), "Same.Item -> Tail.Item -> Same.Item")
   assertEq(#result.cycle, 3, "the slice picked up the wrong entry point")
end

return M
