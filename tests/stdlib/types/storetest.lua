-- Behavioral tests for types keys and stores, and the checker fixtures
-- that hold a key to its value type.
--
-- A key is a phantom-typed identity over an integer id; a store is one table
-- behind generic methods. What matters is observable at both layers:
-- the runtime must keep ids unique and values intact, and the checker must
-- reject a wrong write through a key without rejecting the annotation-driven
-- declaration every caller writes.

local check = require("assert")
local data = require("types")
local parser = require("nupp.compiler.syntax.parser")
local fragment = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
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
    check(not ok, "expected a raise")
    check(tostring(why):find(needle, 1, true) ~= nil, "unexpected message: " .. tostring(why))
end

-- Runtime -------------------------------------------------------------------

function M.idsAreSequentialAcrossNamedAndAnonymousKeys()
    local first = data.newkey(nil)
    local named = data.newkey("store.test.sequence")
    local third = data.newkey(nil)
    check.eq(named.id, first.id + 1)
    check.eq(third.id, named.id + 1)
    check.eq(named.name, "store.test.sequence")
    check.eq(first.name, nil)
end

function M.emptyAndDuplicateNamesRaiseBeforeAnIdIsUsed()
    local before = data.newkey(nil)
    raises(
        function()
            data.newkey("")
        end,
        "must not be empty"
    )
    local named = data.newkey("store.test.duplicate")
    raises(
        function()
            data.newkey("store.test.duplicate")
        end,
        "already registered"
    )
    local after = data.newkey(nil)
    check.eq(named.id, before.id + 1)
    check.eq(after.id, named.id + 1)
end

function M.keyFindReturnsTheRegisteredIdentityOrNil()
    local key = data.newkey("store.test.find")
    check(rawequal(data.Key.find("store.test.find"), key), "lookup returned another table")
    check.eq(data.Key.find("store.test.absent"), nil)
end

function M.keyRegisteredWalksNamesAscendingByIdWithoutTheRegistry()
    local first = data.newkey("store.test.list.first")
    local anonymous = data.newkey(nil)
    local second = data.newkey("store.test.list.second")
    local seen = {}
    for id, name in data.Key.registered() do
        seen[name] = id
        check(id ~= anonymous.id, "an anonymous key was walked")
    end
    check.eq(seen["store.test.list.first"], first.id)
    check.eq(seen["store.test.list.second"], second.id)
    -- Ascending by id, where the old snapshot came back in pairs order.
    local ids = {}
    for id in data.Key.registered() do
        ids[#ids + 1] = id
    end
    for index = 2, #ids do
        check(ids[index] > ids[index - 1], "ids did not ascend")
    end
    -- The loop is handed a step and an integer, so there is no registry to reach.
    local _, state = data.Key.registered()
    check.eq(state, nil)
end

function M.storesAreIndependentAndKeysAreShared()
    local score = data.newkey("store.test.score")
    local first = data.newstore()
    local second = data.newstore()
    first:set(score, 10)
    second:set(score, 20)
    check.eq(first:get(score), 10)
    check.eq(second:get(score), 20)
    check.eq(data.newstore():get(score), nil)
end

function M.removeDeletesAndSetRejectsNil()
    local key = data.newkey(nil)
    local store = data.newstore()
    local held = {}
    store:set(key, held)
    check(rawequal(store:get(key), held), "reference identity was lost")
    store:set(key, false)
    check(rawequal(store:get(key), false), "false was not stored")
    store:set(key, 0)
    check.eq(store:get(key), 0)
    store:set(key, "")
    check.eq(store:get(key), "")
    raises(
        function()
            store:set(key, nil)
        end,
        "use Store:remove"
    )
    check.eq(store:get(key), "")
    store:remove(key)
    check.eq(store:get(key), nil)
    local remaining = 0
    for _ in store:entries() do
        remaining = remaining + 1
    end
    check.eq(remaining, 0)
end

function M.clearDropsValuesAndKeepsRegistrations()
    local key = data.newkey("store.test.clear")
    local store = data.newstore()
    store:set(key, "ready")
    store:clear()
    check.eq(store:get(key), nil)
    check(rawequal(data.Key.find("store.test.clear"), key), "clearing touched the registry")
    store:set(key, "again")
    check.eq(store:get(key), "again")
end

function M.entriesAscendByIdAndCarryNoValue()
    local named = data.newkey("store.test.inspect")
    local anonymous = data.newkey(nil)
    local store = data.newstore()
    store:set(anonymous, 4)
    store:set(named, "text")
    local seen = {}
    for id, name, valueType in store:entries() do
        seen[#seen + 1] = {id = id, name = name, valueType = valueType}
    end
    check.eq(#seen, 2)
    check.eq(seen[1].id, named.id)
    check.eq(seen[1].name, "store.test.inspect")
    check.eq(seen[1].valueType, "string")
    check.eq(seen[2].id, anonymous.id)
    check.eq(seen[2].name, nil)
    check.eq(seen[2].valueType, "number")
end

function M.entriesWalkABorrowedStore()
    -- The walk returns the store it was handed as its loop state, so a caller
    -- holding the store as a borrow can drive it without naming the step.
    local key = data.newkey("store.test.step")
    local store = data.newstore()
    store:set(key, "text")
    local seen = {}
    for id, name, valueType in store:entries() do
        seen[#seen + 1] = {id = id, name = name, valueType = valueType}
    end
    check.eq(#seen, 1)
    check.eq(seen[1].id, key.id)
    check.eq(seen[1].name, "store.test.step")
    check.eq(seen[1].valueType, "string")
end

-- Checker -------------------------------------------------------------------

local PRELUDE = [=[
local record State
    frames: integer
end
local frames: types.Key<integer> = types.newkey("fixture.frames")
local state: types.Key<State> = types.newkey("fixture.state")
local store = types.newstore()
]=]

function M.annotatedDeclarationsTypeTheKey()
    check.eq(
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
    check.eq(codes(PRELUDE .. [=[
store:set(frames, "one")
]=])[1], "NUPP2006")
    check.eq(codes(PRELUDE .. [=[
local text: string = store:get(frames)
print(text)
]=])[1], "NUPP2001")
    check.eq(codes(PRELUDE .. [=[
store:set(state, {frames = 1})
]=])[1], "NUPP2006")
end

function M.keysNeitherWidenNorNarrow()
    check.eq(codes(PRELUDE .. [=[
local wide: types.Key<number> = frames
print(wide)
]=])[1], "NUPP2001")
    check.eq(
        codes(
            PRELUDE
            .. [=[
local narrow: types.Key<integer> = types.newkey<number>("fixture.number") as types.Key<number>
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
    check.eq(found[1], "NUPP2009")
    check.eq(found[2], "NUPP2009")
end

function M.lookupRequiresACast()
    check.eq(
        codes(PRELUDE .. [=[
local direct: types.Key<integer>? = types.Key.find("fixture.frames")
print(direct)
]=])[1],
        "NUPP2001"
    )
    check.eq(
        #errors(
            PRELUDE
            .. [=[
local found = types.Key.find("fixture.frames") as types.Key<integer>
store:set(found, 2)
print(store:get(found))
]=]
        ),
        0
    )
end

function M.anUnannotatedKeyNeedsATypeArgument()
    -- A key's value type is phantom: no runtime argument can answer it. Leaving off
    -- both the destination and the explicit argument must not produce Key<any>.
    check.eq(
        codes(
            PRELUDE
            .. [=[
local loose = types.newkey("fixture.loose")
store:set(loose, 7)
local text: string? = store:get(loose)
print(text)
]=]
        )[1],
        "NUPP2148"
    )
end

return M
