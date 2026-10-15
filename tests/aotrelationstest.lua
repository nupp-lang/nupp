-- Difference constraints over a kernel's guards.
--
-- The solver decides admission by implication rather than by matching source
-- syntax, so what has to hold is that equivalent facts reach one answer, that
-- a transitive bound is found, and that a contradiction is caught.

local relations = require("nupp.compiler.aot.relations")
local test = require("assert")

local M = {}

local ZERO = relations.zero()

local function uniform(name)
    return relations.uniform(name)
end

local function count(name)
    return relations.count(name)
end

local function solve(pool, spans, extraUniforms)
    local terms = {ZERO}
    for _, name in ipairs(spans) do
        terms[#terms + 1] = count(name)
    end
    for _, name in ipairs(extraUniforms or {}) do
        terms[#terms + 1] = uniform(name)
    end

    return relations.solve(pool, spans, terms)
end

-- `first >= 1 and last <= #out and first <= last + 1`, normalized.
local function reference()
    return {
        relations.relation(ZERO, uniform("first"), -1),
        relations.relation(uniform("last"), count("out"), 0),
        relations.relation(uniform("first"), uniform("last"), 1),
    }
end

function M.aBoundHoldsThroughAnIntermediate()
    local closure = solve(
        {
            relations.relation(uniform("last"), uniform("middle"), 0),
            relations.relation(uniform("middle"), count("out"), 0)
        },
        {"out"},
        {"first", "last", "middle"}
    )
    local proof = relations.proves(closure, uniform("last"), count("out"), 0)
    assert(proof, "last <= #out follows from the two comparisons")
    test.equal(#proof, 2, "and the proof names both of them")
end

function M.anEqualityIsProvedInBothDirections()
    local closure = solve(
        {
            relations.relation(count("a"), count("b"), 0),
            relations.relation(count("b"), count("a"), 0),
            relations.relation(count("b"), count("out"), 0),
            relations.relation(count("out"), count("b"), 0),
        },
        {"out", "a", "b"}
    )
    assert(relations.equalCounts(closure, "out", "a"), "the transitive agreement holds")
    assert(relations.equalCounts(closure, "out", "b"), "so does the written one")
end

-- A span's length is never negative, which is what makes a loop over the whole
-- of one oblige nothing rather than oblige something unprovable.
function M.aSpanLengthIsKnownNonNegative()
    local closure = solve({}, {"out"})
    assert(relations.proves(closure, ZERO, count("out"), 0), "0 <= #out needs no source guard")
    assert(not relations.proves(closure, ZERO, count("out"), -1), "but 1 <= #out is not free")
end

function M.aCycleThatLosesGroundIsAContradiction()
    local closure = solve(
        {
            relations.relation(uniform("first"), uniform("last"), -1),
            relations.relation(uniform("last"), uniform("first"), -1)
        },
        {},
        {"first", "last"}
    )
    assert(closure.contradiction, "first < last and last < first cannot both hold")
end

function M.aTermTheSignatureDoesNotDeclareProvesNothing()
    local closure = solve(reference(), {"out"}, {"first", "last"})
    assert(not relations.proves(closure, uniform("stride"), count("out"), 0), "an unknown term has no path")
end

function M.equivalentPoolsNormalizeToOneCanonicalOrder()
    local a = relations.canonical(reference())
    local shuffled = {reference()[3], reference()[1], reference()[2], reference()[1]}
    local b = relations.canonical(shuffled)
    test.equal(#a, 3, "the repeat is dropped")
    test.equal(#b, #a, "and both source forms reach the same length")
    for index = 1, #a do
        test.equal(relations.key(b[index].left), relations.key(a[index].left), "same left term at " .. index)
        test.equal(relations.key(b[index].right), relations.key(a[index].right), "same right term at " .. index)
        test.equal(b[index].offset, a[index].offset, "same offset at " .. index)
    end
end

function M.tautologiesLeaveNoWrapperRelationButContradictionsRemain()
    local zero = relations.zero()
    local tautology = relations.canonical({relations.relation(zero, zero, 1)})
    test.equal(#tautology, 0, "a true constant comparison needs no wrapper check")

    local contradiction = relations.canonical({relations.relation(zero, zero, -1)})
    test.equal(#contradiction, 1, "a false constant comparison remains visible to the solver")
    assert(solve(contradiction, {}).contradiction, "the retained self-edge is contradictory")
end

function M.theBudgetIsFarBeyondAnySignature()
    assert(relations.BUDGET >= 128, "the budget is what the plan fixed it at")
    assert(relations.MAX_OFFSET < relations.INFINITE, "an offset can never be mistaken for no path")
end

local function scaled(name, factor)
    return relations.scaledCount(name, factor)
end

-- `#rgb == 3 * #grey`, as two relations over the scaled count.
local function tripled()
    return {
        relations.relation(count("rgb"), scaled("grey", 3), 0),
        relations.relation(scaled("grey", 3), count("rgb"), 0),
    }
end

--- The transfers from one span to another, by factor.
local function transfersFrom(closure, from, to)
    local found = {}
    for _, transfer in ipairs((relations.transfers(closure, {"grey", "rgb", "input", "output"})[from] or {})[to] or {}) do
        found[transfer.factor] = transfer.offset
    end

    return found
end

-- A scaled count is at least the count it scales, so an equality through a
-- factor carries the plain bound the loop needs, one way only.
function M.aFactorRelationBoundsTheCountItScales()
    local closure = solve(tripled(), {"grey", "rgb"})
    assert(relations.proves(closure, count("grey"), count("rgb"), 0), "#grey <= #rgb follows from #rgb == 3 * #grey")
    assert(not relations.proves(closure, count("rgb"), count("grey"), 0), "and #rgb <= #grey does not")
    assert(not relations.equalCounts(closure, "grey", "rgb"), "a factor is not an equality of counts")
    test.equal(relations.scaledCount("grey", 1).factor, nil, "a factor of one is the count itself")
end

-- A cursor one element below `#grey` is three below `#rgb`: the room carries
-- through the factor, and only from the scaled span to the other.
function M.aFactorRelationCarriesCursorRoomThroughTheFactor()
    local closure = solve(tripled(), {"grey", "rgb"})
    local carried = transfersFrom(closure, "grey", "rgb")
    test.equal(carried[3], 0, "three elements of rgb per element of grey")
    test.equal(carried[1], 0, "and the count itself carries one")
    test.equal(next(transfersFrom(closure, "rgb", "grey")), nil, "nothing carries back from rgb to grey")

    -- `#output >= 4 * #input + 2`: four per element, plus the two.
    local padded = solve({relations.relation(scaled("input", 4), count("output"), -2)}, {"input", "output"})
    local room = transfersFrom(padded, "input", "output")
    test.equal(room[4], -2, "four per element of input, and two more")
    test.equal(room[1], -2, "the count itself reaches output by the same two")
    assert(relations.proves(padded, count("input"), count("output"), -2), "#input + 2 <= #output follows")
end

return M
