-- The storage contract for a `Fixed<N>` vector field, per target: payload,
-- alignment, padding and size, as `nupp.compiler.targetlayout` states them,
-- and the layout of a struct holding such fields, which the generated C
-- declaration, the native emitter and the load-time check are all held to.
local test = require("assert")
local targetLayout = require("nupp.compiler.targetlayout")

local M = {}

local function vector(key, elementBytes, lanes)
    local layout, why = targetLayout.vector(key, elementBytes, lanes)
    assert(layout, tostring(why))
    return layout
end

-- A register-sized vector aligns to its size on every 64-bit target and Wasm.
function M.aRegisterSizedVectorAlignsToItsSize()
    for _, key in ipairs({"aarch64-apple-darwin", "x86_64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "wasm32-unknown-emscripten"}) do
        local four = vector(key, 4, 4)
        test.equal(four.payload, 16, key)
        test.equal(four.alignment, 16, key)
        test.equal(four.padding, 0, key)
        test.equal(four.size, 16, key)
    end
end

-- Fixed<3> of float has twelve payload bytes, aligns to the next power of two,
-- and pads to it: sixteen bytes occupied and a sixteen-byte array stride.
function M.aNonPowerOfTwoLaneCountPadsToItsAlignment()
    local three = vector("aarch64-apple-darwin", 4, 3)
    test.equal(three.payload, 12)
    test.equal(three.alignment, 16)
    test.equal(three.padding, 4)
    test.equal(three.size, 16)
    local bytes = vector("aarch64-apple-darwin", 1, 3)
    test.equal(bytes.alignment, 4)
    test.equal(bytes.size, 4)
end

-- A vector wider than the target's cap aligns to the cap and pads to a
-- multiple of it; on a 32-bit target the cap is what its allocator gives.
function M.aWiderThanRegisterVectorAlignsToTheCap()
    local wide = vector("x86_64-unknown-linux-gnu", 4, 8)
    test.equal(wide.payload, 32)
    test.equal(wide.alignment, 16)
    test.equal(wide.size, 32)
    local odd = vector("x86_64-unknown-linux-gnu", 4, 5)
    test.equal(odd.payload, 20)
    test.equal(odd.alignment, 16)
    test.equal(odd.size, 32)
    local small = vector("i686-unknown-linux-gnu", 4, 4)
    test.equal(small.alignment, 8, "a 32-bit allocator guarantees eight")
    test.equal(small.size, 16)
end

-- An element never aligns below its own width, and an unknown target or a
-- malformed shape is a reason rather than a layout.
function M.theContractRefusesWhatItCannotLayOut()
    local two = vector("aarch64-apple-darwin", 8, 1)
    test.equal(two.alignment, 8)
    local none, why = targetLayout.vector("m68k-unknown-none", 4, 4)
    assert(none == nil and why:find("unknown target"), tostring(why))
    local bad, badWhy = targetLayout.vector("aarch64-apple-darwin", 4, 0)
    assert(bad == nil and badWhy, tostring(badWhy))
end


local function vectorType(elementTag, lanes)
    return {
        tag = "nominal",
        origin = {moduleName = "nupp.simd", name = "Vector"},
        typeArgs = {
            {tag = elementTag},
            {
                tag = "nominal",
                origin = {moduleName = "nupp.simd", name = "Fixed"},
                constArgs = {{tag = "constLiteral", domain = "integer", value = lanes}},
            },
        },
    }
end

local function struct(fields)
    local order, byname = {}, {}
    for _, field in ipairs(fields) do
        order[#order + 1] = field[1]
        byname[field[1]] = field[2]
    end
    return {tag = "nominal", declKind = "struct", name = "S", fieldOrder = order, byname = byname}
end

-- A struct holding vectors is laid out by the vector contract: each vector
-- field at its alignment, occupying its padded size, and the struct aligned
-- to the largest field and sized to a multiple of it.
function M.aStructHoldingVectorsIsLaidOutByTheModel()
    local particle = struct{{"mass", {tag = "float"}}, {"velocity", vectorType("float", 4)}, {"color", vectorType("float", 3)}}
    local layout, why = targetLayout.of(particle, "aarch64-apple-darwin")
    assert(layout, tostring(why))
    test.equal(layout.offsets.mass, 0)
    test.equal(layout.offsets.velocity, 16)
    test.equal(layout.offsets.color, 32)
    test.equal(layout.fields[3].size, 16, "a three-lane field occupies its padded size")
    test.equal(layout.fields[3].alignment, 16)
    test.equal(layout.size, 48)
    test.equal(layout.alignment, 16)
    local narrow = assert(targetLayout.of(particle, "i686-unknown-linux-gnu"))
    test.equal(narrow.offsets.velocity, 8, "an eight-byte cap places the vector at eight")
    test.equal(narrow.offsets.color, 24)
    test.equal(narrow.size, 40)
    test.equal(narrow.alignment, 8)
end

-- A mask and a preferred-species vector have no layout a struct could hold.
function M.tierDependentFieldsHaveNoLayout()
    local mask = {tag = "nominal", origin = {moduleName = "nupp.simd", name = "Mask"}, typeArgs = {{tag = "float"}}}
    local _, why = targetLayout.of(struct{{"hit", mask}}, "aarch64-apple-darwin")
    assert(why and why:find("a mask has no storage layout", 1, true), tostring(why))
    local preferred = {
        tag = "nominal",
        origin = {moduleName = "nupp.simd", name = "Vector"},
        typeArgs = {{tag = "float"}, {tag = "nominal", origin = {moduleName = "nupp.simd", name = "Preferred"}}},
    }
    local _, reason = targetLayout.of(struct{{"v", preferred}}, "aarch64-apple-darwin")
    assert(reason and reason:find("tier-dependent species", 1, true), tostring(reason))
end

return M
