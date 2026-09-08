-- Behavioural tests for nupp.store keys and stores, and the checker fixtures
-- that hold a key to its value type.
--
-- A key is a phantom-typed identity over an integer id; a store is one table
-- behind generic methods. What matters is observable at both layers:
-- the runtime must keep ids unique and values intact, and the checker must
-- reject a wrong write through a key without rejecting the annotation-driven
-- declaration every caller writes.

local check = require("assert")
local data = require("nupp.store")
local parser = require("nupp.compiler.parser")
local fragment = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local M = {}

local function errors(source)
    local parsed = parser.parse(source, "store_fixture.nupp")
    assert(#parsed.errors == 0, "store fixture parses")
    local found = {}
    for _, problem in ipairs(fragment.check(parsed, "store_fixture.nupp", env)) do
        if problem.severity ~= "warning" and problem.severity ~= "note" then
            found[#found + 1] = problem
        end
    end

    return found
end

local function codes(source)
    local out = {}
    for _, problem in ipairs(errors(source)) do
        out[#out + 1] = problem.code
    end

    return out
end

local function raises(body, needle)
    local ok, why = pcall(body)
    check.assert(not ok, "expected a raise")
    check.assert(tostring(why):find(needle, 1, true) ~= nil, "unexpected message: " .. tostring(why))
end

-- Runtime -------------------------------------------------------------------

function M.idsAreSequentialAcrossNamedAndAnonymousKeys()
    local first = data.newKey(nil)
    local named = data.newKey("store.test.sequence")
    local third = data.newKey(nil)
    check.equal(named.id, first.id + 1)
    check.equal(third.id, named.id + 1)
    check.equal(named.name, "store.test.sequence")
    check.equal(first.name, nil)
end

function M.emptyAndDuplicateNamesRaiseBeforeAnIdIsUsed()
    local before = data.newKey(nil)
    raises(
        function()
            data.newKey("")
        end,
        "must not be empty"
    )
    local named = data.newKey("store.test.duplicate")
    raises(
        function()
            data.newKey("store.test.duplicate")
        end,
        "already registered"
    )
    local after = data.newKey(nil)
    check.equal(named.id, before.id + 1)
    check.equal(after.id, named.id + 1)
end

function M.findKeyReturnsTheRegisteredIdentityOrNil()
    local key = data.newKey("store.test.find")
    check.assert(rawequal(data.findKey("store.test.find"), key), "lookup returned another table")
    check.equal(data.findKey("store.test.absent"), nil)
end

function M.registeredKeysWalksNamesAscendingByIdWithoutTheRegistry()
    local first = data.newKey("store.test.list.first")
    local anonymous = data.newKey(nil)
    local second = data.newKey("store.test.list.second")
    local seen = {}
    for id, name in data.registeredKeys() do
        seen[name] = id
        check.assert(id ~= anonymous.id, "an anonymous key was walked")
    end
    check.equal(seen["store.test.list.first"], first.id)
    check.equal(seen["store.test.list.second"], second.id)
    -- Ascending by id, where the old snapshot came back in pairs order.
    local ids = {}
    for id in data.registeredKeys() do
        ids[#ids + 1] = id
    end
    for index = 2, #ids do
        check.assert(ids[index] > ids[index - 1], "ids did not ascend")
    end
    -- The loop is handed a step and an integer, so there is no registry to reach.
    local _, state = data.registeredKeys()
    check.equal(state, nil)
end

function M.storesAreIndependentAndKeysAreShared()
    local score = data.newKey("store.test.score")
    local first = data.newStore()
    local second = data.newStore()
    first:set(score, 10)
    second:set(score, 20)
    check.equal(first:get(score), 10)
    check.equal(second:get(score), 20)
    check.equal(data.newStore():get(score), nil)
end

function M.removeDeletesAndSetRejectsNil()
    local key = data.newKey(nil)
    local store = data.newStore()
    local held = {}
    store:set(key, held)
    check.assert(rawequal(store:get(key), held), "reference identity was lost")
    store:set(key, false)
    check.assert(rawequal(store:get(key), false), "false was not stored")
    store:set(key, 0)
    check.equal(store:get(key), 0)
    store:set(key, "")
    check.equal(store:get(key), "")
    raises(
        function()
            store:set(key, nil)
        end,
        "use Store:remove"
    )
    check.equal(store:get(key), "")
    store:remove(key)
    check.equal(store:get(key), nil)
    local remaining = 0
    for _ in store:entries() do
        remaining = remaining + 1
    end
    check.equal(remaining, 0)
end

function M.clearDropsValuesAndKeepsRegistrations()
    local key = data.newKey("store.test.clear")
    local store = data.newStore()
    store:set(key, "ready")
    store:clear()
    check.equal(store:get(key), nil)
    check.assert(rawequal(data.findKey("store.test.clear"), key), "clearing touched the registry")
    store:set(key, "again")
    check.equal(store:get(key), "again")
end

function M.entriesAscendByIdAndCarryNoValue()
    local named = data.newKey("store.test.inspect")
    local anonymous = data.newKey(nil)
    local store = data.newStore()
    store:set(anonymous, 4)
    store:set(named, "text")
    local seen = {}
    for id, name, valueType in store:entries() do
        seen[#seen + 1] = {id = id, name = name, valueType = valueType}
    end
    check.equal(#seen, 2)
    check.equal(seen[1].id, named.id)
    check.equal(seen[1].name, "store.test.inspect")
    check.equal(seen[1].valueType, "string")
    check.equal(seen[2].id, anonymous.id)
    check.equal(seen[2].name, nil)
    check.equal(seen[2].valueType, "number")
end

function M.entriesWalkABorrowedStore()
    -- The walk returns the store it was handed as its loop state, so a caller
    -- holding the store as a borrow can drive it without naming the step.
    local key = data.newKey("store.test.step")
    local store = data.newStore()
    store:set(key, "text")
    local seen = {}
    for id, name, valueType in store:entries() do
        seen[#seen + 1] = {id = id, name = name, valueType = valueType}
    end
    check.equal(#seen, 1)
    check.equal(seen[1].id, key.id)
    check.equal(seen[1].name, "store.test.step")
    check.equal(seen[1].valueType, "string")
end

-- Checker -------------------------------------------------------------------

local PRELUDE = [=[
local record State
    frames: integer
end
local frames: nupp.store.Key<integer> = nupp.store.newKey("fixture.frames")
local state: nupp.store.Key<State> = nupp.store.newKey("fixture.state")
local store = nupp.store.newStore()
]=]

function M.annotatedDeclarationsTypeTheKey()
    check.equal(
        #errors(
            PRELUDE
            .. [=[
store:set(frames, (store:get(frames) or 0) + 1)
store:set(state, new State(frames = 1))
store:remove(state)
local current = store:get(state)
print(current and current.frames, store:get(frames))
]=]
        ),
        0
    )
end

function M.wrongWritesAndReadsAreRejected()
    check.equal(codes(PRELUDE .. [=[
store:set(frames, "one")
]=])[1], "NUPP2006")
    check.equal(codes(PRELUDE .. [=[
local text: string = store:get(frames)
print(text)
]=])[1], "NUPP2001")
    check.equal(codes(PRELUDE .. [=[
store:set(state, {frames = 1})
]=])[1], "NUPP2006")
end

function M.keysNeitherWidenNorNarrow()
    check.equal(codes(PRELUDE .. [=[
local wide: nupp.store.Key<number> = frames
print(wide)
]=])[1], "NUPP2001")
    check.equal(
        codes(
            PRELUDE
            .. [=[
local narrow: nupp.store.Key<integer> = nupp.store.newKey("fixture.number") as nupp.store.Key<number>
print(narrow)
]=]
        )[1],
        "NUPP2001"
    )
end

function M.identityFieldsAreReadOnly()
    local found = codes(PRELUDE .. [=[
frames.id = 4
frames.name = "renamed"
]=])
    check.equal(found[1], "NUPP2009")
    check.equal(found[2], "NUPP2009")
end

function M.lookupRequiresACast()
    check.equal(
        codes(
            PRELUDE .. [=[
local direct: nupp.store.Key<integer>? = nupp.store.findKey("fixture.frames")
print(direct)
]=]
        )[1],
        "NUPP2001"
    )
    check.equal(
        #errors(
            PRELUDE
            .. [=[
local found = nupp.store.findKey("fixture.frames") as nupp.store.Key<integer>
store:set(found, 2)
print(store:get(found))
]=]
        ),
        0
    )
end

function M.anUnannotatedKeyIsGradual()
    -- The type argument comes from the annotation and nothing else, so a
    -- declaration without one resolves to Key<any> and the store checks nothing
    -- through it. This pins that the checker stays silent, which is the
    -- language's rule for `any`, so the documentation can say so.
    check.equal(
        #errors(
            PRELUDE
            .. [=[
local loose = nupp.store.newKey("fixture.loose")
store:set(loose, 7)
local text: string? = store:get(loose)
print(text)
]=]
        ),
        0
    )
end

return M
