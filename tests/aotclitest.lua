-- `nupp aot`: what scalar and explicit SIMD `@aot` functions compile to.
--
-- Driven through the real binary because artifacts and exit status are the interface.

local test = require("assert")
local equivalenceMutation = require("tests.simd.equivalence-mutation")

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

-- The NEON instructions of FILE. The code generator targets aarch64 from any
-- host, so every machine reads them.
local function neonAsm(dir, file)
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
--- them, so a single compiler invocation supplies the complete report.
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

-- A register-resident scalar loop: sixteen bytes read once, then arithmetic
-- over locals that touches no memory.
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

    local summary, summaryCode = run(dir, "gpu.nupp")
    test.equal(summaryCode, 0, summary)
    assert(
        summary:find(", gpu, one iteration per GPU invocation", 1, true),
        "a compiled GPU artifact is reported with its lowered shape: " .. summary
    )
end

function M.gpuIntegerSignednessUsesBitcastAndJsonBindingIsUtf8()
    local dir = project({
        [
            "gpu.nupp"
        ] = [[
local span = require("nupp.mem.span")
@aot(target = "gpu")
local function convert(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<int32>): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        output[i] = nupp.math.u32.xorBits(nupp.math.u32.fromI32(input[i]), nupp.math.u32.wrap(input[i]))
    end
end
return convert
]]
    })
    local module, code = run(dir, "--emit spirv gpu.nupp")
    test.equal(code, 0, module)
    assert(spirvOpcodeCount(module, 124) > 0, "equal-width signedness conversion uses OpBitcast")
    test.equal(spirvOpcodeCount(module, 113), 0, "OpUConvert requires a change of width")
    test.equal(spirvOpcodeCount(module, 114), 0, "OpSConvert requires a change of width")
    test.equal(spirvOpcodeCount(module, 111), 0, "integer wrap must not round through binary32")
    local raw, jsonCode = run(dir, "--json gpu.nupp")
    test.equal(jsonCode, 0, raw)
    local report = require("testjson").decode(raw)
    for index = 1, #raw do
        assert(raw:byte(index) < 128, "binary SPIR-V escaped the JSON source literal at byte " .. index)
    end
    local shader = assert(report.functions[1].gpu, "GPU identity is structured inspection output")
    local authored = require("nupp.compiler.fs").readFile(shader.sourceFile)
    assert(
        authored and authored:find("local function convert", 1, true),
        "source identity resolves independently of the invocation directory"
    )
    test.equal(shader.sourceLine, 2)
    test.equal(shader.artifactId, require("nupp.compiler.hash").digest(module))
    assert(report.binding:find(shader.artifactId, 1, true), "runtime and inspection share the shader digest")
    assert(report.binding:find('sourceLine = 2', 1, true), report.binding)
    assert(report.binding:find('artifactId = "', 1, true), report.binding)
    assert(report.binding:find('readonlyNames = {"input"}', 1, true), report.binding)
    assert(report.binding:find('writableNames = {"output"}', 1, true), report.binding)
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

function M.gpuCountedLoopsEmitNativeAndBrowserControlFlow()
    local source = assert(io.open(HERE .. "/../bench/wgpu-spike/typed/counted.nupp", "rb"))
    local dir = project({["counted.nupp"] = source:read("*a")})
    source:close()
    for _, name in ipairs({"literal", "boundaries", "snapshots", "control"}) do
        local module, moduleCode = run(dir, "--emit spirv --function " .. name .. " counted.nupp")
        test.equal(moduleCode, 0, module)
        assertSpirvStructure(module)
        assert(spirvOpcodeCount(module, 246) > 0, "counted loops require structured loop control")
        local shader, shaderCode = run(
            dir,
            "--emit wgsl --target wasm32-unknown-emscripten --function " .. name .. " counted.nupp"
        )
        test.equal(shaderCode, 0, shader)
        assert(shader:find("continuing {", 1, true), shader)
        assert(shader:find("break if ", 1, true), shader)
        assert(
            not shader:find("let __", 1, true) and not shader:find("var __", 1, true),
            "WGSL forbids the C temporary identifier prefix\n" .. shader
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
    assert(
        decoded.llvm:find("call float @expf(", 1, true),
        where .. ": the CPU body calls the native exponential: " .. decoded.llvm
    )
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
    local decoded, raw, code, where = lowered(dir, "--json gather.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.ir:find("guards\n  equal_count out offsets @", 1, true)
            and not decoded.ir:find("equal_count out source", 1, true),
        where .. ": only the spans the loop index addresses are guarded equal: " .. decoded.ir
    )
    assert(
        decoded.llvm:match("%%t%d+ = zext i32 %%t%d+ to i64\n  %%t%d+ = getelementptr inbounds nuw float, ptr %%p_source, i64 %%t%d+\n"),
        where .. ": the other span is read at the widened cursor its own count check proved: " .. decoded.llvm
    )
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
    local llvm, code = run(dir, "--emit llvm shared-count.nupp")
    test.equal(code, 0, llvm)
    assert(llvm:find("i64 range(i64 0, 9007199254740993) %count)", 1, true), "the entry takes one shared count: " .. llvm)
    assert(llvm:find("zext i64 %count to i65", 1, true), "the cursor check reads it: " .. llvm)
    assert(not llvm:find("count_input", 1, true), llvm)
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
    @readonly count: integer
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

--- A target every host can compile for, at a tier that holds wide vectors.
---
--- Pinned because these assert how many lanes a body takes, and that depends on what
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
local array = require("nupp.mem.array")

@aot
local function quotes(borrows source: span.Span<uint8>): uint32
    local species = assert(simd.species(array.uint8))
    local cursor: integer = 0
    local found: uint32 = 0
    while cursor < #source do
        local bytes = species:load(source, cursor + 1)
        local tail = species:tail(#source - cursor)
        local quote = bytes == 34
        local slash = bytes == 92
        local either = quote | slash
        local syntax = either & tail
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
-- Byte-identical LLVM IR is the claim: a source form that reaches a different
-- artifact would be one the backend understood differently.
function M.equivalentGuardFormsReachTheSameKernel()
    local wanted, wantedCode = run(project{["compute.nupp"] = COMPUTE}, PINNED .. "--emit llvm compute.nupp")
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
        local got, code = run(project{["compute.nupp"] = source}, PINNED .. "--emit llvm compute.nupp")
        test.equal(code, 0, name .. " is admitted\n" .. got)
        test.equal(got, wanted, name .. " emits the same LLVM IR as the reference form")
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

-- A parameter only a guard mentions is still a parameter of the kernel, and
-- what the guard says about it reaches LLVM as an assumption rather than as
-- work the body does. The loop's own uniform is still what the loop reads.
function M.aUniformUsedOnlyByAGuardBecomesAnAssumption()
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
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json compute.nupp")
    test.equal(code, 0, "the precondition is admitted\n" .. raw)
    assert(decoded.ir:find("  1 <= guardOnly @", 1, true), where .. ": the guard is a relation: " .. decoded.ir)
    assert(
        decoded.ir:find("while lt(local:f64 iteration, uniform:i32 limit)", 1, true),
        where .. ": the loop still reads its limit: " .. decoded.ir
    )
    assert(
        decoded.llvm:find("i32 %p_limit, i32 %p_guardOnly,", 1, true),
        where .. ": both are kernel parameters: " .. decoded.llvm
    )
    assert(
        decoded.llvm:match("(%%t%d+) = sext i32 %%p_guardOnly to i64\n  (%%t%d+) = add nsw i64 %1, %-1\n  (%%t%d+) = icmp sle i64 0, %2\n  call void @llvm%.assume%(i1 %3%)"),
        where .. ": the guard-only value reaches LLVM as the fact the guard states: " .. decoded.llvm
    )
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

function M.anOrdinaryLoopCompilesScalarAndSaysSo()
    local dir = project{["stream.nupp"] = STREAMING}
    local out, code = run(dir, "stream.nupp")
    test.equal(code, 0, "an ordinary loop compiles\n" .. out)
    assert(out:find("advance, kernel, scalar", 1, true), "the report says it runs scalar: " .. out)
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
        assert(decoded.ir:find("reducer.exact.sum", 1, true), tier .. decoded.ir)
        assert(decoded.ir:find("reducer.add", 1, true), tier .. ": missing scalar contribution")
        assert(not decoded.ir:find("simd_load", 1, true), tier .. ": no inferred vector load")
        assert(decoded.ir:find("reducer.integer.argmax", 1, true), tier .. ": missing indexed extremum")
        assert(
            decoded.llvm:find("call void @nupp.reduce.integer.argmax.u64.add(ptr %slot", 1, true),
            tier .. ": the indexed extremum folds each uint64 at its own width"
        )
        assert(
            decoded.llvm:find("%position = load i64, ptr %positionp", 1, true),
            tier .. ": and keeps a 64-bit logical position beside it"
        )
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
    -- Byte and float vectors share the tier width even when byte operations
    -- need decomposition into instructions supported by AVX-512F.
    local both = project{
        [
            "mixed.nupp"
        ] = SCOPED_SIMD:gsub(
            "return {quotes = quotes}",
            ""
        )
        .. [[

@aot
local function twice(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    local species = assert(simd.species(array.float))
    local active = species:tail(#input)
    species:store(output, 1, species:load(input, 1, active) * 2, active)
end

return {quotes = quotes, twice = twice}
]]
    }
    local mixed, mixedCode = run(both, "--target " .. triple .. " --features avx512f --emit c mixed.nupp")
    test.equal(mixedCode, 0, mixed)
    local scanner = ("ks_exp_u8x%d"):format(width)
    assert(mixed:find(scanner, 1, true), "byte vectors keep the " .. scanner .. " scanner: " .. mixed)
end

function M.genericExplicitSimdEmitsRealTargetVectorArithmetic()
    local dir = project{["vectors.nupp"] = GENERIC_EXPLICIT_SIMD}
    local out = neonAsm(dir, "vectors.nupp")
    if out == nil then
        test.skip("reading NEON instructions needs Clang or an aarch64 host")
    end
    assert(out:find("fmul.4s", 1, true), "binary32 multiplication remains a vector operation: " .. out)
    assert(out:find("fadd.4s", 1, true), "binary32 addition remains a vector operation: " .. out)
    -- The C lowering's oracle walked lanes one at a time. The LLVM route's is
    -- the same IR left unoptimized, and the Lua body is the reference.
    if not out:find("; codegen ", 1, true) then
        assert(out:find("0 vector", 1, true), "the separately reported scalar oracle has no vector instructions: " .. out)
    end
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
        -- As for the float kernels: only the C lowering's oracle walked lanes.
        if not asm:find("; codegen ", 1, true) then
            assert(asm:find("0 vector", 1, true), "the narrow scalar oracle has no vector instructions: " .. asm)
        end
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
    assert(asm:find("ushr.16b", 1, true), "the shift stays a byte vector operation: " .. asm)
    assert(asm:find("and.16b", 1, true), "the and stays a byte vector operation: " .. asm)
    assert(asm:find("tbl.16b", 1, true), "and the nibble indexes a table: " .. asm)

    local mismatched = source:gsub(
        "local low = entries:swizzle%(%(bytes & 15%) %+ 1%)",
        [[
    local words = assert(simd.species(array.uint32))
    local low = entries:swizzle((bytes & words:splat(15)) + 1)]]
    )
    local refused = project{["mismatched.nupp"] = mismatched}
    local out, refusedCode = run(refused, "--target aarch64-apple-darwin --features neon mismatched.nupp")
    assert(refusedCode ~= 0, "a byte vector against a word vector is refused: " .. out)
    assert(out:find("NUPP2003", 1, true), "as an operand type error: " .. out)
end

-- One lane previously reached fixedSimdPrelude and crashed after lowering.
-- Keep the unsupported source as a diagnostic regression, not a larger vector.
function M.fixedSpeciesRejectUnsupportedLaneCountsAtTheSource()
    for _, lanes in ipairs({0, 1, 65}) do
        local dir = project{
            [
                "fixed-count.nupp"
            ] = (
                [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")
@aot
local function count(): uint32
    local species = assert(simd.species(array.uint8, %d))
    return species.lanes
end
return {count = count}
]]
            ):format(lanes)
        }
        local out, code = run(dir, "--target aarch64-apple-darwin --features neon --emit ir fixed-count.nupp")
        test.equal(code, 1, out)
        assert(out:find("fixed-count.nupp:5:", 1, true), out)
        assert(out:find("integer lane count between 2 and 64", 1, true), out)
        assert(not out:find("stack traceback", 1, true), out)
    end
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
        assert(
            asm:match("kernel: [^\n]* [1-9]%d* vector"),
            "fixed structural operations retain real vector work: " .. asm
        )
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
            -- A float gather is `vgatherqps` to LLVM and was an integer
            -- `vpgatherqd` to the C lowering; either is the native one.
            assert(asm:find("v%a*gather"), asm)
            assert(asm:find("v%a*scatter"), asm)
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
    local chain = require("nupp.tools.build.aot").toolchain()
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
        decoded.llvm:match("%%t%d+ = and i64 %%t%d+, %%t%d+\n"),
        where .. ": the pattern keeps its width rather than narrowing to 32 bits\n" .. decoded.llvm
    )
    local shiftLlvm = decoded.llvm
    if equivalenceMutation.active("shift-masking") then
        local count
        shiftLlvm, count = shiftLlvm:gsub("(and i64 %%t%d+), 63\n", "%1, 31\n")
        assert(count > 0, "equivalence mutation fixture did not match shift-masking")
    end
    assert(
        shiftLlvm:match("(%%t%d+) = and i64 %%t%d+, 63\n  %%t%d+ = shl i64 %%t%d+, %1\n")
            and shiftLlvm:match("(%%t%d+) = and i64 %%t%d+, 63\n  %%t%d+ = lshr i64 %%t%d+, %1\n"),
        equivalenceMutation.active("shift-masking") and equivalenceMutation.marker("shift-masking", "wrong-result")
        or where .. ": a shift count is masked one bit wider than the 32-bit pair"
    )
end

function M.compositeLaneExtractionKeepsNativeVectorsWhole()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function sum(borrows input: span.Span<int32>): int32
    local species = assert(simd.species(array.int32, 17))
    local fold = simd.reducer.i32.wrappingSum(0)
    do
        local active = species:tail(#input)
        local value = species:load(input, 1, active)
        fold:add(value, active)
    end
    return fold:value()
end

return {sum = sum}
]]
    local dir = project{["composite.nupp"] = source}
    local decoded, raw, code, where = lowered(
        dir,
        "--target x86_64-unknown-linux-gnu --features baseline --json composite.nupp"
    )
    test.equal(code, 0, raw)
    -- Seventeen lanes are one `<17 x i32>` value, which LLVM legalizes into
    -- native registers itself. Lane 2 is read out of that whole value, never
    -- out of a chunk the backend split off it.
    local composite = assert(
        decoded.llvm:match("define i32 @ks_sum__baseline%(.-\n}\n"),
        where .. ": the kernel is emitted\n" .. decoded.llvm
    )
    if equivalenceMutation.active("gcc-sra") then
        local count
        composite, count = composite:gsub(
            "extractelement <17 x i32> (%%t%d+), i32 1\n",
            "extractelement <4 x i32> %1, i32 1\n"
        )
        assert(count == 1, "equivalence mutation fixture did not match gcc-sra")
    end
    assert(
        composite:match("extractelement <17 x i32> %%t%d+, i32 1\n"),
        equivalenceMutation.active("gcc-sra") and equivalenceMutation.marker("gcc-sra", "wrong-result")
        or where .. ": composite extraction split a native vector\n" .. composite
    )
    assert(
        not composite:find("x <4 x i32>", 1, true) and not composite:find("extractelement <4 x i32>", 1, true),
        equivalenceMutation.active("gcc-sra") and equivalenceMutation.marker("gcc-sra", "wrong-result")
        or where .. ": composite extraction directly indexed a native vector\n" .. composite
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
        decoded.llvm:find("define void @ks_lookup__neon(", 1, true)
            and decoded.llvm:find("define void @ks_lookup_forced_scalar__neon(", 1, true),
        where .. ": production and oracle bodies are both emitted"
    )
    assert(
        decoded.llvm:find("call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(", 1, true),
        where .. ": a byte table reaches the target instruction rather than a lane loop"
    )
    assert(
        decoded.llvm:match("(%%t%d+) = sub <16 x i8> %%t%d+, splat %(i8 1%)\n  %%t%d+ = call <16 x i8> @llvm%.aarch64%.neon%.tbl1%.v16i8%(<16 x i8> %%t%d+, <16 x i8> %1%)"),
        where .. ": one-based lane numbering is adapted once, not per lane"
    )
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
        decoded.llvm:find("define void @ks_joined__neon(", 1, true)
            and decoded.llvm:find("define void @ks_joined_forced_scalar__neon(", 1, true),
        where .. ": production and oracle bodies are both emitted"
    )
    assert(
        decoded.llvm:find("call <16 x i8> @llvm.aarch64.neon.tbl2.v16i8(", 1, true),
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
        decoded.c:find("KS_EXP_ELEMENT(32, f32x8, float, int32_t, 8, 4, FLOAT)", 1, true),
        where .. ": the f32x8 helpers are instantiated\n" .. decoded.c
    )
    assert(
        header:find("KS_EXP_EXTREMES_##KIND(exp, ELEM, CTYPE, LANES, CHUNKED)", 1, true),
        "a fixed species takes its extrema from the shared bodies"
    )
    assert(
        header:find(
            "ks_##P##_propagating_min2_##ELEM(CTYPE left, CTYPE right) { if (left != left || right != right) { return ks_##P##_nan_##ELEM(); }",
            1,
            true
        ),
        "the propagating contract answers a canonical NaN"
    )
    assert(
        header:find(
            "ks_##P##_number_min2_##ELEM(CTYPE left, CTYPE right) { if (left != left) { return right != right ? ks_##P##_nan_##ELEM() : right; }",
            1,
            true
        )
        and header:find("KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, number, min)", 1, true)
        and decoded.c:find("ks_exp_number_min_f32x8(", 1, true),
        "the number-preferring contract is a separate body"
    )
    assert(header:find("signbit", 1, true), "both contracts order the two zeros by sign")
    assert(
        decoded.ir:find("simd_horizontal.propagating_min", 1, true)
        and decoded.c:find("ks_exp_propagating_min_i32x", 1, true),
        where .. ": an extremum is defined at an integer element a sum is refused at\n" .. decoded.c
    )
    assert(
        decoded.c:find("KS_EXP_FIXED(i32x8, int32_t, int32_t, 8, i32x4, 4, 2, INT)", 1, true),
        where .. ": the i32x8 helpers are instantiated\n" .. decoded.c
    )
    assert(
        header:find(
            "ks_##P##_##contract##_##which##2_##ELEM(CTYPE left, CTYPE right) { return left op right ? left : right; }",
            1,
            true
        )
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
        decoded.ir:find("reducer.add", 1, true),
        where .. ": the scalar contribution retains its order\n" .. decoded.ir
    )
    assert(
        decoded.llvm:find("call void @nupp.compensated.add(ptr %slot", 1, true),
        where .. ": the compensated state has its own native form"
    )
    assert(
        decoded.llvm:find("alloca { double, double }", 1, true),
        where .. ": the accumulator is more than one double"
    )
    assert(decoded.functions[1].regions == nil, where .. ": no inferred SIMD region")
end

function M.fixedExplicitSimdSplitsIntoNativeRegistersWithoutChangingItsIdentity()
    -- Only the lane count is added. One constructor serves both shapes, which
    -- is the point: nothing else at the call site says which one it built.
    local source = GENERIC_EXPLICIT_SIMD:gsub("array%.float%)", "array.float, 8)", 1)
    local dir = project{["vectors.nupp"] = source}
    local llvm, llvmCode = run(dir, "--target aarch64-apple-darwin --features neon --emit llvm vectors.nupp")
    test.equal(llvmCode, 0, llvm)
    local kernel = assert(llvm:match("define void @ks_saxpy__neon%(.-\n}\n"), "the kernel is emitted: " .. llvm)
    assert(
        kernel:find("fadd <8 x float>", 1, true) and not kernel:find("<4 x float>", 1, true),
        "Fixed<8> is one eight-lane vector, whatever the register holds: " .. kernel
    )

    local asm = neonAsm(dir, "vectors.nupp")
    local _, adds = asm:gsub("fadd%.4s", "")
    assert(adds >= 2, "both logical halves execute as vector additions in NEON registers: " .. asm)
end

function M.provedFixedVectorsCopyOnlyTheirLogicalLanes()
    local source = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function copy(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    if #output ~= #input then error("length mismatch", 2) end
    local species = assert(simd.species(array.float, 5))
    local cursor: uint32 = 0
    while cursor + species.lanes <= #input and cursor + species.lanes <= #output do
        species:store(output, cursor + 1, species:load(input, cursor + 1))
        cursor = cursor + species.lanes
    end
    if cursor < #input then
        local active = species:tail(#input - cursor)
        species:store(output, cursor + 1, species:load(input, cursor + 1, active), active)
    end
end

return {copy = copy}
]]
    local dir = project{["copy.nupp"] = source}
    local c, code = run(dir, "--target aarch64-apple-darwin --features neon --emit c copy.nupp")
    test.equal(code, 0, c)
    assert(c:find("ks_exp_load_at_f32x5(p_input + (size_t)", 1, true), c)
    assert(c:find("ks_exp_store_at_f32x5(p_output + (size_t)", 1, true), c)
    local header = assert(io.open(HERE .. "/../src/nupp/compiler/aot/include/ks_simd.h", "rb")):read("*a")
    assert(header:find("ks_exp_load_part_##NATIVE(source +", 1, true), "partial final chunk reads exactly one lane")
    assert(
        header:find("ks_exp_store_part_##NATIVE(destination +", 1, true),
        "partial final chunk writes exactly one lane"
    )
end

function M.readOnlySoaRowsHaveContiguousExplicitLoads()
    local source = [[
local soa = require("nupp.mem.soa")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

local struct Row
    x: float
    y: float
end

@aot
local function sumX(borrows rows: soa.Span<Row>): float
    local species = assert(simd.species(array.float))
    local total = species:splat(0.0)
    local cursor: uint32 = 0
    while cursor + species.lanes <= #rows do
        total = total + species:load(rows, cursor + 1, "x")
        cursor = cursor + species.lanes
    end
    if cursor < #rows then
        local active = species:tail(#rows - cursor)
        total = total + species:load(rows, cursor + 1, "x", active)
    end
    return simd.horizontal.algebraicSum(total)
end

return {sumX = sumX}
]]
    local dir = project{["soa.nupp"] = source}
    local c, code = run(dir, "--target aarch64-apple-darwin --features neon --emit c soa.nupp")
    test.equal(code, 0, c)
    assert(c:find("ks_exp_load_at_f32x4(p_rows + (size_t)", 1, true), c)
    assert(not c:find("ks_exp_gather_", 1, true), c)
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
    -- Lane 2 of the source is position 1 of the LLVM vector, for the insert
    -- and for the extract.
    assert(
        decoded.llvm:match("(%%t%d+) = fptrunc double 0x4008000000000000 to float\n  %%t%d+ = insertelement <8 x float> %%t%d+, float %1, i32 1\n"),
        where .. ": insert uses the documented one-based lane convention\n" .. decoded.llvm
    )
    assert(
        decoded.llvm:match("%%t%d+ = extractelement <8 x float> %%t%d+, i32 1\n  %%t%d+ = fpext float"),
        where .. ": and so does extract\n" .. decoded.llvm
    )
    assert(
        decoded.llvm:match("(%%t%d+) = call i64 @llvm%.cttz%.i64%(i64 %%t%d+, i1 false%)\n  (%%t%d+) = trunc i64 %1 to i32\n  %%t%d+ = add i32 %2, 1\n"),
        where .. ": bit zero is lane one\n" .. decoded.llvm
    )
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

function M.emitPrintsTheGeneratedLlvmIr()
    local dir = project{["compute.nupp"] = COMPUTE}
    local decoded, raw, code, where = lowered(dir, PINNED .. "--json compute.nupp")
    test.equal(code, 0, raw)

    local out = decoded.llvm
    local body = out:match("define void @ks_escapes__avx2%(.-\n}\n")
    assert(body, where .. ": the exported symbol is defined: " .. out)
    assert(
        body:find("(ptr noalias captures(none) %p_out, ", 1, true),
        where .. ": the writable span carries the disjointness ownership proved: " .. body
    )
    assert(not body:find(" x double>", 1, true), where .. ": no inferred vector: " .. body)
    local llvm, llvmCode = run(dir, PINNED .. "--emit llvm compute.nupp")
    test.equal(llvmCode, 0, llvm)
    test.equal(llvm, out, where .. ": `--emit llvm` prints the IR the report carries")
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
    return (require("nupp.tools.build.aot").toolchain()) ~= nil
end

-- Instructions come from LLVM's code generator, linked into nupp, which targets
-- any of its triples from any host; `PINNED` makes them the same everywhere.
function M.emitAsmShowsWhatLlvmMadeOfTheBody()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "--emit asm compute.nupp")
    test.equal(code, 0, out)
    assert(
        out:match("^%-%- compute%.nupp, x86_64%-unknown%-linux%-gnu, avx2, llvm [^\n]+\n") ~= nil,
        "the header names the file, the target, the tier and the code generator: " .. out
    )
    assert(out:find("ks_escapes (escapes), kernel:", 1, true), "the compiled body is named by both spellings: " .. out)
    assert(not out:find("forced_scalar", 1, true), "scalar loops have no generated oracle: " .. out)
end

function M.asmShowsOneFunctionWhenOneIsNamed()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "--emit asm --function ks_escapes compute.nupp")
    test.equal(code, 0, out)
    assert(out:find("ks_escapes (escapes), kernel:", 1, true), out)
    assert(not out:find("forced_scalar", 1, true), "only the symbol that was named is listed: " .. out)
end

-- A name nothing matches is the common mistake -- the source spells it one way
-- and the symbol another -- so the refusal says what it would have taken.
function M.asmSaysWhatItWouldHaveAccepted()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "--emit asm --function escape compute.nupp")
    test.equal(code, 1, out)
    assert(out:find("escapes", 1, true) and out:find("ks_escapes", 1, true), out)
end

-- The counts are the part two runs are compared on, so they have to be over the
-- listing rather than beside it.
function M.asmJsonCountsWhatItLists()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, PINNED .. "--json --emit asm compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    local asm = decoded.asm
    test.equal(asm.toolchain.command, "<llvm>", "the code generator answered: " .. out)
    assert(asm.toolchain.version ~= "", "and is named: " .. out)
    local flags = table.concat(asm.flags, " ")
    -- The options are the code generator's, and the numeric contract is in
    -- the IR -- no instruction carries a fast-math flag the source did not
    -- relax -- so none of them may loosen it.
    assert(flags:find("opt=3", 1, true), "the flags are the ones an artifact is built with: " .. flags)
    assert(flags:find("triple=x86_64-unknown-linux-gnu", 1, true), "for the target asked for: " .. flags)
    assert(not flags:lower():find("fast", 1, true), "no option relaxes the numeric contract: " .. flags)

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
    assert(not ir:find("simd vector", 1, true), where .. ": scalar source has no vector body: " .. ir)
    assert(ir:find("disjoint r0 r1", 1, true), where .. ": the alias matrix is in the IR: " .. ir)

    local binding = decoded.binding
    assert(
        binding:find("layoutof(Escape)", 1, true),
        where .. ": the wrapper checks the struct layout rather than trusting it: " .. binding
    )
    assert(binding:find("@unsafe do", 1, true), where .. ": the foreign call is the only unsafe part: " .. binding)
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
    assert(not ir:find("simd_load", 1, true), where .. ": scalar byte loads are not rewritten: " .. ir)

    local c = equivalenceMutation.text(
        "narrow-scalar-mapping",
        decoded.c,
        "uint8_t %*restrict p_flags",
        "uint32_t *restrict p_flags"
    )
    assert(
        c:find("uint8_t *restrict p_flags", 1, true),
        equivalenceMutation.active("narrow-scalar-mapping")
        and equivalenceMutation.marker("narrow-scalar-mapping", "wrong-result")
        or where .. ": the output pointer retains byte storage: " .. c
    )
    assert(c:find("const uint8_t *p_bytes", 1, true), where .. ": the input pointer retains const byte storage: " .. c)
    assert(not c:find("ks_exp_store_full_u8x8(p_flags", 1, true), where .. ": no inferred vector store: " .. c)

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

    local llvm = decoded.llvm
    local signature = llvm:match("define i32 @ks_delimiters__%w+%(([^\n]*)%)")
    assert(signature, "the scalar result crosses the native ABI: " .. llvm)
    assert(
        signature:find("%count_source, ", 1, true) and signature:find("%count_offsets", 1, true),
        "the two spans keep independent counts: " .. signature
    )
    assert(
        llvm:match("(%%t%d+) = zext i32 %%t%d+ to i64\n  (%%t%d+) = getelementptr inbounds nuw i32, ptr %%p_offsets, i64 %1\n  store i32 %%t%d+, ptr %2,"),
        "the proved zero-based cursor directly indexes the output: " .. llvm
    )

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
        ir:find("store offsets[written+1] = numeric_cast(local:f64 i)", 1, true),
        "the span-counted induction retains its numeric range before explicit wrapping: " .. ir
    )

    -- Span counts retain binary64 induction values rather than narrowing to
    -- int32. Explicit wrap therefore keeps its modular conversion.
    local llvm = decoded.llvm
    assert(
        llvm:match("(%%t%d+) = load double, ptr %%slot%d+\n  %%t%d+ = call i32 @nupp%.wrap%.u32%(double %1%)"),
        "the LLVM IR preserves the requested modular conversion of the binary64 index: " .. llvm
    )
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
    assert(baseline:find("ks_exp_load_full_u8x16", 1, true), baseline)

    local avx, avxCode = run(dir, "--target x86_64-unknown-linux-gnu --features avx2 --emit c simd.nupp")
    test.equal(avxCode, 0, avx)
    assert(avx:find("#define KS_SIMD_WIDTH 32", 1, true), avx)
    assert(avx:find("ks_exp_bits_u8x32", 1, true), avx)

    local neon, neonCode = run(dir, "--target aarch64-unknown-linux-gnu --emit ir simd.nupp")
    test.equal(neonCode, 0, neon)
    assert(neon:find("simd species(uint8,16)", 1, true), neon)
    assert(neon:find("simd_load", 1, true) and neon:find("simd_mask_count", 1, true), neon)
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
    local decoded, raw, code, where = lowered(dir, "--json switch.nupp")
    test.equal(code, 0, raw)
    assert(
        decoded.ir:find("if eq(local:f64 $switch_selector_", 1, true),
        where .. ": the arms are binary64 comparisons: " .. decoded.ir
    )
    test.equal(decoded.llvm:find("\n  switch ", 1, true), nil, "binary64 is not converted for native switch")
    assert(
        decoded.llvm:match("%%t%d+ = fcmp oeq double %%t%d+, 0x3FF0000000000000\n  br i1 "),
        where .. ": each arm is a comparison branch: " .. decoded.llvm
    )
end

function M.jsonReportsAScalarLoop()
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
    test.equal(#only.loops, 1)
    test.equal(only.loops[1].kind, "map")
    test.equal(only.loops[1].outcome, "scalar")
    assert(only.loops[1].nodes > 0)
    assert(decoded.ir and decoded.c and decoded.binding, "all three artifacts are carried")
end

-- Two scalar functions over one struct and two arithmetic widths.
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
    test.equal(decoded.functions[1].regions, nil)
    test.equal(decoded.functions[2].regions, nil)

    -- One struct declared once, with each function bringing its own body.
    local llvm = decoded.llvm
    test.equal(select(2, llvm:gsub("%%struct%.KsSample = type ", "")), 1, "the shared struct is declared once")
    for _, symbol in ipairs({"ks_scale", "ks_brighten"}) do
        assert(llvm:find("define void @" .. symbol .. "__avx2(", 1, true), symbol .. " is defined")
    end

    local binding = decoded.binding
    assert(
        binding:find("scale = scale", 1, true) and binding:find("brighten = brighten", 1, true),
        "the generated module exports both wrappers: " .. binding:sub(-200)
    )
end

function M.armHasOneTierAndNeedsNoSelection()
    local dir = project{["compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--json --target aarch64-apple-darwin compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.target.tier, "neon", "its 16-byte registers are mandatory, so there is nothing to opt into")
    test.equal(decoded.functions[1].regions, nil)
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
    builder.setScratchWord(scratch, nupp.math.u32.wrap(0), count)
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
        nupp.math.u32.add(direct, packedState)
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
    assert(decoded.ir:find("u64_mul", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_builder_integer64", 1, true), decoded.ir)
    assert(decoded.ir:find("lua_builder_decimal64", 1, true), decoded.ir)
    assert(decoded.c:find("KsLuaBuilder", 1, true), decoded.c)
    assert(decoded.c:find("uint32_t inline_words[32]", 1, true), decoded.c)
    assert(decoded.c:find("lua_rawget(L, -10000)", 1, true), decoded.c)
    assert(decoded.c:find("static const char", 1, true), decoded.c)
    assert(decoded.c:find("KsLuaScratchU32", 1, true), decoded.c)
    assert(decoded.c:find("KsLuaScratchU8", 1, true), decoded.c)
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
    local out, code = run(dir, PINNED .. "--emit llvm classes.g.nupp")
    test.equal(code, 0, out)
    assert(
        out:find('constant [5 x i8] c"\\01\\02\\22\\5C\\00"', 1, true),
        "an escaped constant is placed as the four bytes it denotes: " .. out
    )
    assert(
        out:find('constant [4 x i8] c"a\\22b\\00"', 1, true),
        "and one holding a quote is placed rather than refused: " .. out
    )
end

function M.aFileWithNoAotFunctionIsAnError()
    local dir = project{["plain.nupp"] = "local m = {}\n\nreturn m\n"}
    local out, code = run(dir, "plain.nupp")
    test.equal(code, 1, out)
    assert(out:find("no @aot function", 1, true), "which says so: " .. out)
end

function M.assignedCountedIndicesDoNotKeepTheirSpanProof()
    local dir = project{
        [
            "changed.nupp"
        ] = [[
local span = require("nupp.mem.span")
@aot
local function acc(borrows input: span.Span<uint32>): number
    local total = 0
    for outer = 1, 2 do
        for cursor = 1, #input do
            cursor = 0
            total = total + input[cursor]
        end
    end
    return total
end
return {acc = acc}
]]
    }
    local out, code = run(dir, "changed.nupp")
    test.equal(code, 1, out)
    assert(out:find("changed.nupp:8:", 1, true), out)
    assert(out:find("an assigned counted-loop index does not prove span access bounds", 1, true), out)
    assert(not out:find("stack traceback", 1, true), out)
end

function M.cpuCountedLoopsRefuseExplicitStepsAtTheLoop()
    for _, step in ipairs({"1", "0", "-1"}) do
        local dir = project{
            [
                "step.nupp"
            ] = (
                [=[
@aot
local function acc(): number
    local total = 0
    for cursor = 1, 3, %s do
        total = total + cursor
    end
    return total
end
return {acc = acc}
]=]
            ):format(step)
        }
        local out, code = run(dir, "step.nupp")
        test.equal(code, 1, out)
        assert(out:find("step.nupp:4:5: aot: a native nested for loop takes no explicit step", 1, true), out)
        assert(not out:find("stack traceback", 1, true), out)
    end
end

function M.countedLoopEntryUsesTheSelectedRuntime()
    local dir = project{
        [
            "entry.nupp"
        ] = [[
@aot
local function entry(first: number, last: number): number
    for cursor = first, last do
        return 1 / cursor
    end
    return 0
end
return {entry = entry}
]]
    }
    for _, selection in ipairs({
        {"x86_64-unknown-linux-gnu", "baseline", "luajit-single"},
        {"aarch64-apple-darwin", "neon", "luajit-dual"},
        {"wasm32-unknown-emscripten", "simd128", "luajit-single"},
        {"wasm32-unknown-emscripten", "simd128", "luajit-single", "luajit"},
    }) do
        local dialect = selection[4] and " --dialect " .. selection[4] or ""
        local out, code = run(
            dir,
            "--target " .. selection[1] .. " --features " .. selection[2] .. dialect .. " --emit llvm entry.nupp"
        )
        test.equal(code, 0, out)
        -- LuaJIT's dual-number VM starts a loop whose bound is an integer at
        -- an integer zero, so `-0.0` becomes `0.0` exactly there.
        local normalized = out:match(
            "(%%t%d+) = call i32 @nupp%.wrap%.u32%(double %%t%d+%)\n  (%%t%d+) = sitofp i32 %1 to double\n  (%%t%d+) = fcmp oeq double %%t%d+, %2\n"
        ) ~= nil
        test.equal(normalized, selection[3] == "luajit-dual", selection[1] .. " dual-number entry")
        local prepared = out:match("fsub double %%t%d+, 1%.0\n") ~= nil
        test.equal(prepared, false, selection[1] .. " uses LuaJIT loop entry")
    end
end

function M.aotRejectsTheRemovedCallerDialect()
    local dir = project{
        [
            "caller.nupp"
        ] = [[
local enabled = jit.status()
@aot
local function entry(value: number): number
    return value + 1
end
return {entry = entry, enabled = enabled}
]]
    }
    local target = "--target wasm32-unknown-emscripten --emit llvm "
    local accepted, acceptedCode = run(dir, target .. "--dialect luajit caller.nupp")
    test.equal(acceptedCode, 0, accepted)
    local refused, refusedCode = run(dir, target .. "--dialect lua51 caller.nupp")
    assert(refusedCode ~= 0, refused)
    assert(refused:find("option --dialect does not take lua51; expected luajit", 1, true), refused)
end

function M.aotRejectsAnUnknownCallerDialect()
    local dir = project{
        [
            "entry.nupp"
        ] = [[
@aot
local function entry(value: number): number
    return value + 1
end
return {entry = entry}
]]
    }
    local out, code = run(dir, "--dialect lua54 entry.nupp")
    assert(code ~= 0, "an unsupported caller dialect must fail")
    assert(out:find("option --dialect does not take lua54; expected luajit", 1, true), out)
    assert(not out:find("stack traceback", 1, true), out)
end

function M.unrolledCountedLoopsRetainRuntimeCompatibilityGuards()
    local dir = project{
        [
            "unrolled.nupp"
        ] = [[
@aot
local function total(value: number): number
    local result = value
    for cursor = 1, 2 do result = result + cursor end
    return result
end
return {total = total}
]]
    }
    local c, code = run(dir, "--target x86_64-unknown-linux-gnu --features baseline --emit c unrolled.nupp")
    test.equal(code, 0, c)
    assert(not c:find("ks_for_counter_", 1, true), "the fixture really unrolls its counted loop")
    local out, bindingCode = run(
        dir,
        "--target x86_64-unknown-linux-gnu --features baseline --emit binding unrolled.nupp"
    )
    test.equal(bindingCode, 0, out)
    assert(out:find("AOT numeric-for runtime mismatch", 1, true), "unrolling retains original runtime dependency")
end

function M.aForBoundOutsideInt32RetainsItsNumericValue()
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
]]
    }
    local decoded, raw, code, where = lowered(dir, "--json bigbound.nupp")
    test.equal(code, 0, "a binary64 counted bound is not narrowed\n" .. raw)
    assert(decoded.ir:find(".. constant:f64 3000000000 ", 1, true), where .. ": " .. decoded.ir)
    -- 0x41E65A0BC0000000 is 3000000000.0: the counter is a double compared
    -- against the bound's own value.
    assert(
        decoded.llvm:match("%%t%d+ = fcmp ole double %%t%d+, 0x41E65A0BC0000000\n"),
        where .. ": " .. decoded.llvm
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
    local out, code = run(dir, "--emit llvm nested.nupp")
    test.equal(code, 0, out)
    assert(
        out:match("%%t%d+ = icmp ule i64 %%t%d+, %%count_weights\n"),
        "the nested loop counts the span it reads: " .. out
    )

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

function M.aNestedLoopMovingACursorRetiresTheEnclosingProof()
    -- A cursor moved by a nested loop cannot keep the enclosing range proof.
    local dir = project{
        [
            "annotated.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function scan(borrows bytes: span.Span<number>, exclusive out: span.WriteSpan<number>): number
    local cursor: uint32 = nupp.math.u32.wrap(0)
    local total = 0.0
    if cursor < #bytes then
        while total < 10.0 do
            total = total + bytes[cursor + 1]
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
    test.equal(code, 1, "a cursor the nested loop moves is not proved by the enclosing check\n" .. out)
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

--- The LLVM definition of the entry `symbol` compiles to, at whatever tier:
--- `@ks_scan__neon`, never its `_forced_scalar` oracle twin.
local function kernelBody(llvm, symbol)
    local body = llvm:match("define [^\n]- @" .. symbol .. "__%w+%(.-\n}\n")
    assert(body, "the kernel " .. symbol .. " is emitted:\n" .. llvm)
    return body
end

--- The oracle twin of `symbol`, which LLVM is told not to optimize.
local function oracleBody(llvm, symbol)
    local body = llvm:match("define [^\n]- @" .. symbol .. "_forced_scalar__%w+%(.-\n}\n")
    assert(body, "the oracle of " .. symbol .. " is emitted:\n" .. llvm)
    local group = assert(body:match("^[^\n]- #(%d+) {\n"), body)
    assert(
        llvm:find("\nattributes #" .. group .. " = { noinline optnone ", 1, true),
        "the oracle of " .. symbol .. " is left unoptimized:\n" .. llvm
    )
    return body
end

--- Whether `body` reads or writes `span` at an offset a proof holds in bounds:
--- a `nuw` element address, which a checked access never takes.
local function provenAccess(body, span)
    return body:match("getelementptr inbounds nuw [%w]+, ptr %%p_" .. span .. ", ") ~= nil
end

--- Whether `body` measures the room left in `span` before touching it, as a
--- checked access does.
local function checkedAccess(body, span)
    return body:find("sub i64 %count_" .. span .. ", ", 1, true) ~= nil
end

function M.aSpeciesBindingIsDecidedPerTier()
    -- `if species = simd.species(array.uint32) then` is the vector loop on
    -- a tier that has vectors and nothing at all on one that does not; the
    -- scalar tail that follows is the same code on every tier, its span read
    -- proved by the left of the `and` it sits under.
    local dir = project{["scan.nupp"] = CONDITIONAL_SCAN}
    local tail = "%%t%d+ = getelementptr inbounds nuw i32, ptr %%p_cps, i64 %%t%d+\n  %%t%d+ = load i32, ptr %%t%d+, align 4\n  %%t%d+ = icmp ugt i32 %%t%d+, 15\n"
    for _, tier in ipairs({
        {args = "--target aarch64-apple-darwin --features neon", lanes = 4},
        {args = "--target x86_64-unknown-linux-gnu --features baseline", lanes = 4},
        {args = "--target x86_64-unknown-linux-gnu --features avx2", lanes = 8},
        {args = "--target wasm32-unknown-emscripten --features simd128", lanes = 4},
    }) do
        local decoded, raw, code = lowered(dir, tier.args .. " --json scan.nupp")
        test.equal(code, 0, raw)
        local body = kernelBody(decoded.llvm, "ks_scan")
        assert(
            body:match(
                "(%%t%d+) = getelementptr inbounds nuw i32, ptr %%p_cps, i64 %%t%d+\n.-= load <"
                .. tier.lanes .. " x i32>, ptr %1, align 4\n"
            ),
            tier.args .. ": the arm is the vector loop\n" .. body
        )
        assert(
            body:match("zext i32 " .. tier.lanes .. " to i64\n  %%t%d+ = add i64 %%t%d+, %%t%d+\n  %%t%d+ = icmp ule i64 %%t%d+, %%count_cps\n"),
            tier.args .. ": species.lanes is the tier's constant\n" .. body
        )
        assert(
            body:match("= call i64 @llvm%.cttz%.i64%(.-\n  %%t%d+ = trunc i64 %%t%d+ to i32\n  store i32 "),
            tier.args .. ": first() is a uint32\n" .. body
        )
        assert(body:match(tail), tier.args .. ": the scalar tail follows\n" .. body)
    end

    local decoded, raw, code = lowered(dir, "--target wasm32-unknown-emscripten --features scalar --json scan.nupp")
    test.equal(code, 0, raw)
    local body = kernelBody(decoded.llvm, "ks_scan")
    assert(not body:find(" x i32>", 1, true), "the scalar tier drops the arm\n" .. body)
    assert(body:match(tail), "and keeps the tail\n" .. body)
    assert(not decoded.ir:find("species", 1, true), "nothing of the test survives lowering\n" .. decoded.ir)
end

function M.aProvenVectorAccessIsOneCopyAndAnIntegerCompare()
    -- `cursor + s.lanes <= #span`, taken exactly in u64, is the guard that
    -- proves a whole vector at `cursor + 1` lies inside the span. Under it
    -- an unmasked load or store is one vector access at the cursor. Where
    -- every span fits in 32 bits the index cannot wrap and the loop runs
    -- that way throughout; elsewhere each pass proves its index does not
    -- wrap, and one that might keeps the checked access. The tail is a
    -- checked prefix access of the lanes its mask names, the lane count
    -- taken once, and moves its partial vector through registers rather
    -- than a stack array. Nothing in the loop goes through a double.
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
    local body = kernelBody(decoded.llvm, "ks_add")
    assert(
        body:find("icmp ule i64 %count_input, 4294967295\n", 1, true)
            and body:find("icmp ule i64 %count_output, 4294967295\n", 1, true),
        "the loop is versioned on whether its spans fit in 32 bits\n" .. body
    )
    local loop = body:match("\nwhile%.head%.%d+:\n.-\nwhile%.end%.%d+:\n")
    assert(loop, "the vector loop\n" .. body)
    for _, span in ipairs({"input", "output"}) do
        assert(
            loop:match("zext i32 16 to i64\n  %%t%d+ = add i64 %%t%d+, %%t%d+\n  %%t%d+ = icmp ule i64 %%t%d+, %%count_" .. span .. "\n"),
            "the guard is exact and compares the count as an integer\n" .. loop
        )
    end
    assert(
        loop:match("(%%t%d+) = getelementptr inbounds nuw i8, ptr %%p_input, i64 %%t%d+\n  br i1 true, label %%simd%.yes%.%d+, label %%simd%.no%.%d+\nsimd%.yes%.%d+:\n  %%t%d+ = load <16 x i8>, ptr %1, align 1\n")
            and loop:match("(%%t%d+) = getelementptr inbounds nuw i8, ptr %%p_output, i64 %%t%d+\n  br i1 true, label %%simd%.yes%.%d+, label %%simd%.no%.%d+\nsimd%.yes%.%d+:\n  store <16 x i8> %%t%d+, ptr %1, align 1\n"),
        "the proven load and store are bare vector accesses\n" .. loop
    )
    assert(not loop:find("double", 1, true), "nothing in the loop goes through a double\n" .. loop)
    assert(
        body:match("add nuw i64 %%t%d+, 16\n  %%t%d+ = icmp ule i64 %%t%d+, 4294967295\n"),
        "where a span may not fit, the unchecked path proves its index does not wrap\n" .. body
    )
    assert(
        loop:match("%%t%d+ = icmp ult i64 %%t%d+, %%count_input\n  %%t%d+ = sub i64 %%count_input, %%t%d+\n"),
        "wrapping indices keep the original checked access\n" .. loop
    )

    -- A `tail(n)` mask activates the first n lanes, so the tail is a prefix
    -- access of at most n elements, still bounded by the span's count.
    local tail = assert(body:match("\ncursors%.done%.%d+:\n.*"), body)
    local prefixes = {}
    local room = "icmp ult i64 %%t%d+, %%count_(%w+)\n  %%t%d+ = sub i64 %%count_%w+, %%t%d+\n"
    for span, active in tail:gmatch(room .. ".-icmp ult i32 (%%t%d+), %%t%d+\n") do
        prefixes[#prefixes + 1] = {span = span, active = active}
    end
    test.equal(#prefixes, 2, "the tail load and store are each a checked prefix\n" .. tail)
    test.equal(prefixes[1].span, "input", tail)
    test.equal(prefixes[2].span, "output", tail)
    test.equal(prefixes[1].active, prefixes[2].active, "the lane count is taken once, where the mask is\n" .. tail)
    assert(
        tail:match("switch i32 %%t%d+, label %%tail%.done%.%d+ %[")
            and tail:find("= insertelement <16 x i8> ", 1, true)
            and tail:find("= extractelement <16 x i8> ", 1, true),
        "a partial vector is gathered into and scattered from a register\n" .. tail
    )
    assert(
        not body:match("alloca %[%d+ x i8%]"),
        "and never goes through a stack array\n" .. body
    )
end

function M.aProofNeedsTheGuardAndTheCursorItLeft()
    -- A guard for one span proves nothing about another; a masked access
    -- keeps its mask and its checks; a cursor moved between the guard and
    -- the access is no longer the one the guard was about. Each stays a
    -- checked access, measuring the room its span has left.
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
    local other = kernelBody(decoded.llvm, "ks_other")
    assert(
        checkedAccess(other, "output") and not provenAccess(other, "output"),
        "the unguarded span is checked\n" .. other
    )
    assert(provenAccess(other, "input"), "while the guarded one is proven\n" .. other)
    local masked = kernelBody(decoded.llvm, "ks_masked")
    assert(
        checkedAccess(masked, "input") and masked:find("select <16 x i1> ", 1, true),
        "a masked access keeps its mask and its checks\n" .. masked
    )
    local moved = kernelBody(decoded.llvm, "ks_moved")
    assert(checkedAccess(moved, "input"), "a moved cursor loses the proof\n" .. moved)
    assert(
        not provenAccess(moved, "input") and not provenAccess(masked, "input"),
        "no bare access without a proof\n" .. decoded.llvm
    )
end

function M.aGuardProvesASpanTheEntryGuardsHoldNoShorter()
    -- `assert(#output == #input)` makes a guard on `#input` a guard on
    -- `#output` too, for whole-vector stores and for a scalar tail store.
    -- A span the entry guards may hold shorter stays checked.
    local dir = project{
        [
            "related.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function equal(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input, "length mismatch")
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1) * 2.0)
        cursor = cursor + s.lanes
    end
    while cursor < #input do
        output[cursor + 1] = input[cursor + 1] * 2.0
        cursor = cursor + 1
    end
end

@aot
local function longer(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output >= #input, "output too short")
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1))
        cursor = cursor + s.lanes
    end
end

@aot
local function shorter(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output <= #input, "output too long")
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1))
        cursor = cursor + s.lanes
    end
end
return {equal = equal, longer = longer, shorter = shorter}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json related.nupp")
    test.equal(code, 0, raw)
    local vectorStore = "(%%t%d+) = getelementptr inbounds nuw double, ptr %%p_output, i64 %%t%d+\n.-store <4 x double> %%t%d+, ptr %1, "
    local equal = kernelBody(decoded.llvm, "ks_equal")
    assert(equal:match(vectorStore), "an equal span is proven\n" .. equal)
    assert(
        equal:match("(%%t%d+) = getelementptr inbounds nuw double, ptr %%p_output, i64 %%t%d+\n  store double %%t%d+, ptr %1, "),
        "and so is its scalar tail\n" .. equal
    )
    local longer = kernelBody(decoded.llvm, "ks_longer")
    assert(longer:match(vectorStore), "a span held no shorter is proven\n" .. longer)
    local shorter = kernelBody(decoded.llvm, "ks_shorter")
    assert(checkedAccess(shorter, "output"), "a span that may be shorter stays checked\n" .. shorter)
    assert(not provenAccess(shorter, "output"), "with no bare access\n" .. shorter)

    local refused = project{
        [
            "tail.nupp"
        ] = [[
local span = require("nupp.mem.span")

@aot
local function tail(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output <= #input, "output too long")
    local cursor: uint32 = 0
    while cursor < #input do
        output[cursor + 1] = input[cursor + 1]
        cursor = cursor + 1
    end
end
return {tail = tail}
]],
    }
    local out, refusedCode = run(refused, "tail.nupp")
    test.equal(refusedCode, 1, out)
    assert(out:find("span stores need a counted-loop index or cursor + 1 under cursor < #span", 1, true), out)
end

function M.aGuardedCursorLoopIsVersionedWhereItsCursorCannotWrap()
    -- Under `cursor + s.lanes <= #input` the cursor cannot wrap once `#input`
    -- fits in 32 bits, so that copy of the loop skips the wrap check on its
    -- accesses and runs two iterations' bodies per pass (about 64 bytes). A
    -- larger span runs the loop as written, checking each pass. The guards
    -- make the two counts one, so the loop names only one of them. A cursor
    -- written twice is an ordinary 32-bit value the guard reads again every
    -- pass, so it compiles too. The oracle is the loop as written everywhere.
    local dir = project{
        [
            "wide.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function scale(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input, "length mismatch")
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1) * 2.0)
        cursor = cursor + s.lanes
    end
end

@aot
local function twice(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input, "length mismatch")
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1))
        cursor = cursor + 1
        cursor = cursor + 1
    end
end
return {scale = scale, twice = twice}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json wide.nupp")
    test.equal(code, 0, raw)
    local llvm = decoded.llvm
    local scale = kernelBody(llvm, "ks_scale")
    assert(
        scale:match("(%%t%d+) = icmp ule i64 %%count_output, 4294967295\n.-br i1 %%t%d+, label %%cursors%.wide%.%d+, label %%cursors%.narrow%.%d+\n"),
        "the loop is versioned on the count fitting in 32 bits\n" .. scale
    )
    local fits = assert(scale:match("\ncursors%.wide%.%d+:\n.-\ncursors%.narrow%.%d+:\n"), scale)
    local larger = assert(scale:match("\ncursors%.narrow%.%d+:\n.-\ncursors%.done%.%d+:\n"), scale)
    assert(
        fits:match("getelementptr inbounds nuw double, ptr %%p_output, i64 %%t%d+\n  br i1 true, ")
            and not fits:find("4294967295", 1, true),
        "the copy that fits has no wrap check on its accesses\n" .. fits
    )
    local loopId = fits:match("br label %%while%.head%.%d+, !llvm%.loop (!%d+)\n")
    local hint = loopId and llvm:match("\n" .. loopId .. " = distinct !{" .. loopId .. ", (!%d+)}\n")
    assert(
        hint and llvm:find("\n" .. hint .. ' = !{!"llvm.loop.unroll.count", i32 2}\n', 1, true),
        "and a 32-byte vector runs two bodies a pass\n" .. llvm
    )
    assert(not fits:find("%count_input", 1, true), "the loop names one of the two equal counts\n" .. fits)
    assert(
        larger:match("add nuw i64 %%t%d+, 4\n  %%t%d+ = icmp ule i64 %%t%d+, 4294967295\n"),
        "a larger span runs the loop as written, checking each pass\n" .. larger
    )
    assert(larger:match("= add i32 %%t%d+, 4\n"), "with its wrapping cursor\n" .. larger)
    kernelBody(llvm, "ks_twice")
    local oracle = oracleBody(llvm, "ks_scale")
    assert(not oracle:find("cursors.wide", 1, true), "the oracle is not versioned\n" .. oracle)
end

function M.anIntegerCompareFeedingAnyIsOneReductionAndAFlagStaysAFlag()
    -- `(x >= c):any()` over integer lanes asks one horizontal question of
    -- `x`, and `(x ~= 0):any()` whether any bit is set; neither forms the mask.
    -- A boolean the loop reassigns is a variable of its own, kept as a flag
    -- rather than rebuilt from the comparison every pass.
    local dir = project{
        [
            "scan.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function scan(borrows input: span.Span<uint8>): uint32
    local s = assert(simd.species(array.uint8))
    local cursor: uint32 = 0
    local ascii = true
    while cursor + s.lanes <= #input do
        local bytes = s:load(input, cursor + 1)
        if (bytes >= 0x80):any() then
            ascii = false
        end
        if ((bytes ~ 0x20) ~= 0):any() and not ascii then
            break
        end
        cursor = cursor + s.lanes
    end
    return cursor
end
return {scan = scan}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json scan.nupp")
    test.equal(code, 0, raw)
    local body = kernelBody(decoded.llvm, "ks_scan")
    local reduction = "call i32 @llvm%%.aarch64%%.neon%%.u[maxin]+v%%.i32%%.v16i8%%(<16 x i8> %s%%)"
    assert(not body:find("icmp uge <16 x i8>", 1, true), "neither forms the mask\n" .. body)
    assert(not body:find("icmp ne <16 x i8>", 1, true), "neither forms the mask\n" .. body)
    assert(
        body:match("(%%t%d+) = call i32 @llvm%.aarch64%.neon%.umaxv%.i32%.v16i8%(<16 x i8> %%t%d+%)\n.-icmp uge i32 "),
        "aarch64 answers a compare against a bound with one horizontal max\n" .. body
    )
    local bits = body:match("(%%t%d+) = xor <16 x i8> %%t%d+, %%t%d+\n")
    assert(bits, "the bits under test\n" .. body)
    local _, reductions = body:gsub(reduction:format((bits:gsub("%%", "%%%%"))), "")
    test.equal(reductions, 1, "a test for any set bit is one reduction too\n" .. body)
    assert(
        body:find("alloca i1, ", 1, true) and body:find("store i1 false, ptr %slot", 1, true),
        "the flag is a variable of its own\n" .. body
    )
end

function M.aByteLookupOverFourTablesIsOneTableInstruction()
    -- `swizzle` with three or four tables continues one run of lanes; on a
    -- sixteen-lane byte species NEON answers it with `tbl` over three or four
    -- registers.
    local dir = project{
        [
            "lookup.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function lookup(exclusive output: span.WriteSpan<uint8>, borrows table: span.Span<uint8>, borrows input: span.Span<uint8>): nil
    local s = assert(simd.species(array.uint8, 16))
    local t0 = s:load(table, 1)
    local t1 = s:load(table, 17)
    local t2 = s:load(table, 33)
    local t3 = s:load(table, 49)
    local index = s:load(input, 1)
    s:store(output, 1, t0:swizzle(index, t1, t2))
    s:store(output, 17, t0:swizzle(index, t1, t2, t3))
end
return {lookup = lookup}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json lookup.nupp")
    test.equal(code, 0, raw)
    local body = kernelBody(decoded.llvm, "ks_lookup")
    local _, triples = body:gsub("call <16 x i8> @llvm%.aarch64%.neon%.tbl3%.v16i8%(", "")
    local _, quads = body:gsub("call <16 x i8> @llvm%.aarch64%.neon%.tbl4%.v16i8%(", "")
    test.equal(triples, 1, "three tables are one NEON table instruction\n" .. body)
    test.equal(quads, 1, "and so are four\n" .. body)
    oracleBody(decoded.llvm, "ks_lookup")

    local asm = neonAsm(dir, "lookup.nupp")
    assert(
        asm:match("tbl%.16b v%d+, { v%d+, v%d+, v%d+ }, v%d+") and asm:match("tbl%.16b v%d+, { v%d+, v%d+, v%d+, v%d+ }, v%d+"),
        "which reach the target as `tbl` over three and four registers\n" .. asm
    )
end

function M.anInterleavedLoadIsOneLd3AndTheStoreOneSt4()
    -- Each result of `loadTriples` is its own strided view of one load of the
    -- whole run, proved by the loop condition like a load of three vectors;
    -- LLVM reads the run once, with `ld3`. `storeQuads` is one store of four
    -- vectors interleaved, `st4`. Outside the proof both take their checked
    -- forms, and the oracle is left unoptimized.
    local dir = project{
        [
            "records.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function widen(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): uint32
    local s = assert(simd.species(array.uint8))
    local at: uint32 = 0
    local out: uint32 = 0
    while at + 3 * s.lanes <= #input and out + 4 * s.lanes <= #output do
        local r, g, b = s:loadTriples(input, at + 1)
        s:storeQuads(output, out + 1, b, g, r, s:splat(255))
        at = at + 3 * s.lanes
        out = out + 4 * s.lanes
    end
    while at + 2 * s.lanes <= #input and out + 2 * s.lanes <= #output do
        local x, y = s:loadPairs(input, at + 1)
        s:storePairs(output, out + 1, y, x)
        at = at + 2 * s.lanes
        out = out + 2 * s.lanes
    end
    local r, g, b = s:loadTriples(input, at + 1)
    s:storeTriples(output, out + 1, b, g, r)
    return out
end
return {widen = widen}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json records.nupp")
    test.equal(code, 0, raw)
    local body = kernelBody(decoded.llvm, "ks_widen")
    assert(
        body:match("(%%t%d+) = getelementptr inbounds nuw i8, ptr %%p_input, i64 %%t%d+\n.-= load <48 x i8>, ptr %1, align 1\n"),
        "a proved run is one load\n" .. body
    )
    for part = 0, 2 do
        local stride = "shufflevector <48 x i8> %%t%d+, <48 x i8> poison, <16 x i32> <i32 "
            .. part .. ", i32 " .. part + 3 .. ", i32 " .. part + 6 .. ", "
        assert(body:match(stride), "part " .. part .. " is every third byte of it\n" .. body)
    end
    assert(
        body:match("(%%t%d+) = getelementptr inbounds nuw i8, ptr %%p_output, i64 %%t%d+\n.-store <64 x i8> %%t%d+, ptr %1, align 1\n"),
        "a proved store is one store\n" .. body
    )
    assert(checkedAccess(body, "input"), "an unproved run is checked\n" .. body)
    assert(checkedAccess(body, "output"), "and so is its store\n" .. body)
    oracleBody(decoded.llvm, "ks_widen")

    local asm = neonAsm(dir, "records.nupp")
    local _, reads = asm:gsub("ld3%.16b", "")
    assert(reads >= 1, "the run is read with ld3\n" .. asm)
    assert(asm:find("st4.16b", 1, true), "and written with st4\n" .. asm)
    -- Swapping each pair back is one `rev16` where LLVM sees the load and
    -- store together; the checked path still interleaves with st2.
    assert(
        asm:find("ld2.16b", 1, true) and asm:find("st2.16b", 1, true)
            or asm:find("rev16.16b", 1, true) and asm:find("st2.16b", 1, true),
        "pairs are ld2 and st2, or one pair swap\n" .. asm
    )

    -- A result is only ever a local's initializer.
    local refused = project{
        [
            "misplaced.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function misplaced(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): nil
    local s = assert(simd.species(array.uint8))
    s:store(output, 1, s:loadPairs(input, 1) + 1)
end
return {misplaced = misplaced}
]],
    }
    local out, refusedCode = run(refused, "--target aarch64-apple-darwin --features neon misplaced.nupp")
    assert(refusedCode ~= 0 and out:find("initializes up to 2 locals", 1, true), out)
end

function M.anUnrolledLoopReadsEveryCopyBeforeItWrites()
    -- The unrolled copies of a versioned loop read the spans they never write
    -- first, every copy at its own cursor, and then do their work; a store no
    -- longer separates one copy from the next copy's loads. A span the body
    -- writes keeps its reads in place, and the scalar oracle is not unrolled.
    local dir = project{
        [
            "unrolled.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function scale(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>, factor: number): nil
    assert(#output == #input)
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        s:store(output, cursor + 1, s:load(input, cursor + 1) * factor)
        cursor = cursor + s.lanes
    end
end

@aot
local function double(exclusive values: span.WriteSpan<number>): nil
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #values do
        s:store(values, cursor + 1, s:load(values, cursor + 1) * 2)
        cursor = cursor + s.lanes
    end
end
return {scale = scale, double = double}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json unrolled.nupp")
    test.equal(code, 0, raw)
    local body = kernelBody(decoded.llvm, "ks_scale")
    assert(body:find(", !llvm.loop !", 1, true), "the versioned loop is unrolled\n" .. body)
    local oracle = oracleBody(decoded.llvm, "ks_scale")
    assert(not oracle:find("!llvm.loop", 1, true), "the oracle is not unrolled\n" .. oracle)

    -- The order the instructions run in, in the first loop of each entry.
    local function order(symbol)
        local asm, asmCode = run(
            dir,
            "--target aarch64-apple-darwin --features neon --emit asm --function " .. symbol .. " unrolled.nupp"
        )
        test.equal(asmCode, 0, asm)
        local first = asm:find("\n%s+ldp%s+q")
        local second = first and asm:find("\n%s+ldp%s+q", first + 1)
        local store = asm:find("\n%s+stp%s+q")
        assert(first and second and store, symbol .. " has two copies of its body\n" .. asm)
        return second < store, asm
    end
    local hoisted, asm = order("ks_scale")
    assert(hoisted, "both copies read before either writes\n" .. asm)
    local inPlace, inPlaceAsm = order("ks_double")
    assert(not inPlace, "a written span keeps its reads in place\n" .. inPlaceAsm)
end

function M.aLoopCarriedMaskStaysInItsRegister()
    -- A mask a loop reassigns is carried lane-wide and pinned to its vector
    -- registers, so LLVM does not carry it as one bit a lane, and the loop
    -- tests that register rather than rebuilding it.
    local dir = project{
        [
            "halve.nupp"
        ] = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function halve(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input, "length mismatch")
    local s = assert(simd.species(array.number, 4))
    local cursor: uint32 = 0
    while cursor + s.lanes <= #input do
        local value = s:load(input, cursor + 1)
        local live = value > 1
        while live:any() do
            value = live:select(value * 0.5, value)
            live = value > 1
        end
        s:store(output, cursor + 1, value)
        cursor = cursor + s.lanes
    end
end
return {halve = halve}
]],
    }
    local decoded, raw, code = lowered(dir, "--target aarch64-apple-darwin --features neon --json halve.nupp")
    test.equal(code, 0, raw)
    local body = kernelBody(decoded.llvm, "ks_halve")
    local slot = body:match("(%%slot%d+) = alloca <4 x i64>\n")
    assert(slot, "the carried mask has a lane-wide slot\n" .. body)
    assert(not body:find("alloca <4 x i1>", 1, true), "and no slot of one bit a lane\n" .. body)
    local escaped = slot:gsub("%%", "%%%%")
    local _, pinned = body:gsub(
        'call <2 x i64> asm "", "=w,0"%(<2 x i64> %%t%d+%)\n  %%t%d+ = shufflevector <2 x i64> %%t%d+, <2 x i64> %%t%d+, <4 x i32> <i32 0, i32 1, i32 2, i32 3>\n  store <4 x i64> %%t%d+, ptr '
            .. escaped .. "\n",
        ""
    )
    local _, stores = body:gsub("store <4 x i64> %%t%d+, ptr " .. escaped .. "\n", "")
    assert(pinned >= 2, "its definitions are pinned to their registers\n" .. body)
    test.equal(pinned, stores, "every one of them\n" .. body)
    assert(
        body:match("\nwhile%.head%.%d+:\n  %%t%d+ = load <4 x i64>, ptr " .. escaped .. "\n.-umaxp"),
        "and the loop tests the register it carries\n" .. body
    )
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
        assert(
            decoded.ir:find("simd_species_f32_preferred", 1, true),
            tier.args .. ": the preferred shape\n" .. decoded.ir
        )
        assert(decoded.ir:find("simd_vector_f32_fixed8", 1, true), tier.args .. ": the fixed shape\n" .. decoded.ir)
        local body = kernelBody(decoded.llvm, "ks_total")
        assert(
            body:find("= load <" .. tier.lanes .. " x float>, ptr %t", 1, true),
            tier.args .. ": the tier's width\n" .. body
        )
        assert(body:find("<8 x float>", 1, true), tier.args .. ": and the fixed one\n" .. body)
        assert(
            not decoded.llvm:find("needs vectors", 1, true),
            tier.args .. ": nothing of the assert survives\n" .. decoded.llvm
        )
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

function M.inspectionFindsNestedProjectAndCarriesSourcePositions()
    local dir = project{["nested/nupp.lua"] = 'return {include={"src"}}', ["nested/src/compute.nupp"] = COMPUTE}
    local out, code = run(dir, "--source-locations --json --emit c nested/src/compute.nupp")
    test.equal(code, 0, out)
    local decoded = require("testjson").decode(out)
    assert(decoded.c:find('#line ', 1, true), "inspection C carries authored positions")
    assert(decoded.c:find('nested/src/compute.nupp', 1, true), "C names the source file")
    if hasToolchain() then
        out, code = run(dir, "--json --emit asm nested/src/compute.nupp")
        test.equal(code, 0, out)
        local found, attributed = false, false
        for _, listing in ipairs(require("testjson").decode(out).asm.functions) do
            if listing.role == "kernel" then
                for _, instruction in ipairs(listing.instructions) do
                    if instruction.sourceFile and instruction.sourceFile:find("compute.nupp", 1, true) then
                        assert(instruction.sourceLine > 0)
                        found = true
                        attributed = attributed or #(instruction.loopIds or {}) > 0
                    end
                end
            end
        end
        assert(found, "native kernel instructions retain authored locations")
        assert(attributed, "native instructions identify their originating IR loops")
    end
end

return M
