-- Holds the vector validator to the table-driven scalar reference on one
-- corpus, byte position by byte position: not only whether a string is valid
-- but how many leading bytes are, which is the number an error at the wrong
-- lane, a stale carry across vectors, or a tail rewound to the wrong byte
-- would each change.
--
-- The corpus is built from the cases the vector algorithm branches on: a
-- vector that is all ASCII and skips the lookup, one that is not, a scalar
-- that straddles the edge between two vectors, a lead left dangling at the
-- end of a vector followed by ASCII, every tail length after the last whole
-- vector, and every kind of malformed byte at every position of a string
-- long enough to reach every one of those paths.
local math = assert(loadfile("../../tests/simd/corpusmath.lua"))()
local simd = require("utf8simd")
local reference = require("utf8reference")
local shipped = require("nupp.text.utf8")

local proveNative = assert(loadfile("../../tests/simd/nativeproof.lua"))()
proveNative("utf8simd", function()
    local input = ("ASCII with \195\169 and \230\151\165"):rep(8)
    assert(simd.validPrefix(input) == reference.validPrefix(input))
end)

local checks = 0

local function agree(value, what)
    local want = reference.validPrefix(value)
    local got = simd.validPrefix(value)
    if got ~= want then
        error(("vector path disagrees on %s (%q): valid prefix %d, reference %d"):format(what, value, got, want), 0)
    end
    if simd.isValid(value) ~= (want == #value) then
        error(("isValid disagrees with validPrefix on %s (%q)"):format(what, value), 0)
    end
    -- The reference is held to the shipped validator on the same corpus, so a
    -- transition table typo cannot hide behind two implementations agreeing.
    if shipped.isValid(value) ~= (want == #value) then
        error(("reference disagrees with nupp.text.utf8 on %s (%q)"):format(what, value), 0)
    end
    checks = checks + 1
end

-- Well-formed scalars of every length, and the malformed sequences at the
-- edges of each rule: overlong forms, surrogate halves, values past
-- U+10FFFF, bytes that lead nothing, and continuations without a lead.
local valid = {
    "a",
    "\127",
    "\194\128",
    "\223\191",
    "\224\160\128",
    "\237\159\191",
    "\238\128\128",
    "\239\191\191",
    "\240\144\128\128",
    "\243\191\191\191",
    "\244\143\191\191",
}
local invalid = {
    "\128",
    "\191",
    "\192\128",
    "\193\191",
    "\194\127",
    "\194\192",
    "\224\128\128",
    "\224\159\191",
    "\237\160\128",
    "\237\191\191",
    "\225\128\065",
    "\225\192\128",
    "\240\128\128\128",
    "\240\143\191\191",
    "\244\144\128\128",
    "\245\128\128\128",
    "\248\136\128\128\128",
    "\252\132\128\128\128\128",
    "\254",
    "\255",
    "\241\128\128\065",
    "\241\128\065",
}

for _, value in ipairs(valid) do
    agree(value, "a scalar alone")
end
for _, value in ipairs(invalid) do
    agree(value, "a malformed sequence alone")
end
for b = 0, 255 do
    agree(string.char(b), "one byte")
end
for a = 0, 255 do
    for b = 0, 255 do
        agree(string.char(a, b), "two bytes")
    end
end

-- Every scalar and every malformed sequence at every offset of an ASCII
-- string of every length up to three vectors and a tail: this walks each of
-- them through every lane, across each vector edge, and into every tail
-- length, and the ASCII on both sides is what selects the fast path around
-- it. Truncating the string after it covers the incomplete-at-end case at
-- every position too.
local ascii = ("abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-=[];',./"):rep(2)
for _, list in ipairs({valid, invalid}) do
    for _, sequence in ipairs(list) do
        for offset = 0, 70 do
            local placed = ascii:sub(1, offset) .. sequence .. ascii:sub(offset + 1, 100)
            agree(placed, "a sequence placed at " .. offset)
            for cut = offset, offset + #sequence do
                agree(placed:sub(1, cut), "a sequence placed at " .. offset .. " cut at " .. cut)
            end
        end
    end
end

-- Multibyte text with no ASCII in it keeps every vector on the lookup path,
-- so a corruption here is found by the tables rather than the ladder, and a
-- truncation is a scalar the last vector could not finish.
local cjk = ("\230\151\165\230\156\172\232\170\158\240\159\141\176\195\169"):rep(12)
agree(cjk, "multibyte text")
for at = 1, #cjk do
    agree(cjk:sub(1, at), "multibyte text truncated at " .. at)
    for _, bad in ipairs({"\255", "\128", "\192", "\245", "\065", "\237\160\128"}) do
        agree(cjk:sub(1, at - 1) .. bad .. cjk:sub(at + #bad), "multibyte text corrupted at " .. at)
    end
end

-- A lead left dangling at the end of one vector with ASCII in the next is
-- the one error the ASCII fast path has to remember from the vector before.
for edge = 14, 66 do
    for _, lead in ipairs({"\195", "\226", "\226\130", "\240", "\240\159", "\240\159\141"}) do
        agree(("a"):rep(edge) .. lead .. ("b"):rep(40), "a dangling lead before ASCII at " .. edge)
        agree(("a"):rep(edge) .. lead, "a dangling lead at the end at " .. edge)
    end
end

-- Random strings drawn from the bytes that decide the hard cases, at lengths
-- from empty to a few vectors.
math.randomseed(31)
local leads = {0xC2, 0xC3, 0xDF, 0xE0, 0xED, 0xE6, 0xEF, 0xF0, 0xF4, 0xF5, 0x80, 0xBF, 0x41, 0x9f, 0xa0}
for _ = 1, 100000 do
    local t = {}
    for i = 1, math.random(0, 80) do
        t[i] = string.char(math.random() < 0.55 and leads[math.random(#leads)] or math.random(0, 255))
    end
    agree(table.concat(t), "a random string")
end
for _ = 1, 20000 do
    local t = {}
    for i = 1, math.random(0, 80) do
        local pick = math.random()
        t[i] = pick < 0.7 and valid[math.random(#valid)]
            or pick < 0.9 and string.char(math.random(0x20, 0x7e))
            or invalid[math.random(#invalid)]
    end
    agree(table.concat(t), "a random string of scalars")
end

print(("ok - %d UTF-8 differential checks: vector path, scalar reference and nupp.text.utf8 agree"):format(checks))

print("SIMD_CHECKS=" .. checks)
if math.fingerprint then
    print("SIMD_CORPUS_RANDOM=" .. math.fingerprint())
end
