-- `nupp aot`: what an `@aot` function compiles to, and whether it vectorised.
--
-- Driven through the real binary rather than the module, because the artifacts and
-- the exit status are the whole interface. `--check` is an exit status, so a test that
-- could not read one would not be testing it.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function project(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write('return {include = {"."}}\n')
    manifest:close()
    for name, source in pairs(files) do
        local parent = name:match("^(.*)/[^/]+$")
        if parent then
            assert(os.execute(("mkdir -p %q"):format(dir .. "/" .. parent)) == 0)
        end
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(source)
        handle:close()
    end

    return dir
end

-- Keep command status separate from stdout. `--emit spirv` writes arbitrary binary,
-- and a Windows text-mode pipe can translate it or treat Ctrl-Z as the end before a
-- sentinel appended to that same stream. The artifact is always read in binary mode;
-- failed commands still put their ordinary diagnostic in the same file.
local function run(dir, argv)
    local outputPath = dir .. "/.nupp-aot-output"
    local statusPath = dir .. "/.nupp-aot-status"
    os.remove(outputPath)
    os.remove(statusPath)
    os.execute(
        (
            "cd %q && { NO_COLOR= '%s' aot %s > .nupp-aot-output 2>&1; code=$?; printf '%%s\\n' \"$code\" > .nupp-aot-status; }"
        ):format(dir, NUPP, argv)
    )
    local output = assert(io.open(outputPath, "rb"), "aot command wrote no output file")
    local out = output:read("*a")
    output:close()
    local status = assert(io.open(statusPath, "rb"), "aot command wrote no status file")
    local code = assert(tonumber(status:read("*a")), "aot command wrote an invalid status")
    status:close()
    os.remove(outputPath)
    os.remove(statusPath)

    return out, code
end

local function spirvWord(module, offset)
    local a, b, c, d = module:byte(offset, offset + 3)
    assert(d ~= nil, "truncated SPIR-V word")
    return a + b * 256 + c * 65536 + d * 16777216
end

local function spirvInstructions(module)
    local instructions = {}
    local offset = 21
    while offset <= #module do
        local first = spirvWord(module, offset)
        local wordCount = math.floor(first / 65536)
        assert(wordCount > 0, "zero-length SPIR-V instruction")
        local operands = {}
        for word = 1, wordCount - 1 do
            operands[word] = spirvWord(module, offset + word * 4)
        end
        instructions[#instructions + 1] = {opcode = first % 65536, operands = operands}
        offset = offset + wordCount * 4
    end
    test.equal(offset, #module + 1)

    return instructions
end

local function spirvOpcodeCount(module, opcode)
    local count = 0
    for _, instruction in ipairs(spirvInstructions(module)) do
        if instruction.opcode == opcode then
            count = count + 1
        end
    end

    return count
end

local function spirvDecorationCount(module, decoration)
    local count = 0
    for _, instruction in ipairs(spirvInstructions(module)) do
        if instruction.opcode == 71 and instruction.operands[2] == decoration then
            count = count + 1
        end
    end

    return count
end

local function spirvHasExtendedInstruction(module, number)
    for _, instruction in ipairs(spirvInstructions(module)) do
        if instruction.opcode == 12 and instruction.operands[4] == number then
            return true
        end
    end

    return false
end

local function spirvHasFloatNaNConstant(module)
    local instructions = spirvInstructions(module)
    local floatTypes = {}
    for _, instruction in ipairs(instructions) do
        if instruction.opcode == 22 and instruction.operands[2] == 32 then
            floatTypes[instruction.operands[1]] = true
        end
    end
    for _, instruction in ipairs(instructions) do
        local bits = instruction.operands[3]
        if instruction.opcode == 43 and floatTypes[instruction.operands[1]] and bits ~= nil then
            local exponent = math.floor(bits / 8388608) % 256
            local fraction = bits % 8388608
            if exponent == 255 and fraction ~= 0 then
                return true
            end
        end
    end

    return false
end

local function assertSpirvStructure(module)
    local instructions = spirvInstructions(module)

    local functionReturns = {}
    local functions, loops = 0, 0
    for index, instruction in ipairs(instructions) do
        if instruction.opcode == 33 then -- OpTypeFunction
            functionReturns[instruction.operands[1]] = instruction.operands[2]
        elseif instruction.opcode == 54 then -- OpFunction
            functions = functions + 1
            test.equal(
                functionReturns[instruction.operands[4]],
                instruction.operands[1],
                "SPIR-V function result and function type disagree"
            )
        elseif instruction.opcode == 246 then -- OpLoopMerge
            loops = loops + 1
            local nextOpcode = assert(instructions[index + 1], "unterminated SPIR-V loop merge").opcode
            assert(nextOpcode == 249 or nextOpcode == 250, "SPIR-V loop merge does not immediately precede its branch")
        end
    end
    assert(functions > 1, "SPIR-V module has no helper functions")
    assert(loops > 0, "SPIR-V module has no structured loops")
end

-- A register-resident loop: sixteen bytes read once, then arithmetic over locals that
-- touches no memory. Above the intensity threshold, so lanes are expected to pay.
local COMPUTE = [[
local span = require("nupp.mem.span")

local struct Point
    re: float
    im: float
end

local struct Escape
    iterations: int32
    escaped: uint32
end

@aot
local function escapes(
    exclusive out: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    limit: int32
): nil
    if #out ~= #points then
        error("length mismatch", 2)
    end
    if first < 1 or last > #out or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local cell = out[i]
        local point = points[i]
        local cx = point.re
        local cy = point.im
        local zx = 0.0
        local zy = 0.0
        local zxSquared = 0.0
        local zySquared = 0.0
        local iteration = 0
        local escaped = 0
        while iteration < limit do
            if zxSquared + zySquared > 4.0 then
                escaped = 1
                break
            end
            zy = 2.0 * zx * zy + cy
            zx = zxSquared - zySquared + cx
            zxSquared = zx * zx
            zySquared = zy * zy
            iteration = iteration + 1
        end
        cell.iterations = iteration
        cell.escaped = escaped
    end
end

return {escapes = escapes, Point = Point, Escape = Escape,}
]]

function M.gpuTargetEmitsShaderAndTypedHostBinding()
    local dir = project({
        [
            "gpu.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function doubled(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        local value = nupp.math.f32.narrow(input[i])
        local product: float = 0.0
        local repetition: uint32 = 0
        while repetition < nupp.math.u32.wrap(1) do
            product = nupp.math.f32.mul(value, scale)
            repetition = nupp.math.u32.add(repetition, 1)
        end
        local adjusted = nupp.math.f32.sub(scale, 1.0)
        output[i] = nupp.math.f32.fma(nupp.math.f32.add(product, adjusted), scale, 0.0)
    end
end
return {doubled = doubled}
]],
    })
    local module, moduleCode = run(dir, "--emit spirv gpu.nupp")
    test.equal(moduleCode, 0, module)
    test.equal(#module > 20, true)
    test.equal(module:sub(1, 4), "\3\2\35\7")
    assertSpirvStructure(module)
    assert(spirvDecorationCount(module, 42) > 0, "strict binary32 arithmetic lost NoContraction")
    assert(not spirvHasFloatNaNConstant(module), "SPIR-V emitted a validator-rejected NaN float constant")

    local binding, bindingCode = run(dir, "--emit binding gpu.nupp")
    test.equal(bindingCode, 0, binding)
    assert(binding:find("Buffer<float>", 1, true), binding)
    assert(binding:find("scale: float", 1, true), binding)
    assert(binding:find("ArtifactSet", 1, true), binding)
    assert(binding:find("spirv =", 1, true), binding)
    assert(not binding:find("msl =", 1, true), binding)
    assert(binding:find("compileGenerated", 1, true), binding)
    assert(binding:find("bindKernel", 1, true), binding)
    assert(binding:find("setRead(0, input, true)", 1, true), binding)
    assert(binding:find("setWrite(0, output, true)", 1, true), binding)
    assert(binding:find("dispatchPacked", 1, true), binding)

    local wasmBinding, wasmBindingCode = run(dir, "--emit binding --target wasm32-unknown-emscripten gpu.nupp")
    test.equal(wasmBindingCode, 1, wasmBinding)
    assert(wasmBinding:find("webgpu-int32", 1, true), wasmBinding)
    assert(not wasmBinding:find('wgsl = "nil"', 1, true), wasmBinding)

    local summary, summaryCode = run(dir, "--check gpu.nupp")
    test.equal(summaryCode, 0, summary)
    assert(
        summary:find(", gpu, one iteration per GPU invocation", 1, true),
        "a compiled GPU artifact is reported with its lowered shape: " .. summary
    )
    assert(not summary:find("refused", 1, true), "a working GPU kernel is not treated as a refusal: " .. summary)
end

function M.mandelbrotGpuBenchmarkUsesTheCpuFmaRecurrence()
    for _, path in ipairs({"../bench/simd-mandelbrot/mandelbrot.nupp", "../bench/wgpu-spike/typed/mandelbrot.nupp",}) do
        local handle = assert(io.open(HERE .. "/" .. path, "rb"))
        local source = handle:read("*a")
        handle:close()
        assert(
            source:find("zy = nupp.math.f32.fma(doubledZx, zy, cy)", 1, true),
            path .. " must use the explicitly fused binary32 recurrence"
        )
    end
end

function M.gpuTargetEmitsWebGpuIntegerArtifact()
    local dir = project({
        [
            "gpu.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function xorMask(
    exclusive output: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>,
    mask: uint32
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.u32.xorBits(input[i], mask)
    end
end
return xorMask
]],
    })
    local shader, code = run(dir, "--emit wgsl gpu.nupp")
    test.equal(code, 0, shader)
    assert(shader:find("@compute @workgroup_size(256)", 1, true), shader)
    assert(shader:find("var<storage, read> input: array<u32>", 1, true), shader)
    assert(shader:find("var<storage, read_write> output: array<u32>", 1, true), shader)
    assert(shader:find("output[uniforms.output_offset + dispatch_index]", 1, true), shader)
    assert(shader:find("^ uniforms.mask", 1, true), shader)

    local binding, bindingCode = run(dir, "--emit binding --target wasm32-unknown-emscripten gpu.nupp")
    test.equal(bindingCode, 0, binding)
    assert(binding:find("local artifacts = new gpuRuntime_ks_xor_mask.ArtifactSet", 1, true), binding)
    assert(binding:find("wgsl = \"struct NuppUniforms", 1, true), binding)
    assert(binding:find("compileGenerated(artifacts, 1, 1", 1, true), binding)

    local floatingDir = project({
        [
            "gpu.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function doubled(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        local value = nupp.math.f32.narrow(input[i])
        output[i] = nupp.math.f32.mul(value, 2.0)
    end
end
return doubled
]],
    })
    local floating, floatingCode = run(floatingDir, "--emit wgsl gpu.nupp")
    test.equal(floatingCode, 1, floating)
    assert(floating:find("webgpu-int32 profile", 1, true), floating)
end

function M.loopFreeScalarExplainsWhyLanesDoNotApply()
    local dir = project({
        ["scalar.nupp"] = [[
@aot
local function doubled(value: number): number
    return value * 2.0
end
return doubled
]],
    })
    local summary, code = run(dir, "scalar.nupp")
    test.equal(code, 0, summary)
    assert(
        summary:find("no map loop to run in lanes", 1, true),
        "the summary describes the body rather than inventing lanes=false: " .. summary
    )
    assert(not summary:find("@aot(lanes = false)", 1, true), summary)
end

function M.qualifiedAotDeclarationIsRefusedWithoutATraceback()
    local dir = project({
        [
            "qualified.nupp"
        ] = [[
local api = {}
@aot
function api.doubled(value: number): number
    return value * 2.0
end
return api
]],
    })
    local output, code = run(dir, "qualified.nupp")
    assert(code ~= 0, output)
    assert(output:find("NUPP2902", 1, true) and output:find("requires a local function declaration", 1, true), output)
    assert(not output:find("stack traceback", 1, true), output)
end

function M.gpuTargetHonoursPerFunctionFpContraction()
    local dir = project({
        [
            "relaxed.nupp"
        ] = [[
local span = require("nupp.mem.span")

@relax("fp-contract")
@aot(target = "gpu")
local function relaxed(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float,
    bias: float
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.f32.add(
            nupp.math.f32.mul(nupp.math.f32.narrow(input[i]), scale),
            bias
        )
    end
end
return {relaxed = relaxed}
]],
    })
    local module, code = run(dir, "--emit spirv relaxed.nupp")
    test.equal(code, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    test.equal(spirvDecorationCount(module, 42), 0, "relaxed arithmetic retained NoContraction")
end

function M.aotUsesNativeTranscendentalsOnlyWhenGranted()
    local dir = project({
        [
            "native-exp.nupp"
        ] = [[
local span = require("nupp.mem.span")

@relax("fp-transcendentals")
@aot(target = "gpu")
local function nativeExp(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.f32.exp(nupp.math.f32.narrow(input[i]))
    end
end

@relax("fp-transcendentals")
@aot
local function nativeExpCpu(value: float): float
    return nupp.math.f32.exp(value)
end

return {nativeExp = nativeExp, nativeExpCpu = nativeExpCpu}
]],
    })
    local module, moduleCode = run(dir, "--emit spirv native-exp.nupp")
    test.equal(moduleCode, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    assert(spirvHasExtendedInstruction(module, 27), "native exponential did not emit GLSL.std.450 Exp")

    local c, cCode = run(dir, "--emit c native-exp.nupp")
    test.equal(cCode, 0, c)
    assert(c:find("expf(", 1, true), c)

    local ir, irCode = run(dir, "--emit ir native-exp.nupp")
    test.equal(irCode, 0, ir)
    assert(ir:find("contract fp-transcendentals(native)", 1, true), ir)
end

function M.gpuTargetLoadsAndStoresBinary16Bits()
    local dir = project({
        [
            "half.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function roundTrip(
    exclusive output: span.WriteSpan<float>,
    exclusive packed: span.WriteSpan<uint16>,
    borrows input: span.Span<uint16>
): nil
    assert(#output == #packed and #output == #input, "length mismatch")
    for i = 1, #output do
        local value = nupp.math.f32.fromF16Bits(input[i])
        output[i] = value
        packed[i] = nupp.math.f32.toF16Bits(value)
    end
end

@aot
local function roundTripCpu(
    exclusive output: span.WriteSpan<float>,
    exclusive packed: span.WriteSpan<uint16>,
    borrows input: span.Span<uint16>
): nil
    assert(#output == #packed and #output == #input, "length mismatch")
    for i = 1, #output do
        local value = nupp.math.f32.fromF16Bits(input[i])
        output[i] = value
        packed[i] = nupp.math.f32.toF16Bits(value)
    end
end

@aot(target = "gpu")
local function roundTripBf16(
    exclusive output: span.WriteSpan<float>,
    exclusive packed: span.WriteSpan<uint16>,
    borrows input: span.Span<uint16>
): nil
    assert(#output == #packed and #output == #input, "length mismatch")
    for i = 1, #output do
        local value = nupp.math.f32.fromBF16Bits(input[i])
        output[i] = value
        packed[i] = nupp.math.f32.toBF16Bits(value)
    end
end

@aot
local function roundTripBf16Cpu(
    exclusive output: span.WriteSpan<float>,
    exclusive packed: span.WriteSpan<uint16>,
    borrows input: span.Span<uint16>
): nil
    assert(#output == #packed and #output == #input, "length mismatch")
    for i = 1, #output do
        local value = nupp.math.f32.fromBF16Bits(input[i])
        output[i] = value
        packed[i] = nupp.math.f32.toBF16Bits(value)
    end
end

@aot(target = "gpu")
local function signedToFloat(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<int8>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.f32.narrow(input[i])
    end
end
return {
    roundTrip = roundTrip,
    roundTripCpu = roundTripCpu,
    roundTripBf16 = roundTripBf16,
    roundTripBf16Cpu = roundTripBf16Cpu,
    signedToFloat = signedToFloat,
}
]],
    })
    local module, code = run(dir, "--emit spirv --function roundTrip half.nupp")
    test.equal(code, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    assert(spirvOpcodeCount(module, 113) > 0, "half conversion emitted no OpUConvert")
    assert(spirvOpcodeCount(module, 124) > 0, "half conversion emitted no OpBitcast")

    local signedModule, signedCode = run(dir, "--emit spirv --function signedToFloat half.nupp")
    test.equal(signedCode, 0, signedModule)
    assert(spirvOpcodeCount(signedModule, 114) > 0, "signed storage emitted no OpSConvert")

    local c, cCode = run(dir, "--emit c half.nupp")
    test.equal(cCode, 0, c)
    assert(c:find("nupp_f16_to_f32", 1, true), c)
    assert(c:find("nupp_bf16_to_f32", 1, true), c)
    assert(c:find("uint16_t *restrict p_packed", 1, true), c)
end

function M.gpuTargetUsesTheIrPolynomialExponential()
    local dir = project({
        [
            "exp.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function exponential(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.f32.exp(nupp.math.f32.narrow(input[i]))
    end
end

@aot
local function exponentialCpu(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.f32.exp(nupp.math.f32.narrow(input[i]))
    end
end
return {exponential = exponential, exponentialCpu = exponentialCpu}
]],
    })
    local module, moduleCode = run(dir, "--emit spirv exp.nupp")
    test.equal(moduleCode, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    assert(not spirvHasExtendedInstruction(module, 27), "IR exponential delegated to GLSL.std.450 Exp")
    assert(spirvDecorationCount(module, 42) >= 8, "IR exponential lost its binary32 contraction barriers")

    local c, cCode = run(dir, "--emit c exp.nupp")
    test.equal(cCode, 0, c)
    assert(c:find("nupp_f32_exp", 1, true), c)
    assert(c:find("nupp_f32_fma(out, y", 1, true), c)
end

-- Spans a matrix product relates by dimension, not equality: the guard names
-- only the index spans, every a/b access is a proved cursor, and the shader
-- keeps each dominating bound check against the span counts in its uniforms.
function M.gpuTargetTakesManyBuffersAndProvedCursors()
    local dir = project({
        [
            "gemm.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function gemm(
    exclusive c: span.WriteSpan<float>,
    borrows rowOf: span.Span<uint32>,
    borrows a: span.Span<float>,
    columns: uint32
): nil
    if #c ~= #rowOf then error("length mismatch", 2) end
    for i = 1, #c do
        local row = rowOf[i]
        local ai = nupp.math.u32.mul(row, columns)
        local value: float = 0.0
        if ai < #a then
            value = nupp.math.f32.narrow(a[ai + 1])
        end
        c[i] = value
    end
end
return {gemm = gemm}
]],
    })
    local module, moduleCode = run(dir, "--emit spirv gemm.nupp")
    test.equal(moduleCode, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    assert(spirvDecorationCount(module, 33) >= 4, "SPIR-V lost buffer or uniform bindings")
    assert(spirvDecorationCount(module, 34) >= 4, "SPIR-V lost descriptor-set assignments")
    assert(spirvOpcodeCount(module, 65) > 0, "cursor access emitted no OpAccessChain")
    assert(spirvOpcodeCount(module, 176) > 0, "cursor guard emitted no OpULessThan")

    local binding, bindingCode = run(dir, "--emit binding gemm.nupp")
    test.equal(bindingCode, 0, binding)
    assert(binding:find("setRead(0, rowOf, true)", 1, true), binding)
    assert(binding:find("setRead(1, a, false)", 1, true), binding)
    assert(binding:find("setWrite(0, c, true)", 1, true), binding)
end

-- CPU maps use the same per-access proof as GPU maps: only spans addressed by
-- the counted-loop index need an equality guard, while a differently sized span
-- may be reached through a cursor dominated by its own count check.
function M.cpuTargetTakesPartialGuardsAndProvedCursors()
    local dir = project({
        [
            "gather.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function gather(
    exclusive out: span.WriteSpan<float>,
    borrows offsets: span.Span<uint32>,
    borrows source: span.Span<float>
): nil
    if #out ~= #offsets then error("length mismatch", 2) end
    for i = 1, #out do
        local cursor = offsets[i]
        local value: float = 0.0
        if cursor < #source then
            value = nupp.math.f32.narrow(source[cursor + 1])
        end
        out[i] = value
    end
end
return {gather = gather}
]],
    })
    local c, code = run(dir, "--emit c gather.nupp")
    test.equal(code, 0, c)
    assert(c:find("p_source[((size_t)v", 1, true), c)
end

-- A proved cursor may still name a guarded-equal span. Such a map shares one
-- count in its private ABI, so the in-body bound check must read that shared
-- count rather than inventing a count_input parameter the signature omitted.
function M.cpuCursorUsesTheSharedCountOfGuardedSpans()
    local dir = project({
        [
            "shared-count.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function copyFirst(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        local cursor: uint32 = 0
        local value: float = 0.0
        if cursor < #input then
            value = nupp.math.f32.narrow(input[cursor + 1])
        end
        output[i] = value
    end
end
return {copyFirst = copyFirst}
]],
    })
    local c, code = run(dir, "--emit c shared-count.nupp")
    test.equal(code, 0, c)
    assert(c:find("< ((double)count)", 1, true), c)
    assert(not c:find("count_input", 1, true), c)
end

function M.gpuTargetExposesItsLoopIndexAndUnsignedDivision()
    local dir = project({
        [
            "coordinates.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function coordinates(
    exclusive out: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>,
    columns: uint32
): nil
    assert(#out == #input, "length mismatch")
    for i = 1, #out do
        local offset = nupp.math.u32.sub(nupp.math.u32.wrap(i), 1)
        local row = nupp.math.u32.div(offset, columns)
        local column = nupp.math.u32.mod(offset, columns)
        out[i] = nupp.math.u32.add(input[i], nupp.math.u32.add(row, column))
    end
end

@aot
local function coordinatesCpu(
    exclusive out: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>,
    columns: uint32
): nil
    assert(#out == #input, "length mismatch")
    for i = 1, #out do
        local offset = nupp.math.u32.sub(nupp.math.u32.wrap(i), 1)
        local row = nupp.math.u32.div(offset, columns)
        local column = nupp.math.u32.mod(offset, columns)
        out[i] = nupp.math.u32.add(input[i], nupp.math.u32.add(row, column))
    end
end
return {coordinates = coordinates, coordinatesCpu = coordinatesCpu}
]],
    })
    local module, code = run(dir, "--emit spirv coordinates.nupp")
    test.equal(code, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    assert(spirvOpcodeCount(module, 134) > 0, "coordinate row emitted no OpUDiv")
    assert(spirvOpcodeCount(module, 137) > 0, "coordinate column emitted no OpUMod")

    local c, cCode = run(dir, "--emit c coordinates.nupp")
    test.equal(cCode, 0, c)
    assert(c:find("nupp_u32_div", 1, true), c)
    assert(c:find("(i + 1u)", 1, true), c)
end

local GPU_PHASE_DECLARATIONS = [[
module nupp.gpu

export record Shared<T>
    readonly count: integer
    metamethod __len: function(borrows self: Shared<T>): integer
    metamethod __index: function(borrows self: Shared<T>, index: integer): T
    metamethod __newindex: function(exclusive self: Shared<T>, index: integer, value: T): nil
end

export record Phases
    scratch: function<T>(borrows self: Phases, initial: T, count: integer): Shared<T>
    run: function(borrows self: Phases, scoped stage: function(uint32): nil): nil
    reduceSumF32: function(borrows self: Phases, exclusive values: Shared<float>): nil
    inclusiveScanU32: function(
        borrows self: Phases,
        exclusive values: Shared<uint32>,
        exclusive temporary: Shared<uint32>
    ): nil
end

export const workgroups: function(
    groups: uint32,
    size: uint32,
    scoped controller: function(uint32, Phases): nil
)
]]

function M.gpuTargetEmitsStructuredWorkgroupPhasesAndFixedTreeReduction()
    local dir = project({
        ["nupp/gpu.d.nupp"] = GPU_PHASE_DECLARATIONS,
        [
            "reduce.nupp"
        ] = [[
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function reduce(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    local zero = nupp.math.f32.narrow(0.0)
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#input), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        local values = phases:scratch(zero, 4)
        phases:run(function(localIndex: uint32)
            local cursor = nupp.math.u32.add(
                nupp.math.u32.mul(groupIndex, nupp.math.u32.wrap(4)),
                localIndex
            )
            if cursor < #input then
                values[localIndex] = nupp.math.f32.narrow(input[cursor + 1])
            else
                values[localIndex] = nupp.math.f32.narrow(0.0)
            end
        end)
        phases:reduceSumF32(values)
        phases:run(function(localIndex: uint32)
            if localIndex == nupp.math.u32.wrap(0) and groupIndex < #output then
                output[groupIndex + 1] = values[0]
            end
        end)
    end)
end
return {reduce = reduce}
]],
    })
    local spirv, spirvCode = run(dir, "--emit spirv reduce.nupp")
    test.equal(spirvCode, 0, spirv)
    test.equal(spirv:sub(1, 4), "\3\2#\7")
    test.equal(spirvOpcodeCount(spirv, 224), 5, "reduction emitted the wrong barrier count")
    assert(spirvDecorationCount(spirv, 11) >= 3, "workgroup kernel lost invocation builtins")

    local binding, bindingCode = run(dir, "--emit binding reduce.nupp")
    test.equal(bindingCode, 0, binding)
    assert(binding:find("bindKernel(self._kernel, input.count)", 1, true), binding)
    assert(binding:find("raw:setRead(0, input, false)", 1, true), binding)
    assert(binding:find(", 4)", 1, true), binding)
end

function M.gpuTargetSkipsBarriersForScratchFreeWorkgroups()
    local dir = project({
        ["nupp/gpu.d.nupp"] = GPU_PHASE_DECLARATIONS,
        [
            "map.nupp"
        ] = [[
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function map(
    exclusive output: span.WriteSpan<float>
): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#output), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        phases:run(function(localIndex: uint32)
            if localIndex == nupp.math.u32.wrap(0) then
                if groupIndex < #output then
                    output[groupIndex + 1] = nupp.math.f32.narrow(1.0)
                end
            end
        end)
    end)
end
return {map = map}
]],
    })
    local module, code = run(dir, "--emit spirv map.nupp")
    test.equal(code, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    test.equal(spirvOpcodeCount(module, 224), 0, "scratch-free workgroup emitted a barrier")
    assert(spirvDecorationCount(module, 11) >= 3, "workgroup kernel lost invocation builtins")
end

function M.gpuTargetLoadsReadonlyStructOnce()
    local dir = project({
        ["nupp/gpu.d.nupp"] = GPU_PHASE_DECLARATIONS,
        [
            "fields.nupp"
        ] = [[
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

local struct Pair
    left: float
    right: float
end

@aot(target = "gpu")
local function addPairs(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<Pair>
): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#output), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        phases:run(function(localIndex: uint32)
            local index = nupp.math.u32.add(
                nupp.math.u32.mul(groupIndex, nupp.math.u32.wrap(4)),
                localIndex
            )
            local inputCursor = index
            local outputCursor = index
            if inputCursor < #input then
                if outputCursor < #output then
                    local pair = input[inputCursor + 1]
                    output[outputCursor + 1] = nupp.math.f32.add(
                        nupp.math.f32.narrow(pair.left),
                        nupp.math.f32.narrow(pair.right)
                    )
                end
            end
        end)
    end)
end
return {addPairs = addPairs}
]],
    })
    local module, code = run(dir, "--emit spirv fields.nupp")
    test.equal(code, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    test.equal(spirvOpcodeCount(module, 65), 7, "repeated struct fields rebuilt a storage address")
end

function M.gpuTargetEmitsDeterministicInclusiveScan()
    local dir = project({
        ["nupp/gpu.d.nupp"] = GPU_PHASE_DECLARATIONS,
        [
            "scan.nupp"
        ] = [[
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function scan(exclusive output: span.WriteSpan<uint32>): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#output), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        local values = phases:scratch(nupp.math.u32.wrap(0), 4)
        local temporary = phases:scratch(nupp.math.u32.wrap(0), 4)
        phases:run(function(localIndex: uint32)
            values[localIndex] = nupp.math.u32.add(localIndex, nupp.math.u32.wrap(1))
        end)
        phases:inclusiveScanU32(values, temporary)
        phases:run(function(localIndex: uint32)
            local cursor = nupp.math.u32.add(
                nupp.math.u32.mul(groupIndex, nupp.math.u32.wrap(4)),
                localIndex
            )
            if cursor < #output then
                output[cursor + 1] = values[localIndex]
            end
        end)
    end)
end
return {scan = scan}
]],
    })
    local module, code = run(dir, "--emit spirv scan.nupp")
    test.equal(code, 0, module)
    test.equal(module:sub(1, 4), "\3\2#\7")
    test.equal(spirvOpcodeCount(module, 224), 5, "scan emitted the wrong barrier count")
    assert(spirvDecorationCount(module, 11) >= 3, "scan lost workgroup invocation builtins")
end

function M.gpuTargetRefusesNonDisjointWorkgroupScratchWrites()
    local dir = project({
        ["nupp/gpu.d.nupp"] = GPU_PHASE_DECLARATIONS,
        [
            "bad-phase.nupp"
        ] = [[
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function bad(exclusive output: span.WriteSpan<float>): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#output), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        local values = phases:scratch(nupp.math.f32.narrow(0.0), 4)
        phases:run(function(localIndex: uint32)
            values[nupp.math.u32.add(localIndex, nupp.math.u32.wrap(1))] = nupp.math.f32.narrow(0.0)
        end)
    end)
end

return {bad = bad}
]],
    })
    local shader, code = run(dir, "--emit spirv bad-phase.nupp")
    assert(code ~= 0, shader)
    assert(shader:find("shared scratch writes must use exactly localIndex", 1, true), shader)
end

function M.gpuTargetRefusesSamePhaseCrossLaneScratchRace()
    local dir = project({
        ["nupp/gpu.d.nupp"] = GPU_PHASE_DECLARATIONS,
        [
            "racy-phase.nupp"
        ] = [[
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function racy(exclusive output: span.WriteSpan<float>): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#output), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        local values = phases:scratch(nupp.math.f32.narrow(0.0), 4)
        phases:run(function(localIndex: uint32)
            values[localIndex] = nupp.math.f32.narrow(1.0)
        end)
        phases:run(function(localIndex: uint32)
            values[localIndex] = nupp.math.f32.narrow(values[nupp.math.u32.mod(
                nupp.math.u32.add(localIndex, nupp.math.u32.wrap(1)), nupp.math.u32.wrap(4))])
        end)
        phases:run(function(localIndex: uint32)
            if localIndex == nupp.math.u32.wrap(0) and groupIndex < #output then
                output[groupIndex + 1] = values[0]
            end
        end)
    end)
end
return {racy = racy}
]],
    })
    local shader, code = run(dir, "--emit spirv racy-phase.nupp")
    assert(code ~= 0, shader)
    assert(shader:find("cannot read another lane", 1, true), shader)
end

-- A guardless GPU map may only reach an unguarded span through proved cursors.
-- A dispatch-indexed read of one has no proof anywhere -- no guard host-side,
-- no dominating check in the shader -- so the entry is refused at the source.
function M.gpuTargetRefusesDispatchIndexingAnUnguardedSpan()
    local dir = project({
        [
            "fill.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function fill(
    exclusive out: span.WriteSpan<float>,
    borrows inp: span.Span<float>
): nil
    for i = 1, #out do
        out[i] = inp[i]
    end
end
return {fill = fill}
]],
    })
    local shader, shaderCode = run(dir, "--emit spirv fill.nupp")
    assert(shaderCode ~= 0, shader)
    assert(shader:find("guarded equal", 1, true), shader)
end

-- A block kernel -- no guard prologue -- whose loop counts one span and reads another.
-- Nothing relates their lengths, and before this was refused here it reached the IR
-- verifier and came back as a Lua traceback with no source position in it.
local UNPROVED_SPAN = [[
local span = require("nupp.mem.span")

@aot
local function fill(
    exclusive out: span.WriteSpan<float>,
    borrows inp: span.Span<float>
): nil
    for i = 1, #out do
        out[i] = inp[i] * 2.0
    end
end

return {fill = fill}
]]

-- The same hole one step earlier: a block kernel whose loop is counted by something
-- that is not a span length at all. Nothing then relates the index to any span, and
-- the load and the store each used to reach the IR verifier -- "unbounded load index"
-- and "invalid store root" -- rather than being refused against the line that wrote
-- them.
local UNCOUNTED_LOAD = [[
local span = require("nupp.mem.span")

@aot
local function readIt(borrows values: span.Span<number>): number
    local total = 0.0
    for i = 1, 1 do
        total = values[i]
    end
    return total
end

return {readIt = readIt}
]]

local UNCOUNTED_STORE = [[
local span = require("nupp.mem.span")

@aot
local function writeIt(exclusive out: span.WriteSpan<number>): nil
    for i = 1, 1 do
        out[i] = 1.0
    end
end

return {writeIt = writeIt}
]]

-- A store through a span the loop does not count. The read of the same shape was
-- already refused; the write was not checked at all, so this one reached the
-- verifier even though the loop had a perfectly good bound -- just not this span's.
local UNPROVED_STORE = [[
local span = require("nupp.mem.span")

@aot
local function crossWrite(
    exclusive out: span.WriteSpan<number>,
    borrows other: span.Span<number>
): nil
    for i = 1, #other do
        out[i] = other[i]
    end
end

return {crossWrite = crossWrite}
]]

-- Two compiled entries, one calling the other. The callee is scalar in and scalar
-- out, which is what this IR can carry across a call.
local ENTRY_CALL = [[
local span = require("nupp.mem.span")

@aot
local function scale(value: number, factor: number): number
    return value * factor
end

@aot
local function apply(
    exclusive out: span.WriteSpan<float>,
    borrows inp: span.Span<float>,
    factor: number
): nil
    assert(#out == #inp, "length mismatch")

    for i = 1, #out do
        out[i] = scale(inp[i], factor)
    end
end

return {apply = apply, scale = scale}
]]

-- The same shape with almost no arithmetic: two fields in, two fields out, one multiply
-- and add each. Below the threshold, so lane lowering is declined rather than refused.
local STREAMING = [[
local span = require("nupp.mem.span")

local struct Position
    x: float
    y: float
end

local struct Velocity
    vx: float
    vy: float
end

@aot
local function advance(
    exclusive positions: span.WriteSpan<Position>,
    borrows velocities: span.Span<Velocity>,
    first: integer,
    last: integer,
    dt: float
): nil
    if #positions ~= #velocities then
        error("length mismatch", 2)
    end
    if first < 1 or last > #positions or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local position = positions[i]
        local velocity = velocities[i]
        position.x = position.x + velocity.vx * dt
        position.y = position.y + velocity.vy * dt
    end
end

return {advance = advance, Position = Position, Velocity = Velocity,}
]]

local CONTIGUOUS_STREAMING = [[
local span = require("nupp.mem.span")

@aot
local function copy(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    first: integer,
    last: integer
): nil
    if #output ~= #input then error("length mismatch", 2) end
    if first < 1 or last > #output or first > last + 1 then error("range out of bounds", 2) end
    for index = first, last do
        output[index] = input[index]
    end
end
return {copy = copy}
]]

-- Lanes asked for, and a construct the rewrite has no lane form for. This is the one
-- outcome `--check` fails on: the loop wanted to run several iterations at once and did
-- not, which is what an ordinary edit can take away without any test noticing.
local REFUSED = STREAMING:gsub("@aot\n", "@aot(lanes = true)\n")
    :gsub(
    "        local position = positions%[i%]",
    "        local scale = dt\n"
    .. "        for step = 1, 5 do\n"
    .. "            scale = scale\n"
    .. "        end\n"
    .. "        local position = positions[i]"
)

local FIXED_MIX = [[
local span = require("nupp.mem.span")

@aot(lanes = true)
local function mix(
    exclusive output: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    first: integer,
    last: integer
): nil
    if #output ~= #input then error("length mismatch", 2) end
    if first < 1 or last > #output or first > last + 1 then error("range out of bounds", 2) end
    for index = first, last do
        local value = input[index]
        for round = 1, 4 do
            value = value * 1.0009765625 + round * 0.125
        end
        output[index] = value
    end
end
return {mix = mix}
]]

--- A target every host can compile for, at a tier that holds the wide gangs.
---
--- Pinned because these assert which gang a body takes, and that depends on what
--- the target can hold: the same source takes four lanes at avx2 and two at the
--- x86-64 baseline. Left to the host, they would assert the runner's CPU.
local PINNED = "--target x86_64-unknown-linux-gnu --features avx2 "

local BYTE_CLASSIFIER = [[
local span = require("nupp.mem.span")

@aot(lanes = true)
local function classify(
    exclusive flags: span.WriteSpan<uint8>,
    borrows bytes: span.Span<uint8>
): nil
    if #flags ~= #bytes then error("length mismatch", 2) end
    for i = 1, #flags do
        local byte = bytes[i]
        local flag: uint32 = 0
        if byte == 34 then
            flag = 1
        elseif byte == 92 then
            flag = 2
        end
        flags[i] = flag
    end
end

return {classify = classify}
]]

-- A non-JSON variable-rate block kernel. Its output cursor advances only under
-- the count check that authorizes the following one-based span store.
local DELIMITERS = [[
local span = require("nupp.mem.span")

@aot(lanes = false)
local function delimiters(
    borrows source: span.Span<uint8>,
    exclusive offsets: span.WriteSpan<uint32>
): uint32
    local written: uint32 = 0
    for i = 1, #source do
        if source[i] == 44 then
            if written < #offsets then
                offsets[written + 1] = written
                written = nupp.math.u32.add(written, 1)
            else
                return written
            end
        end
    end
    return written
end

return {delimiters = delimiters}
]]

local MUTATED_WHILE_CURSOR = [[
local span = require("nupp.mem.span")

@aot(lanes = false)
local function afterIncrement(borrows source: span.Span<uint8>): uint32
    local cursor: uint32 = 0
    local byte: uint32 = 0
    while cursor < #source do
        cursor = nupp.math.u32.add(cursor, 1)
        byte = source[(cursor + 1) as integer]
    end
    return byte
end

return {afterIncrement = afterIncrement}
]]

local SCOPED_SIMD = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local preferredBytes = simd.preferredU8

@aot(lanes = false)
local function quotes(borrows source: span.Span<uint8>): uint32
    local species = preferredBytes()
    local cursor: integer = 0
    local found: uint32 = 0
    while cursor < #source do
        local bytes = species:load(source, cursor)
        local tail = species:tail(#source - cursor)
        local quote = bytes:equal(34)
        local slash = bytes:equal(92)
        local either = quote:orBits(slash)
        local syntax = either:andBits(tail)
        found = nupp.math.u32.add(found, syntax:count())
        cursor = cursor + species.lanes
    end
    return found
end

return {quotes = quotes}
]]

-- The same kernel with its two preconditions written as asserts. `assert(ok, m)` and
-- `if not ok then error(m) end` state one fact in opposite polarity, so the backend
-- reads either spelling and has to reach the same kernel from both.
local function replaceOnce(text, from, to)
    local at = assert(text:find(from, 1, true), "fixture text not found:\n" .. from)
    return text:sub(1, at - 1) .. to .. text:sub(at + #from)
end

local COMPUTE_ASSERTED = replaceOnce(
    replaceOnce(
        COMPUTE,
        [[
    if #out ~= #points then
        error("length mismatch", 2)
    end]],
        [[
    assert(#out == #points, "length mismatch")]]
    ),
    [[
    if first < 1 or last > #out or first > last + 1 then
        error("range out of bounds", 2)
    end]],
    [[
    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]]
)

function M.assertGuardsReachTheSameKernel()
    local plain = project{["compute.nupp"] = COMPUTE}
    local asserted = project{["compute.nupp"] = COMPUTE_ASSERTED}
    local wanted, wantedCode = run(plain, PINNED .. "--emit c compute.nupp")
    local got, gotCode = run(asserted, PINNED .. "--emit c compute.nupp")
    test.equal(wantedCode, 0, wanted)
    test.equal(gotCode, 0, "assert guards are admitted like error guards\n" .. got)
    test.equal(got, wanted, "both spellings emit the same C")
end

function M.anAssertGuardStillHasToSayTheRightThing()
    local dir = project{
        ["compute.nupp"] = replaceOnce(COMPUTE_ASSERTED, "assert(#out == #points", "assert(#out ~= #points")
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a guard that proves nothing is refused\n" .. out)
    assert(
        out:find("compare span counts with ==", 1, true),
        "the comparison the asserted spelling wants is named: " .. out
    )
end

function M.anAssertRangeGuardIsMatchedAgainstItsWrittenForm()
    local dir = project{
        ["compute.nupp"] = replaceOnce(COMPUTE_ASSERTED, "first >= 1 and last <= #out", "first > 1 and last <= #out")
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a range guard that is not the admitted one is refused\n" .. out)
    assert(
        out:find("first >= 1 and last <= #output and first <= last + 1", 1, true),
        "the asserted spelling is quoted back: " .. out
    )
end

function M.anAssertGuardTakesAConditionAndAMessage()
    local dir = project{
        ["compute.nupp"] = replaceOnce(COMPUTE_ASSERTED, '"length mismatch")', '"length mismatch", "and another")')
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a third argument is rejected by the checked source\n" .. out)
    assert(out:find("expected 2, got 3", 1, true), "the ordinary call contract is reported first: " .. out)
end

function M.aRegisterResidentLoopReportsItsGangAndWidth()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 0, out)
    assert(out:find("mixed4", 1, true), "the gang is named: " .. out)
    assert(out:find("4 lanes", 1, true), "the width is named: " .. out)
    assert(out:find("operations per byte", 1, true), "the estimate behind the decision is shown: " .. out)
end

function M.aStreamingLoopDeclinesRatherThanFailing()
    local dir = project{["stream.nupp"] = STREAMING}
    local out, code = run(dir, "--check stream.nupp")
    test.equal(code, 0, "declining is not a failure\n" .. out)
    assert(out:find("too little arithmetic per byte", 1, true), "the reason it declined is the estimate: " .. out)
    assert(
        out:find("nupp.mem.soa", 1, true) and out:find("make them contiguous", 1, true),
        "strided field traffic points at the layout that removes it: " .. out
    )
end

function M.aContiguousStreamingLoopDoesNotReceiveAnAoSLayoutSuggestion()
    local dir = project{["stream.nupp"] = CONTIGUOUS_STREAMING}
    local out, code = run(dir, "--check stream.nupp")
    test.equal(code, 0, out)
    assert(out:find("too little arithmetic per byte", 1, true), "the loop declines: " .. out)
    assert(not out:find("nupp.mem.soa", 1, true), "contiguous spans need no layout suggestion: " .. out)
end

function M.aLoopThatWantedLanesAndDidNotGetThemFails()
    local dir = project{["refused.nupp"] = REFUSED}
    local out, code = run(dir, "--check refused.nupp")
    test.equal(code, 1, "wanting lanes and not getting them is the failure\n" .. out)
    assert(out:find("ran one iteration at a time", 1, true), "the outcome is named: " .. out)
    assert(
        out:find("nested numeric loop", 1, true),
        "the construct that stopped it is named, not only that it stopped: " .. out
    )
end

-- The lane body out of `--emit ir`, which is what a helper call and the same source
-- written inline have to agree on. The scalar body cannot be compared directly: one
-- spelling carries a `helper_call` and the other carries the expression, which is the
-- difference the inline is supposed to erase by the time lanes are chosen.
local function laneIr(dir, file, label)
    local out, code = run(dir, PINNED .. "--emit ir " .. file)
    test.equal(code, 0, label .. ": " .. out)
    local lanes = out:match("\nsimd lanes%(.-\n(.*)$") and out:match("(\nsimd lanes.*)$")
    assert(lanes, label .. " ran one iteration at a time, so there is no lane body to compare:\n" .. out)

    return lanes
end

-- Both spellings of one kernel: the predicate behind a helper, and the same predicate
-- written where it is used. Derived from one source so the two cannot drift apart.
local function bothSpellings(inlined, predicate, call, helper)
    local withHelper = inlined:gsub("@aot\n", helper .. "\n\n@aot\n", 1):gsub(predicate, call)
    assert(withHelper ~= inlined, "the predicate moved behind the helper")

    return withHelper, inlined
end

function M.aHelperCallLowersToTheSameLaneIrAsWritingItInline()
    -- The property the inline exists to have, and the one that regressed silently:
    -- a helper's parameters lowered as ordinary locals, the lane rewriter read the
    -- inlined body as uniform, and the loop ran scalar. Comparing the gang and the
    -- width would not have caught the shape being wrong, only its absence.
    local withHelper, inlined = bothSpellings(
        COMPUTE,
        "if zxSquared %+ zySquared > 4%.0 then",
        "if hasEscaped(zxSquared, zySquared) then",
        "local function hasEscaped(a: number, b: number): boolean\n    return a + b > 4.0\nend"
    )
    local dir = project{["helper.nupp"] = withHelper, ["inline.nupp"] = inlined}
    test.equal(laneIr(dir, "helper.nupp", "the helper spelling"), laneIr(dir, "inline.nupp", "the inline spelling"))
end

function M.aNumericHelperCallLowersToTheSameLaneIrAsWritingItInline()
    -- The condition path and the value path reach the rewriter differently -- one
    -- through a mask, one through a vector of the wanted element -- so one case
    -- passing says nothing about the other.
    local withHelper, inlined = bothSpellings(
        COMPUTE,
        "zy = 2%.0 %* zx %* zy %+ cy",
        "zy = twiceProduct(zx, zy) + cy",
        "local function twiceProduct(a: number, b: number): number\n    return 2.0 * a * b\nend"
    )
    local dir = project{["helper.nupp"] = withHelper, ["inline.nupp"] = inlined}
    test.equal(laneIr(dir, "helper.nupp", "the helper spelling"), laneIr(dir, "inline.nupp", "the inline spelling"))
end

function M.aFourTripLoopLowersToTheSameLaneIrAsWritingItOut()
    local written = FIXED_MIX:gsub(
        "        for round = 1, 4 do\n            value = value %* 1%.0009765625 %+ round %* 0%.125\n        end",
        table.concat(
            {
                "        value = value * 1.0009765625 + 0.125",
                "        value = value * 1.0009765625 + 0.25",
                "        value = value * 1.0009765625 + 0.375",
                "        value = value * 1.0009765625 + 0.5",
            },
            "\n"
        )
    )
    assert(written ~= FIXED_MIX, "the fixed loop was replaced by its control")
    local dir = project{["loop.nupp"] = FIXED_MIX, ["written.nupp"] = written}
    test.equal(laneIr(dir, "loop.nupp", "the fixed loop"), laneIr(dir, "written.nupp", "the written body"))

    local out, code = run(dir, PINNED .. "--json loop.nupp")
    test.equal(code, 0, out)
    local optimization = require("testjson").decode(out).functions[1].optimization
    test.equal(optimization.unrolledLoops, 1)
    test.equal(optimization.unrolledIterations, 4)
end

function M.aLoopRefusesASpanNothingProvesIsLongEnough()
    local dir = project{["unproved.nupp"] = UNPROVED_SPAN}
    local out, code = run(dir, "unproved.nupp")
    test.equal(code, 1, out)
    assert(out:find("unproved.nupp:9:18:", 1, true), "the refusal names the access, not the compiler: " .. out)
    assert(out:find("nothing proves inp is that long", 1, true), "it names the span that is not proved: " .. out)
    assert(out:find("assert(#out == #inp)", 1, true), "and the guard that would prove it: " .. out)
end

function M.aLoopCountedByNoSpanRefusesTheLoadItCannotProve()
    local dir = project{["uncounted.nupp"] = UNCOUNTED_LOAD}
    local out, code = run(dir, "uncounted.nupp")
    test.equal(code, 1, out)
    assert(out:find("uncounted.nupp:", 1, true), "the refusal names the access, not the compiler: " .. out)
    assert(
        out:find("the loop's bound is not a span count", 1, true),
        "it says what is missing rather than asserting: " .. out
    )
    assert(out:find("for i = 1, #values", 1, true), "and how to count the loop instead: " .. out)
end

function M.aLoopCountedByNoSpanRefusesTheStoreItCannotProve()
    local dir = project{["uncounted.nupp"] = UNCOUNTED_STORE}
    local out, code = run(dir, "uncounted.nupp")
    test.equal(code, 1, out)
    assert(out:find("uncounted.nupp:", 1, true), "the refusal names the store: " .. out)
    assert(
        out:find("the loop's bound is not a span count", 1, true),
        "a store gets the same account of itself as a load: " .. out
    )
end

function M.aStoreRefusesASpanNothingProvesIsLongEnough()
    local dir = project{["crosswrite.nupp"] = UNPROVED_STORE}
    local out, code = run(dir, "crosswrite.nupp")
    test.equal(code, 1, out)
    assert(out:find("crosswrite.nupp:", 1, true), "the refusal names the store: " .. out)
    assert(out:find("nothing proves out is that long", 1, true), "it names the span that is not proved: " .. out)
    assert(out:find("assert(#other == #out)", 1, true), "and the guard that would prove it: " .. out)
end

function M.oneCompiledEntryCallsAnotherAsARealCall()
    -- `@aot` used to disqualify a function from being callable at all: the
    -- annotation that says "compile this" also said "nothing compiled may reach
    -- it". A callee compiled once, reached through its own symbol, is the answer
    -- rather than a second copy inlined into every caller.
    local dir = project{["pair.nupp"] = ENTRY_CALL}
    local out, code = run(dir, PINNED .. "--emit c pair.nupp")
    test.equal(code, 0, out)
    assert(out:find("ks_scale(", 1, true), "the caller reaches the callee's own symbol: " .. out)
    assert(
        out:find("static inline double ks_scale", 1, true) == nil,
        "the callee is the entry it already is, not a second inlined copy: " .. out
    )
    assert(out:find("KS_API double ks_scale", 1, true), "and it keeps its own exported definition: " .. out)
end

function M.aLaneBodyDeclinesRatherThanCallingAnEntryPerLane()
    -- A compiled entry takes one set of scalars and answers once, so there is no
    -- per-lane form of it. Declining names that, rather than the loop quietly
    -- running scalar for a reason nothing reports.
    local source = COMPUTE:gsub(
        "@aot\n",
        "@aot\nlocal function beyondFour(a: number, b: number): number\n" .. "    return a + b - 4.0\nend\n\n@aot\n",
        1
    )
        :gsub("if zxSquared %+ zySquared > 4%.0 then", "if beyondFour(zxSquared, zySquared) > 0.0 then")
    local dir = project{["perlane.nupp"] = source}
    local out, code = run(dir, "--check perlane.nupp")
    test.equal(code, 1, "a loop that wanted lanes and did not get them fails --check\n" .. out)
    assert(
        out:find("cannot call a compiled entry", 1, true),
        "the refusal names the call, not just the outcome: " .. out
    )
end

function M.checkAloneDoesNotFailAWorkingLoop()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--check compute.nupp")
    test.equal(code, 0, out)
end

function M.emitPrintsTheGeneratedC()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "--emit c compute.nupp")
    test.equal(code, 0, out)
    assert(out:find("void ks_escapes(", 1, true), "the exported symbol is defined: " .. out)
    assert(
        out:find("ks_escapes_forced_scalar", 1, true),
        "the oracle the lane body is diffed against comes out too: " .. out
    )
    assert(out:find("*restrict", 1, true), "the writable span carries the disjointness ownership proved: " .. out)
    assert(out:find("ks_sel_f64x4", 1, true), "the conditional became a select rather than a branch: " .. out)
end

-- A result the wrapper has to establish. `loadlib` hands back `any`, so a
-- wrapper declared with a fixed width has to convert on the way out or fail its
-- own check -- and it failed at a position inside the generated text, which
-- surfaced as NUPP2011 on whatever line of the author's file it landed on. The
-- multi-result path always converted; the single-result one returned the call.
function M.aSingleFixedWidthResultIsEstablishedByItsWrapper()
    local dir = project{
        [
            "counter.nupp"
        ] = table.concat(
            {
                "module counter",
                "local valuebuilder = require(\"nupp.data.valuebuilder\")",
                "@aot(lanes = false)",
                "local function count(bytes: string): uint32",
                "    local limit: uint32 = valuebuilder.length(bytes)",
                "    local at: uint32 = nupp.math.u32.wrap(0)",
                "    while at < limit do",
                "        at = nupp.math.u32.add(at, nupp.math.u32.wrap(1))",
                "    end",
                "",
                "    return at",
                "end",
                "local counter = {}",
                "counter.count = count",
                "export = counter",
            },
            "\n"
        ),
    }
    local binding, bindingCode = run(dir, "--emit binding counter.nupp")
    test.equal(bindingCode, 0, binding)
    assert(
        binding:find("nupp.math.u32.wrap(native1 as integer)", 1, true),
        "the single result is established rather than returned as any: " .. binding
    )
    local checked, checkedCode = run(dir, "--check --emit ir counter.nupp")
    test.equal(checkedCode, 0, checked)
end

-- Whether the instructions can be read on this machine at all. The condition is
-- a C compiler, which is what produces them; a machine without one is missing a
-- build dependency rather than failing.
local function hasToolchain()
    return (require("nupp.compiler.build.aot").toolchain()) ~= nil
end

-- Deliberately not `PINNED`. Instructions come from a real compilation, and
-- compiling for a triple this machine is not needs that target's headers, so
-- these ask for the host and assert what holds on either architecture.
function M.emitAsmShowsWhatTheCCompilerMadeOfTheBody()
    if not hasToolchain() then
        test.skip("reading instructions needs a C compiler")
    end
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--emit asm compute.nupp")
    test.equal(code, 0, out)
    assert(
        out:match("^%-%- compute%.nupp, [^,]+, [^,]+, .+\n") ~= nil,
        "the header names the file, the target, the tier and the compiler: " .. out
    )
    assert(out:find("ks_escapes (escapes), kernel:", 1, true), "the compiled body is named by both spellings: " .. out)
    assert(
        out:find("ks_escapes_forced_scalar (escapes), oracle:", 1, true),
        "the forced-scalar twin is told apart from the body it is the oracle for: " .. out
    )
    assert(
        out:find("ks_escapes (escapes)", 1, true) < out:find("forced_scalar", 1, true),
        "what the reader came for is first, whatever order the compiler emitted: " .. out
    )
end

function M.asmShowsOneFunctionWhenOneIsNamed()
    if not hasToolchain() then
        test.skip("reading instructions needs a C compiler")
    end
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--emit asm --function ks_escapes compute.nupp")
    test.equal(code, 0, out)
    assert(out:find("ks_escapes (escapes), kernel:", 1, true), out)
    assert(not out:find("forced_scalar", 1, true), "only the symbol that was named is listed: " .. out)
end

-- A name nothing matches is the common mistake -- the source spells it one way
-- and the symbol another -- so the refusal says what it would have taken.
function M.asmSaysWhatItWouldHaveAccepted()
    if not hasToolchain() then
        test.skip("reading instructions needs a C compiler")
    end
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--emit asm --function escape compute.nupp")
    test.equal(code, 1, out)
    assert(out:find("escapes", 1, true) and out:find("ks_escapes", 1, true), out)
end

-- The counts are the part two runs are compared on, so they have to be over the
-- listing rather than beside it.
function M.asmJsonCountsWhatItLists()
    if not hasToolchain() then
        test.skip("reading instructions needs a C compiler")
    end
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --emit asm compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    local asm = decoded.asm
    assert(asm.toolchain.version ~= "" and asm.toolchain.command ~= "", "the compiler that answered is named: " .. out)
    local flags = table.concat(asm.flags, " ")
    assert(flags:find("-O3", 1, true), "the flags are the ones an artifact is built with: " .. flags)

    local kernel = nil
    for _, listing in ipairs(asm.functions) do
        if listing.role == "kernel" then
            kernel = listing
        end
    end
    assert(kernel ~= nil, "the compiled body is in the report: " .. out)
    test.equal(kernel.symbol, "ks_escapes")
    test.equal(kernel.counts.total, #kernel.instructions)
    local vector = 0
    for _, one in ipairs(kernel.instructions) do
        for _, kind in ipairs(one.kinds or {}) do
            vector = vector + (kind == "vector" and 1 or 0)
        end
    end
    test.equal(kernel.counts.vector, vector, "every count is over the instructions it lists")
    if decoded.functions[1].outcome == "lowered" then
        assert(vector > 0, "a body that lowered has vector instructions to show for it: " .. out)
    end
end

-- A total with six zeroes beside it would read as a kernel that touches no
-- memory rather than as a question nothing answered.
function M.asmRefusesAnArchitectureWithNoInstructionRules()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--emit asm --target wasm32-unknown-emscripten --features simd128 compute.nupp")
    test.equal(code, 1, out)
    assert(out:find("wasm32", 1, true) and out:find("aarch64", 1, true), out)
end

function M.emitPrintsTheIrAndTheBinding()
    local dir = project{["compute.nupp"] = COMPUTE}
    local ir, irCode = run(dir, PINNED .. "--emit ir compute.nupp")
    test.equal(irCode, 0, ir)
    assert(ir:find("simd lanes(4)", 1, true), "the lane body is in the IR beside the scalar one: " .. ir)
    assert(ir:find("disjoint r0 r1", 1, true), "the alias matrix is in the IR: " .. ir)

    local binding, bindingCode = run(dir, "--emit binding compute.nupp")
    test.equal(bindingCode, 0, binding)
    assert(
        binding:find("layoutof(Escape)", 1, true),
        "the wrapper checks the struct layout rather than trusting it: " .. binding
    )
    assert(binding:find("unsafe do", 1, true), "the foreign call is the only unsafe part: " .. binding)
end

function M.narrowScalarSpansKeepTheirStorageAndUseLanes()
    local dir = project{["bytes.nupp"] = BYTE_CLASSIFIER}

    local ir, irCode = run(dir, PINNED .. "--check --emit ir bytes.nupp")
    test.equal(irCode, 0, ir)
    assert(
        ir:find("flags:u32 source(uint8)", 1, true),
        "the IR distinguishes storage from its established value: " .. ir
    )
    assert(ir:find("vspan:i32x8 bytes[i..i+7]", 1, true), "a byte load is widened into the gang: " .. ir)
    assert(ir:find("vset flags[i..i+7]", 1, true), "a scalar span store is scattered from the gang: " .. ir)

    local c, cCode = run(dir, PINNED .. "--emit c bytes.nupp")
    test.equal(cCode, 0, c)
    assert(c:find("uint8_t *restrict p_flags", 1, true), "the output pointer retains byte storage: " .. c)
    assert(c:find("const uint8_t *p_bytes", 1, true), "the input pointer retains const byte storage: " .. c)
    assert(c:find("p_flags[i + 7] = (uint8_t)lanes[7]", 1, true), "lane values narrow only when stored: " .. c)

    local binding, bindingCode = run(dir, "--emit binding bytes.nupp")
    test.equal(bindingCode, 0, binding)
    assert(binding:find("exclusive flags: uint8*", 1, true), binding)
    assert(binding:find("borrows bytes: const uint8*", 1, true), binding)
    assert(binding:find("span.WriteSpan<uint8>", 1, true), binding)
end

local ONE_PUBLISH = [[
module publishing

local valuebuilder = require("nupp.data.valuebuilder")

local publishing = {}

local function u32(value: integer): uint32
    return nupp.math.u32.wrap(value)
end

@aot(lanes = false)
local function once(source: string, nullValue: any): any
    local builder = valuebuilder.newSized(nullValue, u32(2), u32(16))
    local scratch = valuebuilder.newByteScratch(u32(16))
    valuebuilder.setScratchByte(scratch, u32(0), valuebuilder.byte(source, u32(0)))
    valuebuilder.stringScratch(builder, scratch, u32(0), u32(1))
    return valuebuilder.finish(builder)
end

@aot(lanes = false)
local function twice(source: string, nullValue: any): any
    local builder = valuebuilder.newSized(nullValue, u32(4), u32(16))
    local scratch = valuebuilder.newByteScratch(u32(16))
    valuebuilder.openArray(builder, u32(2))
    valuebuilder.setScratchByte(scratch, u32(0), valuebuilder.byte(source, u32(0)))
    valuebuilder.stringScratch(builder, scratch, u32(0), u32(1))
    valuebuilder.resetByteScratch(scratch)
    valuebuilder.setScratchByte(scratch, u32(0), valuebuilder.byte(source, u32(1)))
    valuebuilder.stringScratch(builder, scratch, u32(0), u32(1))
    valuebuilder.close(builder)
    return valuebuilder.finish(builder)
end

--- @export
function publishing.once(value: string): any
    return once(value, false)
end

--- @export
function publishing.twice(value: string): any
    return twice(value, false)
end

export = publishing
]]

--- A reused byte scratch is offered back to its cache at the publish, so it is
--- only safe where nothing writes the buffer afterwards. The emitter decides
--- that per entry, and getting it wrong hands a live buffer to a second
--- caller, so both answers are pinned here rather than only the interesting
--- one.
function M.onlySinglePublishEntriesReuseAByteScratch()
    local dir = project{["publishing.nupp"] = ONE_PUBLISH}

    local ir, irCode = run(dir, "--emit ir publishing.nupp")
    test.equal(irCode, 0, ir)
    local once = ir:match("function once.-\nfunction ") or ir:match("function once.*")
    local twice = ir:match("function twice.-\nfunction ") or ir:match("function twice.*")
    assert(
        once ~= nil and once:find("reuses scratch", 1, true),
        "an entry that publishes once and returns proves its scratch reusable: " .. tostring(once)
    )
    assert(
        twice ~= nil and not twice:find("reuses scratch", 1, true),
        "an entry that publishes and then fills again proves nothing: " .. tostring(twice)
    )

    -- And that the emitter acts on the proof rather than deciding again.
    local c, code = run(dir, "--emit c publishing.nupp")
    test.equal(code, 0, c)
    local _, cached = c:gsub("ks_lua_scratch_u8_cached%(L,", "")
    local _, plain = c:gsub("= ks_lua_scratch_u8%(L,", "")
    test.equal(cached, 1, "one entry takes the cached buffer: " .. c)
    test.equal(plain, 1, "the other allocates its own: " .. c)
end

function M.blockKernelsAppendUnderDominatingCapacityChecks()
    local dir = project{["delimiters.nupp"] = DELIMITERS}
    local c, code = run(dir, "--emit c delimiters.nupp")
    test.equal(code, 0, c)
    assert(c:find("uint32_t ks_delimiters(", 1, true), "the scalar result crosses the native ABI: " .. c)
    assert(c:find("size_t count_source, size_t count_offsets", 1, true), "the two spans keep independent counts: " .. c)
    assert(c:find("p_offsets[((size_t)v", 1, true), "the proved zero-based cursor directly indexes the output: " .. c)

    local ir = select(1, run(dir, "--emit ir delimiters.nupp"))
    assert(ir:find("store offsets[written+1]", 1, true), "inspection preserves the checked append relationship: " .. ir)
end

-- `u32.wrap` takes an `integer`, and a counted-loop index is one. The backend
-- carries that index as an `i32`, so reaching the conversion means promoting it
-- to the binary64 the conversion is admitted over -- exact for every 32-bit
-- integer, and establishing nothing that the conversion does not establish
-- itself. Without the promotion the one spelling that type-checks was refused
-- here, and the spellings that were not refused here did not type-check.
function M.aCountedLoopIndexReachesAnEntryConversion()
    local dir = project{
        [
            "positions.nupp"
        ] = replaceOnce(DELIMITERS, "offsets[written + 1] = written", "offsets[written + 1] = nupp.math.u32.wrap(i)")
    }
    local ir, code = run(dir, "--emit ir positions.nupp")
    test.equal(code, 0, ir)
    assert(
        ir:find("store offsets[written+1] = numeric_cast(int_to_f64(local:i32 i))", 1, true),
        "the promotion is written into the IR rather than left to the emitter: " .. ir
    )

    -- And the emitter collapses it, because a widen immediately narrowed back
    -- to the width it came from is the value. The reduction the conversion
    -- otherwise carries -- `wrap` is modular, and a C cast is not -- has
    -- nothing to reduce here, so paying for it would be undoing the promotion's
    -- own work.
    local c = select(1, run(dir, "--emit c positions.nupp"))
    assert(c:find("((uint32_t)v", 1, true), "and the C narrows the index directly: " .. c)
    assert(not c:find("((uint32_t)((double)v", 1, true), "without a round trip through binary64: " .. c)
    assert(not c:find("nupp_wrap_u32(((double)v", 1, true), "and without reducing what cannot need it: " .. c)
end

-- Narrowing is the direction that would invent establishment the source never
-- performed, and it stays refused.
function M.anUnestablishedOperandIsStillRefused()
    local dir = project{
        [
            "scale.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(lanes = false)
local function scale(borrows input: span.Span<float>, exclusive out: span.WriteSpan<float>, k: number): nil
    for i = 1, #input do
        out[i] = nupp.math.f32.mul(input[i], k)
    end
end

return {scale = scale}
]]
    }
    local out, code = run(dir, "scale.nupp")
    test.equal(code, 1, out)
    assert(
        out:find("number is not established as float", 1, true),
        "and the checker says so before the backend has to: " .. out
    )
end

function M.blockKernelsRejectAnUnguardedAppendCursor()
    local source = DELIMITERS:gsub("            if written < #offsets then\n", "            if true then\n")
    local dir = project{["unguarded.nupp"] = source}
    local out, code = run(dir, "unguarded.nupp")
    test.equal(code, 1, out)
    assert(out:find("cursor + 1 under cursor < #span", 1, true), out)
end

function M.whileBoundsStopAuthorizingAChangedCursor()
    local dir = project{["changed.nupp"] = MUTATED_WHILE_CURSOR}
    local out, code = run(dir, "changed.nupp")
    test.equal(code, 1, out)
    assert(out:find("cursor + 1 under cursor < #span", 1, true), out)
end

function M.scopedSimdSelectsOnePackedRegisterForTheTargetTier()
    local dir = project{["simd.nupp"] = SCOPED_SIMD}
    local baseline, baselineCode = run(dir, "--target x86_64-unknown-linux-gnu --emit c simd.nupp")
    test.equal(baselineCode, 0, baseline)
    assert(baseline:find("vector_size(16)", 1, true), baseline)
    assert(baseline:find("ks_load_u8x16", 1, true), baseline)

    local avx, avxCode = run(dir, "--target x86_64-unknown-linux-gnu --features avx2 --emit c simd.nupp")
    test.equal(avxCode, 0, avx)
    assert(avx:find("vector_size(32)", 1, true), avx)
    assert(avx:find("ks_bits_u8x32", 1, true), avx)

    local neon, neonCode = run(dir, "--target aarch64-unknown-linux-gnu --emit ir simd.nupp")
    test.equal(neonCode, 0, neon)
    assert(neon:find("simd species(uint8,16)", 1, true), neon)
    assert(neon:find("simd_load_u8", 1, true) and neon:find("simd_count", 1, true), neon)
end

function M.rootedStringSimdLoadsRequireAnEntryParameter()
    local dir = project{
        [
            "local-string.g.nupp"
        ] = [[
local simd = require("nupp.simd")

@aot(lanes = false)
local function quotes(source: string): uint32
    local rooted = "not the parameter"
    local species = simd.preferredU8()
    return species:loadString(rooted, nupp.math.u32.wrap(0)):equal(34):count()
end

return {quotes = quotes}
]]
    }
    local out, code = run(dir, "local-string.g.nupp")
    test.equal(code, 1, out)
    assert(out:find("rooted string parameter", 1, true), out)
end

function M.fixedWidthSwitchesEmitNativeCDispatch()
    local source = [[
local span = require("nupp.mem.span")

local struct Signed
    value: int32
end

local struct Unsigned
    value: uint32
end

@aot
local function signed(
    exclusive output: span.WriteSpan<Signed>,
    borrows input: span.Span<Signed>
): nil
    if #output ~= #input then
        error("length mismatch", 2)
    end
    for i = 1, #output do
        local value = input[i].value
        local result: int32 = switch value do
            case -2147483648 -> 1
            case 1, 2 -> 2
            else -> 0
        end
        output[i].value = result
    end
end

@aot
local function unsigned(
    exclusive output: span.WriteSpan<Unsigned>,
    borrows input: span.Span<Unsigned>
): nil
    if #output ~= #input then
        error("length mismatch", 2)
    end
    for i = 1, #output do
        local value = input[i].value
        local result: uint32 = switch value do
            case 0 -> 1
            case 4294967295 -> 2
            else -> 0
        end
        output[i].value = result
    end
end

return {signed = signed, unsigned = unsigned, Signed = Signed, Unsigned = Unsigned}
]]
    local dir = project{["switch.nupp"] = source}
    local out, code = run(dir, "--emit c switch.nupp")
    test.equal(code, 0, out)
    local first = assert(out:find("switch (", 1, true), out)
    assert(out:find("switch (", first + 1, true), "both exact-width selectors use native switch: " .. out)
    assert(
        out:find("case (-INT32_C(2147483647) - INT32_C(1)):", 1, true),
        "int32 minimum has an exact C spelling: " .. out
    )
    assert(
        out:find("case INT32_C(1):", 1, true) and out:find("case INT32_C(2):", 1, true),
        "grouped labels remain separate C labels: " .. out
    )
    assert(out:find("case INT32_C(2):\n        {", 1, true), "native switch arms scope conversion temporaries: " .. out)
    assert(out:find("case UINT32_C(4294967295):", 1, true), "uint32 maximum has an exact C spelling: " .. out)
end

function M.binary64SwitchesKeepComparisonBranches()
    local dir = project{
        [
            "switch.nupp"
        ] = [[
local span = require("nupp.mem.span")

local struct Value
    value: int32
end

@aot
local function classify(
    exclusive output: span.WriteSpan<Value>,
    borrows input: span.Span<Value>,
    selector: number
): nil
    if #output ~= #input then
        error("length mismatch", 2)
    end
    for i = 1, #output do
        local ignored = input[i].value
        local result: int32 = switch selector do
            case 1 -> 1.0
            case 2 -> 2.0
            else -> 0.0
        end
        output[i].value = result + ignored
    end
end
return {classify = classify, Value = Value}
]]
    }
    local out, code = run(dir, "--emit c switch.nupp")
    test.equal(code, 0, out)
    test.equal(out:find("switch (", 1, true), nil, "binary64 is not converted for native switch")
    assert(out:find("if (", 1, true), out)
end

function M.jsonCarriesTheOutcomeAndTheEstimate()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "--json compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.file, "compute.nupp")
    -- One entry per `@aot` function in the file, in source order.
    test.equal(#decoded.functions, 1)

    local only = decoded.functions[1]
    test.equal(only.name, "escapes")
    test.equal(only.symbol, "ks_escapes")
    test.equal(only.outcome, "lowered")
    test.equal(only.lanes.shape, "mixed4")
    test.equal(only.lanes.lanes, 4)
    test.equal(#only.loops, 1)
    test.equal(only.loops[1].kind, "map")
    test.equal(only.loops[1].outcome, "lowered")
    assert(only.loops[1].nodes > 0)
    assert(only.intensity.perByte > 1.0, "the estimate is above the threshold it was judged by")
    test.equal(#only.refusals, 0, "a lowered loop has nothing to explain")
    assert(decoded.ir and decoded.c and decoded.binding, "all three artifacts are carried")
end

function M.jsonNamesWhatRefusedTheLoop()
    local dir = project{["refused.nupp"] = REFUSED}
    local out, code = run(dir, "--json --check refused.nupp")
    test.equal(code, 1, out)
    local decoded = require("testjson").decode(out:match("^(%b{})"))
    local only = decoded.functions[1]
    test.equal(only.outcome, "refused")
    test.equal(only.loops[1].outcome, "refused")
    test.equal(only.lanes, nil, "there is no gang to report")
    assert(#only.refusals >= 1, "the refusal is data, not only a message")
    assert(
        only.refusals[1].message:find("nested numeric loop", 1, true),
        "and it names the construct: " .. only.refusals[1].message
    )
    assert(only.refusals[1].line > 0, "at a position")
end

-- Two functions over one struct, landing on different gangs: `scale` is
-- ordinary binary64 and takes four lanes, `brighten` is written through
-- `nupp.math.f32` and takes eight. One file used to hold exactly one function,
-- and two gangs in one file is where the shared prelude has to not collide.
local TWO = [[
local span = require("nupp.mem.span")

local struct Sample
    value: float
    weight: float
end

@aot(lanes = true)
local function scale(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    factor: number
): nil
    if #samples ~= #source then
        error("length mismatch", 2)
    end
    if first < 1 or last > #samples or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples[i]
        local input = source[i]
        sample.value = input.value * factor + input.weight
        sample.weight = input.weight * factor
    end
end

@aot(lanes = true)
local function brighten(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    lift: float
): nil
    if #samples ~= #source then
        error("length mismatch", 2)
    end
    if first < 1 or last > #samples or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples[i]
        local input = source[i]
        local value = nupp.math.f32.narrow(input.value)
        local weight = nupp.math.f32.narrow(input.weight)
        sample.value = nupp.math.f32.add(value, lift)
        sample.weight = nupp.math.f32.mul(weight, lift)
    end
end

return {scale = scale, brighten = brighten, Sample = Sample,}
]]

function M.everyAotFunctionInAFileIsCompiled()
    local dir = project{["two.nupp"] = TWO}
    local out, code = run(dir, PINNED .. "--json two.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(#decoded.functions, 2, "both functions are reported")
    test.equal(decoded.functions[1].name, "scale", "in source order")
    test.equal(decoded.functions[2].name, "brighten")
    test.equal(decoded.functions[1].lanes.shape, "mixed4", "ordinary arithmetic takes four lanes")
    test.equal(decoded.functions[2].lanes.shape, "f32x8", "explicit binary32 takes eight")

    -- One struct declared once, both gangs present, and each function bringing
    -- its own pair of bodies.
    local _, ccode = run(dir, PINNED .. "--emit c two.nupp")
    test.equal(ccode, 0)
    local c = select(1, run(dir, PINNED .. "--emit c two.nupp"))
    test.equal(select(2, c:gsub("} KsSample;", "")), 1, "the shared struct is declared once")
    assert(
        c:find("ks_any_m64x4", 1, true) and c:find("ks_any_m32x8", 1, true),
        "each gang brings its own mask helpers, named so they cannot collide"
    )
    test.equal(
        select(2, c:gsub("float nupp_f32_nan", "")),
        1,
        "the helpers no gang owns appear once however many gangs the file uses"
    )
    for _, symbol in ipairs({"ks_scale", "ks_scale_forced_scalar", "ks_brighten", "ks_brighten_forced_scalar"}) do
        assert(c:find("void " .. symbol .. "(", 1, true), symbol .. " is defined")
    end

    local binding = select(1, run(dir, PINNED .. "--emit binding two.nupp"))
    assert(
        binding:find("scale = scale", 1, true) and binding:find("brighten = brighten", 1, true),
        "the generated module exports both wrappers: " .. binding:sub(-200)
    )
end

-- A gang is 16, 32, or 64 bytes. The tier decides which fit: those are one SSE2,
-- AVX, or AVX-512 register. The tier is selected rather than measured, because a
-- build that probed the machine in front of it would produce an artifact that
-- only runs there.
function M.theBaselineX86TierGetsTheNarrowGang()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu compute.nupp")
    test.equal(code, 0, "plain x86-64 vectorises rather than refusing\n" .. out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.tier, "baseline", "and did not quietly promise instructions nobody asked for")
    test.equal(decoded.functions[1].lanes.shape, "mixed2")
    test.equal(
        decoded.functions[1].lanes.lanes,
        2,
        "half the lanes of AVX, which is the point: a smaller win, not no win"
    )

    local checkOut, checkCode = run(dir, "--check --target x86_64-unknown-linux-gnu compute.nupp")
    test.equal(checkCode, 0, "and --check agrees it lowered\n" .. checkOut)
end

function M.aWiderTierGetsTheWiderGang()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx2 compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.triple, "x86_64-unknown-linux-gnu")
    test.equal(decoded.target.tier, "avx2", "the tier is reported, because it changed the answer")
    test.equal(decoded.functions[1].lanes.shape, "mixed4")
    test.equal(decoded.functions[1].lanes.lanes, 4)
end

function M.theAvx512TierGetsEightMixedLanes()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx512f compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.tier, "avx512f")
    test.equal(decoded.functions[1].lanes.shape, "mixed8")
    test.equal(decoded.functions[1].lanes.lanes, 8)
    assert(
        decoded.c:find("ks_f64x8", 1, true) and decoded.c:find("ks_m64x8", 1, true),
        "the eight-lane gang carries binary64 values and masks at 64 bytes"
    )
end

function M.anAll32BitLoopDoesNotTakeTheWiderTie()
    local dir = project{["classify.nupp"] = BYTE_CLASSIFIER}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx512f classify.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(
        decoded.functions[1].lanes.shape,
        "f32x8",
        "eight lanes in 32 bytes win over mixed8 when no binary64 value needs it"
    )
    test.equal(decoded.c:find("ks_f64x8", 1, true), nil, "the narrower tie does not emit an unused 64-byte vector")
end

function M.theWidestGangThatFitsWins()
    -- Both widths are available at avx2, so the choice has to be the wider one.
    -- Preference used to come from the order the shapes were listed in, which
    -- would have picked four narrow lanes over four wide ones here.
    local dir = project{["compute.nupp"] = COMPUTE}
    local out = select(1, run(dir, "--json --target x86_64-unknown-linux-gnu --features avx2 compute.nupp"))
    local decoded = require("testjson").decode(out)
    test.equal(decoded.functions[1].lanes.shape, "mixed4", "not mixed2, which also fits and holds half as much")
end

function M.armHasOneTierAndNeedsNoSelection()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target aarch64-apple-darwin compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.tier, "neon", "its 16-byte registers are mandatory, so there is nothing to opt into")
    test.equal(decoded.functions[1].lanes.shape, "mixed4")
end

function M.anUnknownTargetOrTierIsRejected()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--target sparc-sun-solaris compute.nupp")
    test.equal(code, 1, out)
    assert(out:find("unknown target", 1, true), out)

    local tierOut, tierCode = run(dir, "--target aarch64-apple-darwin --features sse9 compute.nupp")
    test.equal(tierCode, 1, tierOut)
    assert(tierOut:find("has no feature tier sse9", 1, true), "and names the tiers it does have: " .. tierOut)
end

function M.aCountedLoopRefusesAValueOnlyTheVmCanHold()
    -- The other half of the rule the test below states. A block body that reaches a
    -- Lua value becomes a builder; a counted native loop runs per element with no VM
    -- to allocate against and cannot become one, so the value is refused where it is
    -- written.
    --
    -- It used to lower instead. Nothing refused it, the entry mode stayed `kernel`
    -- because this shape hardcodes it, and the IR verifier then raised `Lua
    -- allocation outside a builder` -- reached from `nupp aot` on ordinary source,
    -- so an uncaught error carrying no file and no line was what a mistyped local
    -- got you.
    local dir = project{
        [
            "loop.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function scale(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    assert(#out == #input, "length mismatch")
    for i = 1, #out do
        local scratch = {1.0}
        out[i] = input[i] * 2.0
    end
end

return {scale = scale}
]]
    }
    local out, code = run(dir, "loop.nupp")
    test.equal(code, 1, out)
    assert(out:find("not admitted in a counted native loop", 1, true), out)
    -- On the allocation, not on the loop that contains it.
    assert(out:find("loop.nupp:7:25:", 1, true), "the refusal names the allocation: " .. out)
end

function M.luaBuildersReportAndEmitTheirSeparateVmAbi()
    local dir = project{
        [
            "builder.nupp"
        ] = [[
@aot
local function object(name: string): {[string]: any}
    local result = {name = name, values = {1, 2, 3}}
    result["ready"] = true
    return result
end

return {object = object}
]]
    }
    local out, code = run(dir, "--json builder.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    local only = decoded.functions[1]
    test.equal(only.entryMode, "lua-builder")
    test.equal(only.runtimeAbi, "lua-5.1")
    assert(only.registrar:match("^ks_register_[0-9a-f]+$"), only.registrar)
    assert(decoded.ir:find("entry lua-builder", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.new_table", 1, true), decoded.ir)
    assert(decoded.c:find("static int ks_object_lua(lua_State *L)", 1, true), decoded.c)
    assert(decoded.c:find("lua_rawset(L", 1, true), decoded.c)
    assert(decoded.binding:find("package", 1, true) and decoded.binding:find(only.registrar, 1, true), decoded.binding)
end

function M.ordinaryLuaConstructionLowersThroughVmAwareIr()
    local dir = project{
        [
            "ordinary.nupp"
        ] = [[
@aot(lanes = false)
local function label(text: string): string
    local offsets: {integer} = {}
    offsets[1] = #text
    local answer = string.sub(text, 1, offsets[1])
    answer = answer .. "!"
    return answer
end

return {label = label}
]],
    }
    local out, code = run(dir, "--json ordinary.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.functions[1].entryMode, "lua-builder")
    for _, operation in ipairs({
        "lua.new_table",
        "lua.get_index",
        "lua.substring",
        "lua.string_buffer",
        "lua.string_buffer_append",
        "lua.string_buffer_finish",
    }) do
        assert(decoded.ir:find(operation, 1, true), operation .. " is absent from:\n" .. decoded.ir)
    end
    assert(decoded.c:find("lua_rawgeti", 1, true), decoded.c)
    assert(decoded.c:find("luaL_addlstring", 1, true), decoded.c)
end

function M.aStringAccumulatorKeepsTheVmStackAboveItsChunksTemporary()
    local dir = project{
        [
            "unsafe.nupp"
        ] = [[
@aot(lanes = false)
local function unsafe(text: string): string
    local answer = ""
    answer = answer .. text
    local retained = {1}
    retained[1] = 2
    return answer
end

return {unsafe = unsafe}
]],
    }
    local out, code = run(dir, "unsafe.nupp")
    test.equal(code, 1, out)
    assert(out:find("a persistent Lua root follows a string accumulator", 1, true), out)
end

function M.valueTreesLowerToOneCheckedVmConstructionOperation()
    local dir = project{
        [
            "nupp/data/valuebuilder.nupp"
        ] = [[
local builder = {}
function builder.materializeTree(nodes: string, links: string, source: string, root: integer, nullValue: any): any
    return nullValue
end
return builder
]],
        [
            "tree.g.nupp"
        ] = [[
local builder = require("nupp.data.valuebuilder")
@aot
local function materialize(nodes: string, links: string, source: string, root: integer, nullValue: any): any
    return builder.materializeTree(nodes, links, source, root, nullValue)
end
return {materialize = materialize}
]],
    }
    local out, code = run(dir, "--json tree.g.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    local only = decoded.functions[1]
    test.equal(only.entryMode, "lua-builder")
    assert(decoded.ir:find("lua.tree(", 1, true), decoded.ir)
    assert(decoded.c:find("ks_lua_tree_push", 1, true), decoded.c)
    assert(decoded.c:find("luaL_checklstring", 1, true), decoded.c)
end

function M.valueStreamsFuseRootedByteReadsAndLuaConstruction()
    local dir = project{
        [
            "nupp/data/valuebuilder.nupp"
        ] = [[
local builder = {}
function builder.new(nullValue: any): any return {} end
function builder.newSized(nullValue: any, depth: uint32, bytes: uint32): any return {} end
function builder.byte(bytes: string, offset: uint32): uint32 return offset end
function builder.byteAt(bytes: string, offset: uint32): uint32 return offset end
function builder.word(bytes: string, index: uint32): uint32 return index end
function builder.newWordScratch(capacity: uint32): any return {} end
function builder.scratchWord(scratch: any, index: uint32): uint32 return index end
function builder.setScratchWord(scratch: any, index: uint32, value: uint32): nil end
function builder.appendSetBits(scratch: any, index: uint32, base: uint32, bits: any): uint32 return index end
function builder.appendStringBits(scratch: any, index: uint32, base: uint32, events: any, quotes: any, slashes: any, inString: boolean, stringEscaped: boolean): uint32 return index end
function builder.newByteScratch(capacity: uint32): any return {} end
function builder.scratchByte(scratch: any, index: uint32): uint32 return index end
function builder.setScratchByte(scratch: any, index: uint32, value: uint32): nil end
function builder.resetByteScratch(scratch: any): nil end
function builder.length(bytes: string): uint32 return nupp.math.u32.wrap(#bytes) end
function builder.depth(state: any): uint32 return nupp.math.u32.wrap(0) end
function builder.kind(state: any): uint32 return nupp.math.u32.wrap(0) end
function builder.count(state: any): uint32 return nupp.math.u32.wrap(0) end
function builder.state(state: any): uint32 return nupp.math.u32.wrap(0) end
function builder.openArray(state: any, capacity: uint32): nil end
function builder.openObject(state: any, capacity: uint32): nil end
function builder.key(state: any, source: string, start: uint32, length: uint32, escaped: boolean): nil end
function builder.string(state: any, source: string, start: uint32, length: uint32, escaped: boolean): nil end
function builder.stringScratch(state: any, scratch: any, start: uint32, length: uint32): nil end
function builder.keyScratch(state: any, scratch: any, start: uint32, length: uint32): nil end
function builder.number(state: any, value: number): nil end
function builder.numberSlice(state: any, source: string, start: uint32, length: uint32): nil end
function builder.integerSlice(state: any, source: string, start: uint32, length: uint32): nil end
function builder.integer64(state: any, magnitude: uint64, negative: boolean): nil end
function builder.decimal64(state: any, source: string, start: uint32, length: uint32, magnitude: uint64, exponent: int32, negative: boolean, exact: boolean): nil end
function builder.boolean(state: any, value: boolean): nil end
function builder.null(state: any): nil end
function builder.close(state: any): nil end
function builder.finish(state: any): any return nil end
return builder
]],
        [
            "stream.g.nupp"
        ] = [[
local builder = require("nupp.data.valuebuilder")
local simd = require("nupp.simd")
local function drain(bits: simd.MaskBits64): (uint32, uint32)
    return bits:firstSet(), bits:clearFirst():count()
end
@aot(lanes = false)
local function decode(source: string, tape: string, nullValue: any): (any, uint32, uint32)
    local count = builder.length(source)
    local cursor: uint32 = 0
    local direct: uint32 = 0
    if cursor < count then
        direct = builder.byteAt(source, cursor)
    end
    local state = builder.newSized(nullValue, count, count)
    local packedState = builder.state(state)
    local scratch = builder.newWordScratch(count)
    local byteScratch = builder.newByteScratch(count)
    local view = simd.paddedStringU8(source)
    local lookup = simd.tableU8x16(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
    local block = view:loadBlock64(nupp.math.u32.wrap(0))
    local blockQuotes = block:equal(34):count()
    local blockLow = block:andByte(nupp.math.u32.wrap(15)):lookup16(lookup)
    local blockHigh = block:shiftRight(nupp.math.u32.wrap(4)):lookup16(lookup)
    local blockClasses = blockLow:andBits(blockHigh):anyBitsSet(nupp.math.u32.wrap(7)):count()
    local bytes = view:loadFull(nupp.math.u32.wrap(0))
    local previous = view:loadTail()
    local blockLast = block:lastVector():equal(0):count()
    local blockUtf8 = block:utf8Errors(previous, lookup, lookup, lookup):count()
    local aligned = simd.alignBytes(previous, bytes, nupp.math.u32.wrap(1))
    local classified = aligned:lookup16(lookup)
    local quotes = bytes:equal(34):count()
    local classes = classified:equal(1):count()
    local shifted = nupp.math.u32.shiftLeft(nupp.math.u32.wrap(1), nupp.math.u32.wrap(3))
    local rawWide = simd.maskBits64(shifted, nupp.math.u32.wrap(1))
    local wide = rawWide:prefixXor(false)
    local first, left = drain(wide)
    local next = builder.appendSetBits(scratch, nupp.math.u32.wrap(0), view.fullLength, wide)
    local stringNext = builder.appendStringBits(
        scratch,
        nupp.math.u32.wrap(0),
        view.fullLength,
        rawWide,
        rawWide,
        rawWide,
        false,
        false
    )
    builder.setScratchByte(byteScratch, nupp.math.u32.wrap(0), nupp.math.u32.wrap(65))
    builder.openObject(state, nupp.math.u32.wrap(1))
    builder.key(state, source, nupp.math.u32.wrap(0), count, false)
    builder.openArray(state, nupp.math.u32.wrap(2))
    builder.stringScratch(state, byteScratch, nupp.math.u32.wrap(0), nupp.math.u32.wrap(1))
    builder.number(state, 1)
    builder.numberSlice(state, source, nupp.math.u32.wrap(0), count)
    builder.integerSlice(state, source, nupp.math.u32.wrap(0), count)
    local magnitude: uint64 = count as uint64
    magnitude = magnitude * (10 as uint64) + (1 as uint64)
    builder.integer64(state, magnitude, false)
    builder.decimal64(state, source, nupp.math.u32.wrap(0), count, magnitude, nupp.math.i32.wrap(-1), false, true)
    builder.close(state)
    builder.close(state)
    return builder.finish(state), builder.byte(source, nupp.math.u32.wrap(0)), nupp.math.u32.add(
        builder.scratchWord(scratch, nupp.math.u32.wrap(0)),
        nupp.math.u32.add(blockUtf8, nupp.math.u32.add(blockLast, nupp.math.u32.add(blockClasses, nupp.math.u32.add(blockQuotes, nupp.math.u32.add(direct, nupp.math.u32.add(packedState, nupp.math.u32.add(quotes, nupp.math.u32.add(classes, nupp.math.u32.add(first, nupp.math.u32.add(left, nupp.math.u32.add(next, nupp.math.u32.add(stringNext, view.tailLength))))))))))))
    )
end
return {decode = decode}
]],
    }
    local out, code = run(dir, "--json stream.g.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    assert(decoded.ir:find("lua_builder_open_object", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_string_byte", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.builder_finish", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_builder_state", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_string_byte_at", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_block64_load_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_block64_lookup16_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_block64_any_bits_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_block64_last_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_block64_utf8_errors_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.scratch_u32", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_padded_load_full_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_lookup16_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_align_bytes_u8", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.scratch_u32_append_bits", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.scratch_u32_append_string_bits", 1, true), decoded.ir)
    assert(decoded.ir:find("u64_mul", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_builder_integer64", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_builder_decimal64", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_mask64:simd_mask_bits64(constant:u32 8", 1, true), decoded.ir)
    test.equal(decoded.ir:find("u32_shl", 1, true), nil, "constant shifts fold before emission")
    assert(decoded.c:find("KsLuaBuilder", 1, true), decoded.c)
    assert(decoded.c:find("ks_lookup16_u8x", 1, true), decoded.c)
    assert(decoded.c:find("ks_lua_scratch_u32_append_bits", 1, true), decoded.c)
    assert(decoded.c:find("ks_lua_scratch_u32_append_string_bits", 1, true), decoded.c)
    assert(decoded.c:find("uint32_t inline_words[32]", 1, true), decoded.c)
    assert(decoded.c:find("lua_rawget(L, -10000)", 1, true), decoded.c)
    assert(decoded.c:find("static const char", 1, true), decoded.c)
    assert(decoded.c:find("KsLuaScratchU32", 1, true), decoded.c)
    assert(decoded.c:find("KsLuaScratchU8", 1, true), decoded.c)
    assert(decoded.c:find("KsMaskBits64", 1, true), decoded.c)
    assert(decoded.c:find("ks_block64_eq_u8x", 1, true), decoded.c)
    assert(decoded.c:find("ks_block64_lookup16_u8x", 1, true), decoded.c)
    assert(decoded.c:find("ks_block64_utf8_errors_u8x", 1, true), decoded.c)
    assert(decoded.c:find("_helper_drain_result", 1, true), decoded.c)
    assert(decoded.c:find("ks_bytes_1", 1, true), decoded.c)
    assert(decoded.c:find("ks_lua_builder_number_slice", 1, true), decoded.c)
    assert(decoded.c:find("ks_lua_builder_integer64", 1, true), decoded.c)
    assert(decoded.c:find("ks_lua_builder_decimal64", 1, true), decoded.c)
    assert(decoded.c:find("ks_lua_builder_escaped_string", 1, true), decoded.c)
    assert(decoded.c:find("always_inline", 1, true), decoded.c)
    assert(decoded.binding:find("nupp.math.u32.wrap", 1, true), decoded.binding)
end

function M.valueStreamBuilderModesAreAotConstants()
    local dir = project{
        [
            "nupp/data/valuebuilder.nupp"
        ] = [[
local builder = {}
function builder.newSized(nullValue: any, depth: uint32, bytes: uint32): any return {} end
function builder.newPull(nullValue: any, depth: uint32, bytes: uint32, arrayMarker: any, objectMarker: any, shape: any, arrayShape: any, markers: any): any return {} end
function builder.newSerde(nullValue: any, depth: uint32, bytes: uint32, arrayMarker: any, objectMarker: any, shape: any, arrayShape: any, markers: any): any return {} end
function builder.number(state: any, value: number): nil end
function builder.finish(state: any): any return nil end
return builder
]],
        [
            "modes.nupp"
        ] = [[
local builder = require("nupp.data.valuebuilder")

@aot
local function eager(nullValue: any): any
    local state = builder.newSized(nullValue, nupp.math.u32.wrap(1), nupp.math.u32.wrap(1))
    builder.number(state, 1)
    return builder.finish(state)
end

@aot
local function pull(nullValue: any, arrayMarker: any, objectMarker: any, shape: any, arrayShape: any, markers: any): any
    local state = builder.newPull(nullValue, nupp.math.u32.wrap(1), nupp.math.u32.wrap(1), arrayMarker, objectMarker, shape, arrayShape, markers)
    builder.number(state, 1)
    return builder.finish(state)
end

@aot
local function serde(nullValue: any, arrayMarker: any, objectMarker: any, shape: any, arrayShape: any, markers: any): any
    local state = builder.newSerde(nullValue, nupp.math.u32.wrap(1), nupp.math.u32.wrap(1), arrayMarker, objectMarker, shape, arrayShape, markers)
    builder.number(state, 1)
    return builder.finish(state)
end

return {
    eager = eager as function(unknown): unknown,
    pull = pull as function(unknown, unknown, unknown, unknown, unknown, unknown): unknown,
    serde = serde as function(unknown, unknown, unknown, unknown, unknown, unknown): unknown,
}
]],
    }
    local out, code = run(dir, "--json modes.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    assert(decoded.ir:find("lua.builder(eager", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.builder(pull", 1, true), decoded.ir)
    assert(decoded.ir:find("lua.builder(serde", 1, true), decoded.ir)
    assert(decoded.c:find("= ks_lua_eager_builder_new(L", 1, true), decoded.c)
    assert(decoded.c:find("= ks_lua_builder_new(L", 1, true), decoded.c)
    assert(decoded.functions[1].builderMode == "eager")
    assert(decoded.functions[2].builderMode == "pull")
    assert(decoded.functions[3].builderMode == "serde")
    for _, fn in ipairs(decoded.functions) do
        assert(fn.optimization.beforeNodes >= fn.optimization.afterNodes)
        assert(fn.optimization.specializedHelperCalls >= 0)
    end
end

function M.uncheckedRootedByteReadsAreRejected()
    local dir = project{
        [
            "nupp/data/valuebuilder.nupp"
        ] = [[
local builder = {}
function builder.byteAt(bytes: string, offset: uint32): uint32 return offset end
return builder
]],
        [
            "read.g.nupp"
        ] = [[
local builder = require("nupp.data.valuebuilder")
@aot(lanes = false)
local function read(source: string, offset: uint32): uint32
    return builder.byteAt(source, offset)
end
return {read = read}
]],
    }
    local out, code = run(dir, "read.g.nupp")
    test.equal(code, 1, out)
    assert(out:find("needs offset < length(bytes) to dominate the read", 1, true), out)
end

--- A `const` string placed in static data is the bytes the program reads, not the
--- source that spells them.
---
--- The checker's literal type carries the value rather than the spelling, so a
--- constant holding an escape is written out decoded and one holding a quote is
--- written out at all -- the reader used to rebuild the string by handing the
--- spelling back to Lua, and refused whatever would not go back through a
--- double-quoted literal.
function M.aConstantStringIsPlacedAsTheBytesItDenotes()
    local dir = project{
        [
            "classes.g.nupp"
        ] = [[
local valueBuilder = require("nupp.data.valuebuilder")

const CLASSES = "\1\2\34\92"
const QUOTED = 'a"b'

@aot(lanes = false)
local function entry(index: uint32, nullValue: any): any
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    valueBuilder.openArray(state, nupp.math.u32.wrap(2))
    valueBuilder.number(state, valueBuilder.byte(CLASSES, index) * 1.0)
    valueBuilder.number(state, valueBuilder.byte(QUOTED, index) * 1.0)
    valueBuilder.close(state)

    return valueBuilder.finish(state)
end

return {entry = entry}
]]
    }
    local out, code = run(dir, PINNED .. "--emit c classes.g.nupp")
    test.equal(code, 0, out)
    assert(
        out:find("ks_bytes_konst_0[] = {1,2,34,92}", 1, true),
        "an escaped constant is placed as the four bytes it denotes: " .. out
    )
    assert(
        out:find("ks_bytes_konst_1[] = {97,34,98}", 1, true),
        "and one holding a quote is placed rather than refused: " .. out
    )
end

function M.aFileWithNoAotFunctionIsAnError()
    local dir = project{["plain.nupp"] = "local m = {}\n\nreturn m\n"}
    local out, code = run(dir, "plain.nupp")
    test.equal(code, 1, out)
    assert(out:find("no @aot function", 1, true), "which says so: " .. out)
end

function M.aForBoundOutsideInt32IsRefusedRatherThanNarrowed()
    -- The generated loop counts in int32. A literal past that used to be
    -- narrowed into whatever the C cast made of it, so the loop ran a different
    -- number of times than the source said, or not at all.
    local dir = project{
        [
            "bigbound.nupp"
        ] = [[
@aot
local function acc(value: number): number
    local total = value
    for j = 1, 3000000000 do
        total = total + 1
    end
    return total
end

return {acc = acc}
]],
    }
    local out, code = run(dir, "bigbound.nupp")
    test.equal(code, 1, "a bound the counter cannot reach is refused\n" .. out)
    assert(
        out:find("bigbound.nupp:4:5: aot: native for bound 3000000000 is outside int32", 1, true),
        "the refusal names the bound in full at its line: " .. out
    )
end

return {rows = rows}
]]
    local dir = project{["nested.nupp"] = body:gsub("BOUND", "#weights"), ["literal.nupp"] = body:gsub("BOUND", "10"),}
    local out, code = run(dir, "--emit c nested.nupp")
    test.equal(code, 0, out)
    assert(out:find("count_weights", 1, true), "the nested loop counts the span it reads: " .. out)

    out, code = run(dir, "literal.nupp")
    test.equal(code, 1, "a literal bound proves nothing about the span\n" .. out)
    assert(
        out:find(
            "literal.nupp:15:25: aot: the loop's bound is not a span count, so nothing proves weights is that long",
            1,
            true
        ),
        "and the refusal says what would: " .. out
    )
end

@aot
local function negFixed(value: uint32): number
    return -value
end

return {neg = neg, negFixed = negFixed}
]],
    }
    local out, code = run(dir, "--emit c neg.nupp")
    test.equal(code, 0, out)
    assert(out:find("(-(((double)p_value)))", 1, true), "the operand is widened, then negated: " .. out)
end

return M
