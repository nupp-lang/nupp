-- Difference constraints over a kernel's guards, and the wrappers that enforce
-- them.
--
-- The solver decides admission by implication rather than by matching source
-- syntax, so what has to hold is that equivalent facts reach one answer, that
-- a transitive bound is found, and that a contradiction is caught. The wrapper
-- side is the other half of the contract: what it checks is the relations the
-- source wrote, and nothing else about bounds.

local binding = require("nupp.compiler.aot.binding")
local relations = require("nupp.compiler.aot.relations")
local wasmbinding = require("nupp.compiler.aot.wasmbinding")
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

----------------------------------------------------------------------------
-- What the wrappers check
----------------------------------------------------------------------------

local function program(overrides)
    local base = {
        version = 27,
        name = "scale",
        symbol = "ks_scale",
        entryMode = "kernel",
        params = {
            {kind = "write_span", name = "out", type = "f64", sourceType = "number", region = "r0"},
            {kind = "read_span", name = "input", type = "f64", sourceType = "number", region = "r1"},
            {kind = "uniform", name = "first", type = "f64", sourceType = "integer"},
            {kind = "uniform", name = "last", type = "f64", sourceType = "integer"},
        },
        regions = {},
        aliasFacts = {},
        guards = {},
        relations = reference(),
        resultTypes = {},
        resultSourceTypes = {},
        loop = {index = "i", first = "first", last = "last", count = "out", statements = {}},
        rangeGuard = {first = "first", last = "last", count = "out"},
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end

    return base
end

-- The constant folds back onto the side the source had it on, so the wrapper
-- reads as the precondition rather than as the normalizer's rearrangement of it.
function M.theWrapperChecksTheRelationsAsWritten()
    local lines = table.concat(binding.relations(program()), "\n")
    assert(lines:find("first < 1", 1, true), "the lower bound: " .. lines)
    assert(lines:find("last > #out", 1, true), "the upper bound: " .. lines)
    assert(lines:find("first > last + 1", 1, true), "the empty-range bound: " .. lines)
end

function M.aStrongerRelationIsCheckedAsTheStrongerOne()
    local pool = reference()
    pool[1] = relations.relation(ZERO, uniform("first"), -2)
    local lines = table.concat(binding.relations(program{relations = pool}), "\n")
    assert(lines:find("first < 2", 1, true), "what the source wrote is what runs: " .. lines)
    assert(not lines:find("first < 1", 1, true), "and not the weaker bound the loop needs: " .. lines)
end

-- Both directions of one length agreement are one comparison in the wrapper,
-- reported as the mismatch it is rather than as a failed precondition.
function M.aLengthAgreementIsCheckedOnceAndNamed()
    local pool = reference()
    pool[#pool + 1] = relations.relation(count("input"), count("out"), 0)
    pool[#pool + 1] = relations.relation(count("out"), count("input"), 0)
    local lines = binding.relations(program{relations = relations.canonical(pool)})
    local text = table.concat(lines, "\n")
    local seen = 0
    for _ in text:gmatch("incompatible lengths") do
        seen = seen + 1
    end
    test.equal(seen, 1, "one comparison, not two bounds: " .. text)
    assert(text:find("#input ~= #out", 1, true) or text:find("#out ~= #input", 1, true), text)
end

function M.aProgramWithoutRelationsChecksNothing()
    test.equal(#binding.relations(program{relations = {}, rangeGuard = nil}), 0, "no facts, no checks")
end

-- Until the relation list existed the Wasm boundary compared span lengths and
-- nothing else, so a map entry over a guarded sub-range reached the module with
-- its range unchecked.
function M.theWasmWrapperChecksTheSameRelations()
    local text = wasmbinding.replacement(program(), "unit")
    assert(text:find("first < 1", 1, true), "the range reaches the Wasm boundary too: " .. text)
    assert(text:find("last > #out", 1, true), text)
end

return M
