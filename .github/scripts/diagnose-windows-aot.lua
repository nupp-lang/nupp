local ffi = require("ffi")
local mode = arg[2]
if mode == "off" then
    jit.off()
elseif mode == "hot" then
    jit.opt.start("hotloop=1", "hotexit=1")
end
local function trace(phase)
    io.stdout:write(phase .. "\n")
    io.stdout:flush()
end

local test = {}
function test.equal(got, want, message)
    assert(got == want, tostring(message) .. ": " .. tostring(got) .. " ~= " .. tostring(want))
end

local function libraryPath()
    return assert(arg[1])
end

ffi.cdef("int ks_aot_feature_tier(void);")
local function librarySymbol(lib, logical)
    local rank = tonumber(lib.ks_aot_feature_tier())
    local tier = ({[0] = "baseline", "avx2", "avx512f"})[rank]
    trace(logical .. " tier " .. tostring(rank))
    return logical .. "__" .. assert(tier)
end

trace("load")
local ffi = require("ffi")
local lib = ffi.load(libraryPath(dir))
trace("select symbols")
local countQuotes = librarySymbol(lib, "ks_count_quotes")
local countQuotesScalar = librarySymbol(lib, "ks_count_quotes_forced_scalar")
local maskOps = librarySymbol(lib, "ks_mask_ops")
local lookup = librarySymbol(lib, "ks_lookup_aligned")
local lookupScalar = librarySymbol(lib, "ks_lookup_aligned_forced_scalar")
local shapes = librarySymbol(lib, "ks_mask_shapes")
local shapesScalar = librarySymbol(lib, "ks_mask_shapes_forced_scalar")
trace("declare symbols")
ffi.cdef(
    (
        [=[
      uint32_t %s(const uint8_t *source, size_t count_source);
      uint32_t %s(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2, v3, v4; } KsMaskOpsResult;
      KsMaskOpsResult %s(uint32_t low, uint32_t high);
      uint32_t %s(const uint8_t *source, size_t count_source);
      uint32_t %s(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2, v3, v4; } KsMaskShapesResult;
      KsMaskShapesResult %s(const uint8_t *source, size_t count_source);
      KsMaskShapesResult %s(const uint8_t *source, size_t count_source);
      typedef struct { uint32_t v1, v2; } KsMaskAddResult;
      KsMaskAddResult %s(uint32_t low, uint32_t high, uint32_t addend);
   ]=]
    ):format(
        countQuotes,
        countQuotesScalar,
        maskOps,
        lookup,
        lookupScalar,
        shapes,
        shapesScalar,
        librarySymbol(lib, "ks_mask_add")
    )
)
for round = 1, 50 do
    trace("tail comparisons")
    for count = 0, 40 do
        trace("tail " .. count)
        local source = ffi.new("uint8_t[?]", math.max(count, 1))
        local expected = 0
        for i = 0, count - 1 do
            source[i] = i % 5 == 0 and 34 or i
            if source[i] == 34 then
                expected = expected + 1
            end
        end
        test.equal(
            tonumber(lib[countQuotes](source, count)),
            expected,
            "packed and scalar tail lanes agree at length " .. count
        )
        test.equal(
            tonumber(lib[countQuotes](source, count)),
            tonumber(lib[countQuotesScalar](source, count)),
            "packed implementation agrees with its forced-scalar oracle at length " .. count
        )
        -- `bits`, `tail`, `any` and `all` have target-specific lowerings that the
        -- scalar oracle does not share, so each one is compared rather than only
        -- the reduction that happens to consume them.
        local packed = lib[shapes](source, count)
        local oracle = lib[shapesScalar](source, count)
        test.equal(
            tonumber(packed.v1),
            tonumber(oracle.v1),
            "packed bits agree with the scalar oracle at length " .. count
        )
        test.equal(
            tonumber(packed.v2),
            tonumber(oracle.v2),
            "packed tail agrees with the scalar oracle at length " .. count
        )
        test.equal(
            tonumber(packed.v3),
            tonumber(oracle.v3),
            "packed any agrees with the scalar oracle at length " .. count
        )
        test.equal(
            tonumber(packed.v4),
            tonumber(oracle.v4),
            "packed all agrees with the scalar oracle at length " .. count
        )
    end
    -- A 64-bit mask add is only worth having if it carries between the words,
    -- which is the whole reason run parity is stated as an addition.
    trace("mask addition")
    local add = librarySymbol(lib, "ks_mask_add")
    local carried = lib[add](0xFFFFFFFF, 0, 1)
    test.equal(tonumber(carried.v1), 0, "the low word wraps")
    test.equal(tonumber(carried.v2), 1, "and carries into the high word")
    local plain = lib[add](2, 7, 3)
    test.equal(tonumber(plain.v1), 5, "an add that does not carry stays put")
    test.equal(tonumber(plain.v2), 7, "and leaves the high word alone")
    local saturated = lib[add](0xFFFFFFFF, 0xFFFFFFFF, 1)
    test.equal(tonumber(saturated.v1), 0, "the low word wraps at the top")
    test.equal(tonumber(saturated.v2), 0, "and the carry out of the high word is dropped")
    trace("mask operations")
    local mask = lib[maskOps](5, 1)
    test.equal(tonumber(mask.v1), 3, "prefix XOR crosses the low mask word")
    test.equal(tonumber(mask.v2), 0xFFFFFFFF, "prefix XOR carries into the high mask word")
    test.equal(tonumber(mask.v3), 0, "firstSet finds the first logical bit")
    test.equal(tonumber(mask.v4), 33, "clearFirst drains one bit from a 64-bit mask")
    trace("lookup")
    local lookupSource = ffi.new("uint8_t[64]")
    for i = 0, 63 do
        lookupSource[i] = i % 16
    end
    test.equal(
        tonumber(lib[lookup](lookupSource, 64)),
        tonumber(lib[lookupScalar](lookupSource, 64)),
        "lookup and cross-vector alignment agree with the scalar oracle"
    )
    trace("complete")
end
