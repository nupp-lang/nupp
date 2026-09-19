-- Run this once per preserved build, with that build first on LUA_PATH.
-- Alternate baseline and candidate processes; the identical C encoder is a
-- colocated control for each process. Timing excludes validation and warmup.
local ffi = require("ffi")
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local simd = require("base64simd")
local reference = require("base64reference")
local entries = assert(rawget(_G, "__nuppAotCompiled"), "compiled-entry registry missing")
local nativeCalls = 0
jit.off()
debug.sethook(
    function()
        local frame = debug.getinfo(2, "f")
        if frame and entries[frame.func] then
            nativeCalls = nativeCalls + 1
        end
    end,
    "c"
)
simd.encode(("native proof"):rep(8))
debug.sethook()
assert(nativeCalls > 0, "the public encoder did not reach compiled code")
jit.on()

ffi.cdef[[size_t nuppBase64EncodeVector(const uint8_t *, size_t, char *);]]
local control = ffi.load(assert(arg[1], "C control library required"))
local output = ffi.new("char[?]", 100000)

local function encodeControl(value)
    local written = control.nuppBase64EncodeVector(value, #value, output)
    return ffi.string(output, written)
end

local small = ("0123456789abcdef"):rep(4)
local large = small:rep(1024)
for _, input in ipairs({"", "a", "ab", small, large}) do
    local expected = reference.encode(input)
    assert(simd.encode(input) == expected, "native encoder disagrees with scalar reference")
    assert(encodeControl(input) == expected, "C control disagrees with scalar reference")
    assert(simd.allocOnly(input) == string.char(#input % 256), "lease allocation result changed")
end
local cases = {
    {name = "encode64", run = simd.encode, input = small, iterations = 10000},
    {name = "alloc64", run = simd.allocOnly, input = small, iterations = 10000},
    {name = "encode64k", run = simd.encode, input = large, iterations = 100},
    {name = "control64", run = encodeControl, input = small, iterations = 10000},
}
local sink = 0

local function batch(case)
    local fn, input = case.run, case.input
    for _ = 1, case.iterations do
        sink = sink + #fn(input)
    end
end

for _, case in ipairs(cases) do
    batch(case)
    batch(case)
end
io.stderr:write("compiled calls confirmed; native, scalar, and C results agree\n")
io.write("sample,workload,seconds,iterations\n")
for sample = 1, tonumber(os.getenv("BUFFER_SAMPLES") or 15) do
    for offset = 1, #cases do
        local case = cases[(sample + offset - 2) % #cases + 1]
        collectgarbage("collect")
        local started = now()
        batch(case)
        io.write(("%d,%s,%.9f,%d\n"):format(sample, case.name, now() - started, case.iterations))
    end
end
assert(sink > 0)
