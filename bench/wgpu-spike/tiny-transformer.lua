-- One exact, deliberately tiny self-attention block over resident tensors.
-- Q/K/V projections, scores, polynomial softmax, and value mixing are queued
-- without an intermediate CPU boundary; one allocation supplies six dense views.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local gemm = require("gemm")
local transformer = require("transformer")
local gpu = require("nupp.gpu")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local tokens, width = 8, 8
local elements = tokens * width

local cell = ffi.new("float[1]")
local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

local state = 42
local function nextValue()
    state = (state * 1103515245 + 12345) % 2147483648
    return f32(state / 4294967296.0 - 0.25)
end

local input = ffi.new("float[?]", elements)
local queryWeights = ffi.new("float[?]", width * width)
local keyWeights = ffi.new("float[?]", width * width)
local valueWeights = ffi.new("float[?]", width * width)
for index = 0, elements - 1 do input[index] = nextValue() end
for index = 0, width * width - 1 do queryWeights[index] = nextValue() end
for index = 0, width * width - 1 do keyWeights[index] = nextValue() end
for index = 0, width * width - 1 do valueWeights[index] = nextValue() end

local q = ffi.new("float[?]", elements)
local k = ffi.new("float[?]", elements)
local v = ffi.new("float[?]", elements)
local scores = ffi.new("float[?]", tokens * tokens)
local probabilities = ffi.new("float[?]", tokens * tokens)
local expected = ffi.new("float[?]", elements)
local inputSpan = span.fromCarray(input, elements)
gemm.cpu(span.writeCarray(q, elements), inputSpan, span.fromCarray(queryWeights, width * width), width, width)
gemm.cpu(span.writeCarray(k, elements), inputSpan, span.fromCarray(keyWeights, width * width), width, width)
gemm.cpu(span.writeCarray(v, elements), inputSpan, span.fromCarray(valueWeights, width * width), width, width)
local scale = f32(1.0 / math.sqrt(width))
transformer.scoresCpu(
    span.writeCarray(scores, tokens * tokens),
    span.fromCarray(q, elements),
    span.fromCarray(k, elements),
    tokens, width, scale)
transformer.softmaxCpu(
    span.writeCarray(probabilities, tokens * tokens),
    span.fromCarray(scores, tokens * tokens), tokens)
transformer.mixCpu(
    span.writeCarray(expected, elements),
    span.fromCarray(probabilities, tokens * tokens),
    span.fromCarray(v, elements), tokens, width)

local context = gpu.open()
local inputBuffer = context:tensor(ffi.typeof("float"), {tokens, width})
local qWeightsBuffer = context:tensor(ffi.typeof("float"), {width, width})
local kWeightsBuffer = context:tensor(ffi.typeof("float"), {width, width})
local vWeightsBuffer = context:tensor(ffi.typeof("float"), {width, width})
local workspace = context:tensor(ffi.typeof("float"), {6, elements})
local qView = workspace:subview({0, 0}, {1, elements})
local kView = workspace:subview({1, 0}, {1, elements})
local vView = workspace:subview({2, 0}, {1, elements})
local scoresView = workspace:subview({3, 0}, {1, elements})
local probabilitiesView = workspace:subview({4, 0}, {1, elements})
local outputView = workspace:subview({5, 0}, {1, elements})
local dimensions, strides = outputView:dimensions(), outputView:strides()
assert(dimensions[1] == 1 and dimensions[2] == elements)
assert(strides[1] == elements and strides[2] == 1)
local gapped = workspace:subview({0, 0}, {6, elements / 2})
local transposed = gpu.view(workspace, gpu.transposeLayout(gpu.bufferLayout(workspace), {2, 1}))
local broadcast = gpu.view(qView, gpu.broadcastLayout(gpu.bufferLayout(qView), {6, elements}))
local transposedShape, transposedStrides = transposed:dimensions(), transposed:strides()
assert(not gpu.bufferIsDense(gapped) and gpu.bufferIsInjective(gapped))
assert(transposedShape[1] == elements and transposedShape[2] == 6)
assert(transposedStrides[1] == 1 and transposedStrides[2] == elements)
assert(not gpu.bufferIsDense(broadcast) and not gpu.bufferIsInjective(broadcast))
assert(not pcall(function() context:upload(gapped, inputSpan) end),
    "a non-dense tensor upload was admitted")
assert(not pcall(function() context:tensor(ffi.typeof("float"), {tokens, 0}) end),
    "a zero-stride broadcasting shape was admitted")

context:upload(inputBuffer, inputSpan)
context:upload(qWeightsBuffer, span.fromCarray(queryWeights, width * width))
context:upload(kWeightsBuffer, span.fromCarray(keyWeights, width * width))
context:upload(vWeightsBuffer, span.fromCarray(valueWeights, width * width))
context:synchronize()

local gemmKernel = gemm.gemm:compile(context)
local qProjection = gemmKernel:bind(qView, inputBuffer, qWeightsBuffer)
local kProjection = gemmKernel:bind(kView, inputBuffer, kWeightsBuffer)
local vProjection = gemmKernel:bind(vView, inputBuffer, vWeightsBuffer)
local scoreKernel = transformer.scores:compile(context):bind(scoresView, qView, kView)
local softmaxKernel = transformer.softmax:compile(context):bind(probabilitiesView, scoresView)
local mixKernel = transformer.mix:compile(context):bind(outputView, probabilitiesView, vView)

local function dispatch()
    qProjection:dispatch(width, width)
    kProjection:dispatch(width, width)
    vProjection:dispatch(width, width)
    scoreKernel:dispatch(tokens, width, scale)
    softmaxKernel:dispatch(tokens)
    mixKernel:dispatch(tokens, width)
    context:synchronize()
end

for _ = 1, 3 do dispatch() end
local started, passes = now(), 0
repeat
    dispatch()
    passes = passes + 1
until now() - started >= 1.0
local elapsed = (now() - started) / passes

local output = ffi.new("float[?]", elements)
local projected = ffi.new("float[?]", elements)
local gpuScores = ffi.new("float[?]", elements)
local gpuProbabilities = ffi.new("float[?]", elements)
context:enqueueDownload(outputView)
context:synchronize()
context:readDownloaded(outputView, span.writeCarray(output, elements))
context:enqueueDownload(qView)
context:synchronize()
context:readDownloaded(qView, span.writeCarray(projected, elements))
context:enqueueDownload(scoresView)
context:synchronize()
context:readDownloaded(scoresView, span.writeCarray(gpuScores, elements))
context:enqueueDownload(probabilitiesView)
context:synchronize()
context:readDownloaded(probabilitiesView, span.writeCarray(gpuProbabilities, elements))
for index = 0, elements - 1 do
    assert(projected[index] == q[index], ("Q view mismatch at %d"):format(index))
    assert(gpuScores[index] == scores[index], ("score mismatch at %d: got %.9g, want %.9g"):format(
        index, gpuScores[index], scores[index]))
    assert(gpuProbabilities[index] == probabilities[index],
        ("softmax mismatch at %d: got %.9g, want %.9g"):format(
            index, gpuProbabilities[index], probabilities[index]))
    assert(output[index] == expected[index], ("transformer mismatch at %d: got %.9g, want %.9g"):format(
        index, output[index], expected[index]))
end

io.write("Tiny transformer: 6 chained kernels and 6 resident views agree element-exact with CPU AOT\n")
io.write(("%-16s %12.3f us per 8-token block\n"):format("WGPU chain", elapsed * 1e6))
context:drop()
