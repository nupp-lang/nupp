-- Holds the vector encoder to the scalar reference on one corpus, and both
-- to `nupp.codec.base64`, so a shared misreading of the format cannot agree
-- its way past the check.
--
-- The corpus is built from the cases the vector encoder branches on: every
-- length from empty through several whole groups of three vectors and every
-- tail after the last one, so the byte loop and the one- and two-byte padding
-- cases each run at every phase; every byte value at every position of a
-- vector group, which walks every lane of every gather and every entry of
-- the four alphabet tables through every slot of a triple; the all-zero and
-- all-ones blocks whose six-bit values sit at the ends of the alphabet; and
-- random strings up to a few kilobytes.
--
-- `--time` adds a timing run over the encoder and the reference.
local math = arg[1] == "--time" and _G.math or assert(loadfile("../../tests/simd/corpusmath.lua"))()
local simd = require("base64simd")
local reference = require("base64reference")
local shipped = require("nupp.codec.base64")

local proveNative = assert(loadfile("../../tests/simd/nativeproof.lua"))()
proveNative("base64simd", function()
    local source = ("native proof"):rep(16)
    local got = simd.encode(source)
    local want = reference.encode(source)
    assert(got == want, ("native proof mismatch:\n  got  %q\n  want %q"):format(got, want))
end)

local checks = 0

local function agree(value, what)
    local want = reference.encode(value)
    local got = simd.encode(value)
    if got ~= want then
        error(
            (
                "vector path disagrees on %s (%d bytes):\n  got  %s\n  want %s"
            ):format(what, #value, got:sub(1, 96), want:sub(1, 96)),
            0
        )
    end
    if shipped.encode(value) ~= want then
        error(("reference disagrees with nupp.codec.base64 on %s (%d bytes)"):format(what, #value), 0)
    end
    checks = checks + 1
end

-- The encoder consumes three vectors per iteration; 48 bytes on a
-- sixteen-lane species and 96 on a thirty-two-lane one. Lengths through
-- three of the wider groups and a tail cover both.
local GROUP = 96

math.randomseed(20260917)

local function random(length)
    local t = {}
    for i = 1, length do
        t[i] = string.char(math.random(0, 255))
    end

    return table.concat(t)
end

for length = 0, 3 * GROUP + 5 do
    agree(random(length), "a random string of length " .. length)
    agree(("\0"):rep(length), "zero bytes of length " .. length)
    agree(("\255"):rep(length), "0xFF bytes of length " .. length)
    agree(("\170"):rep(length), "0xAA bytes of length " .. length)
end

-- Every byte value at every position of one vector group, against a
-- background that maps to the first alphabet table, and then against one
-- that maps to the last: each six-bit value reaches each of the four tables
-- in each of the four slots of a quantum.
for _, background in ipairs({"\0", "\255", "\85"}) do
    for position = 1, GROUP do
        for byte = 0, 255 do
            local value = background:rep(position - 1) .. string.char(byte) .. background:rep(GROUP - position)
            agree(value, ("byte %d at position %d over %q"):format(byte, position, background))
        end
    end
end

-- Every byte value in every slot of the byte tail, after a whole group.
for tail = 1, 5 do
    for position = 1, tail do
        for byte = 0, 255 do
            local value = random(GROUP) .. ("\0"):rep(position - 1) .. string.char(byte) .. ("\0"):rep(tail - position)
            agree(value, ("byte %d at tail position %d of %d"):format(byte, position, tail))
        end
    end
end

-- Longer random strings, at lengths that put the tail at every phase.
for _ = 1, 2000 do
    agree(random(math.random(0, 4096)), "a long random string")
end

print(("ok - %d base64 differential checks: vector path, scalar reference and nupp.codec.base64 agree"):format(checks))

print("SIMD_CHECKS=" .. checks)
if math.fingerprint then
    print("SIMD_CORPUS_RANDOM=" .. math.fingerprint())
end

if arg[1] == "--time" then
    local clock = os.clock
    local sink = 0

    local function measure(fn, value, seconds)
        local runs = 0
        local started = clock()
        repeat
            sink = sink + #fn(value)
            runs = runs + 1
        until clock() - started >= seconds

        return (clock() - started) / runs
    end

    print("")
    print(("%10s %12s %12s %12s"):format("bytes", "nupp-simd", "reference", "codec.base64"))
    for _, size in ipairs({64, 1024, 65536, 1048576}) do
        local value = random(size)
        local vec = measure(simd.encode, value, 0.5) / size * 1e9
        local ref = measure(reference.encode, value, 0.5) / size * 1e9
        local ship = measure(shipped.encode, value, 0.5) / size * 1e9
        print(("%10d %9.3f ns/B %9.3f ns/B %9.3f ns/B"):format(size, vec, ref, ship))
    end
end
