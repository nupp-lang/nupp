-- Fixed-tree reduction benchmark: one declared 256-lane tree is generated for
-- the GPU and executed in the same stage order by the ordinary CPU control.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local generated = require("reduction")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local workgroupSize = 256
local count = tonumber(os.getenv("REDUCTION_COUNT") or 65536)
assert(count == workgroupSize * workgroupSize, "the two-level spike takes exactly 65536 values")

local cell = ffi.new("float[1]")
local function narrow(value)
    cell[0] = value
    return tonumber(cell[0])
end

ffi.cdef("float fmaf(float, float, float);")
local f32 = {}
function f32.add(left, right)
    return narrow(narrow(left) + narrow(right))
end
function f32.fma(left, right, addend)
    return narrow(ffi.C.fmaf(narrow(left), narrow(right), narrow(addend)))
end
function f32.exp(value)
    local x = math.max(-104.0, math.min(narrow(value), 88.0))
    local y = narrow(x * 0.0078125)
    local out = narrow(0.0000000020876757)
    for _, coefficient in ipairs({
        0.000000025052108, 0.00000027557319, 0.0000027557319,
        0.000024801587, 0.0001984127, 0.0013888889,
        0.0083333333, 0.041666667, 0.16666667, 0.5, 1.0, 1.0,
    }) do
        out = f32.fma(out, y, coefficient)
    end
    for _ = 1, 7 do out = narrow(out * out) end
    return out
end

local state = 42
local values = ffi.new("float[?]", count)
for index = 0, count - 1 do
    state = (state * 1103515245 + 12345) % 2147483648
    values[index] = narrow(-16.0 * state / 2147483648.0)
end

local function tree(sourceValues, active, transform)
    local groups = math.ceil(active / workgroupSize)
    local out = {}
    for group = 0, groups - 1 do
        local scratch = {}
        for localIndex = 0, workgroupSize - 1 do
            local index = group * workgroupSize + localIndex
            local value = index < active and sourceValues[index] or 0.0
            scratch[localIndex] = transform and transform(value) or value
        end
        local stride = workgroupSize / 2
        while stride >= 1 do
            for localIndex = 0, stride - 1 do
                scratch[localIndex] = f32.add(scratch[localIndex], scratch[localIndex + stride])
            end
            stride = stride / 2
        end
        out[group] = scratch[0]
    end
    return out
end

local expectedPartials = tree(values, count, f32.exp)
local expected = tree(expectedPartials, workgroupSize)[0]

local context = gpu.open()
local input = context:buffer(ffi.typeof("float"), count)
local partials = context:buffer(ffi.typeof("float"), workgroupSize)
local result = context:buffer(ffi.typeof("float"), 1)
context:upload(input, span.fromCarray(values, count))
context:synchronize()

local first = generated.exp:compile(context):bind(partials, input)
local second = generated.sum:compile(context):bind(result, partials)

local function dispatch()
    first:dispatch()
    second:dispatch()
    context:synchronize()
end

for _ = 1, 3 do dispatch() end
local started, passes = now(), 0
repeat
    dispatch()
    passes = passes + 1
until now() - started >= 1.0
local elapsed = (now() - started) / passes

local output = ffi.new("float[1]")
context:enqueueDownload(result)
context:synchronize()
context:readDownloaded(result, span.writeCarray(output, 1))
assert(output[0] == expected, ("reduction mismatch: got %.9g, want %.9g"):format(output[0], expected))

io.write(("Fixed 256-lane exp-sum tree: GPU and CPU agree at %.9g\n"):format(expected))
io.write(("%-16s %12.3f us  %8.2f million values/s\n"):format(
    "two GPU levels", elapsed * 1e6, count / elapsed / 1e6))
context:drop()
