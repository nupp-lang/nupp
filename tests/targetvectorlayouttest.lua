-- The storage contract for a `Fixed<N>` vector field, per target: payload,
-- alignment, padding and size, as `nupp.compiler.targetlayout` states them.
-- No storage field is laid out by it yet; this pins the contract an emitter
-- and a reporter will later be held to.
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

return M
