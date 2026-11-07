local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local hash = fixture.hash
local process = fixture.process
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.hashesMissingFilesWithTheirPaths()
    local fingerprint = require("nupp.compiler.project.fingerprint")
    local hash = require("nupp.compiler.hash")
    local missing = os.tmpname()
    os.remove(missing)
    testAssert.eq(fingerprint.hashFile(missing), nil)
    testAssert.eq(fingerprint.hashFiles({missing}), hash.digest(missing .. "\0missing"))
    testAssert.eq(fingerprint.hashFiles({}), hash.digest(""))
end

function M.sha256KnownVectors()
    testAssert.eq(hash.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    testAssert.eq(hash.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end

-- The published XXH64 answers. Cache keys never leave this machine, so
-- nothing forces the digest to be a particular function -- but a hand-rolled
-- one that is subtly wrong is a hand-rolled one nobody notices is wrong, and
-- these vectors are how a rewrite gets caught.
function M.xxh64KnownVectors()
    local function xxh(input, seed)
        -- `xxh64` carries its seed as two `uint32` halves, high then low, the
        -- same as everywhere else in this file; every seed below fits the low
        -- half.
        return hash.hex64(hash.xxh64(input, 0, seed))
    end

    testAssert.eq(xxh("", 0), "ef46db3751d8e999")
    testAssert.eq(xxh("a", 0), "d24ec4f1a98c6e5b")
    testAssert.eq(xxh("abc", 0), "44bc2cf5ad770999")
    testAssert.eq(xxh("abcd", 0), "de0327b0d25d92cc")
    testAssert.eq(xxh("heiå", 0), "b9d3d990d2001a1a")
    testAssert.eq(xxh("", 1), "d5afba1336a3be4b")
    testAssert.eq(xxh("Nobody inspects the spammish repetition", 0), "fbcea83c8a378bf1")
end

-- The formatter reaches the same digest through native host services, so the
-- fast path must keep every durable cache key compatible with the portable
-- implementation. Exercise the stripe boundary, all tail branches, binary
-- bytes, and enough input for the performance-sensitive path.
function M.theNativeContentDigestMatchesThePortableOne()
    local nativeHash = require("nupp.compiler.hostservices").hash
    local inputs = {
        "",
        "a",
        "abc",
        ("x"):rep(31),
        ("y"):rep(32),
        ("z"):rep(33),
        string.char(0, 255, 128, 1, 7),
        ("Nobody inspects the spammish repetition\0"):rep(4096),
    }
    for size = 0, 96 do
        local bytes = {}
        for index = 1, size do
            bytes[index] = string.char((index * 131 + size) % 256)
        end
        inputs[#inputs + 1] = table.concat(bytes)
    end
    for index, input in ipairs(inputs) do
        testAssert.eq(nativeHash.digest(input), hash.digest(input), "portable digest input " .. index)
    end
end

-- The eight bytes a stamped binary's trailer records. The Rust base provider
-- recomputes them on every run of that binary before handing a byte of the
-- payload to Lua, so this is one contract with two spellings and these are the
-- numbers both have to produce. The order matters as much as the value: the
-- field is little-endian so that a binary stamped on one machine verifies on
-- another, and a digest written the other way round would still be eight bytes
-- and still be wrong.
function M.theTrailerDigestIsLittleEndianXxh64()
    local function trailer(input)
        local bytes = hash.trailerDigest(input)
        local out = {}
        for index = 1, 8 do
            out[index] = ("%02x"):format(bytes:byte(index))
        end

        return table.concat(out)
    end

    -- The same published vectors as above, read back the other way round.
    testAssert.eq(trailer(""), "99e9d85137db46ef")
    testAssert.eq(trailer("a"), "5b6e8ca9f1c44ed2")
    testAssert.eq(trailer("abc"), "990977adf52cbc44")

    -- Either side of the thirty-two byte stripe loop, and a tail that reaches
    -- the four-byte branch and then the byte one.
    testAssert.eq(#hash.trailerDigest(("x"):rep(31)), 8)
    testAssert.eq(trailer(("x"):rep(31)), "f0993b08010ddd60")
    testAssert.eq(trailer(("y"):rep(32)), "66ce95341d1fda64")
    testAssert.eq(trailer(("z"):rep(33)), "68024ec6531224c5")
    testAssert.eq(trailer(string.char(0, 255, 128, 1, 7)), "950d048cbb3ee7b9")
end

-- Every tail branch and the stripe loop, at every length that reaches them.
-- The interesting failures here are off-by-one, not wrong constants: a digest
-- that ignores the last byte agrees with itself forever.
function M.digestSeparatesEveryLength()
    local seen = {}
    for n = 0, 200 do
        local input = ("abcdefgh"):rep(30):sub(1, n)
        local d = hash.digest(input)
        testAssert.eq(#d, 32)
        testAssert.eq(seen[d], nil)
        seen[d] = n
        testAssert.eq(hash.digest(input), d)
    end
    -- A one-byte change anywhere has to move the answer, including in the
    -- final byte, which is the one a tail loop drops.
    for _, n in ipairs({1, 4, 7, 8, 15, 16, 31, 32, 33, 64, 100}) do
        local input = ("x"):rep(n)
        local flipped = input:sub(1, n - 1) .. "y"
        assert(hash.digest(input) ~= hash.digest(flipped), "digest ignored the last byte at length " .. n)
    end
end

-- The fingerprint identifies the compiler, not where it was found. It used to
-- hash each file's path as given, and `moduleDir` reports whatever
-- `package.path` was written as -- so the launcher's absolute path and a
-- harness's relative one described the same compiler two ways, and every
-- cache stamped with it discarded the other's work whenever they alternated.

return M
