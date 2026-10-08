local testAssert = require("nupp.test")
-- Projection normalization.
--
-- `types.projection` builds and interns and nothing else; reducing one is
-- `generics.normalize`, which runs to a fixed point. Keeping those apart is the
-- point: a constructor that reduced one hop looks like normalization and is not,
-- which is how an earlier attempt shipped a projection that went gradual.
local T = require("nupp.compiler.types")
local generics = require("nupp.compiler.types.generics")

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
    testAssert.equal(shown(T.projection(lines, "Item")), "string")
end

function M.manyHopsReduceToAFixedPoint()
    local inner = answering("Inner", {Item = T.integer})
    local middle = answering("Middle", {Item = T.projection(inner, "Item")})
    local outer = answering("Outer", {Item = T.projection(middle, "Item")})
    testAssert.equal(shown(T.projection(outer, "Item")), "integer")
end

function M.reductionReachesInsideEveryStructure()
    local lines = answering("Lines", {Item = T.string})
    local item = T.projection(lines, "Item")
    testAssert.equal(shown(T.array(item)), "{string}")
    testAssert.equal(shown(T.union({item, T.integer})), "integer | string")
    testAssert.equal(shown(T.func({item}, {item})), "function(string): string")
    testAssert.equal(shown(T.indexer(T.integer, item)), "{@readonly [integer]: string}")
    local pack = T.pack({item}, nil, {"plain"})
    testAssert.equal(T.tostringPack(generics.normalizePack(pack).pack), "(string)")
end

function M.explicitOpaqueOwnershipSurvivesGenericTypeTransforms()
    local binder = T.typevar("T", "normalize-test:owned-opaque")
    local source = T.affine(binder, nil, true)
    local rebound = generics.rebind(source, {[binder] = T.optional(T.string)})
    testAssert.equal(rebound.transferOnly, true, "rebinding erased explicit transfer-only affinity")
    testAssert.equal(T.tostring(rebound), "affine(string?)")

    local normalized = generics.normalize(rebound).type
    testAssert.equal(normalized.transferOnly, true, "normalization erased explicit transfer-only affinity")
    testAssert.equal(T.tostring(normalized), "affine(string?)")
end

-- Substituting the head is what makes a projection reducible; the two stay
-- separate operations, and rebinding alone must not reduce.
function M.rebindingTheHeadThenNormalizingReduces()
    local lines = answering("Lines", {Item = T.string})
    local binder = T.typevar("C", "normalize-test:head")
    local open = T.projection(binder, "Item")
    testAssert.equal(T.tostring(open), "C.Item")
    testAssert.equal(T.tostring(generics.normalize(open).type), "C.Item", "an opaque projection is already a normal form")
    local bound = generics.rebind(open, {[binder] = lines})
    testAssert.equal(T.tostring(bound), "Lines.Item", "rebinding substitutes the head and does not reduce")
    testAssert.equal(T.tostring(generics.normalize(bound).type), "string")
end

function M.anOpaqueHeadStaysAProjection()
    local binder = T.typevar("T", "normalize-test:opaque")
    local result = generics.normalize(T.projection(binder, "Item"))
    testAssert.equal(T.tostring(result.type), "T.Item")
    testAssert.equal(result.cycle, nil, "an opaque projection is not a cycle")
    testAssert.equal(#result.gradual, 0, "and it is not gradual either")
end

-- A declaration answering nothing of that name is opaque too, not an error and
-- not `any`.
function M.anUnansweredNameStaysAProjection()
    local bare = answering("Bare", {})
    testAssert.equal(shown(T.projection(bare, "Item")), "Bare.Item")
end

function M.aGradualHeadReducesToAnyAndSaysSo()
    local binder = T.typevar("C", "normalize-test:gradual")
    local open = T.projection(binder, "Item")
    local materialized = generics.materialize(open, {})
    testAssert.equal(T.tostring(materialized), "any.Item", "materializing the head does not reduce the projection")
    local result = generics.normalize(materialized)
    testAssert.equal(T.tostring(result.type), "any")
    testAssert.equal(#result.gradual, 1, "the gradual reduction went unrecorded")
    testAssert.equal(result.gradual[1], "Item")
end

function M.aDirectCycleIsReportedAndNotFollowed()
    local loop = T.nominal("Loop", "record")
    loop.associatedAnswers = {Item = {type = T.projection(loop, "Item")}}
    local result = generics.normalize(T.projection(loop, "Item"))
    assert(result.cycle, "a direct cycle went unreported")
    testAssert.equal(table.concat(result.cycle, " -> "), "Loop.Item -> Loop.Item")
    testAssert.equal(T.tostring(result.type), "Loop.Item", "a cycle must not collapse to any")
end

function M.aTwoNodeCycleIsReported()
    local a = T.nominal("A", "record")
    local b = T.nominal("B", "record")
    a.associatedAnswers = {Item = {type = T.projection(b, "Item")}}
    b.associatedAnswers = {Item = {type = T.projection(a, "Item")}}
    local result = generics.normalize(T.projection(a, "Item"))
    assert(result.cycle, "a two-node cycle went unreported")
    testAssert.equal(table.concat(result.cycle, " -> "), "A.Item -> B.Item -> A.Item")
    testAssert.equal(T.tostring(result.type), "A.Item")
end

-- The reason answers are stored apart from `nestedTypes`.
function M.aNestedAliasOfTheSameNameDoesNotAnswer()
    local shape = answering("Shape", {}, {Unit = T.number})
    testAssert.equal(T.tostring(shape.nestedTypes.Unit), "number", "the alias is there")
    testAssert.equal(
        shown(T.projection(shape, "Unit")),
        "Shape.Unit",
        "a private alias answered a contract it knows nothing about"
    )
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
        testAssert.equal(twice, once, "normalizing twice changed " .. T.tostring(subject))
    end
end

-- The wrapper tags. Each is a member of the type union, so a projection can sit
-- inside one, and each needs its own branch in the walker to be rebuilt: a tag with
-- no branch is returned whole and its contents never reduce.
function M.reductionReachesInsideTheWrapperTags()
    local lines = answering("Lines", {Item = T.string})
    local item = T.projection(lines, "Item")
    testAssert.equal(shown(T.carray(item, 4)), "string[4]")
    testAssert.equal(shown(T.carray(item, nil)), "string[?]")
    testAssert.equal(shown(T.constOf(item)), "const string")
    testAssert.equal(shown(T.ctype(item)), "ctype<string>")
    testAssert.equal(shown(T.ptr(item)), "string*")
    -- and nested, so a wrapper around a wrapper is rebuilt too
    testAssert.equal(shown(T.constOf(T.carray(item, 2))), "const string[2]")
end

function M.theWrapperTagsStayOpaqueWhenTheHeadIs()
    local binder = T.typevar("T", "normalize-test:wrappers")
    local item = T.projection(binder, "Item")
    testAssert.equal(shown(T.carray(item, 4)), "T.Item[4]")
    testAssert.equal(shown(T.constOf(item)), "const T.Item")
    testAssert.equal(shown(T.ctype(item)), "ctype<T.Item>")
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
    testAssert.equal(table.concat(result.cycle, " -> "), "Same.Item -> Tail.Item -> Same.Item")
    testAssert.equal(#result.cycle, 3, "the slice picked up the wrong entry point")
end

return M
