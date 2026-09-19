-- `nupp aot`: what an `@aot` function compiles to, and the gang each `@simd`
-- loop in it runs in.
--
-- Driven through the real binary rather than the module, because the artifacts and
-- the exit status are the whole interface: a `@simd` loop that cannot run in
-- lanes is an exit status, so a test that could not read one would not be
-- testing it.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

--- The file set this project is, as one string, so two cases asking for the
--- same sources get the same answer rather than the same work twice.
local function projectKey(files)
    local names = {}
    for name in pairs(files) do
        names[#names + 1] = name
    end
    table.sort(names)
    local pieces = {}
    for _, name in ipairs(names) do
        pieces[#pieces + 1] = name .. "\0" .. files[name]
    end

    return table.concat(pieces, "\1")
end

-- One directory per distinct file set. `nupp aot` reports what a file compiles
-- to and writes nothing, so a project is an input rather than a place a case
-- leaves state: two cases that ask about the same sources are asking about the
-- same project, and building it twice bought nothing. A case that wants a
-- different project writes different sources, which is a different key.
local projects = {}

local function project(files)
    local key = projectKey(files)
    local existing = projects[key]
    if existing then
        return existing
    end

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
    projects[key] = dir

    return dir
end

-- Keep command status separate from stdout. `--emit spirv` writes arbitrary binary,
-- and a Windows text-mode pipe can translate it or treat Ctrl-Z as the end before a
-- sentinel appended to that same stream. The artifact is always read in binary mode;
-- failed commands still put their ordinary diagnostic in the same file.
local function runOnce(dir, argv)
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

-- What one command over one project answered, kept for whoever asks again.
-- `nupp aot` is a report over a file: the same project and the same arguments
-- are the same answer, and the invocation behind it is a compiler start and a
-- check of the standard library the file names.
local answers = {}

local function run(dir, argv)
    local key = dir .. "\0" .. argv
    local kept = answers[key]
    if not kept then
        local out, code = runOnce(dir, argv)
        kept = {out, code}
        answers[key] = kept
    end

    return kept[1], kept[2]
end

-- The NEON instructions of FILE, or nil where this machine cannot read them.
-- Compiling for a triple the machine is not needs a compiler that can target
-- it, which is Clang: GCC answers for the host whatever triple it was given,
-- and the host's instructions say nothing about the aarch64 ones a test
-- asserts on. An aarch64 host reads them with either.
local function neonAsm(dir, file)
    local chain = require("nupp.compiler.build.aot").toolchain()
    local host = require("nupp.compiler.aot.target").hostTriple()
    if chain == nil or (chain.dialect ~= "clang" and host ~= "aarch64-apple-darwin") then
        return nil
    end
    local asm, code = run(dir, "--target aarch64-apple-darwin --features neon --emit asm " .. file)
    test.equal(code, 0, asm)
    return asm
end

--- Every artifact one file lowers to, out of one command.
---
--- `--emit` prints one artifact and nothing else, so a case that wants two of
--- them used to start the compiler twice over the same file. `--json` without
--- `--emit` carries the IR, the C and the binding together, and the C in it is
--- byte for byte the C `--emit c` prints. The exit status comes back beside
--- them, which is what says every `@simd` loop got its lanes.
---
--- The command and the directory it ran in come back last, because a project is
--- now shared between the cases that ask about the same sources and a failure
--- has to say which report it is reading.
local function lowered(dir, argv)
    local out, code = run(dir, argv)
    local where = ("`nupp aot %s` in %s"):format(argv, dir)
    local body = out:match("^(%b{})")
    assert(body, where .. " did not answer JSON: " .. out)

    return require("testjson").decode(body), out, code, where
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
-- touches no memory. Marked `@simd`, so it runs in lanes or fails to compile.
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

    @simd
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

    local summary, summaryCode = run(dir, "gpu.nupp")
    test.equal(summaryCode, 0, summary)
    assert(
        summary:find(", gpu, one iteration per GPU invocation", 1, true),
        "a compiled GPU artifact is reported with its lowered shape: " .. summary
    )
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

function M.gpuRepeatKeepsItsTrailingTestAndBodyScope()
    local dir = project({
        [
            "gpu.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function shrink(
    exclusive output: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        local value = input[i]
        repeat
            local done = value <= 1
            if done then
                continue
            end
            value = nupp.math.u32.sub(value, 1)
        until done
        output[i] = value
    end
end

return {shrink = shrink}
]],
    })
    local module, moduleCode = run(dir, "--emit spirv gpu.nupp")
    test.equal(moduleCode, 0, module)
    assertSpirvStructure(module)

    local shader, shaderCode = run(dir, "--emit wgsl --target wasm32-unknown-emscripten gpu.nupp")
    test.equal(shaderCode, 0, shader)
    assert(shader:find("continuing {", 1, true), "WGSL repeat has a continuing block\n" .. shader)
    assert(shader:find("break if ", 1, true), "WGSL repeat evaluates its trailing condition\n" .. shader)
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
    assert(binding:find("local artifacts = new gpuImplementation_ks_xor_mask.ArtifactSet", 1, true), binding)
    assert(binding:find("wgsl = \"struct NuppUniforms", 1, true), binding)
    assert(binding:find("compileGenerated(context, artifacts, 1, 1", 1, true), binding)

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
    assert(summary:find(", scalar", 1, true), "the summary says the body runs scalar: " .. summary)
    assert(not summary:find("lanes", 1, true), "and does not invent a lane decision for it: " .. summary)
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

    local decoded, raw, code, where = lowered(dir, "--json native-exp.nupp")
    test.equal(code, 0, raw)
    assert(decoded.c:find("expf(", 1, true), where .. ": the CPU body calls the native exponential: " .. decoded.c)
    assert(
        decoded.ir:find("contract fp-transcendentals(native)", 1, true),
        where .. ": and the IR records the contract that granted it: " .. decoded.ir
    )
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
    assert(c:find("(uint64_t)v1_cursor < (uint64_t)count)", 1, true), c)
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
    assert(binding:find("bindKernel(self._context, self._kernel, input.count)", 1, true), binding)
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
-- and add each. Not marked, so it compiles scalar and nothing has to decide that.
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

local REQUIRED_CONTIGUOUS = CONTIGUOUS_STREAMING:gsub(
    "    for index = first, last do",
    "    @simd\n    for index = first, last do",
    1
)

local REQUIRED_REGIONS = [[
local span = require("nupp.mem.span")

@aot
local function process(
    exclusive output: span.WriteSpan<number>,
    scale: number
): number
    local adjusted = scale + 1.0
    @simd
    for i = 1, #output do
        output[i] = adjusted * 2.0
    end

    local result = adjusted + 3.0
    @simd
    for i = 1, #output do
        output[i] = output[i] + result
    end
    return result
end

return {process = process}
]]

local REQUIRED_THRESHOLD = [[
local span = require("nupp.mem.span")

local function refine(value: number, sample: integer): number
    return value + sample * 0.25
end

@aot
local function thresholded(
    exclusive output: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    threshold: number,
    sampleCount: integer
): nil
    if #output ~= #input then error("length mismatch", 2) end
    @simd
    for pixel = 1, #output do
        local value = input[pixel]
        if value > threshold then
            for sample = 1, sampleCount do
                value = refine(value, sample)
            end
        end
        output[pixel] = value
    end
end

return {thresholded = thresholded}
]]

local REQUIRED_VARYING_FOR = [[
local span = require("nupp.mem.span")

@aot
local function varying(exclusive output: span.WriteSpan<number>): nil
    @simd
    for pixel = 1, #output do
        local value = 0.0
        for sample = 1, pixel do
            if sample > 2 then
                break
            end
            value = value + sample
        end
        output[pixel] = value
    end
end

return {varying = varying}
]]

local GENERIC_EXPLICIT_SIMD = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function saxpy(
    exclusive output: span.WriteSpan<float>,
    borrows x: span.Span<float>,
    borrows y: span.Span<float>,
    scale: float
): nil
    local species = assert(simd.species(array.float))
    local offset: integer = 1
    while offset <= #output do
        local active = species:tail(#output - offset + 1)
        local xv = species:load(x, offset, active)
        local yv = species:load(y, offset, active)
        local result = xv * scale + yv
        species:store(output, offset, result, active)
        offset = offset + species.lanes
    end
end

return {saxpy = saxpy}
]]

-- Lanes required around a real native entry call. A compiled entry has one
-- scalar ABI call, not one invocation per lane, so the build fails.
local REFUSED = STREAMING:gsub(
    "@aot\nlocal function advance",
    "@aot\nlocal function compiledScale(value: float): float\n"
    .. "    return value\n"
    .. "end\n\n"
    .. "@aot\nlocal function advance",
    1
)
    :gsub("    for i = first, last do", "    @simd\n    for i = first, last do", 1)
    :gsub(
        "        local position = positions%[i%]",
        "        local position = positions[i]\n        local scale = compiledScale(position.x)",
        1
    )
    :gsub("velocity%.vx %* dt", "velocity.vx * scale", 1)
    :gsub("velocity%.vy %* dt", "velocity.vy * scale", 1)

local FIXED_MIX = [[
local span = require("nupp.mem.span")

@aot
local function mix(
    exclusive output: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    first: integer,
    last: integer
): nil
    if #output ~= #input then error("length mismatch", 2) end
    if first < 1 or last > #output or first > last + 1 then error("range out of bounds", 2) end
    @simd
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

@aot
local function classify(
    exclusive flags: span.WriteSpan<uint8>,
    borrows bytes: span.Span<uint8>
): nil
    if #flags ~= #bytes then error("length mismatch", 2) end
    @simd
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

@aot
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

@aot
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

@aot
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
-- reads either form and has to reach the same kernel from both.
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
    local wantedReport, wanted, wantedCode, wantedWhere = lowered(plain, PINNED .. "--json compute.nupp")
    local gotReport, got, gotCode, gotWhere = lowered(asserted, PINNED .. "--json compute.nupp")
    test.equal(wantedCode, 0, wanted)
    test.equal(gotCode, 0, "assert guards are admitted like error guards\n" .. got)
    test.equal(
        gotReport.c,
        wantedReport.c,
        ("both guard forms emit the same C (%s versus %s)"):format(gotWhere, wantedWhere)
    )
end

-- `assert(a ~= b)` states that two lengths differ, which bounds neither of them
-- in either direction. Nothing is read out of it, and because dropping it would
-- give the wrapper a precondition it does not check, the clause is named rather
-- than skipped.
function M.aGuardThatBoundsNothingNamesItsClause()
    local dir = project{
        ["compute.nupp"] = replaceOnce(COMPUTE_ASSERTED, "assert(#out == #points", "assert(#out ~= #points")
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a guard that proves nothing is refused\n" .. out)
    assert(out:find("`#out ~= #points` cannot be read as a guard", 1, true), "the clause is named: " .. out)
end

-- Every one of these says what the admitted form says, and the backend is asked
-- whether the facts imply the loop's bounds rather than whether the text matches.
-- Byte-identical C is the claim: a source form that reaches a different artifact
-- would be one the backend understood differently.
function M.equivalentGuardFormsReachTheSameKernel()
    local wanted, wantedCode = run(project{["compute.nupp"] = COMPUTE}, PINNED .. "--emit c compute.nupp")
    test.equal(wantedCode, 0, wanted)
    local forms = {
        reordered = {
            "first >= 1 and last <= #out and first <= last + 1",
            "last <= #out and first >= 1 and first <= last + 1"
        },
        strict = {"first >= 1 and last <= #out", "first > 0 and last <= #out"},
        reversed = {"first >= 1 and last <= #out", "1 <= first and #out >= last"},
        offset = {"first <= last + 1", "first - 1 <= last"},
        throughTheGuardedSpan = {"last <= #out and", "last <= #points and"},
        split = {
            [[    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]],
            [[    assert(first >= 1, "low")
    assert(last <= #out and first <= last + 1, "high")]],
        },
    }
    for name, pair in pairs(forms) do
        local source = replaceOnce(COMPUTE_ASSERTED, pair[1], pair[2])
        local got, code = run(project{["compute.nupp"] = source}, PINNED .. "--emit c compute.nupp")
        test.equal(code, 0, name .. " is admitted\n" .. got)
        test.equal(got, wanted, name .. " emits the same C as the reference form")
    end
end

-- The wrapper enforces the relations the source wrote, so a precondition
-- stronger than the loop needs stays stronger. Moving this function from
-- interpreted to native must not widen the calls it accepts.
function M.aStrongerRangeGuardIsAdmittedAndEnforced()
    local dir = project{
        ["compute.nupp"] = replaceOnce(COMPUTE_ASSERTED, "first >= 1 and last <= #out", "first >= 2 and last <= #out")
    }
    local out, code = run(dir, PINNED .. "--emit binding compute.nupp")
    test.equal(code, 0, "a guard the loop does not need is carried, not refused\n" .. out)
    assert(out:find("first < 2", 1, true), "the wrapper refuses what the source refuses: " .. out)
    assert(not out:find("first < 1", 1, true), "the loop's own weaker bound is not what is checked: " .. out)
end

function M.constantAndNegativeGuardFactsReachValidWrapperSource()
    local source = replaceOnce(
        COMPUTE_ASSERTED,
        [[    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]],
        [[    assert(1 <= 2, "constant truth")
    assert(first >= -1, "negative literal")
    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]]
    )
    local out, code = run(project{["compute.nupp"] = source}, PINNED .. "--emit binding compute.nupp")
    test.equal(code, 0, "bounded integer literals are admitted\n" .. out)
    assert(out:find("first < -1", 1, true), "the negative relation is preserved: " .. out)
    assert(not out:find("nil <", 1, true), "the constant tautology emits no origin-to-origin check: " .. out)
end

function M.aStrictGuardBeyondTheRelationOffsetLimitNamesItsClause()
    local source = replaceOnce(
        COMPUTE_ASSERTED,
        [[    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]],
        [[    assert(1048576 < first, "large strict offset")
    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]]
    )
    local out, code = run(project{["compute.nupp"] = source}, PINNED .. "compute.nupp")
    test.equal(code, 1, "an adjusted offset outside the bounded solver is refused\n" .. out)
    assert(out:find("`1048576 < first` cannot be read as a guard", 1, true), "the clause is named: " .. out)
    assert(
        not out:find("guard relation offsets further", 1, true),
        "the invalid IR never reaches verification: " .. out
    )
end

-- A precondition about something the loop's bounds do not involve at all. It is
-- still a fact the source stated, so the wrapper carries it.
function M.anUnrelatedPreconditionIsCarriedIntoTheWrapper()
    local dir = project{
        [
            "compute.nupp"
        ] = replaceOnce(
            COMPUTE_ASSERTED,
            [[    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")]],
            [[    assert(first >= 1 and last <= #out and first <= last + 1, "range out of bounds")
    assert(last <= 4096, "too many rows")]]
        )
    }
    local out, code = run(dir, PINNED .. "--emit binding compute.nupp")
    test.equal(code, 0, "an extra precondition does not cost the map shape\n" .. out)
    assert(out:find("last > 4096", 1, true), "the wrapper checks it: " .. out)
end

-- The C has no use for a parameter only a guard mentioned, and `-Werror` would
-- refuse the generated translation unit for declaring one. `KS_UNUSED` says the
-- parameter may go unread without saying that it does, so a read the emitter
-- drops is still caught.
function M.aUniformUsedOnlyByAGuardIsMarkedUnusedInC()
    local dir = project{
        [
            "compute.nupp"
        ] = replaceOnce(
            replaceOnce(COMPUTE_ASSERTED, [[    limit: int32
): nil]], [[    limit: int32,
    guardOnly: int32
): nil]]),
            [["range out of bounds")]],
            [["range out of bounds")
    assert(guardOnly >= 1, "guard-only value")]]
        )
    }
    local out, code = run(dir, PINNED .. "--emit c compute.nupp")
    test.equal(code, 0, "the precondition is admitted\n" .. out)
    assert(out:find("p_guardOnly KS_UNUSED", 1, true), "the generated C does not read the wrapper-only value: " .. out)
    assert(not out:find("p_limit KS_UNUSED", 1, true), "the loop still reads its limit: " .. out)
end

-- A range over spans no equality relates. The length guard used to be what the
-- backend read the range out of, so a kernel whose spans differ in length could
-- not have one at all.
function M.aRangeGuardDoesNotNeedALengthGuard()
    local dir = project{
        [
            "rows.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function rowSums(
    exclusive sums: span.WriteSpan<number>,
    borrows matrix: span.Span<number>,
    first: integer,
    last: integer,
    width: integer
): nil
    assert(first >= 1 and last <= #sums and first <= last + 1, "range out of bounds")

    for row = first, last do
        sums[row] = sums[row] + width
    end
end

return {rowSums = rowSums}
]],
    }
    local out, code = run(dir, PINNED .. "--emit binding rows.nupp")
    test.equal(code, 0, "a range alone is a guard prefix\n" .. out)
    assert(out:find("first < 1", 1, true), "the range is still checked: " .. out)
    assert(not out:find("incompatible lengths", 1, true), "no agreement is claimed: " .. out)
end

function M.transitiveLengthAndRangeFactsReachLowering()
    local dir = project{
        [
            "transitive.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function copy(
    exclusive out: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    borrows bridge: span.Span<number>
): nil
    assert(#input == #bridge and #bridge == #out, "lengths")
    for i = 1, #out do
        out[i] = input[i]
    end
end

@aot
local function fill(
    exclusive out: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    first: integer,
    last: integer,
    middle: integer
): nil
    assert(#out == #input, "lengths")
    assert(first >= 1 and last <= middle and middle <= #out and first <= last + 1, "range")
    for i = first, last do
        out[i] = input[i]
    end
end

return {copy = copy, fill = fill}
]],
    }
    local out, code = run(dir, PINNED .. "--emit binding transitive.nupp")
    test.equal(code, 0, "lowering consumes transitive closure facts\n" .. out)
    assert(out:find("#input ~= #out", 1, true), "the transitive length equality becomes a body claim: " .. out)
    assert(out:find("last > middle", 1, true), "the first range edge is preserved: " .. out)
    assert(out:find("middle > #out", 1, true), "the second range edge is preserved: " .. out)
end

-- A clause that cannot be read is not one the backend may skip: skipping it
-- would compile a wrapper that never checks it.
function M.anUnreadableClauseRefusesTheKernel()
    local dir = project{
        [
            "compute.nupp"
        ] = replaceOnce(
            COMPUTE_ASSERTED,
            [["range out of bounds")]],
            [["range out of bounds")
    assert(first == 1 or last == 2, "either")]]
        )
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a known-true `or` states no fact about either side\n" .. out)
    assert(out:find("cannot be read as a guard", 1, true), "the clause is named: " .. out)
end

function M.aGuardCannotDiscardAnEvaluatedArgument()
    local source = [[
local span = require("nupp.mem.span")
local function message(): string return "length mismatch" end
@aot
local function copy(
    exclusive out: span.WriteSpan<number>,
    borrows input: span.Span<number>
): nil
    assert(#out == #input, message())
    for i = 1, #out do
        out[i] = input[i]
    end
end
return {copy = copy}
]]
    local out, code = run(project{["copy.nupp"] = source}, PINNED .. "copy.nupp")
    test.equal(code, 1, "an eager message call is not dropped from the wrapper\n" .. out)
    assert(out:find("`message()` cannot be discarded from a guard", 1, true), "the discarded call is named: " .. out)
end

function M.aShadowedGuardNameEstablishesNoAotFact()
    local source = [[
local span = require("nupp.mem.span")
local function assert(ok: boolean, message: string): boolean return true end
@aot
local function copy(
    exclusive out: span.WriteSpan<number>,
    borrows input: span.Span<number>
): nil
    assert(#out == #input, "ignored")
    for i = 1, #out do
        out[i] = input[i]
    end
end
return {copy = copy}
]]
    local out, code = run(project{["copy.nupp"] = source}, PINNED .. "copy.nupp")
    test.equal(code, 1, "the local function is not consumed as a prelude guard\n" .. out)
    assert(not out:find("compiled copy", 1, true), "no invented length relation reaches an artifact: " .. out)
end

-- Everything follows from a contradiction, the loop's bounds included, so a
-- kernel whose guards can never pass is not one to compile.
function M.contradictoryGuardsRefuseTheKernel()
    local dir = project{
        [
            "compute.nupp"
        ] = replaceOnce(
            COMPUTE_ASSERTED,
            [["range out of bounds")]],
            [["range out of bounds")
    assert(last >= 3 and last <= 2, "impossible")]]
        )
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a contradiction is refused\n" .. out)
    assert(out:find("cannot all hold at once", 1, true), "it says why: " .. out)
end

-- The bound exists so the closure is provably cheap, not because a kernel is
-- expected to reach it. Overrunning it declines a kernel; it never admits one.
function M.aGuardPoolBeyondTheBudgetRefusesTheKernel()
    local extra = {}
    for value = 1, 130 do
        extra[#extra + 1] = ('    assert(last <= %d, "cap %d")'):format(100000 + value, value)
    end
    local dir = project{
        [
            "compute.nupp"
        ] = replaceOnce(
            COMPUTE_ASSERTED,
            [["range out of bounds")]],
            [["range out of bounds")
]] .. table.concat(extra, "\n")
        )
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "the budget is enforced\n" .. out)
    assert(out:find("at most 128 relations", 1, true), "the budget is named: " .. out)
end

-- A dispatch has no wrapper to check a relation in, so a GPU kernel may only
-- state facts its host binding already carries: one count per span.
function M.aGpuKernelMayOnlyRelateSpanLengths()
    local dir = project{
        [
            "compute.nupp"
        ] = [[
local span = require("nupp.mem.span")

local struct Cell value: float end

@aot(target = "gpu")
local function convert(
    exclusive out: span.WriteSpan<Cell>,
    borrows input: span.Span<Cell>,
    rounds: int32
): nil
    assert(#out == #input, "length mismatch")
    assert(rounds >= 1, "at least one round")

    for i = 1, #out do
        out[i].value = input[i].value * 2.0
    end
end

return {convert = convert}
]],
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a precondition no dispatch checks is refused\n" .. out)
    assert(out:find("only relate span lengths", 1, true), "it says why: " .. out)
end

function M.aGpuBindingChecksEveryWrittenSpanRelation()
    local dir = project{
        [
            "compute.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function fill(
    exclusive out: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>
): nil
    assert(#out <= #input, "input capacity")
    for i = 1, #out do
        out[i] = 1
    end
end

return {fill = fill}
]],
    }
    local out, code = run(dir, PINNED .. "--emit binding compute.nupp")
    test.equal(code, 0, "a one-way count relation is admitted\n" .. out)
    assert(out:find("out.count > input.count", 1, true), "the generated binding enforces the relation: " .. out)
    assert(out:find("GPU precondition failed", 1, true), "the relation has a binding failure: " .. out)
end

-- Says what was needed and what was read, rather than a form to copy.
function M.anUnprovedRangeSaysWhatWasMissing()
    local dir = project{
        [
            "compute.nupp"
        ] = replaceOnce(
            COMPUTE_ASSERTED,
            "first >= 1 and last <= #out and first <= last + 1",
            "first >= 1 and first <= last + 1"
        )
    }
    local out, code = run(dir, PINNED .. "compute.nupp")
    test.equal(code, 1, "a range missing its upper bound is refused\n" .. out)
    assert(out:find("needed `last <= #out`", 1, true), "the missing bound is named: " .. out)
    assert(out:find("understood ", 1, true) and out:find("`1 <= first`", 1, true), "so is what was read: " .. out)
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
    assert(out:find("Fixed<4>", 1, true), "the species is named: " .. out)
    assert(out:find("4 lanes", 1, true), "the width is named: " .. out)
end

function M.anUnmarkedLoopCompilesScalarAndSaysSo()
    local dir = project{["stream.nupp"] = STREAMING}
    local out, code = run(dir, "stream.nupp")
    test.equal(code, 0, "a loop without @simd is not a failure\n" .. out)
    assert(out:find("advance, kernel, scalar", 1, true), "the report says it runs scalar: " .. out)
    assert(not out:find("lanes", 1, true), "and offers no lane decision to read: " .. out)
end

function M.aVectorizeMemberOnAotIsUnknown()
    -- Whether a loop runs in lanes is the loop's own `@simd` to say, so `@aot`
    -- has no member for it and the old spelling is refused at the source.
    for _, spelling in ipairs({"@aot(vectorize = true)", "@aot(vectorize = false)", "@aot(lanes = true)"}) do
        local dir = project{["stream.nupp"] = replaceOnce(STREAMING, "@aot\n", spelling .. "\n")}
        local out, code = run(dir, "stream.nupp")
        test.equal(code, 1, spelling .. " is not accepted\n" .. out)
        assert(out:find("NUPP2115", 1, true), spelling .. " is an unknown member: " .. out)
    end
end

function M.aRequiredSimdLoopLowersAContiguousCopy()
    local dir = project{["required.nupp"] = REQUIRED_CONTIGUOUS}
    local out, code = run(dir, PINNED .. "required.nupp")
    test.equal(code, 0, out)
    assert(out:find("Fixed<8>", 1, true), "the required species is named: " .. out)
    assert(out:find("8 lanes", 1, true), "the required width is named: " .. out)
end

function M.aRequiredSimdLoopFailsWithoutLaneCode()
    local dir = project{["required.nupp"] = REFUSED}
    local out, code = run(dir, PINNED .. "required.nupp")
    test.equal(code, 1, "required SIMD cannot fall back to scalar execution\n" .. out)
    assert(out:find("cannot call a compiled entry", 1, true), "the failed construct is named: " .. out)
    assert(
        not out:find("ran one iteration at a time", 1, true),
        "required SIMD is a build error, not a report: " .. out
    )
end

function M.requiredSimdRegionsKeepScalarSetupTeardownAndOrder()
    local dir = project{["required.nupp"] = REQUIRED_REGIONS}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json required.nupp")
    test.equal(code, 0, raw)
    local ir = decoded.ir
    local _, regions = ir:gsub("simd vector", "")
    test.equal(regions, 2, where .. ": both authored regions have vector bodies\n" .. ir)
    assert(
        ir:find(
            "let adjusted",
            1,
            true
        ) < ir:find(
            "@simd for",
            1,
            true
        ) and ir:find(
            "let result",
            1,
            true
        ) > ir:find("simd vector", 1, true) and ir:find("return local:f64 result", 1, true) > ir:match(".*()simd vector"),
        where .. ": scalar setup, between-region work, and teardown remain ordered\n" .. ir
    )
    local _, loops = decoded.c:gsub("_base1 = UINT32_C%(0%);", "")
    test.equal(loops, 2, where .. ": each region emits its own whole-group loop")
    local scalarOracle = decoded.c:match("ks_process_forced_scalar.-\n}\n")
    assert(scalarOracle ~= nil, where .. ": required regions retain a scalar-source C oracle")
    assert(
        not scalarOracle:find("ks_exp_", 1, true),
        where .. ": the scalar-source oracle erases vector regions instead of sharing their lowering"
    )
end

function M.requiredSimdKeepsUniformNestedLoopsInsideLaneBranches()
    local dir = project{["required.nupp"] = REQUIRED_THRESHOLD}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json required.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("for sample", 1, true), where .. ": the uniform inner loop remains structured")
    assert(decoded.ir:find("simd_select", 1, true), where .. ": its assignment is masked by the outer condition")
end

function M.requiredSimdControlsVaryingNestedForAndBreakPerLane()
    local dir = project{["required.nupp"] = REQUIRED_VARYING_FOR}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json required.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_mask_any", 1, true), where .. ": varying bounds become a live-mask loop")
    assert(decoded.ir:find("simd_unary.not", 1, true), where .. ": break retires only participating lanes")
    assert(decoded.ir:find("simd_iota", 1, true), where .. ": the authored outer index is a vector value")
end

function M.mandelbrotUsesRequiredSimdWithLaneLocalEarlyExit()
    local handle = assert(io.open(HERE .. "/../bench/simd-mandelbrot/mandelbrot.nupp", "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(source:find("@simd", 1, true), "the bench marks its loop")
    local dir = project{["mandelbrot.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json mandelbrot.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_mask_any", 1, true), where .. ": Mandelbrot retains its varying loop")
    assert(decoded.ir:find("simd_unary.not", 1, true), where .. ": each escaped point retires independently")
end

function M.requiredSimdRepeatTestsEachLaneAfterItsBody()
    local source = [[
local span = require("nupp.mem.span")

@aot
local function refine(
    exclusive output: span.WriteSpan<number>,
    borrows input: span.Span<number>
): nil
    if #output ~= #input then error("length mismatch", 2) end
    @simd
    for i = 1, #output do
        local value = input[i]
        repeat
            local done = value <= 1.0
            if done then
                continue
            end
            value = value * 0.5
            if value < input[i] * 0.1 then
                break
            end
        until done
        output[i] = value
    end
end

return {refine = refine}
]]
    local dir = project{["repeat.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json repeat.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_mask_any", 1, true), where .. ": repeat becomes one lane-live loop")
    assert(decoded.ir:find("$exec", 1, true), where .. ": continue reaches the trailing lane test")
    assert(decoded.ir:find("$live", 1, true), where .. ": break retires only its lane")
    local scalarOracle = decoded.c:match("ks_refine_forced_scalar.-\n}\n")
    assert(scalarOracle ~= nil, where .. ": repeat retains an independent scalar oracle")
    assert(
        scalarOracle:find(
            "goto ks_repeat_continue_",
            1,
            true
        ) and scalarOracle:find("ks_repeat_continue_", 1, true) and scalarOracle:find("if (v2_done) break;", 1, true),
        where .. ": scalar continue evaluates a body-local trailing condition\n" .. scalarOracle
    )
end

function M.exactReducersKeepNativeWidthAndLogicalPositionsAtEveryTier()
    local source = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
@aot
local function folds(borrows input: span.Span<uint64>, seed: uint64): (uint64, integer, uint64, boolean)
    local sum = simd.reducer.u64.wrappingSum(4294967296ULL)
    local arg: simd.IntegerArgMax<uint64> = simd.reducer.integerArgMax()
    local count = simd.reducer.count()
    local all = simd.reducer.all()
    @simd
    for i = 3, #input do
        sum:add(input[i])
        arg:add(input[i])
        count:add(input[i] > seed)
        all:add(true)
    end
    return sum:value(), arg:value(), count:value(), all:value()
end
return {folds = folds}
]]
    local dir = project{["folds.nupp"] = source}
    for _, tier in ipairs({
        "--target x86_64-unknown-linux-gnu --features baseline ",
        "--target x86_64-unknown-linux-gnu --features avx2 ",
        "--target x86_64-unknown-linux-gnu --features avx512f ",
        "--target aarch64-apple-darwin --features neon ",
        "--target wasm32-unknown-emscripten --features simd128 ",
    }) do
        local decoded, raw, code = lowered(dir, tier .. "--json folds.nupp")
        test.equal(code, 0, raw)
        assert(decoded.ir:find("simd.reducer.exact.sum", 1, true), tier .. decoded.ir)
        assert(decoded.ir:find("simd_load.load:simd_vector_u64_fixed", 1, true), tier .. decoded.ir)
        assert(decoded.c:find("simd_acc_", 1, true), tier .. ": missing lane accumulator")
        assert(decoded.c:find("ks_reduce_integer_argmax_u64_add", 1, true), tier .. ": missing indexed extremum")
    end
end

function M.requiredSimdReducersCarryTheirArithmeticContractAcrossTheRegion()
    local source = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function totals(borrows values: span.Span<number>): (number, number, number)
    local ordered = simd.reducer.orderedSum(1.0)
    @simd
    for i = 1, #values do
        ordered:add(values[i])
    end

    local pairwise = simd.reducer.pairwiseSum(1.0)
    @simd
    for i = 1, #values do
        pairwise:add(values[i])
    end

    local algebraic = simd.reducer.algebraicSum(1.0)
    @simd
    for i = 1, #values do
        algebraic:add(values[i])
    end

    return ordered:value(), pairwise:value(), algebraic:value()
end

return {totals = totals}
]]
    local dir = project{["reducers.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json reducers.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("reducer.ordered.sum", 1, true), where .. ": ordered contract is explicit\n" .. decoded.ir)
    assert(decoded.ir:find("reducer.pairwise.sum", 1, true), where .. ": pairwise contract is explicit\n" .. decoded.ir)
    assert(
        decoded.ir:find("reducer.algebraic.sum", 1, true),
        where .. ": algebraic contract is explicit\n" .. decoded.ir
    )
    assert(
        decoded.ir:find("simd.reducer.pairwise.sum", 1, true),
        where .. ": the pairwise contribution carries its order\n" .. decoded.ir
    )
    assert(decoded.c:find("ks_pairwise_f64_add", 1, true), where .. ": pairwise tree has its own native state")
    assert(
        decoded.c:find("simd_acc_", 1, true),
        where .. ": algebraic sum uses lane accumulators rather than an ordered chain"
    )
    assert(decoded.c:find("ks_totals_forced_scalar", 1, true), where .. ": reducers retain the scalar-source C oracle")
    test.equal(#decoded.functions[1].regions, 3, where .. ": each authored region is reported")
    test.equal(decoded.functions[1].regions[1].gang.lanes, 4, where .. ": the selected gang is reported")
    test.equal(decoded.functions[1].regions[1].reducers[1].serialized, true, where .. ": ordered edges are visible")
    test.equal(decoded.functions[1].regions[3].reducers[1].serialized, false, where .. ": algebraic freedom is visible")
end

function M.requiredSimdReducersHaveOneRegionAndOneFinalization()
    local prefix = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function total(borrows values: span.Span<number>): number
    local sum = simd.reducer.orderedSum(0.0)
]]
    local suffix = [[
end

return {total = total}
]]
    local cases = {
        {
            name = "reused.nupp",
            body = [[
    @simd
    for i = 1, #values do
        sum:add(values[i])
    end
    @simd
    for i = 1, #values do
        sum:add(values[i])
    end
    return sum:value()
]],
            message = "a reducer is scoped to exactly one @simd loop",
        },
        {
            name = "early.nupp",
            body = [[
    return sum:value()
]],
            message = "a reducer must receive its contribution before it is finalized",
        },
        {
            name = "unfinished.nupp",
            body = [[
    @simd
    for i = 1, #values do
        sum:add(values[i])
    end
    return 0.0
]],
            message = "a reducer is finalized exactly once after its @simd loop",
        },
        {
            name = "copied.nupp",
            body = [[
    local other = sum
    @simd
    for i = 1, #values do
        other:add(values[i])
    end
    return other:value()
]],
            message = "a reducer cannot be copied or passed through another value",
        },
        {
            name = "twice.nupp",
            body = [[
    @simd
    for i = 1, #values do
        sum:add(values[i])
    end
    local first = sum:value()
    return first + sum:value()
]],
            message = "a reducer is finalized exactly once",
        },
        {
            name = "nested.nupp",
            body = [[
    @simd
    for i = 1, #values do
        @simd
        for j = 1, #values do
            sum:add(values[j])
        end
    end
    return sum:value()
]],
            message = "an @simd loop cannot be nested in another @simd loop",
        },
    }

    for _, case in ipairs(cases) do
        local dir = project{[case.name] = prefix .. case.body .. suffix}
        local out, code = run(dir, case.name)
        test.equal(code, 1, case.name .. " must fail\n" .. out)
        assert(out:find(case.message, 1, true), case.name .. ": " .. out)
    end
end

function M.genericExplicitSimdKeepsIntrinsicTypesAndAnIndependentOracle()
    local dir = project{["vectors.nupp"] = GENERIC_EXPLICIT_SIMD}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json vectors.nupp")
    test.equal(code, 0, raw)
    -- The shape is said once, by the type. The intrinsic beside it used to
    -- repeat it and nothing read the repetition.
    assert(
        decoded.ir:find("simd_species.species:simd_species_f32_preferred", 1, true),
        where .. ": species identity is in IR\n" .. decoded.ir
    )
    assert(
        decoded.ir:find("simd_binary.mul:simd_vector_f32_preferred", 1, true),
        where .. ": vector multiplication is intrinsic\n" .. decoded.ir
    )
    assert(
        decoded.ir:find("simd_binary.add:simd_vector_f32_preferred", 1, true),
        where .. ": vector addition is intrinsic\n" .. decoded.ir
    )
    assert(
        decoded.ir:find("simd_store.store:lua_effect", 1, true),
        where .. ": the masked store is intrinsic\n" .. decoded.ir
    )
    assert(decoded.c:find("KS_EXP_ELEMENT(32, f32x8, float", 1, true), where .. ": AVX2 selects eight binary32 lanes")
    assert(decoded.c:find("ks_saxpy_forced_scalar", 1, true), where .. ": the scalar-source oracle remains separate")
    assert(decoded.c:find("ks_scalar_exp_mul_f32x8", 1, true), where .. ": oracle primitives execute lane by lane")
end

-- AVX-512F is the one tier whose preferred vector is 64 bytes, and it only
-- gets there once every earlier width is compiled with narrower flags: the
-- 64-byte block is instantiated for this tier alone, so no wider vector ever
-- meets a `-mavx2` compilation and the ABI warning that follows.
function M.genericExplicitSimdPrefersSixteenLanesAtAvx512f()
    local targets = require("nupp.compiler.aot.target")
    local host = assert(targets.hostTriple())
    local triple = host:gsub("^[^-]+", "x86_64")
    -- The triple follows the host, so on Windows this targets Windows, whose
    -- frame carries no more than sixteen bytes however wide the tier's
    -- registers are. The tier still selects its instructions; what it gives up
    -- is the register width, so the species and the assertions follow the
    -- ceiling rather than the tier.
    local ceiling = targets.vectorCeiling({triple = triple, architecture = "x86_64", tier = "avx512f"})
    local width = ceiling or 64
    local lanes = width / 4
    local dir = project{["vectors.nupp"] = GENERIC_EXPLICIT_SIMD}
    local decoded, raw, code, where = lowered(dir, "--target " .. triple .. " --features avx512f --json vectors.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.c:find(("#define KS_SIMD_WIDTH %d"):format(width), 1, true),
        where .. (": AVX-512F selects %d bytes"):format(width)
    )
    assert(
        decoded.c:find(("KS_EXP_ELEMENT(%d, f32x%d, float"):format(width, lanes), 1, true),
        (where .. ": %d binary32 lanes"):format(lanes)
    )
    assert(
        decoded.c:find(("ks_scalar_exp_mul_f32x%d"):format(lanes), 1, true),
        (where .. ": the oracle walks %d lanes"):format(lanes)
    )
    local asm, asmCode = run(dir, "--target " .. triple .. " --features avx512f --emit asm vectors.nupp")
    test.equal(asmCode, 0, asm)
    local register = width == 64 and "zmm" or width == 32 and "ymm" or "xmm"
    assert(asm:find(register, 1, true), ("the multiply lives in a %d-byte register: "):format(width) .. asm)
    -- The packed byte scanner stays at 32 bytes there: AVX-512F alone has no
    -- byte compare or shuffle, so a program carrying both keeps compiling.
    local both = project{["mixed.nupp"] = SCOPED_SIMD:gsub("return {quotes = quotes}", "") .. [[
local array = require("nupp.mem.array")

@aot
local function twice(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    local species = assert(simd.species(array.float))
    local active = species:tail(#input)
    species:store(output, 1, species:load(input, 1, active) * 2, active)
end

return {quotes = quotes, twice = twice}
]]}
    local mixed, mixedCode = run(both, "--target " .. triple .. " --features avx512f --emit c mixed.nupp")
    test.equal(mixedCode, 0, mixed)
    local scanner = ("ks_u8x%d"):format(math.min(32, width))
    assert(mixed:find(scanner, 1, true), "byte vectors keep the " .. scanner .. " scanner: " .. mixed)
    assert(not mixed:find("ks_u8x64", 1, true), "no 64-byte byte scanner exists: " .. mixed)
end

function M.genericExplicitSimdEmitsRealTargetVectorArithmetic()
    local dir = project{["vectors.nupp"] = GENERIC_EXPLICIT_SIMD}
    local out = neonAsm(dir, "vectors.nupp")
    if out == nil then
        test.skip("reading NEON instructions needs Clang or an aarch64 host")
    end
    assert(out:find("fmul.4s", 1, true), "binary32 multiplication remains a vector operation: " .. out)
    assert(out:find("fadd.4s", 1, true), "binary32 addition remains a vector operation: " .. out)
    assert(out:find("0 vector", 1, true), "the separately reported scalar oracle has no vector instructions: " .. out)
end

function M.narrowIntegerVectorsRetainPhysicalLaneWidth()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function increment(
    exclusive output: span.WriteSpan<uint8>,
    borrows input: span.Span<uint8>
): nil
    local species = assert(simd.species(array.uint8))
    local active = species:tail(#input)
    local values = species:load(input, 1, active)
    species:store(output, 1, values + 1, active)
end

return {increment = increment}
]]
    local dir = project{["narrow.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json narrow.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_vector_u8_preferred", 1, true), where .. ": physical byte identity reaches IR")
    assert(decoded.c:find("KS_EXP_ELEMENT(16, u8x16, uint8_t", 1, true), where .. ": NEON retains sixteen byte lanes")

    local asm = neonAsm(dir, "narrow.nupp")
    if asm ~= nil then
        assert(asm:find("add.16b", 1, true), "byte addition remains a vector operation: " .. asm)
        assert(asm:find("0 vector", 1, true), "the narrow scalar oracle has no vector instructions: " .. asm)
    end
end

--- A byte vector is an integer vector for the bitwise operators, and a scalar
--- beside it splats as it does for `+`.
---
--- `uint8` is a storage width the scalar language widens to `integer`, but a
--- vector of it keeps its physical lanes, so `bytes >> 4` and `bytes & 15` are
--- the nibble split of a lookup validator rather than a type error. The
--- operands still have to agree: a byte vector against a word vector is refused
--- as it always was.
function M.byteVectorsTakeBitwiseOperatorsWithScalarOperands()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function nibbles(
    exclusive output: span.WriteSpan<uint8>,
    borrows input: span.Span<uint8>,
    borrows table: span.Span<uint8>
): nil
    local species = assert(simd.species(array.uint8))
    local active = species:tail(#input)
    local bytes = species:load(input, 1, active)
    local entries = species:load(table, 1, species:tail(#table))
    local high = entries:swizzle((bytes >> 4) + 1)
    local low = entries:swizzle((bytes & 15) + 1)
    local flagged = ((bytes >= 0x80) | (bytes < 0x20)):select(0x80, 0)
    species:store(output, 1, (high & low) ~ flagged, active)
end

return {nibbles = nibbles}
]]
    local dir = project{["nibbles.nupp"] = source}
    local asm = neonAsm(dir, "nibbles.nupp")
    if asm ~= nil then
        assert(asm:find("ushr.16b", 1, true), "the shift stays a byte vector operation: " .. asm)
        assert(asm:find("and.16b", 1, true), "the and stays a byte vector operation: " .. asm)
        assert(asm:find("tbl.16b", 1, true), "and the nibble indexes a table: " .. asm)
    end

    local mismatched = source:gsub("local low = entries:swizzle%(%(bytes & 15%) %+ 1%)", [[
    local words = assert(simd.species(array.uint32))
    local low = entries:swizzle((bytes & words:splat(15)) + 1)]])
    local refused = project{["mismatched.nupp"] = mismatched}
    local out, refusedCode = run(refused, "--target aarch64-apple-darwin --features neon mismatched.nupp")
    assert(refusedCode ~= 0, "a byte vector against a word vector is refused: " .. out)
    assert(out:find("NUPP2003", 1, true), "as an operand type error: " .. out)
end

function M.structuralVectorOperationsHaveScalarReferenceSemantics()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function transform(
    exclusive output: span.WriteSpan<uint8>,
    borrows input: span.Span<uint8>
): uint32
    local species = assert(simd.species(array.uint8, 8))
    local active = species:tail(#input)
    local values = species:load(input, 1, active)
    local selected = values > 4
    local packed = values:compress(selected)
    local expanded = packed:expand(selected)
    local aligned = values:align(values:reverse(), 2):rotateLeft(1):rotateRight(1)
    local prefix = expanded:prefixSumOrdered()
    local parity = values:prefixXor()
    species:store(output, 1, prefix + aligned + parity, active)
    local bits = selected:bits()
    return nupp.math.u64.popcount(bits & (bits - 1))
end

return {transform = transform}
]]
    local dir = project{["structural.nupp"] = source}
    local decoded, raw, code, where = lowered(
        dir,
        "--target aarch64-apple-darwin --features neon --json structural.nupp"
    )
    test.equal(code, 0, raw)
    for _, intrinsic in ipairs({
        "simd_permute.reverse",
        "simd_permute.align",
        "simd_permute.rotate_left",
        "simd_permute.rotate_right",
        "simd_compress.compress",
        "simd_expand.expand",
        "simd_prefix.prefix_sum_ordered",
        "simd_prefix.prefix_xor",
        "u64_and",
        "u64_popcount",
    }) do
        assert(decoded.ir:find(intrinsic, 1, true), where .. ": missing intrinsic " .. intrinsic .. "\n" .. decoded.ir)
    end
    assert(decoded.c:find("ks_scalar_exp_compress_u8x8", 1, true), where .. ": compress has scalar semantics")
    assert(decoded.c:find("ks_scalar_exp_prefix_xor_u8x8", 1, true), where .. ": scan has scalar semantics")

    local asm = neonAsm(dir, "structural.nupp")
    if asm ~= nil then
        assert(asm:match("kernel: [^\n]* [1-9]%d* vector"), "fixed structural operations retain real vector work: " .. asm)
    end
end

local CONVERT_SIMD = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function convert(exclusive out: span.WriteSpan<int32>, borrows input: span.Span<number>): nil
    local source = assert(simd.species(array.number, 8))
    local target = assert(simd.species(array.int32, 8))
    target:store(out, 1, target:convert(source:load(input, 1)))
end
return {convert = convert}
]]

function M.numericSimdConversionsRetainVectorLoweringAcrossCpuTiers()
    local dir = project{["convert.nupp"] = CONVERT_SIMD}
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json convert.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_convert.convert", 1, true), decoded.ir)
    assert(decoded.c:find("__builtin_convertvector(ks_cast_d, ks_cast_int64)", 1, true), decoded.c)
    assert(decoded.c:find("ks_cast_result.lane[ks_cast_i]", 1, true), "independent scalar conversion")
    local host = assert(require("nupp.compiler.aot.target").hostTriple())
    local neon = neonAsm(dir, "convert.nupp")
    if neon ~= nil then
        assert(neon:match("kernel: [^\n]* [1-9]%d* vector"), neon)
        assert(neon:match("fcvtzs[^\n]*%.2d"), "conversion itself uses packed double lanes: " .. neon)
    end
    for _, tier in ipairs({"baseline", "avx2", "avx512f"}) do
        local target = "--target " .. host:gsub("^[^-]+", "x86_64") .. " --features " .. tier
        local asm, asmCode = run(dir, target .. " --emit asm convert.nupp")
        test.equal(asmCode, 0, asm)
        assert(asm:match("kernel: [^\n]* [1-9]%d* vector"), asm)
    end
end

function M.numericSimdConversionsRejectLaneAndBitWidthMismatches()
    for _, case in ipairs({
        {source = CONVERT_SIMD:gsub(", 8%)", ")"), reason = "matching logical lane counts"},
        {source = CONVERT_SIMD:gsub("target:convert", "target:reinterpret"), reason = "equal element widths"},
    }) do
        local dir = project{["convert.nupp"] = case.source}
        local out, code = run(dir, "--target aarch64-apple-darwin --features neon --emit c convert.nupp")
        test.equal(code, 1, out)
        assert(out:find(case.reason, 1, true), out)
    end
end

function M.preferredSimdConversionsPreserveLanesAndReinterpretWithoutArithmetic()
    local source = CONVERT_SIMD:gsub("number", "float"):gsub(", 8%)", ")")
    for _, method in ipairs({"convert", "reinterpret"}) do
        local dir = project{["convert.nupp"] = source:gsub("target:convert", "target:" .. method)}
        local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json convert.nupp")
        test.equal(code, 0, raw)
        assert(decoded.ir:find("simd_" .. method .. "." .. method, 1, true), decoded.ir)
        local asm = neonAsm(dir, "convert.nupp")
        if asm ~= nil and method == "reinterpret" then
            assert(not asm:find("fcvt", 1, true), asm)
        end
    end
end

local INDEXED_SIMD = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function move(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, borrows map: span.Span<uint32>): nil
    local values = assert(simd.species(array.float, 8))
    local positions = assert(simd.species(array.uint32, 8))
    local indices = positions:load(map, 1)
    local active = values:tail(#map)
    local gathered = values:gather(input, indices, active)
    values:scatterUnchecked(output, indices, gathered + 1, active)
end
return {move = move}
]]

function M.indexedSimdMemoryCarriesItsExplicitConflictContract()
    local dir = project{["indexed.nupp"] = INDEXED_SIMD}
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json indexed.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_load.gather", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_store.scatterUnchecked", 1, true), decoded.ir)
    local asm = neonAsm(dir, "indexed.nupp")
    if asm ~= nil then
        assert(asm:match("kernel: [^\n]* [1-9]%d* vector"), asm)
    end
end

function M.scatterRefusesUnprovedUniquenessWithoutARuntimeFallback()
    local source = INDEXED_SIMD:gsub("scatterUnchecked", "scatter")
    local dir = project{["indexed.nupp"] = source}
    local out, code = run(dir, "--target aarch64-apple-darwin --features neon --emit c indexed.nupp")
    test.equal(code, 1, out)
    assert(out:find("provably unique indices", 1, true), out)
    assert(out:find("scatterUnchecked", 1, true), out)
end

-- At AVX-512F the preferred binary32 vector holds sixteen lanes, so the eight
-- the fixture names are one partial chunk of it and the gather still reaches
-- the native instruction through that chunk's contiguous lanes.
function M.indexedSimdUsesNativeAvx512MemoryInstructions()
    local targets = require("nupp.compiler.aot.target")
    local host = assert(targets.hostTriple())
    local triple = host:gsub("^[^-]+", "x86_64")
    -- The gather and scatter this asserts address their lanes through a
    -- 64-byte vector of addresses, so a target whose frame will not carry one
    -- does not get them at all. The triple follows the host, so on Windows
    -- there is nothing here to assert and the rest of the case still is.
    local native = targets.vectorCeiling({triple = triple, architecture = "x86_64", tier = "avx512f"}) == nil
    for _, source in ipairs({INDEXED_SIMD, (INDEXED_SIMD:gsub("float", "number"):gsub(", 8%)", ", 4)"))}) do
        local dir = project{["indexed.nupp"] = source}
        local c, cCode = run(dir, "--target " .. triple .. " --features avx512f --emit c indexed.nupp")
        test.equal(cCode, 0, c)
        if native then
            assert(c:find("#define KS_SIMD_WIDTH 64", 1, true), c)
        end
        local asm, code = run(dir, "--target " .. triple .. " --features avx512f --emit asm indexed.nupp")
        test.equal(code, 0, asm)
        if native then
            assert(asm:find("vpgather", 1, true), asm)
            assert(asm:find("vpscatter", 1, true), asm)
        end

        -- The lanes these walk are ordinary arrays, and a Windows worker died
        -- on one: GCC widened it to the register it moved it with, and the
        -- frame it sat in was sixteen-byte aligned, which is all the calling
        -- convention leaves and all the prologue makes. Each one says what it
        -- is aligned to, which narrows the choice without settling it -- MinGW
        -- GCC widens one of these with the attribute on it. What settles it is
        -- that a Windows target builds no value wider than its frame carries,
        -- and this path is not emitted there at all.
        local staging = {"ks_index", "ks_mask", "ks_value"}
        if native then
            staging[#staging + 1] = "ks_offsets"
            staging[#staging + 1] = "ks_batch"
        end
        for _, staged in ipairs(staging) do
            local declaration = c:match(staged .. "%[%d+%] ([%w_]+)%(")
            test.equal(declaration, "KS_LANE_ARRAY_ALIGN", staged .. " is held to its element's alignment:\n" .. c)
        end
    end
end

function M.scatterProvesAConstantNonWrappingProgression()
    local source = INDEXED_SIMD:gsub("scatterUnchecked%(output, indices", "scatter(output, positions:iota(1, 2)")
    local dir = project{["indexed.nupp"] = source}
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json indexed.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_store.scatter", 1, true), decoded.ir)
    local descending = source:gsub("uint32", "int32"):gsub("positions:iota%(1, 2%)", "positions:iota(8, -1)")
    local reversed = project{["indexed.nupp"] = descending}
    local reverseOut, reverseStatus = run(
        reversed,
        "--target aarch64-apple-darwin --features neon --emit c indexed.nupp"
    )
    test.equal(reverseStatus, 0, reverseOut)
    for _, progression in ipairs({"1, 0", "4294967295, 1", "1, 4294967295"}) do
        local rejected = source:gsub("positions:iota%(1, 2%)", "positions:iota(" .. progression .. ")")
        local failed = project{["indexed.nupp"] = rejected}
        local out, status = run(failed, "--target aarch64-apple-darwin --features neon --emit c indexed.nupp")
        test.equal(status, 1, out)
        assert(out:find("provably unique indices", 1, true), out)
    end
end

function M.indexedSimdRefusesFloatingIndicesAndMismatchedPreferredWidths()
    for _, source in ipairs({
        INDEXED_SIMD:gsub("Span<uint32>", "Span<float>"):gsub("array.uint32", "array.float"),
        (INDEXED_SIMD:gsub("Span<float>", "Span<number>"):gsub("array.float", "array.number"):gsub(", 8%)", ")")),
    }) do
        local dir = project{["indexed.nupp"] = source}
        local out, code = run(dir, "--target aarch64-apple-darwin --features neon --emit c indexed.nupp")
        test.equal(code, 1, out)
        assert(out:find("integer indices with the same logical lane count", 1, true), out)
    end
end

function M.scatterDoesNotAuthorizeCrossIterationCollisions()
    local source = INDEXED_SIMD:gsub(
        "    values:scatterUnchecked%(output, indices, gathered %+ 1, active%)",
        "    @simd\n    for i = 1, #output do\n        values:scatterUnchecked(output, indices, gathered + 1, active)\n    end"
    )
    local dir = project{["indexed.nupp"] = source}
    local out, code = run(dir, "--target aarch64-apple-darwin --features neon --emit c indexed.nupp")
    test.equal(code, 1, out)
    assert(out:find("disjoint destinations between @simd iterations", 1, true), out)
end

function M.horizontalVectorOperationsNameTheirArithmeticContracts()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function horizontal(): (number, number, number)
    local species = assert(simd.species(array.float, 8))
    local left = species:iota(1.0, 1.0)
    local right = species:splat(2.0)
    local ordered: float = simd.horizontal.orderedSum(left)
    local pairwise: float = simd.horizontal.pairwiseSum(left)
    local algebraic: float = simd.horizontal.algebraicSum(left)
    local product: float = simd.horizontal.orderedProduct(left)
    local pairwiseDot: float = simd.horizontal.pairwiseDot(left, right)
    local algebraicDot: float = simd.horizontal.algebraicDot(left, right)
    return ordered + product, pairwise + pairwiseDot, algebraic + algebraicDot
end

return {horizontal = horizontal}
]]
    local dir = project{["horizontal.nupp"] = source}
    local decoded, raw, code, where = lowered(
        dir,
        "--target aarch64-apple-darwin --features neon --json horizontal.nupp"
    )
    test.equal(code, 0, raw)
    for _, intrinsic in ipairs({
        "simd_horizontal.ordered_sum",
        "simd_horizontal.pairwise_sum",
        "simd_horizontal.algebraic_sum",
        "simd_horizontal.ordered_product",
        "simd_horizontal.pairwise_dot",
        "simd_horizontal.algebraic_dot",
    }) do
        assert(decoded.ir:find(intrinsic, 1, true), where .. ": missing intrinsic " .. intrinsic .. "\n" .. decoded.ir)
    end
    assert(
        decoded.c:find("ks_exp_horizontal_pairwise_sum_f32x8", 1, true),
        where .. ": fixed production semantics are emitted"
    )
    assert(
        decoded.c:find("ks_scalar_exp_horizontal_pairwise_sum_f32x8", 1, true),
        where .. ": the scalar executable reference is emitted"
    )
    assert(decoded.c:find("fmaf", 1, true), where .. ": only the named algebraic dot helper requests contraction")
end

-- Contraction is a separate choice from reassociation, and only `algebraicDot`
-- makes it. Reading it out of the C is not enough on its own: every horizontal
-- helper is a prelude macro, so `fmaf` is in the text of every artifact whether
-- or not the program reached it. The instructions are where the claim is
-- decided, and they are decidable here because the build pins
-- `-ffp-contract=off`, so an `a * b + c` the source did not write as a
-- contraction cannot become one behind it.
function M.onlyTheAlgebraicDotContractsItsMultiplyAndAdd()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function ordered(left: float, right: float): float
    local species = assert(simd.species(array.float, 8))
    return simd.horizontal.orderedDot(species:splat(left), species:splat(right))
end

@aot
local function pairwise(left: float, right: float): float
    local species = assert(simd.species(array.float, 8))
    return simd.horizontal.pairwiseDot(species:splat(left), species:splat(right))
end

@aot
local function algebraic(left: float, right: float): float
    local species = assert(simd.species(array.float, 8))
    return simd.horizontal.algebraicDot(species:splat(left), species:splat(right))
end

return {ordered = ordered, pairwise = pairwise, algebraic = algebraic}
]]
    local dir = project{["dots.nupp"] = source}
    local chain = require("nupp.compiler.build.aot").toolchain()
    local host = require("nupp.compiler.aot.target").hostTriple()
    if chain == nil or (chain.dialect ~= "clang" and host ~= "aarch64-apple-darwin") then
        test.skip("reading NEON instructions needs Clang or an aarch64 host")

        return
    end
    local function fusedIn(name)
        local asm, code = run(
            dir,
            "--target aarch64-apple-darwin --features neon --emit asm --function " .. name .. " dots.nupp"
        )
        test.equal(code, 0, asm)
        local fused = 0
        for instruction in asm:gmatch("[%a][%w%.]*") do
            if instruction:find("^fmla") or instruction:find("^fmadd") or instruction:find("^fmsub") then
                fused = fused + 1
            end
        end

        return fused, asm
    end

    for _, name in ipairs({"ordered", "pairwise"}) do
        local fused, asm = fusedIn(name)
        test.equal(fused, 0, name .. "Dot contracted a multiply and an add:\n" .. asm)
    end
    local fused, asm = fusedIn("algebraic")
    assert(fused > 0, "algebraicDot did not contract, which is the one place it may:\n" .. asm)
end

function M.bitwiseOperatorsKeepASixtyFourBitOperandAtItsWidth()
    local source = [[
@aot
local function masks(a: uint64, b: uint64): (uint64, uint64, uint64, uint64)
    return a & b, a | b, a ~ b, ~a
end

@aot
local function shifted(a: uint64, n: uint64): (uint64, uint64)
    return a << n, a >> n
end

return {masks = masks, shifted = shifted}
]]
    local dir = project{["wide.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json wide.nupp")
    test.equal(code, 0, raw)
    for _, op in ipairs({"u64_and", "u64_or", "u64_xor", "u64_not", "u64_shl", "u64_shr"}) do
        assert(decoded.ir:find(op, 1, true), where .. ": missing opcode " .. op .. "\n" .. decoded.ir)
    end
    assert(
        decoded.c:find("(uint64_t)(p_a) & (uint64_t)(p_b)", 1, true),
        where .. ": the pattern keeps its width rather than narrowing to 32 bits\n" .. decoded.c
    )
    assert(
        decoded.c:find("UINT64_C(63)", 1, true),
        where .. ": a shift count is masked one bit wider than the 32-bit pair"
    )
end

function M.aThirtyTwoBitBitwiseOperandIsStillRefusedAtOtherWidths()
    local source = [[
@aot
local function bad(a: number, b: number): number
    return a & b
end

return {bad = bad}
]]
    local dir = project{["narrow.nupp"] = source}
    local out, code = run(dir, PINNED .. "--json narrow.nupp")
    assert(code ~= 0, "a binary64 operand names no width to operate on: " .. out)
    assert(out:find("fixed 32-bit values", 1, true), "the refusal still names the 32-bit rule: " .. out)
end

function M.aSwizzleIsTheTableLookupAndReachesTheTargetsTableInstruction()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function lookup(): (number, number, number)
    local species = assert(simd.species(array.uint8, 16))
    -- A table is a vector, so there is no table type and no constructor
    -- taking one entry per argument. Entry k here is ten times k.
    local table = species:iota(0, 10)
    local looked = table:swizzle(species:iota(1, 1))

    return looked:extract(1), looked:extract(16), table:swizzle(species:splat(200)):extract(3)
end

return {lookup = lookup}
]]
    local dir = project{["swizzle.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json swizzle.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_permute.swizzle", 1, true), where .. ": the lookup is one permutation\n" .. decoded.ir)
    assert(
        decoded.c:find("ks_exp_swizzle_u8x16", 1, true) and decoded.c:find("ks_scalar_exp_swizzle_u8x16", 1, true),
        where .. ": production and oracle bodies are both emitted"
    )
    assert(
        decoded.c:find("vqtbl1q_u8", 1, true),
        where .. ": a byte table reaches the target instruction rather than a lane loop"
    )
    assert(decoded.c:find("indices - 1", 1, true), where .. ": one-based lane numbering is adapted once, not per lane")
end

function M.aPairedSwizzleNumbersBothVectorsInOneRun()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function joined(): (number, number, number, number)
    local species = assert(simd.species(array.uint8, 16))
    local first = species:splat(1)
    local second = species:splat(2)
    -- Lane 1 reads first, lane 17 the first lane of second, 99 neither.
    local pick = species:iota(1, 1):insert(2, 17):insert(3, 99)
    local out = first:swizzle(pick, second)

    return out:extract(1), out:extract(2), out:extract(3), species.lanes
end

return {joined = joined}
]]
    local dir = project{["pair.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json pair.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.ir:find("simd_permute.swizzle_pair", 1, true),
        where .. ": the paired form is its own intrinsic\n" .. decoded.ir
    )
    assert(
        decoded.c:find(
            "ks_exp_swizzle_pair_u8x16",
            1,
            true
        ) and decoded.c:find("ks_scalar_exp_swizzle_pair_u8x16", 1, true),
        where .. ": production and oracle bodies are both emitted"
    )
    assert(
        decoded.c:find("vqtbl2q_u8", 1, true),
        where .. ": two byte tables reach the two-register table instruction rather than a lane loop"
    )
end

function M.aSwizzleNeedsLaneNumbersRatherThanAFloatingElement()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function bad(): number
    local species = assert(simd.species(array.float, 8))
    local values = species:iota(1.0, 1.0)

    return values:swizzle(values):extract(1)
end

return {bad = bad}
]]
    local dir = project{["badswizzle.nupp"] = source}
    local out, code = run(dir, "--target aarch64-apple-darwin --features neon --json badswizzle.nupp")
    assert(code ~= 0, "a float vector has no lane numbering to offer: " .. out)
    assert(out:find("integer vector", 1, true), "the refusal names what it needed: " .. out)
end

function M.horizontalExtremaNameTheirNanContractAndAreDefinedAtEveryElement()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function extrema(): (number, number, number, number)
    local species = assert(simd.species(array.float, 8))
    local values = species:iota(3.0, -1.0)
    local smallest: float = simd.horizontal.propagatingMin(values)
    local largest: float = simd.horizontal.propagatingMax(values)
    local lowAt = simd.horizontal.propagatingArgMin(values)
    local highAt = simd.horizontal.numberArgMax(values)
    return smallest, largest, lowAt, highAt
end

@aot
local function ignoringMissing(): (number, number)
    local species = assert(simd.species(array.float, 8))
    local values = species:iota(3.0, -1.0)
    local other = species:splat(0.5)

    return simd.horizontal.numberMin(values:numberMin(other)), simd.horizontal.numberArgMin(values)
end

@aot
local function counted(): (number, number)
    local species = assert(simd.species(array.int32, 8))
    local values = species:iota(3, -1)
    local clamped = values:propagatingMin(species:splat(1)):propagatingMax(species:splat(-1))
    return simd.horizontal.propagatingMin(clamped), simd.horizontal.propagatingArgMax(clamped)
end

return {extrema = extrema, counted = counted, ignoringMissing = ignoringMissing}
]]
    local dir = project{["extrema.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json extrema.nupp")
    test.equal(code, 0, raw)
    for _, intrinsic in ipairs({
        "simd_horizontal.propagating_min",
        "simd_horizontal.propagating_max",
        "simd_horizontal.propagating_arg_min",
        "simd_horizontal.number_arg_max",
        "simd_horizontal.number_min",
        "simd_horizontal.number_arg_min",
    }) do
        assert(decoded.ir:find(intrinsic, 1, true), where .. ": missing intrinsic " .. intrinsic .. "\n" .. decoded.ir)
    end
    assert(
        decoded.c:find("ks_exp_horizontal_propagating_min_f32x8", 1, true),
        where .. ": the production extremum is emitted"
    )
    assert(
        decoded.c:find("ks_scalar_exp_horizontal_number_arg_max_f32x8", 1, true),
        where .. ": the scalar executable reference is emitted"
    )
    -- The extremum bodies are authored C in ks_simd.h, instantiated for a
    -- fixed species by one line the compiler emits after the width block.
    local header = assert(io.open(HERE .. "/../src/nupp/compiler/aot/include/ks_simd.h", "rb")):read("*a")
    assert(
        decoded.c:find("KS_EXP_FIXED(f32x8, float, int32_t, 8, f32x4, 4, 2, FLOAT)", 1, true),
        where .. ": the f32x8 helpers are instantiated\n" .. decoded.c
    )
    assert(
        header:find("KS_EXP_EXTREMES_##KIND(exp, ELEM, CTYPE, LANES, CHUNKED)", 1, true),
        "a fixed species takes its extrema from the shared bodies"
    )
    assert(
        header:find("ks_##P##_propagating_min2_##ELEM(CTYPE left, CTYPE right) { if (left != left || right != right) { return ks_##P##_nan_##ELEM(); }", 1, true),
        "the propagating contract answers a canonical NaN"
    )
    assert(
        header:find("ks_##P##_number_min2_##ELEM(CTYPE left, CTYPE right) { if (left != left) { return right != right ? ks_##P##_nan_##ELEM() : right; }", 1, true)
            and header:find("KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, number, min)", 1, true)
            and decoded.c:find("ks_exp_number_min_f32x8(", 1, true),
        "the number-preferring contract is a separate body"
    )
    assert(header:find("signbit", 1, true), "both contracts order the two zeros by sign")
    assert(
        decoded.ir:find(
            "simd_horizontal.propagating_min",
            1,
            true
        ) and decoded.c:find("ks_exp_propagating_min_i32x", 1, true),
        where .. ": an extremum is defined at an integer element a sum is refused at\n" .. decoded.c
    )
    assert(
        decoded.c:find("KS_EXP_FIXED(i32x8, int32_t, int32_t, 8, i32x4, 4, 2, INT)", 1, true),
        where .. ": the i32x8 helpers are instantiated\n" .. decoded.c
    )
    assert(
        header:find("ks_##P##_##contract##_##which##2_##ELEM(CTYPE left, CTYPE right) { return left op right ? left : right; }", 1, true)
            and not decoded.c:find("ks_exp_nan_i32x", 1, true),
        where .. ": an integer extremum carries no NaN case"
    )
end

function M.horizontalSumsStillRefuseANonFloatingElement()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function total(): number
    local species = assert(simd.species(array.int32, 8))
    return simd.horizontal.orderedSum(species:iota(1, 1))
end

return {total = total}
]]
    local dir = project{["total.nupp"] = source}
    local out, code = run(dir, "--target aarch64-apple-darwin --features neon --json total.nupp")
    assert(code ~= 0, "an integer horizontal sum has no named rounding contract: " .. out)
    assert(out:find("NUPP2006", 1, true), "the refusal names the element requirement: " .. out)
    assert(out:find("floating%-point vector"), "the refusal names the element requirement: " .. out)
end

function M.compensatedReducerCarriesTheRoundingErrorEachAdditionDiscards()
    local source = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function total(borrows values: span.Span<number>): number
    local exact = simd.reducer.compensatedSum(0.0)
    @simd
    for i = 1, #values do
        exact:add(values[i])
    end

    return exact:value()
end

return {total = total}
]]
    local dir = project{["compensated.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json compensated.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.ir:find("reducer.compensated.sum", 1, true),
        where .. ": the exact contract is explicit\n" .. decoded.ir
    )
    assert(
        decoded.ir:find("simd.reducer.compensated.sum", 1, true),
        where .. ": the contribution carries its order\n" .. decoded.ir
    )
    assert(
        decoded.c:find("ks_compensated_f64_add", 1, true),
        where .. ": the compensated state has its own native form"
    )
    assert(decoded.c:find("KsCompensatedF64", 1, true), where .. ": the accumulator is more than one double")
    test.equal(
        decoded.functions[1].regions[1].reducers[1].serialized,
        true,
        where .. ": a compensated sum keeps its contribution edges"
    )
end

function M.fixedExplicitSimdSplitsIntoNativeRegistersWithoutChangingItsIdentity()
    -- Only the lane count is added. One constructor serves both shapes, which
    -- is the point: nothing else at the call site says which one it built.
    local source = GENERIC_EXPLICIT_SIMD:gsub("array%.float%)", "array.float, 8)", 1)
    local dir = project{["vectors.nupp"] = source}
    local c, cCode = run(dir, "--target aarch64-apple-darwin --features neon --emit c vectors.nupp")
    test.equal(cCode, 0, c)
    assert(
        c:find("KS_EXP_FIXED(f32x8, float, int32_t, 8, f32x4, 4, 2, FLOAT)", 1, true),
        "Fixed<8> is two native NEON registers: " .. c
    )
    local header = assert(io.open(HERE .. "/../src/nupp/compiler/aot/include/ks_simd.h", "rb")):read("*a")
    assert(
        header:find("typedef struct { ks_exp_##NATIVE chunk[CHUNKS]; } ks_exp_##ELEM;", 1, true),
        "a fixed species is an aggregate of native vectors"
    )

    local asm = neonAsm(dir, "vectors.nupp")
    if asm ~= nil then
        local _, adds = asm:gsub("fadd%.4s", "")
        assert(adds >= 2, "both logical halves execute as vector additions: " .. asm)
    end
end

function M.explicitSimdValuesCannotCrossAnEntryAbi()
    local source = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function leaked(): simd.Vector<float, simd.Preferred>
    local species = assert(simd.species(array.float))
    return species:splat(1.0)
end

return {leaked = leaked}
]]
    local dir = project{["leaked.nupp"] = source}
    local out, code = run(dir, "leaked.nupp")
    test.equal(code, 1, out)
    assert(out:find("cannot cross an AOT entry result ABI", 1, true), out)
end

function M.genericHelpersPreserveSpeciesAndKeepASeparateScalarTwin()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

local function twice<T, S>(value: simd.Vector<T, S>): simd.Vector<T, S>
    return value + value
end

@aot
local function apply(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    local species = assert(simd.species(array.float))
    local active = species:tail(#input)
    species:store(output, 1, twice(species:load(input, 1, active)), active)
end

return {apply = apply}
]]
    local dir = project{["helper.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json helper.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.ir:find("twice_simd_vector_f32_preferred", 1, true),
        where .. ": helper specialization retains species"
    )
    assert(
        decoded.c:find("twice_simd_vector_f32_preferred_returns_simd_vector_f32_preferred_forced_scalar", 1, true),
        where .. ": scalar oracle gets a type-correct helper twin"
    )
end

function M.explicitLaneAndBitmaskOperationsKeepOneBasedLaneIdentity()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function inspect(borrows input: span.Span<float>): (float, uint32, integer)
    local species = assert(simd.species(array.float, 8))
    local active = species:tail(#input)
    local values = species:load(input, 1, active):insert(2, 3.0)
    local bits = (values > 0.0):bits()
    local first: integer = 0
    if bits ~= 0 then
        first = nupp.math.u64.trailingZeros(bits) + 1
    end
    return values:extract(2), nupp.math.u64.popcount(bits), first
end

return {inspect = inspect}
]]
    local dir = project{["inspect.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json inspect.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_insert.insert", 1, true), where .. ": insertion remains intrinsic")
    assert(decoded.ir:find("simd_extract.extract", 1, true), where .. ": extraction remains intrinsic")
    assert(decoded.ir:find("u64_popcount", 1, true), where .. ": uint64 population count remains intrinsic")
    assert(decoded.ir:find("u64_ctz", 1, true), where .. ": bit zero maps back to lane one")
    assert(decoded.c:find("(uint32_t)lane - 1u", 1, true), where .. ": C uses the documented one-based lane convention")
end

function M.uint64MaskBitsReplaceTheFixedSixtyFourBitHelperSurface()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function inspect(borrows input: span.Span<float>): (uint32, integer, boolean, boolean)
    local species = assert(simd.species(array.float, 8))
    local values = species:load(input, 1, species:tail(#input))
    local positive = (values > 0.0):bits()
    local large = (values >= 4.0):bits()
    local allBits = species:tail(species.lanes):bits()
    local shift: uint64 = 1
    local selected = (~((positive | large) & positive) << shift) & allBits
    local parity = nupp.math.u64.prefixXor(selected) & allBits
    local first: integer = 0
    if parity ~= 0 then
        first = nupp.math.u64.trailingZeros(parity) + 1
    end
    return nupp.math.u64.popcount(parity), first, parity ~= 0, parity == allBits
end

return {inspect = inspect}
]]
    local dir = project{["bits.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, "--target aarch64-apple-darwin --features neon --json bits.nupp")
    test.equal(code, 0, raw)
    for _, op in ipairs({"u64_or", "u64_not", "u64_shl", "u64_prefix_xor", "u64_popcount", "u64_ctz"}) do
        assert(decoded.ir:find(op, 1, true), where .. ": missing uint64 operation " .. op .. "\n" .. decoded.ir)
    end
    assert(decoded.c:find("ks_bits ^= ks_bits << 32u", 1, true), where .. ": the native contract executes all 64 bits")
    assert(decoded.c:find("ks_inspect_forced_scalar", 1, true), where .. ": the independent scalar oracle remains")
end

function M.productAndDotReducersCarryDistinctArithmeticContracts()
    local source = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function reductions(borrows values: span.Span<number>): (number, number)
    local product = simd.reducer.pairwiseProduct(1.0)
    @simd
    for i = 1, #values do
        product:multiply(values[i])
    end

    local dot = simd.reducer.algebraicDot(0.0)
    @simd
    for i = 1, #values do
        dot:add(values[i], values[i])
    end
    return product:value(), dot:value()
end


return {reductions = reductions}
]]
    local dir = project{["reducers.nupp"] = source}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json reducers.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.ir:find("simd.reducer.pairwise.product", 1, true),
        where .. ": product order and operation are explicit"
    )
    assert(decoded.ir:find("simd.reducer.algebraic.dot", 1, true), where .. ": dot contraction permission is distinct")
    assert(decoded.c:find("ks_pairwise_f64_product_add", 1, true), where .. ": product uses a multiplication tree")
    assert(decoded.c:find("simd_acc_", 1, true), where .. ": algebraic dot uses lane accumulators")
end

-- The lane body out of `--emit ir`, which is what a helper call and the same source
-- written inline have to agree on. The scalar body cannot be compared directly: one
-- spelling carries a `helper_call` and the other carries the expression, which is the
-- difference the inline is supposed to erase by the time lanes are chosen.

--- The vector body inside one pinned report's IR, and the report it came out of.
---
--- `--json` carries the IR beside everything else the run measured, so a case
--- that wants both the vector body and what the optimizer did to it asks once.
local function vectorReport(dir, file, label)
    local decoded, out, code, where = lowered(dir, PINNED .. "--json " .. file)
    test.equal(code, 0, label .. " (" .. where .. "): " .. out)
    local ir = decoded.ir
    local vector = ir:match("(\nsimd vector\n.*)$")
    assert(
        vector,
        label .. " ran one iteration at a time, so there is no vector body to compare (" .. where .. "):\n" .. out
    )

    -- Unrolling a counted loop wraps each copy in a `block`, which the rewrite
    -- carries through to the vector body as an ordinary scope. It is the one
    -- difference between a loop and the same work written out, and it is not a
    -- difference in the vectorized work, so it is normalized away here rather
    -- than asserted about.
    local lines = {}
    for line in (vector .. "\n"):gmatch("([^\n]*)\n") do
        local bare = line:match("^%s*(.-)%s*$")
        if bare ~= "block" then
            lines[#lines + 1] = bare
        end
    end

    return table.concat(lines, "\n"), decoded
end

local function vectorIr(dir, file, label)
    return (vectorReport(dir, file, label))
end

-- Both spellings of one kernel: the predicate behind a helper, and the same predicate
-- written where it is used. Derived from one source so the two cannot drift apart.
local function bothSpellings(inlined, predicate, call, helper)
    local withHelper = inlined:gsub("@aot\n", helper .. "\n\n@aot\n", 1):gsub(predicate, call)
    assert(withHelper ~= inlined, "the predicate moved behind the helper")

    return withHelper, inlined
end

function M.aHelperCallLowersToTheSameVectorIrAsWritingItInline()
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
    test.equal(vectorIr(dir, "helper.nupp", "the helper spelling"), vectorIr(dir, "inline.nupp", "the inline spelling"))
end

function M.aNumericHelperCallLowersToTheSameVectorIrAsWritingItInline()
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
    test.equal(vectorIr(dir, "helper.nupp", "the helper spelling"), vectorIr(dir, "inline.nupp", "the inline spelling"))
end

function M.aFourTripLoopLowersToTheSameVectorIrAsWritingItOut()
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
    local fixed, report = vectorReport(dir, "loop.nupp", "the fixed loop")
    test.equal(fixed, vectorIr(dir, "written.nupp", "the written body"))

    -- The same report the lane body came out of also says what unrolled it.
    local optimization = report.functions[1].optimization
    test.equal(optimization.unrolledLoops, 1)
    test.equal(optimization.unrolledIterations, 4)
end

-- `--emit simd` and the round trip that says it is the same program.
--
-- `@simd` has no vector IR of its own any more: a marked loop is rewritten onto
-- the explicit `simd_*` operations over `Fixed<N>` species, and `--emit simd`
-- prints that rewrite as the Nupp somebody could have written instead. What
-- makes the printer worth having rather than decorative is that the printed
-- source is the same program: it checks, and the region it lowers to is the
-- region the `@simd` loop lowered to.
--
-- Two differences are read past rather than asserted about, because neither is
-- a difference in the vectorized work. A map-shaped kernel takes one `count`
-- for the spans its range guard proved equal where an ordinary function takes
-- one per span; and every generated C local carries the ordinal of the IR
-- binding behind it, which the printed spelling numbers from its own bindings.

--- One generated function's body, with those two differences normalized away.
---
--- Block braces, the `#pragma` a contract carries and the scalar loop bounds a
--- map-shaped entry declares for the oracle beside it are dropped for the same
--- reason: they are the entry's shape rather than the region's work.
local function generatedBody(c, symbol, label)
    local lines = {}
    local inside = false
    local found = false
    for line in (c .. "\n"):gmatch("([^\n]*)\n") do
        if inside and line == "}" then
            inside = false
        elseif inside then
            local bare = line:match("^%s*(.-)%s*$")
            local shape = bare == ""
                or bare == "{"
                or bare == "}"
                or bare:match("^#")
                or bare:match("^%(void%)[%w_]+;$")
                or bare:match("^size_t [%w_]+ = .*;$")
            if not shape then
                lines[#lines + 1] = bare
            end
        elseif line:match("^KS_API .-[ %*]" .. symbol .. "%(") then
            inside = true
            found = true
        end
    end
    assert(found, label .. ": the generated C has no " .. symbol)
    local body = table.concat(lines, " ")
    body = body:gsub("count_[%a_][%w_]*", "count")
    body = body:gsub("%f[%w]v%d+_", ""):gsub("%f[%w]sr%d+_", "")
    body = body:gsub("%f[%w]as%d+%f[%W]", "as")

    return body
end

--- Prints one file's rewrite, compiles the printed source, and holds the two
--- generated regions to each other.
local function roundTrip(files, file, symbol, label)
    local dir = project(files)
    local printed, printedCode = run(dir, PINNED .. "--emit simd " .. file)
    test.equal(printedCode, 0, label .. ": --emit simd refused:\n" .. printed)
    local original, originalCode = run(dir, PINNED .. "--emit c " .. file)
    test.equal(originalCode, 0, label .. ": " .. original)

    -- Compiling the printed source checks it: a diagnostic is a nonzero status
    -- and the diagnostic itself, which is what a failure here reports.
    local again, againCode = run(project{["printed.nupp"] = printed}, PINNED .. "--emit c printed.nupp")
    test.equal(againCode, 0, label .. ": the printed rewrite did not compile:\n" .. again .. "\n" .. printed)
    test.equal(
        generatedBody(again, symbol, label),
        generatedBody(original, symbol, label),
        label .. ": the printed rewrite lowered to different C\n" .. printed
    )

    return printed
end

function M.theMandelbrotRewritePrintsAsNuppThatLowersToTheSameVectorC()
    -- The kernel the vectorizer is measured on: two binary32 fields gathered
    -- from an array of structs, a per-lane escape loop with a break in it, and
    -- two narrowing field stores. Read from the bench tree rather than copied,
    -- so the thing that round-trips is the thing that is benchmarked.
    local path = HERE .. "/../bench/kernel-subset-spike/mandelbrot.nupp"
    local handle = assert(io.open(path, "rb"), "the mandelbrot kernel is missing")
    local source = handle:read("*a")
    handle:close()

    local printed = roundTrip({["mandelbrot.nupp"] = source}, "mandelbrot.nupp", "ks_mandelbrot", "mandelbrot")

    -- The vocabulary it is printed in, which is the point of printing it: a
    -- species per element, the masked tail, and the per-lane loop as a mask.
    for _, spelling in ipairs({
        "assert(simd.species(array.number, 4))",
        "assert(simd.species(array.float, 4))",
        's_f32_x4:load(points, base1 + 1, "re")',
        "while base1 + s_f64_x4.lanes <= #points",
        "s_f64_x4:tail(last - base1)",
        ":any() do",
        ":select(",
    }) do
        assert(printed:find(spelling, 1, true), "the printed rewrite does not say " .. spelling .. ":\n" .. printed)
    end
end

function M.aVaryingNestedLoopWithAPerLaneBreakPrintsAsNuppThatLowersToTheSame()
    -- The control-flow case: an inner trip count that differs per lane and a
    -- break inside it, which is the live mask, the execution mask and the
    -- iota-derived bound all at once.
    local printed = roundTrip({["required.nupp"] = REQUIRED_VARYING_FOR}, "required.nupp", "ks_varying", "varying")
    assert(printed:find("s_i32_x4:iota(", 1, true), "the loop index is an iota:\n" .. printed)
    assert(printed:find("s_f64_x4:mask(", 1, true), "the i32 comparison converts to the control mask:\n" .. printed)
end

function M.twoReducerRegionsInOneBodyPrintAsNuppThatLowersToTheSame()
    -- Two regions in one function, each with its own contract, and each naming
    -- its cursor the same thing: the printed scopes are what keep that legal,
    -- because a native local may not shadow another.
    local source = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function reductions(borrows values: span.Span<number>): (number, number)
    local product = simd.reducer.pairwiseProduct(1.0)
    @simd
    for i = 1, #values do
        product:multiply(values[i])
    end

    local dot = simd.reducer.algebraicDot(0.0)
    @simd
    for i = 1, #values do
        dot:add(values[i], values[i])
    end
    return product:value(), dot:value()
end


return {reductions = reductions}
]]
    local printed = roundTrip({["reducers.nupp"] = source}, "reducers.nupp", "ks_reductions", "reducers")
    assert(printed:find("simd.reducer.pairwiseProduct(1.0)", 1, true), "the contract survives:\n" .. printed)
    assert(printed:find(":multiply(", 1, true), "a product is contributed by multiplying:\n" .. printed)
    assert(printed:find("s_f64_x4:mask(true)", 1, true), "a whole group contributes every lane:\n" .. printed)
end

function M.aCorrectedBinary32RegionPrintsAsNuppThatLowersToTheSame()
    -- The lane-wise corrections, which the rewrite applies one lane at a time
    -- rather than computing in binary64: `min` and `max` become vector
    -- intrinsics and `fma` stays a per-lane call, so printing it needs the
    -- `s:map(nupp.math.f32.fma, ...)` spelling on the way back in.
    local source = [[
local span = require("nupp.mem.span")

local struct Sample
    a: float
    b: float
    c: float
end

local struct Result
    least: float
    greatest: float
    fused: float
end

@aot
local function corrected(
    exclusive results: span.WriteSpan<Result>,
    borrows samples: span.Span<Sample>,
    first: integer,
    last: integer
): nil
    assert(#results == #samples, "length mismatch")
    assert(first >= 1 and last <= #results and first <= last + 1, "range out of bounds")

    @simd
    for i = first, last do
        local result = results[i]
        local sample = samples[i]
        local a = nupp.math.f32.narrow(sample.a)
        local b = nupp.math.f32.narrow(sample.b)
        local c = nupp.math.f32.narrow(sample.c)
        result.least = nupp.math.f32.min(a, b)
        result.greatest = nupp.math.f32.max(a, b)
        result.fused = nupp.math.f32.fma(a, b, c)
    end
end

return {corrected = corrected, Sample = Sample, Result = Result,}
]]
    local printed = roundTrip({["corrected.nupp"] = source}, "corrected.nupp", "ks_corrected", "corrected")
    assert(printed:find("s_f32_x8:map(nupp.math.f32.fma,", 1, true), "the fused lane call:\n" .. printed)
    assert(printed:find(":propagatingMin(", 1, true), "the corrected minimum:\n" .. printed)
end

function M.aFileWithNoVectorizedLoopPrintsNothingForSimd()
    local source = [[
local span = require("nupp.mem.span")

@aot
local function total(borrows values: span.Span<number>): number
    local sum = 0.0
    for i = 1, #values do
        sum = sum + values[i]
    end
    return sum
end

return {total = total}
]]
    local dir = project{["scalar.nupp"] = source}
    local out, code = run(dir, PINNED .. "--emit simd scalar.nupp")
    test.equal(code, 1, out)
    assert(out:find("was vectorized", 1, true), "it says there is no rewrite to show: " .. out)
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

function M.aLaneBodyRefusesRatherThanCallingAnEntryPerLane()
    -- A compiled entry takes one set of scalars and answers once, so there is no
    -- per-lane form of it. The refusal names that, rather than the loop quietly
    -- running scalar for a reason nothing reports.
    local source = COMPUTE:gsub(
        "@aot\n",
        "@aot\nlocal function beyondFour(a: number, b: number): number\n" .. "    return a + b - 4.0\nend\n\n@aot\n",
        1
    )
        :gsub("if zxSquared %+ zySquared > 4%.0 then", "if beyondFour(zxSquared, zySquared) > 0.0 then")
    local dir = project{["perlane.nupp"] = source}
    local out, code = run(dir, "perlane.nupp")
    test.equal(code, 1, "a @simd loop that cannot run in lanes fails the build\n" .. out)
    assert(
        out:find("cannot call a compiled entry", 1, true),
        "the refusal names the call, not just the outcome: " .. out
    )
end

function M.emitPrintsTheGeneratedC()
    local dir = project{["compute.nupp"] = COMPUTE}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json compute.nupp")
    test.equal(code, 0, raw)

    local out = decoded.c
    assert(out:find("void ks_escapes(", 1, true), where .. ": the exported symbol is defined: " .. out)
    assert(
        out:find("ks_escapes_forced_scalar", 1, true),
        where .. ": the oracle the lane body is diffed against comes out too: " .. out
    )
    assert(
        out:find("*restrict", 1, true),
        where .. ": the writable span carries the disjointness ownership proved: " .. out
    )
    assert(
        out:find("ks_exp_select_f64x4", 1, true),
        where .. ": the conditional became a select rather than a branch: " .. out
    )
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
                "local valuebuilder = require(\"nupp.codec.valuebuilder\")",
                "@aot",
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
    -- `--json` so the binding it also carries needs no second command.
    local decoded, raw, code, where = lowered(dir, "--json counter.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.binding:find("nupp.math.u32.wrap(native1 as integer)", 1, true),
        where .. ": the single result is established rather than returned as any: " .. decoded.binding
    )
    assert(decoded.ir, where .. ": and the checked run still reports the IR it judged: " .. raw)
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
    -- The two that make every exact floating differential mean anything. Losing
    -- either one is visible as a low bit that moved in some other suite, a long
    -- way from the line that caused it, so it is named here as well.
    for _, flag in ipairs({"-ffp-contract=off", "-fno-fast-math"}) do
        assert(flags:find(flag, 1, true), "the numeric contract is on the command line: " .. flags)
    end

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
    assert(vector > 0, "a body that lowered has vector instructions to show for it: " .. out)
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
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json compute.nupp")
    test.equal(code, 0, raw)

    local ir = decoded.ir
    assert(ir:find("simd vector", 1, true), where .. ": the vector body is in the IR beside the scalar one: " .. ir)
    assert(ir:find("disjoint r0 r1", 1, true), where .. ": the alias matrix is in the IR: " .. ir)

    local binding = decoded.binding
    assert(
        binding:find("layoutof(Escape)", 1, true),
        where .. ": the wrapper checks the struct layout rather than trusting it: " .. binding
    )
    assert(binding:find("unsafe do", 1, true), where .. ": the foreign call is the only unsafe part: " .. binding)
end

function M.narrowScalarSpansKeepTheirStorageAndUseLanes()
    local dir = project{["bytes.nupp"] = BYTE_CLASSIFIER}

    -- One pinned command for both artifacts; the exit status is the one that
    -- says the loop got its lanes.
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json bytes.nupp")
    test.equal(code, 0, raw)

    local ir = decoded.ir
    assert(
        ir:find("flags:u32 source(uint8)", 1, true),
        where .. ": the IR distinguishes storage from its established value: " .. ir
    )
    assert(
        ir:find("simd_load.load:simd_vector_u8_fixed8", 1, true),
        where .. ": a byte load keeps its own species and is converted from it: " .. ir
    )
    assert(
        ir:find("simd_store.store:lua_effect", 1, true),
        where .. ": a scalar span store is written from the vector: " .. ir
    )

    local c = decoded.c
    assert(c:find("uint8_t *restrict p_flags", 1, true), where .. ": the output pointer retains byte storage: " .. c)
    assert(c:find("const uint8_t *p_bytes", 1, true), where .. ": the input pointer retains const byte storage: " .. c)
    assert(
        c:find("ks_exp_store_full_u8x8(p_flags", 1, true),
        where .. ": lane values narrow only when stored: " .. c
    )

    local binding, bindingCode = run(dir, "--emit binding bytes.nupp")
    test.equal(bindingCode, 0, binding)
    assert(binding:find("exclusive flags: uint8*", 1, true), binding)
    assert(binding:find("borrows bytes: const uint8*", 1, true), binding)
    assert(binding:find("span.WriteSpan<uint8>", 1, true), binding)
end

local ONE_PUBLISH = [[
module publishing

local valuebuilder = require("nupp.codec.valuebuilder")

local publishing = {}

local function u32(value: integer): uint32
    return nupp.math.u32.wrap(value)
end

@aot
local function once(source: string, nullValue: any): any
    local builder = valuebuilder.newSized(nullValue, u32(2), u32(16))
    local scratch = valuebuilder.newByteScratch(u32(16))
    valuebuilder.setScratchByte(scratch, u32(0), valuebuilder.byte(source, u32(0)))
    valuebuilder.stringScratch(builder, scratch, u32(0), u32(1))
    return valuebuilder.finish(builder)
end

@aot
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

    local decoded, raw, code = lowered(dir, "--json publishing.nupp")
    test.equal(code, 0, raw)

    local ir = decoded.ir
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
    local c = decoded.c
    local _, cached = c:gsub("ks_lua_scratch_u8_cached%(L,", "")
    local _, plain = c:gsub("= ks_lua_scratch_u8%(L,", "")
    test.equal(cached, 1, "one entry takes the cached buffer: " .. c)
    test.equal(plain, 1, "the other allocates its own: " .. c)
end

function M.blockKernelsAppendUnderDominatingCapacityChecks()
    local dir = project{["delimiters.nupp"] = DELIMITERS}
    local decoded, raw, code = lowered(dir, "--json delimiters.nupp")
    test.equal(code, 0, raw)

    local c = decoded.c
    assert(c:find("uint32_t ks_delimiters(", 1, true), "the scalar result crosses the native ABI: " .. c)
    assert(c:find("size_t count_source, size_t count_offsets", 1, true), "the two spans keep independent counts: " .. c)
    assert(c:find("p_offsets[((size_t)v", 1, true), "the proved zero-based cursor directly indexes the output: " .. c)

    local ir = decoded.ir
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
    local decoded, raw, code = lowered(dir, "--json positions.nupp")
    test.equal(code, 0, raw)

    local ir = decoded.ir
    assert(
        ir:find("store offsets[written+1] = numeric_cast(int_to_f64(local:i32 i))", 1, true),
        "the promotion is written into the IR rather than left to the emitter: " .. ir
    )

    -- And the emitter collapses it, because a widen immediately narrowed back
    -- to the width it came from is the value. The reduction the conversion
    -- otherwise carries -- `wrap` is modular, and a C cast is not -- has
    -- nothing to reduce here, so paying for it would be undoing the promotion's
    -- own work.
    local c = decoded.c
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

@aot
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
    assert(baseline:find("#define KS_SIMD_WIDTH 16", 1, true), baseline)
    assert(baseline:find("ks_load_u8x16", 1, true), baseline)

    local avx, avxCode = run(dir, "--target x86_64-unknown-linux-gnu --features avx2 --emit c simd.nupp")
    test.equal(avxCode, 0, avx)
    assert(avx:find("#define KS_SIMD_WIDTH 32", 1, true), avx)
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

@aot
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

-- A rooted byte view names an entry's own parameter, and only a parameter: a
-- local holding anything else is not what the load addresses.
function M.rootedByteViewsRequireAnEntryParameter()
    local dir = project{
        [
            "local-view.g.nupp"
        ] = [[
local array = require("nupp.mem.array")
local builder = require("nupp.codec.valuebuilder")
local simd = require("nupp.simd")

@aot
local function quotes(source: string, nullValue: any): (any, uint32, uint32)
    local rooted = "not the parameter"
    local count = builder.length(source)
    local state = builder.newSized(nullValue, count, count)
    local found: uint32 = 0
    if species = simd.species(array.uint8) then
        local bytes = builder.bytes(rooted)
        found = (species:load(bytes, 1) == 34):count()
    end
    builder.null(state)
    return builder.finish(state), found, 0
end

return {quotes = quotes}
]]
    }
    local out, code = run(dir, "local-view.g.nupp")
    test.equal(code, 1, out)
    assert(out:find("rooted string parameter", 1, true), out)
end

-- The view is a name for a pointer and a length rather than a value, so
-- nothing but a vector load may read it, and the refusal says so at the read.
function M.rootedByteViewsAreNotValues()
    local dir = project{
        [
            "escaped-view.g.nupp"
        ] = [[
local builder = require("nupp.codec.valuebuilder")

@aot
local function quotes(source: string, nullValue: any): (any, uint32, uint32)
    local count = builder.length(source)
    local state = builder.newSized(nullValue, count, count)
    local bytes = builder.bytes(source)
    local kept = bytes
    builder.null(state)
    return builder.finish(state), 0, 0
end

return {quotes = quotes}
]]
    }
    local out, code = run(dir, "escaped-view.g.nupp")
    test.equal(code, 1, out)
    assert(out:find("a vector load may read it and nothing else", 1, true), out)
end

-- The load through a view is the unchecked one under the same guard a span
-- parameter's load is proved by, and the checked one without it. Both read the
-- parameter's own pointer and length, which is the whole point: a value-building
-- entry's parameters cross the Lua stack and a span cannot.
function M.rootedByteViewsCarryTheSameCursorProof()
    local dir = project{
        [
            "rooted.g.nupp"
        ] = [[
local array = require("nupp.mem.array")
local builder = require("nupp.codec.valuebuilder")
local simd = require("nupp.simd")
local {type Buffer} = require("nupp.text")

@aot
local function quotes(borrows source: string | Buffer, nullValue: any): (any, uint32, uint32)
    local count = builder.length(source)
    local state = builder.newSized(nullValue, count, count)
    local cursor: uint32 = 0
    local found: uint32 = 0
    local loose: uint32 = 0
    if species = simd.species(array.uint8) then
        local bytes = builder.bytes(source)
        loose = (species:load(bytes, 1) == 34):count()
        while cursor + species.lanes <= count do
            found = found + (species:load(bytes, cursor + 1) == 34):count()
            cursor = cursor + species.lanes
        end
    end
    builder.null(state)
    return builder.finish(state), found, loose
end

return {quotes = quotes}
]]
    }
    local decoded, raw, code, where = lowered(dir, "--json rooted.g.nupp")
    test.equal(code, 0, raw)
    assert(decoded.ir:find("simd_load.load", 1, true), where .. "\n" .. decoded.ir)
    assert(decoded.ir:find("span:source", 1, true), where .. ": the parameter is the load's root\n" .. decoded.ir)
    assert(
        decoded.c:find("ks_exp_load_at_u8x16(ks_bytes_1 + (size_t)", 1, true),
        where .. ": the guarded load reads the parameter's own bytes unchecked\n" .. decoded.c
    )
    assert(
        decoded.c:find("ks_exp_load_full_u8x16(ks_bytes_1, ks_length_1", 1, true),
        where .. ": an unproved load keeps the parameter's length\n" .. decoded.c
    )
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

function M.jsonCarriesTheRegionAndItsGang()
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
    test.equal(#only.regions, 1, "the map loop is the one @simd region")
    test.equal(only.regions[1].gang.lanes, 4)
    test.equal(only.regions[1].gang.species.f64, "simd_vector_f64_fixed4")
    test.equal(#only.loops, 1)
    test.equal(only.loops[1].kind, "map")
    test.equal(only.loops[1].outcome, "lowered")
    test.equal(only.loops[1].line, only.regions[1].line, "the loop and the region are the same source line")
    assert(only.loops[1].nodes > 0)
    assert(decoded.ir and decoded.c and decoded.binding, "all three artifacts are carried")
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

@aot
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

    @simd
    for i = first, last do
        local sample = samples[i]
        local input = source[i]
        sample.value = input.value * factor + input.weight
        sample.weight = input.weight * factor
    end
end

@aot
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

    @simd
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
    local decoded, out, code = lowered(dir, PINNED .. "--json two.nupp")
    test.equal(code, 0, out)
    test.equal(#decoded.functions, 2, "both functions are reported")
    test.equal(decoded.functions[1].name, "scale", "in source order")
    test.equal(decoded.functions[2].name, "brighten")
    test.equal(decoded.functions[1].regions[1].gang.lanes, 4, "a binary64 value takes four lanes of 32 bytes")
    test.equal(
        decoded.functions[1].regions[1].gang.species.f64,
        "simd_vector_f64_fixed4",
        "and the species each element is carried in is reported"
    )
    test.equal(decoded.functions[2].regions[1].gang.lanes, 8, "explicit binary32 takes eight")

    -- One struct declared once, both gangs in use, and each function bringing
    -- its own pair of bodies.
    local c = decoded.c
    test.equal(select(2, c:gsub("} KsSample;", "")), 1, "the shared struct is declared once")
    assert(
        c:find("ks_exp_splat_f64x4(p_factor)", 1, true) and c:find("ks_exp_splat_f32x8(p_lift)", 1, true),
        "each function's body runs on the species it chose"
    )
    test.equal(
        select(2, c:gsub("float nupp_f32_nan", "")),
        1,
        "the helpers no gang owns appear once however many gangs the file uses"
    )
    for _, symbol in ipairs({"ks_scale", "ks_scale_forced_scalar", "ks_brighten", "ks_brighten_forced_scalar"}) do
        assert(c:find("void " .. symbol .. "(", 1, true), symbol .. " is defined")
    end

    local binding = decoded.binding
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
    local decoded, out, code, where = lowered(dir, "--json --target x86_64-unknown-linux-gnu compute.nupp")
    test.equal(code, 0, "plain x86-64 vectorises rather than refusing\n" .. out)
    test.equal(decoded.target.tier, "baseline", where .. ": and did not quietly promise instructions nobody asked for")
    test.equal(
        decoded.functions[1].regions[1].gang.lanes,
        2,
        where .. ": half the lanes of AVX, which is the point: a smaller win, not no win"
    )
end

function M.aWiderTierGetsTheWiderGang()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx2 compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.triple, "x86_64-unknown-linux-gnu")
    test.equal(decoded.target.tier, "avx2", "the tier is reported, because it changed the answer")
    test.equal(decoded.functions[1].regions[1].gang.lanes, 4)
end

function M.theAvx512TierGetsEightMixedLanes()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx512f compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.tier, "avx512f")
    test.equal(decoded.functions[1].regions[1].gang.lanes, 8)
    assert(
        decoded.c:find("ks_exp_f64x8", 1, true) and decoded.c:find("ks_exp_mask_f64x8", 1, true),
        "the eight-lane species carries binary64 values and masks at 64 bytes"
    )
end

function M.anAll32BitLoopFillsTheTierWithNarrowLanes()
    -- A lane is one logical iteration, so the lane count is the tier divided by
    -- the widest element the region touches. Nothing here is wider than 32 bits,
    -- so sixteen iterations fit a 64-byte register rather than eight.
    local dir = project{["classify.nupp"] = BYTE_CLASSIFIER}
    local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx512f classify.nupp")
    test.equal(code, 0, out)
    local gang = require("testjson").decode(out).functions[1].regions[1].gang
    test.equal(gang.lanes, 16, "sixteen 32-bit lanes fill the tier")
    test.equal(gang.species.f64, nil, "and no binary64 species is chosen for a region with no binary64 value")
end

function M.theWidestGangThatFitsWins()
    -- Both widths are available at avx2, so the choice has to be the wider one.
    -- Preference used to come from the order the shapes were listed in, which
    -- would have picked four narrow lanes over four wide ones here.
    local dir = project{["compute.nupp"] = COMPUTE}
    local out = select(1, run(dir, "--json --target x86_64-unknown-linux-gnu --features avx2 compute.nupp"))
    local decoded = require("testjson").decode(out)
    test.equal(decoded.functions[1].regions[1].gang.lanes, 4, "not two, which also fits and holds half as much")
end

function M.armHasOneTierAndNeedsNoSelection()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target aarch64-apple-darwin compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.tier, "neon", "its 16-byte registers are mandatory, so there is nothing to opt into")
    test.equal(
        decoded.functions[1].regions[1].gang.lanes,
        4,
        "and a region pairs two of them, which holds four binary64 lanes"
    )
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
@aot
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
@aot
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

function M.valueStreamsFuseRootedByteReadsAndLuaConstruction()
    local dir = project{
        [
            "nupp/codec/valuebuilder.nupp"
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
local builder = require("nupp.codec.valuebuilder")
local simd = require("nupp.simd")
local function drain(bits: simd.MaskBits64): (uint32, uint32)
    return bits:firstSet(), bits:clearFirst():count()
end
@aot
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
    local species = simd.preferredU8()
    local lookup = simd.tableU8x16(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
    local bytes = species:loadString(source, nupp.math.u32.wrap(0))
    local previous = species:splat(nupp.math.u32.wrap(0))
    local aligned = simd.alignBytes(previous, bytes, nupp.math.u32.wrap(1))
    local classified = aligned:lookup16(lookup)
    local quotes = bytes:equal(34):count()
    local classes = classified:equal(1):count()
    local shifted = nupp.math.u32.shiftLeft(nupp.math.u32.wrap(1), nupp.math.u32.wrap(3))
    local rawWide = simd.maskBits64(shifted, nupp.math.u32.wrap(1))
    local wide = rawWide:prefixXor(false)
    local first, left = drain(wide)
    local next = builder.appendSetBits(scratch, nupp.math.u32.wrap(0), count, wide)
    local stringNext = builder.appendStringBits(
        scratch,
        nupp.math.u32.wrap(0),
        count,
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
        nupp.math.u32.add(direct, nupp.math.u32.add(packedState, nupp.math.u32.add(quotes, nupp.math.u32.add(classes, nupp.math.u32.add(first, nupp.math.u32.add(left, nupp.math.u32.add(next, stringNext)))))))
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
    assert(decoded.ir:find("lua.scratch_u32", 1, true), decoded.ir)
    assert(decoded.ir:find("simd_load_string_u8", 1, true), decoded.ir)
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
            "nupp/codec/valuebuilder.nupp"
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
local builder = require("nupp.codec.valuebuilder")

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
            "nupp/codec/valuebuilder.nupp"
        ] = [[
local builder = {}
function builder.byteAt(bytes: string, offset: uint32): uint32 return offset end
return builder
]],
        [
            "read.g.nupp"
        ] = [[
local builder = require("nupp.codec.valuebuilder")
@aot
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
local valueBuilder = require("nupp.codec.valuebuilder")

const CLASSES = "\1\2\34\92"
const QUOTED = 'a"b'

@aot
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

function M.aLengthAliasDoesNotOutliveItsScope()
    -- `n` was the string's length in the inner block. The outer `n` is a
    -- number that has nothing to do with the string, and the read it guards
    -- has no bounds proof. Lowering once kept the inner fact under the outer
    -- name, and the verifier caught it -- as a traceback with no line in it.
    local dir = project{
        [
            "stale.g.nupp"
        ] = [[
local builder = require("nupp.codec.valuebuilder")
@aot
local function decode(source: string): uint32
    do
        local n = builder.length(source)
    end
    local n: uint32 = nupp.math.u32.wrap(100)
    local cursor: uint32 = nupp.math.u32.wrap(50)
    local direct: uint32 = nupp.math.u32.wrap(0)
    if cursor < n then
        direct = builder.byteAt(source, cursor)
    end
    return direct
end
return {decode = decode}
]],
    }
    local out, code = run(dir, "stale.g.nupp")
    test.equal(code, 1, "an unproved read is refused\n" .. out)
    assert(
        out:find(
            "stale.g.nupp:11:18: aot: valuebuilder.byteAt needs offset < length(bytes) to dominate the read",
            1,
            true
        ),
        "and refused at the read, by lowering: " .. out
    )
    assert(not out:find("traceback", 1, true), "rather than by the verifier: " .. out)
end

function M.aNestedLoopInAMapEntryIsProvedByItsOwnBound()
    -- Under `for j = 1, #weights` the read `weights[j]` is proved by that
    -- loop's own bound, whatever the map's guard prologue related to `i`. It
    -- used to be checked against the map's guarded spans and refused with a
    -- guard that compared `weights` with itself.
    local body = [[
local span = require("nupp.mem.span")

@aot
local function rows(
    exclusive output: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    borrows weights: span.Span<number>
): nil
    if #output ~= #input then
        error("length")
    end
    for i = 1, #output do
        local sum = 0
        for j = 1, BOUND do
            sum = sum + weights[j]
        end
        output[i] = input[i] * sum
    end
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

function M.negatingANarrowValueWidensItLikeArithmetic()
    -- `-value` is binary64 arithmetic the way `0 - value` is, so a float or a
    -- fixed-width operand widens into it rather than being refused.
    local dir = project{
        [
            "neg.nupp"
        ] = [[
@aot
local function neg(value: float): number
    return -value
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

function M.aShadowedStringIsNotThePreludes()
    -- `string.byte` is only the intrinsic when `string` still names the
    -- prelude's module. A file that rebound the name used to have its own
    -- function compiled as the prelude's.
    local dir = project{
        [
            "shadow.g.nupp"
        ] = [[
local string = {byte = function(text: string, index: number): number return 7 end}
@aot
local function first(source: string): number
    return string.byte(source, 1)
end
return {first = first}
]],
    }
    local out, code = run(dir, "--emit ir shadow.g.nupp")
    test.equal(code, 1, "the rebound name is not an intrinsic\n" .. out)
    assert(
        out:find("shadow.g.nupp:4:12: aot: call target string.byte is not an admitted intrinsic or helper", 1, true),
        "and is refused as the call it is: " .. out
    )
end

function M.aLoopBodyReassigningACursorRetiresTheEnclosingProof()
    -- `cursor < #source` outside the loop bounds the read on the first pass
    -- only: the body moves the cursor, and the second pass reads wherever it
    -- left it. Both the lowerer and the verifier used to carry the enclosing
    -- proof into every iteration.
    local body = [[
local span = require("nupp.mem.span")

@aot
local function decode(borrows source: span.Span<uint8>): uint32
    local cursor: uint32 = 0
    local total: uint32 = 0
    local rounds: uint32 = 0
    if cursor < #source then
        while CONDITION do
            total = nupp.math.u32.add(total, source[(cursor + 1) as integer])
            cursor = nupp.math.u32.add(cursor, 1)
            rounds = nupp.math.u32.add(rounds, 1)
        end
    end
    return total
end

return {decode = decode}
]]
    local dir = project{
        ["outside.nupp"] = body:gsub("CONDITION", "rounds < 10"),
        ["reproved.nupp"] = body:gsub("CONDITION", "cursor < #source"),
    }
    local out, code = run(dir, "outside.nupp")
    test.equal(code, 1, "a proof the loop does not renew is not a proof\n" .. out)
    assert(
        out:find(
            "outside.nupp:10:46: aot: span loads need a counted-loop index or cursor + 1 under cursor < #span",
            1,
            true
        ),
        "and the read is what is refused: " .. out
    )

    out, code = run(dir, "reproved.nupp")
    test.equal(code, 0, "a loop whose own condition proves the cursor proves it every pass\n" .. out)
end

function M.anAnnotatedLoopMovingACursorRetiresTheEnclosingProof()
    -- The look-ahead that retires a proof reads the body's statements, and an
    -- `@simd` loop is a pragma wrapping the loop. It used to stop at the
    -- pragma, so a cursor moved inside the annotated loop kept the enclosing
    -- proof through lowering and the verifier crashed on the read instead of
    -- the lowerer refusing it at its line.
    local dir = project{
        ["annotated.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function scan(borrows bytes: span.Span<number>, exclusive out: span.WriteSpan<number>): number
    local cursor: uint32 = nupp.math.u32.wrap(0)
    local total = 0.0
    if cursor < #bytes then
        while total < 10.0 do
            total = total + bytes[cursor + 1]
            @simd
            for i = 1, #out do
                out[i] = total
                cursor = cursor + nupp.math.u32.wrap(1)
            end
        end
    end
    return total
end

return {scan = scan}
]],
    }
    local out, code = run(dir, "annotated.nupp")
    test.equal(code, 1, "a cursor an annotated loop moves is not proved by the enclosing check\n" .. out)
    assert(
        out:find(
            "annotated.nupp:9:29: aot: span loads need a counted-loop index or cursor + 1 under cursor < #span",
            1,
            true
        ),
        "and the read is what is refused: " .. out
    )
end

function M.moduloIsFlooredLikeLuas()
    -- Lua's `%` takes the divisor's sign: `-1 % 3` is 2. C's `fmod` truncates
    -- and says -1, so a kernel that rendered `%` as `fmod` disagreed with the
    -- same source on the interpreter for every negative operand.
    local dir = project{
        [
            "mod.nupp"
        ] = [[
@aot
local function wrap(value: number, modulus: number): number
    return value % modulus
end

return {wrap = wrap}
]],
    }
    local out, code = run(dir, "--emit c mod.nupp")
    test.equal(code, 0, out)
    assert(out:find("nupp_mod(p_value, p_modulus)", 1, true), "the operator is a floored helper: " .. out)
    assert(
        out:find("double r = fmod(a, b); if ((r < 0) != (b < 0) && r != 0) { r += b; } return r;", 1, true),
        "which corrects the truncated remainder toward the divisor's sign: " .. out
    )
end

function M.pairedRearrangementsAndTransposeKeepNativeResultsAtEveryTier()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function rearrange(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    local s = assert(simd.species(array.float, 4))
    local a, b = s:load(input, 1):interleave(s:load(input, 5))
    local c, d = a:deinterleave(b)
    local w, x, y, z = simd.transpose(a, b, c, d)
    s:store(output, 1, w)
    s:store(output, 5, x)
    s:store(output, 9, y)
    s:store(output, 13, z)
end
@aot
local function preferred(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    local s = assert(simd.species(array.float))
    local a, b = s:load(input, 1):interleave(s:load(input, s.lanes + 1))
    local first = a:deinterleave(b)
    s:store(output, 1, first)
end
return {rearrange = rearrange, preferred = preferred}
]]
    local dir = project{["rearrange.nupp"] = source}
    for _, tier in ipairs({
        "--target aarch64-apple-darwin --features neon",
        "--target x86_64-unknown-linux-gnu --features baseline",
        "--target x86_64-unknown-linux-gnu --features avx2",
        "--target x86_64-unknown-linux-gnu --features avx512f",
        "--target wasm32-unknown-emscripten --features simd128",
    }) do
        local decoded, raw, code = lowered(dir, tier .. " --json rearrange.nupp")
        test.equal(code, 0, raw)
        for _, op in ipairs({"interleave", "deinterleave", "transpose"}) do
            assert(decoded.ir:find("rearrange_" .. op .. "_simd_vector_f32_fixed4", 1, true), decoded.ir)
            assert(decoded.c:find("rearrange_" .. op .. "_simd_vector_f32_fixed4_forced_scalar", 1, true), decoded.c)
        end
        assert(not decoded.c:find("malloc(", 1, true), "rearrangements must not allocate")
    end
    local asm, code = run(dir, "--emit asm rearrange.nupp")
    test.equal(code, 0, asm)
    assert(asm:match("kernel: [^\n]* [1-9]%d* vector"), asm)
end

function M.transposeRejectsNonSquareMixedAndPreferredRows()
    for _, case in ipairs({
        {shape = ", 4", value = "s:splat(2.0)", reason = "square tile"},
        {shape = "", value = "s:splat(2.0)", reason = "fixed-width rows"},
        {shape = ", 2", value = "3.0", reason = "SIMD vector rows"},
        {shape = ", 2", value = "other:splat(2)", reason = "same vector type"},
    }) do
        local source = (
            [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function bad(): number
    local s = assert(simd.species(array.float%s))
    local other = assert(simd.species(array.uint32, 2))
    local a, b = simd.transpose(s:splat(1.0), %s)
    return a:extract(1) + b:extract(1)
end
return {bad = bad}
]]
        ):format(case.shape, case.value)
        local dir = project{["badtranspose.nupp"] = source}
        local out, code = run(dir, "--json badtranspose.nupp")
        assert(code ~= 0 and out:find(case.reason, 1, true), out)
    end
end

local CONDITIONAL_SCAN = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function scan(borrows cps: span.Span<uint32>): integer
    local cursor: uint32 = 0
    if species = simd.species(array.uint32) then
        while cursor + species.lanes <= #cps do
            local first = (species:load(cps, cursor + 1) <= 0xF):first()
            if first ~= 0 then
                cursor = cursor + first - 1
                break
            end
            cursor = cursor + species.lanes
        end
    end
    while cursor < #cps and cps[cursor + 1] > 0xF do
        cursor = cursor + 1
    end
    return cursor + 1
end

return {scan = scan}
]]

local function scanBody(c)
    local body = c:match("KS_API double ks_scan%(.-\n}\n")
    assert(body, "the kernel is emitted:\n" .. c)
    return body
end

function M.aSpeciesBindingIsDecidedPerTier()
    -- `if species = simd.species(array.uint32) then` is the vector loop on
    -- a tier that has vectors and nothing at all on one that does not; the
    -- scalar tail that follows is the same C on every tier, its span read
    -- proved by the left of the `and` it sits under.
    local dir = project{["scan.nupp"] = CONDITIONAL_SCAN}
    local tail = "while ((((uint64_t)v1_cursor < (uint64_t)count_cps) && (p_cps[((size_t)v1_cursor)] > UINT32_C(15))))"
    for _, tier in ipairs({
        {args = "--target aarch64-apple-darwin --features neon", lanes = 4},
        {args = "--target x86_64-unknown-linux-gnu --features baseline", lanes = 4},
        {args = "--target x86_64-unknown-linux-gnu --features avx2", lanes = 8},
        {args = "--target wasm32-unknown-emscripten --features simd128", lanes = 4},
    }) do
        local decoded, raw, code = lowered(dir, tier.args .. " --json scan.nupp")
        test.equal(code, 0, raw)
        local body = scanBody(decoded.c)
        assert(body:find("ks_exp_load_at_u32x" .. tier.lanes .. "(p_cps + (size_t)v1_cursor)", 1, true), tier.args .. ": the arm is the vector loop\n" .. body)
        assert(
            body:find("<= (uint64_t)count_cps)", 1, true) and body:find("UINT32_C(" .. tier.lanes .. "))", 1, true),
            tier.args .. ": species.lanes is the tier's constant\n" .. body
        )
        assert(body:find("uint32_t v3_first = ks_exp_first_u32x" .. tier.lanes .. "(", 1, true), tier.args .. ": first() is a uint32\n" .. body)
        assert(body:find(tail, 1, true), tier.args .. ": the scalar tail follows\n" .. body)
    end

    local decoded, raw, code = lowered(dir, "--target wasm32-unknown-emscripten --features scalar --json scan.nupp")
    test.equal(code, 0, raw)
    local body = scanBody(decoded.c)
    assert(not body:find("ks_exp_", 1, true), "the scalar tier drops the arm\n" .. body)
    assert(body:find(tail, 1, true), "and keeps the tail\n" .. body)
    assert(not decoded.ir:find("species", 1, true), "nothing of the test survives lowering\n" .. decoded.ir)
end

function M.aProvenVectorAccessIsOneCopyAndAnIntegerCompare()
    -- `cursor + s.lanes <= #span`, taken exactly in u64, is the guard that
    -- proves a whole vector at `cursor + 1` lies inside the span. Under it
    -- an unmasked load or store is the `_at` helper: one memcpy the C
    -- compiler turns into the vector instruction, with no count and no
    -- check. The masked tail keeps the checked helper, tests all-active
    -- with a vector compare rather than a lane loop, and moves its partial
    -- vector through general registers rather than a stack array. Nothing
    -- in the loop goes through a double.
    local dir = project{
        [
            "map.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function add(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): nil
    local s = assert(simd.species(array.uint8))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input and cursor + s.lanes <= #output do
        s:store(output, cursor + 1, s:load(input, cursor + 1) + 90)
        cursor = cursor + s.lanes
    end
    if cursor < #output then
        local active = s:tail(#output - cursor)
        s:store(output, cursor + 1, s:load(input, cursor + 1, active) + 90, active)
    end
end
return {add = add}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json map.nupp")
    test.equal(code, 0, raw)
    local c = decoded.c
    local body = c:match("KS_API void ks_add%(.-\n}\n")
    assert(body, "the kernel is emitted:\n" .. c)
    local loop = body:match("while %(.-\n    }\n")
    assert(loop, "the vector loop\n" .. body)
    assert(
        loop:find("+ (uint64_t)(((uint64_t)UINT32_C(16)))) <= (uint64_t)count_input)", 1, true)
            and loop:find("+ (uint64_t)(((uint64_t)UINT32_C(16)))) <= (uint64_t)count_output)", 1, true),
        "the guard is exact and compares the count as an integer\n" .. body
    )
    assert(
        loop:find("ks_exp_store_at_u8x16(p_output + (size_t)v2_cursor, (ks_exp_load_at_u8x16(p_input + (size_t)v2_cursor) + ", 1, true),
        "the proven load and store are bare copies\n" .. body
    )
    assert(not loop:find("(double)", 1, true), "nothing in the loop goes through a double\n" .. body)
    assert(not loop:find("count_input, nupp_first", 1, true), "the loop carries no checked access\n" .. body)
    assert(body:find("ks_exp_load_u8x16(p_input, count_input, nupp_first_u64(", 1, true), "the masked tail load is checked\n" .. body)
    assert(body:find("ks_exp_store_u8x16(p_output, count_output, nupp_first_u64(", 1, true), "and so is the masked tail store\n" .. body)

    -- The helpers themselves are authored C, carried as ks_simd.h and
    -- instantiated per element by macro, so their shape is read from the
    -- header rather than from the emitted text.
    local header = assert(io.open(HERE .. "/../src/nupp/compiler/aot/include/ks_simd.h", "rb")):read("*a")
    assert(c:find("KS_EXP_ELEMENT(16, u8x16, uint8_t, int8_t, 16, 1, INT)", 1, true), "the u8x16 helpers are instantiated\n" .. c)
    assert(
        header:find("ks_exp_load_at_##ELEM(const CTYPE *source) { ks_exp_##ELEM out; memcpy(&out, source, sizeof out); return out; }", 1, true)
            and header:find("ks_exp_store_at_##ELEM(CTYPE *destination, ks_exp_##ELEM value) { memcpy(destination, &value, sizeof value); }", 1, true),
        "a proven vector is one copy"
    )
    assert(
        header:find("ks_exp_load_full_##ELEM(const CTYPE *source, size_t count, size_t first) {", 1, true)
            and header:find("if (room >= LANES##u) { memcpy(&out, source + first, sizeof out); return out; }", 1, true),
        "a checked whole vector is still one copy"
    )
    assert(
        header:find("#if KS_WORD_TAIL", 1, true)
            and header:find("switch (n >> 3u) { case 0u: w0 |= ks_gather_word(p + 0u, n & 7u); break; case 1u: w1 |= ks_gather_word(p + 8u, n & 7u); break; default: break; }", 1, true),
        "a partial vector gathers into words"
    )
    assert(
        header:find("case 0u: ks_scatter_word(p + 0u, n & 7u, w0); break; case 1u: ks_scatter_word(p + 8u, n & 7u, w1); break;", 1, true)
            and header:find("static __attribute__((noinline, cold, unused)) void ks_exp_store_masked_part_##ELEM(", 1, true),
        "and scatters from them, with the lane loop cold"
    )
    assert(
        header:find("bool ks_exp_full_##ELEM(ks_exp_mask_##ELEM active) { ks_exp_mask_##ELEM inactive = (ks_exp_mask_##ELEM)(active == (ks_exp_mask_##ELEM){0});", 1, true),
        "all-active is a vector compare"
    )
    assert(
        header:find("ks_exp_mask_##ELEM ks_exp_tail_##ELEM(uint32_t active) { if (active > LANES##u) active = LANES##u;", 1, true)
            and header:find("return (ks_exp_mask_##ELEM)(lane < limit); }", 1, true),
        "and so is a tail mask"
    )

    -- Nothing wider than a vector may cross a call boundary by value, and no
    -- type may ask for more alignment than the narrowest calling convention
    -- gives a by-reference argument temporary. Windows x64 allocates that
    -- temporary in the caller's frame with sixteen bytes of alignment, and GCC
    -- neither rounds it up for an over-aligned type nor declines to move it
    -- with an instruction that requires the wider alignment -- so a
    -- thirty-two byte vector handed to a function it did not inline faults on
    -- whichever half of the calls find the frame sixteen-byte aligned. The
    -- cold lane loop is the one helper here that is never inlined, so it takes
    -- what it reads by pointer; a declared object is aligned correctly where
    -- an argument temporary is not.
    assert(
        header:find("void ks_exp_store_masked_part_##ELEM(CTYPE *destination, size_t room, const ks_exp_##ELEM *value, const ks_exp_mask_##ELEM *active)", 1, true)
            and header:find("ks_exp_store_masked_part_##ELEM(destination, room, &value, &active);", 1, true),
        "the cold lane loop takes its vector and its mask by pointer"
    )
    assert(
        header:find("typedef struct { uint8_t lane[W]; } ks_scalar_u8x##W;", 1, true)
            and not header:find("aligned(", 1, true),
        "and no type in the prelude asks for an alignment a caller does not give it"
    )

    -- Pointers close the boundaries this header writes. The one it does not
    -- write is the hidden pointer a by-value vector is returned through, which
    -- appears whenever the compiler splits a cold path out of an inline helper
    -- into a real call -- its own choice, made again on every version. On
    -- Windows the slot that pointer names is the caller's frame, sixteen-byte
    -- aligned, and GCC stores a vector into it with `vmovdqa`. Every vector
    -- here says its alignment is one there, which is what leaves the compiler
    -- no aligned move to reach for; every other target keeps the natural one.
    assert(
        header:find("#if defined(_WIN32) || defined(_WIN64)\n#define KS_VECTOR_ABI_ALIGN , __aligned__(1)\n#else\n#define KS_VECTOR_ABI_ALIGN\n#endif", 1, true),
        "the Windows calling convention caps what a vector claims about its address"
    )
    for _, vector in ipairs({
        "typedef uint8_t ks_u8x##W __attribute__((vector_size(W) KS_VECTOR_ABI_ALIGN));",
        "typedef CTYPE ks_exp_##ELEM __attribute__((vector_size(W) KS_VECTOR_ABI_ALIGN));",
        "typedef MASK ks_exp_mask_##ELEM __attribute__((vector_size(W) KS_VECTOR_ABI_ALIGN));",
    }) do
        assert(header:find(vector, 1, true), "and every vector carries that cap: " .. vector)
    end
end

function M.aProofNeedsTheGuardAndTheCursorItLeft()
    -- A guard for one span proves nothing about another; a masked access
    -- keeps its mask and its checks; a cursor moved between the guard and
    -- the access is no longer the one the guard was about. Each stays on
    -- the checked `_full` helper.
    local dir = project{
        [
            "unproven.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function other(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): nil
    local s = assert(simd.species(array.uint8))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1))
        cursor = cursor + s.lanes
    end
end

@aot
local function masked(borrows input: span.Span<uint8>): uint32
    local s = assert(simd.species(array.uint8))
    local cursor: uint32 = 0
    local total: uint32 = 0
    while cursor + s.lanes <= #input do
        total = total + (s:load(input, cursor + 1, s:tail(8)) <= 15):count()
        cursor = cursor + s.lanes
    end
    return total
end

@aot
local function moved(borrows input: span.Span<uint8>): uint32
    local s = assert(simd.species(array.uint8))
    local cursor: uint32 = 0
    local total: uint32 = 0
    while cursor + s.lanes <= #input do
        cursor = cursor + 1
        total = total + (s:load(input, cursor + 1) <= 15):count()
        cursor = cursor + s.lanes
    end
    return total
end
return {other = other, masked = masked, moved = moved}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json unproven.nupp")
    test.equal(code, 0, raw)
    local c = decoded.c
    local other = c:match("KS_API void ks_other%(.-\n}\n")
    assert(other and other:find("ks_exp_store_full_u8x16(p_output, count_output, nupp_first_u64(", 1, true), "the unguarded span is checked\n" .. c)
    assert(other:find("ks_exp_load_at_u8x16(p_input + (size_t)v2_cursor)", 1, true), "while the guarded one is proven\n" .. c)
    local masked = c:match("KS_API uint32_t ks_masked%(.-\n}\n")
    assert(masked and masked:find("ks_exp_load_u8x16(p_input, count_input, nupp_first_u64(", 1, true), "a masked access keeps its checks\n" .. c)
    local moved = c:match("KS_API uint32_t ks_moved%(.-\n}\n")
    assert(moved and moved:find("ks_exp_load_full_u8x16(p_input, count_input, nupp_first_u64(", 1, true), "a moved cursor loses the proof\n" .. c)
    assert(not moved:find("load_at_", 1, true) and not masked:find("load_at_", 1, true), "no bare copy without a proof\n" .. c)
end

function M.aSpeciesBindingIsTheOnlyPlaceItsSpeciesLives()
    local dir = project{
        [
            "outside.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function lanes(borrows cps: span.Span<uint32>): integer
    local species = simd.species(array.uint32)
    if species == nil then
        return #cps
    end
    return species.lanes
end

return {lanes = lanes}
]],
        [
            "other.nupp"
        ] = [[
local span = require("nupp.mem.span")

local function limit(): integer?
    return nil
end

@aot
local function first(borrows cps: span.Span<uint32>): integer
    local cursor: integer = 0
    if bound = limit() then
        cursor = bound
    end
    return cursor + #cps
end

return {first = first}
]],
        [
            "witness.nupp"
        ] = [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function lanes(borrows cps: span.Span<uint32>): integer
    if species = simd.species(cps) then
        return species.lanes
    end
    return 0
end

return {lanes = lanes}
]],
    }
    local scalar = "--target wasm32-unknown-emscripten --features scalar "
    local out, code = run(dir, scalar .. "outside.nupp")
    test.equal(code, 1, "a use after the nil test on a tier without vectors\n" .. out)
    assert(
        out:find(
            "outside.nupp:11:12: aot: this tier has no vectors, so species is nil here; "
                .. "keep the vector path inside the branch that tested it against nil",
            1,
            true
        ),
        out
    )

    out, code = run(dir, scalar .. "other.nupp")
    test.equal(code, 1, "a native if binding is the species test\n" .. out)
    assert(out:find("other.nupp:10:16: aot: a native if binding takes simd.species only", 1, true), out)

    out, code = run(dir, scalar .. "witness.nupp")
    test.equal(code, 1, "the argument is an array witness\n" .. out)
    assert(out:find("NUPP2125", 1, true) and out:find("Span<uint32> is not a Scalar<any>", 1, true), out)
end

function M.anAssertedSpeciesIsTheSpeciesWhereThereAreVectorsAndRefusedWhereThereAreNone()
    -- `assert(simd.species(...))` is the required form: the species itself on
    -- a tier with vectors, both shapes, and on one without a refusal at
    -- compile time, since the assert would fail on every call.
    local dir = project{
        [
            "required.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function total(borrows values: span.Span<float>): number
    local wide = assert(simd.species(array.float), "this sum needs vectors")
    local eight = assert(simd.species(array.float, 8))
    local sum = wide:splat(0.0)
    local cursor: uint32 = 0
    while cursor + wide.lanes <= #values do
        sum = sum + wide:load(values, cursor + 1)
        cursor = cursor + wide.lanes
    end
    return simd.horizontal.orderedSum(sum) + simd.horizontal.orderedSum(eight:splat(1.0))
end

return {total = total}
]],
    }
    for _, tier in ipairs({
        {args = "--target aarch64-apple-darwin --features neon", lanes = 4},
        {args = "--target x86_64-unknown-linux-gnu --features avx2", lanes = 8},
        {args = "--target wasm32-unknown-emscripten --features simd128", lanes = 4},
    }) do
        local decoded, raw, code = lowered(dir, tier.args .. " --json required.nupp")
        test.equal(code, 0, raw)
        assert(decoded.ir:find("simd_species_f32_preferred", 1, true), tier.args .. ": the preferred shape\n" .. decoded.ir)
        assert(decoded.ir:find("simd_vector_f32_fixed8", 1, true), tier.args .. ": the fixed shape\n" .. decoded.ir)
        assert(
            decoded.c:find("KS_EXP_ELEMENT(" .. tier.lanes * 4 .. ", f32x" .. tier.lanes .. ", float", 1, true),
            tier.args .. ": the tier's width\n" .. decoded.c
        )
        assert(not decoded.c:find("assert", 1, true), tier.args .. ": nothing of the assert survives\n" .. decoded.c)
    end

    local out, code = run(dir, "--target wasm32-unknown-emscripten --features scalar required.nupp")
    test.equal(code, 1, "no vectors, so the assert would always fail\n" .. out)
    assert(
        out:find(
            "required.nupp:7:25: aot: this tier has no vectors, so simd.species is nil here and the assert "
                .. "would always fail; test it against nil and keep the vector path inside that branch",
            1,
            true
        ),
        out
    )
end

function M.anAndProvesItsRightSpanReadOnlyByTheShapeItPromises()
    -- `cursor < #span and span[cursor + 1] ...` reads under the bound the left
    -- side just tested. Any other left, a different span, or a different
    -- offset is not that proof.
    local body = [[
local span = require("nupp.mem.span")

@aot
local function scan(borrows cps: span.Span<uint32>, borrows other: span.Span<uint32>): integer
    local cursor: uint32 = 0
    while CONDITION do
        cursor = cursor + 1
    end
    return cursor + 1 + #other
end

return {scan = scan}
]]
    local files = {["proved.nupp"] = body:gsub("CONDITION", "cursor < #cps and cps[cursor + 1] > 0xF")}
    local rejected = {
        {"reversed", "#cps > cursor and cps[cursor + 1] > 0xF"},
        {"disjunction", "cursor < #cps or cps[cursor + 1] > 0xF"},
        {"otherspan", "cursor < #other and cps[cursor + 1] > 0xF"},
        {"inclusive", "cursor <= #cps and cps[cursor + 1] > 0xF"},
        {"offset", "cursor < #cps and cps[cursor + 2] > 0xF"},
    }
    for _, case in ipairs(rejected) do
        files[case[1] .. ".nupp"] = body:gsub("CONDITION", function()
            return case[2]
        end)
    end
    local dir = project(files)
    local scalar = "--target wasm32-unknown-emscripten --features scalar "
    local out, code = run(dir, scalar .. "proved.nupp")
    test.equal(code, 0, out)
    for _, case in ipairs(rejected) do
        out, code = run(dir, scalar .. case[1] .. ".nupp")
        test.equal(code, 1, case[1] .. " is not the proof\n" .. out)
        assert(
            out:find(case[1] .. ".nupp:6:", 1, true)
                and out:find("span loads need a counted-loop index or cursor + 1 under cursor < #span", 1, true),
            case[1] .. ": " .. out
        )
    end
end

return M
