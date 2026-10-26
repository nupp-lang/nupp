-- Table semantics as the contracts state them (2.4, 2.13, 4.2, 9), run as
-- small programs through the installed runtime: under a compiler built with
-- `scripts/vm-cli build --native-core` every store, lookup, append and border
-- here runs on the Nupp table handlers; without the object the Rust step
-- answers the same programs, which is what makes the suite differential.
local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function run(lines)
    local src = table.concat(lines, "\n")
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    testAssert.equal(#diags, 0, "check diagnostics" .. (diags[1] and (": " .. diags[1].msg) or ""))

    return program.run(result, "native_tables_test", "test.nupp")
end

local M = {}

function M.hashKeysIterateInInsertionOrderAcrossGrowth()
    local order, count = run({
        "local m: {[string]: integer} = {}",
        "for i = 1, 100 do m['k' .. i] = i end",
        "for i = 1, 100, 3 do m['k' .. i] = nil end",
        "for i = 101, 140 do m['k' .. i] = i end",
        "m.k5 = 500",
        "local order: {string} = {}",
        "local count = 0",
        "for k, v in pairs(m) do order[#order + 1] = k; count = count + 1 end",
        "return table.concat(order, ','), count",
    })
    local expected = {}
    for i = 1, 140 do
        if i > 100 or i % 3 ~= 1 then
            expected[#expected + 1] = "k" .. i
        end
    end
    testAssert.equal(count, #expected, "every surviving key is visited once")
    testAssert.equal(order, table.concat(expected, ","), "first insertion decides the order; a rewrite keeps it")
end

function M.nextContinuesFromAnyKeyAndSkipsNilValues()
    local first, afterB, afterD, visited = run({
        "local m: {[string]: any} = {}",
        "m.a = 1; m.b = 2; m.c = 3; m.d = 4",
        "m.c = nil",
        "local k1 = next(m)",
        "local k2 = next(m, 'b')",
        "local k3 = next(m, 'd')",
        "local visited = 0",
        "for k in pairs(m) do visited = visited + 1; m[k] = nil end",
        "return k1 as string, k2 as string, k3 as string, visited",
    })
    testAssert.equal(first, "a", "the first key")
    testAssert.equal(afterB, "d", "a key whose value went nil is skipped")
    testAssert.equal(afterD, nil, "the last key has no successor")
    testAssert.equal(visited, 3, "clearing the current key during traversal visits every key once")
end

function M.rehashDropsNilEntriesAndKeepsTheRest()
    local keys, absent = run({
        "local m: {[string]: any} = {}",
        "m.a = 1; m.b = 2; m.c = 3; m.d = 4; m.e = 5; m.f = 6",
        "m.b = nil; m.d = nil; m.f = nil",
        "for i = 1, 20 do m['g' .. i] = i end",
        "local keys: {string} = {}",
        "for k in pairs(m) do keys[#keys + 1] = k end",
        "return table.concat(keys, ','), m.b == nil and m.d == nil and m.f == nil",
    })
    local expected = {"a", "c", "e"}
    for i = 1, 20 do
        expected[#expected + 1] = "g" .. i
    end
    testAssert.equal(keys, table.concat(expected, ","), "live entries keep their order through a rehash")
    testAssert.equal(absent, true, "nil-valued keys stay absent")
end

function M.integerKeysFillTheArrayPartAndMigrateFromTheHash()
    local length, second, third, fifth, sparse = run({
        "local t: {[number]: string} = {}",
        "t[3] = 'c'",
        "t[5] = 'e'",
        "t[2] = 'b'",
        "t[1] = 'a'",
        "local sparse = #t",
        "t[4] = 'd'",
        "return #t, t[2], t[3], t[5], sparse",
    })
    testAssert.equal(sparse, 3, "keys contiguous from 1 are the border; a gap stops it")
    testAssert.equal(length, 5, "filling the gap pulls the keys past it into the array part")
    testAssert.equal(second, "b", "a migrated key reads back")
    testAssert.equal(third, "c", "a migrated key reads back")
    testAssert.equal(fifth, "e", "the key past the gap reads back after migration")
end

function M.typedIntegerIndicesAppendAndRead()
    local length, middle, past = run({
        "local a: {integer} = {}",
        "for i = 1, 100 do a[i] = i * 2 end",
        "local past = a[101]",
        "return #a, a[50], past",
    })
    testAssert.equal(length, 100, "a hundred appends by integer index")
    testAssert.equal(middle, 100, "the fiftieth entry")
    testAssert.equal(past, nil, "past the border reads nil")
end

function M.theBorderShrinksPastTrailingNils()
    local afterLast, afterHole, afterBoth, afterHoleOnly = run({
        "local t: {integer} = {1, 2, 3, 4, 5}",
        "t[5] = nil",
        "local afterLast = #t",
        "t[2] = nil",
        "local afterHoleOnly = #t",
        "t[4] = nil",
        "local afterHole = #t",
        "t[3] = nil",
        "return afterLast, afterHole, #t, afterHoleOnly",
    })
    testAssert.equal(afterLast, 4, "clearing the last entry shrinks by one")
    testAssert.equal(afterHoleOnly, 4, "a hole in the middle leaves the border")
    testAssert.equal(afterHole, 3, "clearing the last entry shrinks past the hole's neighbor")
    testAssert.equal(afterBoth, 1, "the border scans back past every trailing nil")
end

function M.negativeZeroIsTheKeyZero()
    local read, overwritten, count = run({
        "local t: {[number]: string} = {}",
        "t[0] = 'z'",
        "local read = t[-0.0]",
        "t[-0.0] = 'w'",
        "local count = 0",
        "for _ in pairs(t) do count = count + 1 end",
        "return read, t[0], count",
    })
    testAssert.equal(read, "z", "-0 reads the entry 0 wrote")
    testAssert.equal(overwritten, "w", "-0 writes the entry 0 holds")
    testAssert.equal(count, 1, "one entry, not two")
end

function M.floatBooleanAndObjectKeysAreTheirOwnIdentity()
    local half, big, yes, no, byTable, byOther, byFunction = run({
        "local t: {[any]: any} = {}",
        "local key: {integer} = {}",
        "local other: {integer} = {}",
        "local function f() return 1 end",
        "t[1.5] = 'half'",
        "t[2 ^ 53] = 'big'",
        "t[true] = 'yes'",
        "t[false] = 'no'",
        "t[key] = 'table'",
        "t[f] = 'function'",
        "return t[1.5] as string, t[2 ^ 53] as string, t[true] as string, t[false] as string, t[key] as string, t[other] as string, t[f] as string",
    })
    testAssert.equal(half, "half", "a fractional key")
    testAssert.equal(big, "big", "a whole float past the array part")
    testAssert.equal(yes, "yes", "true as a key")
    testAssert.equal(no, "no", "false as a key")
    testAssert.equal(byTable, "table", "a table key by identity")
    testAssert.equal(byOther, nil, "another table is another key")
    testAssert.equal(byFunction, "function", "a function key")
end

function M.int64KeysBeyondTheExactRangeAreKeys()
    local found, other, length = run({
        "local t: {[integer]: string} = {}",
        "local big: integer = 9007199254740993",
        "t[big] = 'boxed'",
        "t[big + 1] = 'next'",
        "return t[9007199254740993], t[big + 1], #t",
    })
    testAssert.equal(found, "boxed", "an integer a double cannot hold is a key")
    testAssert.equal(other, "next", "its neighbor is another key")
    testAssert.equal(length, 0, "neither is in the array part")
end

function M.stringKeysAreByContent()
    local long, built, longCount = run({
        "local m: {[string]: integer} = {}",
        "local long = string.rep('x', 60)",
        "m[long] = 1",
        "m['a' .. 'b'] = 2",
        "m[string.rep('y', 60)] = 3",
        "m[string.rep('x', 60)] = 4",
        "local longCount = 0",
        "for _ in pairs(m) do longCount = longCount + 1 end",
        "return m[string.rep('x', 60)], m.ab, longCount",
    })
    testAssert.equal(long, 4, "a long string built twice is one key")
    testAssert.equal(built, 2, "a concatenated short key reads by name")
    testAssert.equal(longCount, 3, "three distinct keys")
end

function M.fieldStoresOnTablesKeepTheirPosition()
    local x, order = run({
        "local m: {[string]: any} = {}",
        "m.x = 1; m.y = 2; m.z = 3",
        "m.x = nil",
        "local gone = m.x",
        "m.x = 9",
        "local order: {string} = {}",
        "for k in pairs(m) do order[#order + 1] = k end",
        "return gone as string, table.concat(order, ',')",
    })
    testAssert.equal(x, nil, "a cleared field reads nil")
    testAssert.equal(order, "x,y,z", "a cleared field written again keeps its first position")
end

function M.metatablesAnswerAbsentKeysOnly()
    local inherited, own, log, rawValue, viaIndexFn = run({
        "local base: {[string]: any} = {value = 'base'}",
        "local written: {string} = {}",
        "local meta: {[string]: any} = {}",
        "meta.__index = base",
        "meta.__newindex = function(t: {[string]: any}, k: string, v: any) written[#written + 1] = k; rawset(t, k, v) end",
        "local obj: {[string]: any} = setmetatable({}, meta)",
        "obj.first = 1",
        "obj.first = 2",
        "obj['second'] = 3",
        "local fn: {[string]: any} = setmetatable({}, {__index = function(t: {[string]: any}, k: string): string return 'computed:' .. k end})",
        "return obj.value as string, obj.first as integer, table.concat(written, ','), rawget(obj, 'value') as string, fn.anything as string",
    })
    testAssert.equal(inherited, "base", "__index as a table answers an absent key")
    testAssert.equal(own, 2, "a present key is stored raw")
    testAssert.equal(log, "first,second", "__newindex runs for absent keys only")
    testAssert.equal(rawValue, nil, "rawget sees through no metatable")
    testAssert.equal(viaIndexFn, "computed:anything", "__index as a function is called with the key")
end

function M.nilAndNaNKeysAreErrorsAndReadNil()
    local nilOk, nilMessage, nanOk, nanMessage, readNaN = run({
        "local t: {[any]: any} = {}",
        "t[1] = 'one'",
        "local nilKey: any = nil",
        "local nilOk, nilMessage = pcall(function() t[nilKey] = 1 end)",
        "local nan = 0 / 0",
        "local nanOk, nanMessage = pcall(function() t[nan] = 1 end)",
        "return nilOk, tostring(nilMessage), nanOk, tostring(nanMessage), t[nan]",
    })
    testAssert.equal(nilOk, false, "storing under nil raises")
    assert(nilMessage:find("nil", 1, true), "the nil message names nil: " .. nilMessage)
    testAssert.equal(nanOk, false, "storing under NaN raises")
    assert(nanMessage:find("NaN", 1, true), "the NaN message names NaN: " .. nanMessage)
    testAssert.equal(readNaN, nil, "reading under NaN is nil")
end

function M.storesDuringCollectionKeepTheirValues()
    local kept, hashKept = run({
        "local keep: {[integer]: {integer}} = {}",
        "local names: {[string]: {integer}} = {}",
        "for i = 1, 20000 do",
        "    local garbage: {integer} = {i, i + 1, i + 2}",
        "    if i % 7 == 0 then keep[#keep + 1] = garbage end",
        "    if i % 11 == 0 then names['n' .. i] = garbage end",
        "end",
        "collectgarbage('collect')",
        "collectgarbage('collect')",
        "local kept = 0",
        "for i = 1, #keep do local entry = keep[i] as {integer}; if entry[1] == i * 7 and entry[3] == i * 7 + 2 then kept = kept + 1 end end",
        "local hashKept = 0",
        "for k, v in pairs(names) do if 'n' .. v[1] == k then hashKept = hashKept + 1 end end",
        "return kept, hashKept",
    })
    testAssert.equal(kept, math.floor(20000 / 7), "every value stored while cycles ran survives")
    testAssert.equal(hashKept, math.floor(20000 / 11), "every hash entry stored while cycles ran survives")
end

return M
