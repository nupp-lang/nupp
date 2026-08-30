-- Batched GEMM over a dense A tensor and one transposed B matrix broadcast
-- across every batch. The generated kernel receives the views' explicit
-- strides, so no transpose or broadcast materialization is needed.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local generated = require("gemm")
local gpu = require("nupp.gpu")
ffi.cdef("float fmaf(float, float, float);")

local batches = tonumber(os.getenv("BATCHED_GEMM_BATCHES") or 4)
local size = tonumber(os.getenv("BATCHED_GEMM_SIZE") or 64)
local rows, columns, inner = size, size, size
local aCount = batches * rows * inner
local bCount = columns * inner
local cCount = batches * rows * columns

local cell = ffi.new("float[1]")
local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

local state = 42
local function nextValue()
    state = (state * 1103515245 + 12345) % 2147483648
    return f32(state / 2147483648.0 - 0.5)
end

local a = ffi.new("float[?]", aCount)
local bTransposed = ffi.new("float[?]", bCount)
local expected = ffi.new("float[?]", cCount)
for index = 0, aCount - 1 do a[index] = nextValue() end
for index = 0, bCount - 1 do bTransposed[index] = nextValue() end
for batch = 0, batches - 1 do
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local value = f32(0.0)
            for cursor = 0, inner - 1 do
                value = f32(ffi.C.fmaf(
                    a[batch * rows * inner + row * inner + cursor],
                    bTransposed[column * inner + cursor],
                    value))
            end
            expected[batch * rows * columns + row * columns + column] = value
        end
    end
end

local context = gpu.open()
local aBuffer = context:tensor(ffi.typeof("float"), {batches, rows, inner})
local storedB = context:tensor(ffi.typeof("float"), {1, columns, inner})
local transposedB = gpu.transposeLayout(gpu.bufferLayout(storedB), {1, 3, 2})
local logicalBLayout = gpu.broadcastLayout(transposedB, {batches, inner, columns})
local logicalB = gpu.view(storedB, logicalBLayout)
local output = context:tensor(ffi.typeof("float"), {batches, rows, columns})
assert(not gpu.bufferIsDense(logicalB) and not gpu.bufferIsInjective(logicalB))
local bShape, bStrides = logicalB:dimensions(), logicalB:strides()
assert(bShape[1] == batches and bShape[2] == inner and bShape[3] == columns)
assert(bStrides[1] == 0 and bStrides[2] == 1 and bStrides[3] == inner)

context:upload(aBuffer, span.fromCarray(a, aCount))
context:upload(storedB, span.fromCarray(bTransposed, bCount))
context:synchronize()

local aStrides = aBuffer:strides()
local kernel = generated.batched:compile(context):bind(output, aBuffer, logicalB)
kernel:dispatch(
    rows,
    columns,
    inner,
    aStrides[1],
    aStrides[2],
    aStrides[3],
    bStrides[1],
    bStrides[2],
    bStrides[3]
)
context:enqueueDownload(output)
context:synchronize()
local actual = ffi.new("float[?]", cCount)
context:readDownloaded(output, span.writeCarray(actual, cCount))
for index = 0, cCount - 1 do
    assert(actual[index] == expected[index], ("batched GEMM mismatch at %d"):format(index))
end

io.write(("Batched GEMM: %d x %dx%dx%d with transposed broadcast B agrees element-exact\n"):format(
    batches, rows, columns, inner))
context:drop()
