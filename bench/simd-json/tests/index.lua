-- Holds the vector structural indexer to the byte-at-a-time reference on one
-- corpus: the tape, the status and the error position must all agree.
--
-- The corpus is built from what the vector path branches on. Every byte
-- value is placed at every offset across two vector widths, outside a
-- string and inside one, so every event class crosses every lane and both
-- vector boundaries; backslash runs of every parity sit before a quote at
-- those same offsets; every UTF-8 lead is followed by continuations that are
-- valid, out of the lead's constrained range, ASCII, missing, or cut off by
-- the end of the input, again at every offset near a boundary; every tape
-- is also run one slot short; and random documents over an alphabet heavy
-- in event bytes cover what that enumeration did not think of.
--
-- `--time` adds a timing run over the indexer and the reference.
local math = arg[1] == "--time" and _G.math or assert(loadfile("../../tests/simd/corpusmath.lua"))()
local ffi = require("ffi")
local span = require("nupp.mem.span")
local indexer = require("simd_json.indexer")
local reference = require("simd_json.indexer_reference")

local checks = 0

local function indexed(source, capacity)
    local storage = ffi.new("uint32_t[?]", math.max(capacity, 1))
    local writable = span.writeCarray(storage, capacity)
    local count, status, position = indexer.index(span.fromString(source), writable)
    writable:drop()
    local positions = {}
    for offset = 0, tonumber(count) - 1 do
        positions[#positions + 1] = tonumber(storage[offset])
    end

    return positions, tonumber(status), tonumber(position)
end

local proveNative = assert(loadfile("../../tests/simd/nativeproof.lua"))()
proveNative("simd_json.indexer", function()
    local input = '{"proof":[1,true,"\\u1234"],"unicode":"é"}'
    local actual, status, position = indexed(input, #input)
    local expected, expectedStatus, expectedPosition = reference.index(input, #input)
    assert(status == expectedStatus and position == expectedPosition)
    assert(table.concat(actual, ",") == table.concat(expected, ","))
end)

local function describe(source)
    return (source:gsub("[^%w%p ]", function(c)
        return ("\\%03d"):format(c:byte())
    end)):sub(1, 120)
end

local function agree(source, capacity, what)
    capacity = capacity or #source
    local wantTape, wantStatus, wantPosition = reference.index(source, capacity)
    local gotTape, gotStatus, gotPosition = indexed(source, capacity)
    local same = #wantTape == #gotTape and wantStatus == gotStatus and wantPosition == gotPosition
    if same then
        for i = 1, #wantTape do
            if wantTape[i] ~= gotTape[i] then
                same = false
                break
            end
        end
    end
    if not same then
        error(
            (
                "vector indexer disagrees on %s (%d bytes, capacity %d): %s\n  got  status %d at %d, %d offsets: %s\n  want status %d at %d, %d offsets: %s"
            ):format(
                what,
                #source,
                capacity,
                describe(source),
                gotStatus,
                gotPosition,
                #gotTape,
                table.concat(gotTape, ","),
                wantStatus,
                wantPosition,
                #wantTape,
                table.concat(wantTape, ",")
            ),
            0
        )
    end
    checks = checks + 1
    if #wantTape > 0 and capacity == #source then
        agree(source, #wantTape - 1, what .. ", one slot short")
        agree(source, 0, what .. ", no tape")
    end
end

-- Two vector widths and a few bytes past them, so the sixteen- and
-- thirty-two-lane species both see every offset relative to a boundary.
local SPAN = 70

-- Every byte at every offset, outside a string and inside one.
for position = 0, SPAN - 1 do
    for byte = 0, 255 do
        local c = string.char(byte)
        agree(
            (" "):rep(position) .. c .. (" "):rep(SPAN - 1 - position),
            nil,
            ("byte %d at %d outside a string"):format(byte, position)
        )
        agree(
            '"' .. ("a"):rep(position) .. c .. ("a"):rep(SPAN - 1 - position) .. '"',
            nil,
            ("byte %d at %d inside a string"):format(byte, position)
        )
    end
end

-- Backslash runs of every parity before a quote, inside a string and not.
for position = 0, SPAN - 1 do
    for run = 1, 4 do
        local slashes = ("\\"):rep(run)
        agree(
            '"' .. ("a"):rep(position) .. slashes .. '"' .. ("b"):rep(3) .. '"',
            nil,
            ("%d backslashes at %d inside a string"):format(run, position)
        )
        agree(
            (" "):rep(position) .. slashes .. '"',
            nil,
            ("%d backslashes at %d outside a string"):format(run, position)
        )
        agree(
            '"' .. ("a"):rep(position) .. slashes .. 'x"',
            nil,
            ("%d backslashes then a letter at %d"):format(run, position)
        )
    end
end

-- Every UTF-8 lead with every kind of continuation, at every offset near a
-- boundary and at the end of the input.
local function utf8Cases(position)
    local cases = {}
    local pad = ("a"):rep(position)
    for lead = 0xC0, 0xFF do
        local l = string.char(lead)
        cases[#cases + 1] = {pad .. l .. "\128", "lead " .. lead .. " then 80"}
        cases[#cases + 1] = {pad .. l .. "\128\128", "lead " .. lead .. " then 80 80"}
        cases[#cases + 1] = {pad .. l .. "\128\128\128", "lead " .. lead .. " then 80 80 80"}
        cases[#cases + 1] = {pad .. l .. "\191\191\191", "lead " .. lead .. " then BF BF BF"}
        cases[#cases + 1] = {pad .. l .. "\159\128\128", "lead " .. lead .. " then 9F 80 80"}
        cases[#cases + 1] = {pad .. l .. "\160\128\128", "lead " .. lead .. " then A0 80 80"}
        cases[#cases + 1] = {pad .. l .. "\143\128\128", "lead " .. lead .. " then 8F 80 80"}
        cases[#cases + 1] = {pad .. l .. "\144\128\128", "lead " .. lead .. " then 90 80 80"}
        cases[#cases + 1] = {pad .. l .. "a", "lead " .. lead .. " then ASCII"}
        cases[#cases + 1] = {pad .. l .. "\"", "lead " .. lead .. " then a quote"}
        cases[#cases + 1] = {pad .. l .. "\128a", "lead " .. lead .. " then 80 then ASCII"}
        cases[#cases + 1] = {pad .. l .. "\128\128a", "lead " .. lead .. " then 80 80 then ASCII"}
        cases[#cases + 1] = {pad .. l .. "\128\192", "lead " .. lead .. " then 80 then a lead"}
        cases[#cases + 1] = {pad .. l, "lead " .. lead .. " at the end"}
        cases[#cases + 1] = {pad .. l .. "\128", "lead " .. lead .. " then 80 at the end"}
        cases[#cases + 1] = {pad .. l .. "\128\128", "lead " .. lead .. " then 80 80 at the end"}
    end
    cases[#cases + 1] = {pad .. "\128", "a stray continuation"}
    cases[#cases + 1] = {pad .. "\191\128", "two stray continuations"}

    return cases
end

for position = 0, SPAN - 1 do
    for _, case in ipairs(utf8Cases(position)) do
        agree(case[1], nil, case[2] .. " at " .. position)
        agree(case[1] .. ("b"):rep(40), nil, case[2] .. " at " .. position .. " with a tail")
    end
end

-- Documents of the ordinary shape.
local documents = {
    "",
    " ",
    "{}",
    "[]",
    '{"a":1,"b":[true,false,null],"c":{"d":"e\\"f","g":"h\\\\"}}',
    '["\\u00e9", "é", "日本語", "😀", "a\\\\\\"b"]',
    '{"key with spaces": "value\\ttab", "n": -1.5e10}',
    "\t\n\r {\"x\":\t[1,\n2,\r3]}\n",
    '{"nested":{"deep":{"deeper":{"deepest":[[[[[]]]]]}}}}',
    ('{"id":%d,"name":"user%d","tags":["a","b","c"]}'):rep(20),
    '"' .. ("x"):rep(200) .. '"',
    '"' .. ("\\\\"):rep(100) .. '"',
    '"' .. ("\\\""):rep(100) .. '"',
    '"' .. ("é"):rep(100) .. '"',
    '"' .. ("😀"):rep(50) .. '"',
    "{\"a\":\"b\n\"}",
    '{"a":\\"b"}',
    "[\1]",
    '"\127"',
}
for i, document in ipairs(documents) do
    agree(document, nil, "document " .. i)
end

-- Random documents over an alphabet heavy in event bytes.
math.randomseed(20260917)
local alphabet = {
    '"',
    '"',
    '"',
    "\\",
    "\\",
    "{",
    "}",
    "[",
    "]",
    ":",
    ",",
    " ",
    "\n",
    "\t",
    "a",
    "b",
    "1",
    "\1",
    "\127",
    "\128",
    "\191",
    "\192",
    "\194",
    "\223",
    "\224",
    "\237",
    "\239",
    "\240",
    "\244",
    "\245",
    "\255",
    "é",
    "日",
    "😀",
}
for _ = 1, 3000 do
    local parts = {}
    for _ = 1, math.random(0, 300) do
        parts[#parts + 1] = alphabet[math.random(#alphabet)]
    end
    agree(table.concat(parts), nil, "a random document")
end

print(("ok - %d structural index differential checks: vector path and byte-at-a-time reference agree"):format(checks))

print("SIMD_CHECKS=" .. checks)
if math.fingerprint then
    print("SIMD_CORPUS_RANDOM=" .. math.fingerprint())
end

if arg[1] == "--time" then
    local clock = os.clock

    local function measure(fn, seconds)
        local runs = 0
        local started = clock()
        repeat
            fn()
            runs = runs + 1
        until clock() - started >= seconds

        return (clock() - started) / runs
    end

    print("")
    print(("%10s %12s %12s"):format("bytes", "nupp-simd", "reference"))
    local record = '{"id":12345,"name":"user name","active":true,"tags":["one","two","three"],"score":98.6}'
    for _, size in ipairs({64, 1024, 65536, 1048576}) do
        local source = record:rep(math.ceil(size / #record)):sub(1, size)
        local storage = ffi.new("uint32_t[?]", size)
        local input = span.fromString(source)
        local writable = span.writeCarray(storage, size)
        local vec = measure(
            function()
                indexer.index(input, writable)
            end,
            0.5
        ) / size * 1e9
        local ref = measure(
            function()
                reference.index(source, size)
            end,
            0.5
        ) / size * 1e9
        writable:drop()
        print(("%10d %9.3f ns/B %9.3f ns/B"):format(size, vec, ref))
    end
end
