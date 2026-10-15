-- The build's ahead-of-time policy.
--
-- Driven through the real binary, because the policy is a manifest key and what
-- it produces is a file on disk; neither is visible from inside the compiler.

local test = require("assert")
local aot = require("nupp.tools.build.aot")
local aotCompile = require("nupp.compiler.aot.compile")
local compilerCheck = require("nupp.compiler.check")
local diagnosticMod = require("nupp.compiler.diagnostics")
local envMod = require("nupp.compiler.project.env")
local parser = require("nupp.compiler.syntax.parser")
local targets = require("nupp.compiler.aot.target")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
-- `pwd` under Git Bash answers `/d/a/...`, which is a path for that shell and
-- not one the native `luajit.exe` can open. A file written to disk carries the
-- native spelling, because nothing rewrites a file.
local NATIVE_HERE = (HERE:gsub("^/([A-Za-z])/", "%1:/"))

-- A command line cannot carry it. The runner hands every test command to Git
-- Bash and turns `X:/` back into `/x/` on the way, so the shell can read the
-- paths in it -- and that reaches the whole line, including a `package.path`
-- addressed to the interpreter the shell is about to start rather than to the
-- shell. So the path travels in the shell's spelling and is converted by the
-- interpreter that reads it, after the rewrite has had its say.
local function searchPathPrelude()
    return (
        'package.path="build/native/?.lua;"' .. '..((%q):gsub("^/(%%a)/","%%1:/")).."/../build/?.lua;"..package.path;'
    ):format(HERE)
end

local NUPP = HERE .. "/../bin/nupp"

local KERNEL = [[
local span = require("nupp.mem.span")

local struct Sample
    value: float
    weight: float
end

local struct Decimal
    value: number
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
local function sumBytes(
    borrows first: span.Span<uint8>,
    borrows second: span.Span<uint8>
): (number, uint32, uint32)
    local total = 0.0
    for i = 1, #first do
        total = total + first[i]
    end
    for i = 1, #second do
        total = total + second[i]
    end
    return total, nupp.math.u32.wrap(#first), nupp.math.u32.wrap(#second)
end

@aot
local function fillDecimals(exclusive values: span.WriteSpan<Decimal>, value: number): nil
    for i = 1, #values do
        values[i].value = value
    end
end

return {
    scale = scale,
    sumBytes = sumBytes,
    fillDecimals = fillDecimals,
    Sample = Sample,
    Decimal = Decimal,
}
]]

local PLAIN = [[
local m = {}

--- An ordinary module with no `@aot` anywhere in it.
function m.greet(name: string): string
    return "hello " .. name
end

return m
]]

local CONST_KERNEL = [[
module constkernel

@aot
local function doubled<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do
        answer = answer * 2.0
    end
    return answer
end

local function doubled3(value: number): number
    return doubled(value, 3)
end

export = {doubled = doubled, doubled3 = doubled3}
]]

local function constProject(policy)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        (
            [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"constkernel"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]]
        ):format(policy)
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
    source:write(CONST_KERNEL)
    source:close()

    return dir
end

local function project(policy)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        (
            [[
return {
   include = {"src"},
   build = {
      targets = {
         native = {
            kind = "modules",
            entries = {"kernel", "plain"},
            outDir = "build/native",
            %s
         },
      },
   },
}
]]
        ):format(policy and ('aot = "' .. policy .. '",') or "")
    )
    manifest:close()
    for name, source in pairs({["src/kernel.nupp"] = KERNEL, ["src/plain.nupp"] = PLAIN}) do
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(source)
        handle:close()
    end

    return dir
end

local function gpuProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"gpucheck"}, outDir = "build/native",
      aot = "require",
   }}},
}
]]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/gpucheck.nupp", "wb"))
    source:write(
        [[
module gpucheck

local span = require("nupp.mem.span")

@aot(target = "gpu")
local function copy(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    assert(#output == #input)
    for index = 1, #output do
        output[index] = input[index]
    end
end

export const kernel = copy
]]
    )
    source:close()

    return dir
end

-- One binding read only inside the `@aot` body, and one read nowhere. A policy
-- that links replaces the whole declaration with its wrapper before the module
-- build checks the file, so the first of these has no reader left in the text
-- that gets checked and the second never had one.
local UNUSED_SOURCE = [[
local valueBuilder = require("nupp.codec.valuebuilder")

const READ_ONLY_IN_THE_BODY = "\001\002\003\004"

local trulyUnused = 42

@aot
local function entry(index: uint32, nullValue: any): any
    local state = valueBuilder.newSized(nullValue, nupp.math.u32.wrap(2), nupp.math.u32.wrap(8))
    valueBuilder.openArray(state, nupp.math.u32.wrap(1))
    valueBuilder.number(state, valueBuilder.byte(READ_ONLY_IN_THE_BODY, index) * 1.0)
    valueBuilder.close(state)

    return valueBuilder.finish(state)
end

return {entry = entry}
]]

local function unusedProject(policy)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        (
            [=[
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {"reader"}, outDir = "build/native",
      aot = "%s",
   }}},
}
]=]
        ):format(policy)
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/reader.nupp", "wb"))
    source:write(UNUSED_SOURCE)
    source:close()

    return dir
end

--- One store every fixture that makes no reuse assertion shares.
---
--- `NUPP_CACHE_DIR` is what a run over many small projects has for this: the
--- entries in it are keyed by what they were computed from and stamped with the
--- code that computed them, so two fixtures can only hit each other's entries
--- when the answer is the same answer. Every project here is a handful of files
--- over the same standard library, and each one used to pay to rediscover the
--- whole of it.
local sharedCacheDir = nil

local function sharedCache()
    if not sharedCacheDir then
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
        sharedCacheDir = dir
    end

    return sharedCacheDir
end

--- Fixtures whose case asserts what two builds of *that project* did.
---
--- A shared content store would make such an assertion depend on whichever
--- unrelated temporary project the worker built first. These keep reuse within
--- the fixture and nowhere else: successive builds of the directory still share
--- the cache whose behaviour the case is exercising, and nothing else reaches
--- it. Say so at the fixture rather than leaving it to the order cases run in.
local isolatedCaches = {}

--- Where a build of this fixture keeps its content-addressed stores.
local function cacheFor(dir)
    if isolatedCaches[dir] then
        return dir .. "/build/test-cache"
    end

    return sharedCache()
end

local function build(dir)
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_CACHE_DIR=%q NO_COLOR= '%s' build --target native 2>&1; echo \"__exit__:$?\""
            ):format(dir, cacheFor(dir), NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

local function check(dir)
    local pipe = assert(
        io.popen(
            (
                "cd %q && NUPP_CACHE_DIR=%q NO_COLOR= '%s' check 2>&1; echo \"__exit__:$?\""
            ):format(dir, cacheFor(dir), NUPP)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

-- The immutable baseline read-only assertions share. Cases that make cache
-- assertions get a fixture of their own below: suite slicing can run several
-- cases in one long-lived process, and a case that appends source or damages an
-- artifact must not decide what a later case starts from.
--
-- `require` is the one whose two reuse cases assert about the fixture itself, so
-- that policy's shared fixture keeps its own store.

--- The builder fixture, built once per policy, and a script run against it.
---
--- The cases below ask the same two projects -- one that links compiled code and
--- one that does not -- a different question about what an entry answers at run
--- time. The question travels in the script rather than in the source, so the
--- build is the same build every time, and building it per question paid for a
--- native compilation and a link per assertion. The directory comes back beside the
--- answer, so a failure still names which of the two fixtures produced it.

local function read(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()

    return text
end

local function buildTiers(triple, ceiling)
    return assert(require("nupp.compiler.aot.target").buildTiers(triple, ceiling))
end

-- The LLVM IR unit a tier was emitted as.
local function tieredUnit(dir, tier, stem)
    return dir .. "/build/native/aot/src/" .. (stem or "kernel") .. "." .. tier .. ".ll"
end

local function firstHostTier()
    return buildTiers(nil, nil)[1].tier
end

local M = {}

function M.gpuCheckStagesTheDefaultProviderTypeSurface()
    local dir = gpuProject()
    local out, code = check(dir)
    test.equal(code, 0, out)
    assert(
        read(dir .. "/build/native/cache/runtime-source/nupp/gpu/init.nupp"),
        "a GPU check did not stage the native provider types its public facade re-exports"
    )
end

function M.gpuRemarksNameTheAuthoredDeclarationAndArtifact()
    local dir = gpuProject()
    for _ = 1, 2 do
        local pipe = assert(
            io.popen(
                (
                    "cd %q && NUPP_CACHE_DIR=%q '%s' build --target native --remarks-out --json 2>/dev/null"
                ):format(dir, cacheFor(dir), NUPP)
            )
        )
        local text = pipe:read("*a")
        pipe:close()
        local report = require("testjson").decode(text)
        assert(report.ok, text)
        local remarks = require("testjson").decode(assert(read(dir .. "/build/remarks.json")))
        local found = 0
        for _, remark in ipairs(remarks.remarks) do
            if remark.code == "GPU-DISPATCH" then
                found = found + 1
                test.equal(remark.range.start.line, 5)
                test.equal(remark.range.start.column, 1)
                test.equal(remark.range.start.offset, assert(read(dir .. "/src/gpucheck.nupp")):find("@aot", 1, true))
                assert(remark.message:find("artifact ", 1, true), remark.message)
            end
        end
        test.equal(found, 1, "GPU-only modules produce one authored dispatch remark on cold and warm builds")
    end
end

function M.gpuCountedLoopUnsupportedBoundsAndStepsHaveJsonPositions()
    for _, bounds in ipairs({
        "1, #input",
        "0.5, 2.5",
        "1, limit",
        "1, 2147483648",
        "-2147483649, 0",
        "3, 1, -1",
        "1, 3, 1",
        "1, 3, 0"
    }) do
        do
            local dir = gpuProject()
            local file = assert(io.open(dir .. "/src/gpucheck.nupp", "wb"))
            file:write(
                [[
module gpucheck
local span = require("nupp.mem.span")
@aot(target = "gpu")
local function kernel(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>, limit: uint32): nil
    assert(#output == #input)
    for index = 1, #output do
        local value = input[index] -- π before the diagnostic tests byte offsets
        for cursor = ]]
                .. bounds
                .. [[ do
            value = nupp.math.u32.add(value, 1)
        end
        output[index] = value
    end
end
export const kernel = kernel
]]
            )
            file:close()
            local pipe = assert(
                io.popen(
                    (
                        "cd %q && NUPP_CACHE_DIR=%q '%s' build --target native --json 2> .counted-stderr"
                    ):format(dir, cacheFor(dir), NUPP)
                )
            )
            local output = pipe:read("*a")
            pipe:close()
            local report = require("testjson").decode(output)
            assert(report.ok == false, bounds .. " must be refused")
            assert(not (read(dir .. "/.counted-stderr") or ""):find("stack traceback", 1, true), output)
            local found = false
            for _, diagnostic in ipairs(report.diagnostics or {}) do
                local message = diagnostic.message or ""
                if message:find("counted loop bounds", 1, true)
                    or message:find("no explicit step", 1, true)
                    or message:find("outside int32", 1, true)
                then
                    test.equal(diagnostic.file, "src/gpucheck.nupp", output)
                    test.equal(diagnostic.range.start.line, 8, output)
                    local token = bounds:find("#input", 1, true) and "#input"
                        or bounds:find("0.5", 1, true) and "0.5"
                        or bounds:find("limit", 1, true) and "limit"
                        or bounds:find("2147483648", 1, true) and "2147483648"
                        or bounds:find("-2147483649", 1, true) and "-2147483649"
                        or "for"
                    local offset = diagnostic.range.start.offset
                    test.equal(
                        assert(read(dir .. "/" .. diagnostic.file)):sub(offset, offset + #token - 1),
                        token,
                        output
                    )
                    found = true
                end
            end
            assert(found, output)
        end
    end
end

-- A device runs at most 65535 workgroups along one dimension, which is
-- 16,776,960 elements at 256 lanes. The dispatch folds the rest into a second
-- dimension, so a map one element past that bound writes its last element, and
-- a workgroup kernel two groups past it sees its later groups under their own
-- indexes rather than repeating the first row's. The counts are the smallest
-- that cross the bound; a machine without a compute adapter has nothing to run
-- them on and says so instead.
function M.gpuDispatchesPastOneDimensionsWorkgroupLimit()
    local dir = gpuProject()
    local source = assert(io.open(dir .. "/src/gpucheck.nupp", "wb"))
    source:write(
        [[
module gpucheck

local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")

@aot(target = "gpu")
local function increment(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): nil
    assert(#output == #input)
    for index = 1, #output do
        output[index] = nupp.math.u32.add(input[index], 1)
    end
end

@aot(target = "gpu")
local function tiled(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#input), nupp.math.u32.wrap(256))
    gpu.workgroups(groups, 256, function(groupIndex: uint32, phases: gpu.Phases)
        phases:run(function(localIndex: uint32)
            local cursor = nupp.math.u32.add(nupp.math.u32.mul(groupIndex, nupp.math.u32.wrap(256)), localIndex)
            if cursor < #input then
                if cursor < #output then
                    output[cursor + 1] = nupp.math.u32.add(input[cursor + 1], 2)
                end
            end
        end)
    end)
end

export const increment = increment
export const tiled = tiled
]]
    )
    source:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local script = searchPathPrelude()
        .. [[
-- Unbuffered, so a run that dies in the driver still says how far it got.
io.stdout:setvbuf("no")
local ffi = require("ffi")
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")
local gpucheck = require("gpucheck")
local opened, context = pcall(gpu.open)
if not opened then
    assert(tostring(context):find("no suitable compute adapter", 1, true), tostring(context))
    print("no compute adapter")
    return
end
local function run(kernel, count, added)
    local values = ffi.new("uint32_t[?]", count)
    for index = 0, count - 1 do values[index] = index end
    local input = context:buffer(require("nupp.mem.array").uint32, count)
    local output = context:buffer(require("nupp.mem.array").uint32, count)
    context:upload(input, span.fromCarray(values, count))
    kernel:compile(context):bind(output, input):dispatch()
    context:synchronize()
    ffi.fill(values, count * 4)
    context:download(output, span.fromCarray(values, count))
    local wrong = 0
    for index = 0, count - 1 do
        if values[index] ~= index + added then wrong = wrong + 1 end
    end
    print(("%d of %d wrong, last %d"):format(wrong, count, tonumber(values[count - 1])))
    input:close()
    output:close()
end
run(gpucheck.increment, 16776961, 1)
run(gpucheck.tiled, 65537 * 256, 2)
-- A synchronize parks rather than blocking the thread, so a sibling task runs while
-- the device works on a dispatch this large.
do
    local tasks = require("nupp.tasks")
    local time = require("nupp.time")
    local count = 16776961
    local values = ffi.new("uint32_t[?]", count)
    local input = context:buffer(require("nupp.mem.array").uint32, count)
    local output = context:buffer(require("nupp.mem.array").uint32, count)
    context:upload(input, span.fromCarray(values, count))
    local binding = gpucheck.increment:compile(context):bind(output, input)
    local waiting, finished, ran = false, false, 0
    local scope = tasks.open()
    scope:spawn(function()
        binding:dispatch()
        waiting = true
        context:synchronize()
        waiting, finished = false, true
    end)
    scope:spawn(function()
        while not finished do
            if waiting then ran = ran + 1 end
            time.sleep(1)
        end
    end)
    scope:close()
    print(ran > 0 and "a sibling ran while synchronizing" or "nothing ran while synchronizing")
    input:close()
    output:close()
end
]]
    local file = assert(io.open(dir .. "/run.lua", "wb"))
    assert(file:write(script))
    file:close()
    local pipe = assert(io.popen(("cd %q && luajit run.lua 2>&1; echo '__exit__:'$?"):format(dir)))
    local runOut = pipe:read("*a")
    pipe:close()
    test.equal(tonumber(runOut:match("__exit__:(%d+)%s*$")), 0, runOut)
    if runOut:find("no compute adapter", 1, true) then
        io.stderr:write("gpuDispatchesPastOneDimensionsWorkgroupLimit: no compute adapter, nothing dispatched\n")
        return
    end
    assert(runOut:find("0 of 16776961 wrong, last 16776961", 1, true), runOut)
    assert(runOut:find("0 of 16777472 wrong, last 16777473", 1, true), runOut)
    assert(runOut:find("a sibling ran while synchronizing", 1, true), runOut)
end

-- A workgroup kernel runs the groups its source names, the required
-- `u32.div(#span, size)`, which is floor(count / size). The device used to run
-- ceil(count / size), so a span that is not a whole number of groups had its
-- tail written on the GPU and left alone on the CPU. The CPU twin below is the
-- same body without `@aot`, and each count's output is compared with it
-- element by element: a partial group, a whole number of groups, and fewer
-- elements than one group.
function M.gpuWorkgroupsRunTheGroupsTheirCpuDefinitionRuns()
    local dir = gpuProject()
    local body = [[
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#input), nupp.math.u32.wrap(4))
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        phases:run(function(localIndex: uint32)
            local cursor = nupp.math.u32.add(nupp.math.u32.mul(groupIndex, nupp.math.u32.wrap(4)), localIndex)
            if cursor < #input then
                if cursor < #output then
                    output[cursor + 1] = nupp.math.u32.add(input[cursor + 1], 1)
                end
            end
        end)
    end)
]]
    local source = assert(io.open(dir .. "/src/gpucheck.nupp", "wb"))
    source:write(
        [[
module gpucheck

local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")

@aot(target = "gpu")
local function tiled(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): nil
]]
        .. body
        .. [[
end

local function tiledCpu(exclusive output: span.WriteSpan<uint32>, borrows input: span.Span<uint32>): nil
]]
        .. body
        .. [[
end

export const tiled = tiled
export const tiledCpu = tiledCpu
]]
    )
    source:close()
    local out, code = build(dir)
    test.equal(code, 0, out)
    local script = searchPathPrelude()
        .. [[
local ffi = require("ffi")
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local gpucheck = require("gpucheck")
local opened, context = pcall(gpu.open)
if not opened then
    assert(tostring(context):find("no suitable compute adapter", 1, true), tostring(context))
    print("no compute adapter")
    return
end
local UNTOUCHED = 99
for _, count in ipairs({10, 8, 3}) do
    local values = ffi.new("uint32_t[?]", count)
    for index = 0, count - 1 do values[index] = index end
    local cpu = ffi.new("uint32_t[?]", count)
    for index = 0, count - 1 do cpu[index] = UNTOUCHED end
    gpucheck.tiledCpu(span.writeCarray(cpu, count), span.fromCarray(values, count))
    local device = ffi.new("uint32_t[?]", count)
    for index = 0, count - 1 do device[index] = UNTOUCHED end
    local input = context:buffer(array.uint32, count)
    local output = context:buffer(array.uint32, count)
    context:upload(input, span.fromCarray(values, count))
    context:upload(output, span.fromCarray(device, count))
    gpucheck.tiled:compile(context):bind(output, input):dispatch()
    context:synchronize()
    context:download(output, span.writeCarray(device, count))
    local cells = {}
    for index = 0, count - 1 do
        cells[#cells + 1] = ("%d/%d"):format(tonumber(cpu[index]), tonumber(device[index]))
    end
    print(("count %d cpu/gpu %s"):format(count, table.concat(cells, " ")))
    input:close()
    output:close()
end
]]
    local file = assert(io.open(dir .. "/run.lua", "wb"))
    assert(file:write(script))
    file:close()
    local pipe = assert(io.popen(("cd %q && luajit run.lua 2>&1; echo '__exit__:'$?"):format(dir)))
    local runOut = pipe:read("*a")
    pipe:close()
    test.equal(tonumber(runOut:match("__exit__:(%d+)%s*$")), 0, runOut)
    if runOut:find("no compute adapter", 1, true) then
        io.stderr:write("gpuWorkgroupsRunTheGroupsTheirCpuDefinitionRuns: no compute adapter, nothing dispatched\n")
        return
    end
    -- Two whole groups of four: the last two elements are never visited.
    assert(runOut:find("count 10 cpu/gpu 1/1 2/2 3/3 4/4 5/5 6/6 7/7 8/8 99/99 99/99", 1, true), runOut)
    assert(runOut:find("count 8 cpu/gpu 1/1 2/2 3/3 4/4 5/5 6/6 7/7 8/8\n", 1, true), runOut)
    assert(runOut:find("count 3 cpu/gpu 99/99 99/99 99/99", 1, true), runOut)
end

function M.gpuOverlayIsCheckedFromTheSameTypedShaderSchema()
    local source = [[
module gpuoverlay

local span = require("nupp.mem.span")

local struct Input value: float end
local struct Output value: float end

@aot(target = "gpu")
local function convert(
    exclusive output: span.WriteSpan<Output>,
    borrows input: span.Span<Input>,
    scale: float
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do
        output[i].value = input[i].value * scale
    end
end

export const kernel = convert
]]
    -- Two environments, deliberately. Checking the generated overlay in the one
    -- that already checked the source it was generated from would let it resolve
    -- a name the authored module declared and the generated text does not, which
    -- is the whole thing being asked about. Each `envMod.new` re-checks the
    -- standard library the module names, and that is what this case costs.
    local environment = envMod.new(HERE .. "/..")
    local tree = parser.parse(source, "gpuoverlay.nupp")
    local checked = compilerCheck.check(tree, "gpuoverlay.nupp", environment)
    for _, problem in ipairs(checked) do
        assert(not diagnosticMod.isFatal(problem), problem.msg or problem.message)
    end
    local selected = assert(targets.select(nil, nil))
    local artifacts, problems = aotCompile.artifacts(source, "gpuoverlay.nupp", tree, selected)
    assert(artifacts, problems[1] and aotCompile.renderDiagnostic(problems[1]))
    local rewritten = aot.dispatch(
        source,
        artifacts.programs,
        artifacts.sites,
        artifacts.gpu,
        nil,
        nil,
        artifacts.constFamilies
    )
    assert(rewritten:find("Buffer<Output>", 1, true), rewritten)
    assert(rewritten:find("Buffer<Input>", 1, true), rewritten)
    assert(rewritten:find("scale: float", 1, true), rewritten)
    assert(rewritten:find('"ks_convert_gpu"', 1, true), rewritten)
    assert(rewritten:find("export record GpuSpec", 1, true), rewritten)

    local generatedTree = parser.parse(rewritten, "gpuoverlay.nupp")
    assert(#generatedTree.errors == 0, generatedTree.errors[1] and generatedTree.errors[1].msg)
    local generatedDiagnostics = compilerCheck.check(generatedTree, "gpuoverlay.nupp", envMod.new(HERE .. "/.."), {
        generatedSource = true
    })
    local generatedLines = {}
    for line in (rewritten .. "\n"):gmatch("(.-)\n") do
        generatedLines[#generatedLines + 1] = line
    end
    for _, problem in ipairs(generatedDiagnostics) do
        assert(
            not diagnosticMod.isFatal(problem),
            (
                "%s:%s: %s\n%s"
            ):format(
                tostring(problem.line),
                tostring(problem.col),
                problem.msg or problem.message,
                generatedLines[problem.line or 0] or ""
            )
        )
    end
end

function M.theDefaultPolicyEmitsNothing()
    local dir = project(nil)
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredUnit(dir, firstHostTier())), nil, "a project that did not ask for native code gets none")
    assert(read(dir .. "/build/native/kernel.lua"), "the ordinary Lua body is still what was built")
end

function M.offEmitsNothing()
    local dir = project("off")
    local out, code = build(dir)
    test.equal(code, 0, out)
    test.equal(read(tieredUnit(dir, firstHostTier())), nil, "off means off")
end

function M.constGenericAotCapNamesTheWholeDemandSet()
    local dir = constProject("require")
    local source = assert(io.open(dir .. "/src/constkernel.nupp", "wb"))
    local calls = {}
    for count = 1, 9 do
        calls[#calls + 1] = ("tag(1.0, %d)"):format(count)
    end
    source:write(
        table.concat(
            {
                "module constkernel",
                "@aot",
                "local function tag<const N: integer>(value: number, count: N): number",
                "    local answer = value",
                "    for _ = 1, count as integer do answer = answer + 1.0 end",
                "    return answer",
                "end",
                "local answer = " .. table.concat(calls, " + "),
                "export = {tag = tag, answer = answer}",
            },
            "\n"
        )
    )
    source:close()

    local out, code = build(dir)
    assert(code ~= 0, "a required ninth body class must fail")
    assert(out:find("requires 9 body classes", 1, true), out)
    local _, sites = out:gsub("src/constkernel.nupp:8", "")
    assert(sites >= 9, "the diagnostic names every call in the conflicting set: " .. out)
end

--- Every key one source's artifacts were recorded under, tier by tier, or
--- nothing.
---
--- Every tier of it, in a fixed order. An x86-64 build is multiversioned, so
--- one source carries a key per tier, and the state is a JSON object whose
--- members come back in whatever order the encoder walked them. Reading
--- whichever one appeared first compared a different tier between two builds.
local function key(dir)
    local state = read(dir .. "/build/native/.nupp-state.json")
    if not state then
        return nil
    end
    local recorded = state:match('"aot":(%b{})')
    if not recorded then
        return nil
    end
    local tiers = {}
    for tier, digest in recorded:gmatch('kernel%.nupp#([^"]+)":"([0-9a-f]+)"') do
        tiers[#tiers + 1] = tier .. "=" .. digest
    end
    if #tiers == 0 then
        return nil
    end
    table.sort(tiers)

    return table.concat(tiers, " ")
end

function M.anUnknownFeatureTierIsRejected()
    local dir = project("require")
    local manifest = assert(io.open(dir .. "/nupp.lua", "rb"))
    local text = manifest:read("*a")
    manifest:close()
    manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write((text:gsub('aot = "require",', 'aot = "require", aotFeatures = {maximum = "avx9"},')))
    manifest:close()

    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(
        out:find("aotFeatures", 1, true) and out:find("has no feature tier avx9", 1, true),
        "naming the key and what was wrong with it: " .. out
    )
    assert(
        out:find("it has", 1, true),
        "and the tiers this architecture does have, which is the actionable part: " .. out
    )
end

--- The manifest with extra keys spliced into the native target.
local function withKeys(dir, extra)
    local handle = assert(io.open(dir .. "/nupp.lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    handle = assert(io.open(dir .. "/nupp.lua", "wb"))
    handle:write((text:gsub('outDir = "build/native",', 'outDir = "build/native", ' .. extra)))
    handle:close()
end

function M.aFeatureRangeRequiresOneBound()
    local dir = project("require")
    withKeys(dir, 'aotTarget = "x86_64-unknown-linux-gnu", aotFeatures = {},')
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("aotFeatures needs a minimum, a maximum, or both", 1, true), out)
end

function M.aFeatureRangeRejectsUnknownKeys()
    local dir = project("require")
    withKeys(
        dir,
        'aotTarget = "x86_64-unknown-linux-gnu", '
        .. 'aotFeatures = {minimum = "avx2", maximum = "avx512f", preferred = "avx2"},'
    )
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find('has no key "preferred"', 1, true), out)
end

function M.aFeatureRangeRejectsAMinimumWiderThanItsMaximum()
    local dir = project("require")
    withKeys(
        dir,
        'aotTarget = "x86_64-unknown-linux-gnu", ' .. 'aotFeatures = {minimum = "avx512f", maximum = "avx2"},'
    )
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("minimum avx512f is wider than maximum avx2", 1, true), out)
end

function M.anUnknownCrossTargetIsRejected()
    local dir = project("require")
    withKeys(dir, 'aotTarget = "sparc-sun-solaris",')
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(
        out:find("aotTarget", 1, true) and out:find("unknown target", 1, true),
        "and names the key as well as the value: " .. out
    )
end

function M.aTierIsCheckedAgainstTheTargetItAppliesTo()
    local dir = project("require")
    -- `avx2` is a real tier and not one aarch64 has. Checking it against the set
    -- of all tiers would accept it; it has to be checked against the target.
    withKeys(dir, 'aotTarget = "aarch64-apple-darwin", aotFeatures = {maximum = "avx2"},')
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find("aarch64 has no feature tier avx2", 1, true), out)
end

function M.anUnknownPolicyIsRejected()
    local dir = project("sometimes")
    local out, code = build(dir)
    test.equal(code, 1, out)
    assert(out:find('must be "off" or "require"', 1, true), out)
end

--- What this host calls a shared library, asked of the compiler rather than
--- guessed from `uname`. The two could drift, and the one that decides where
--- the file actually goes is the compiler.
local function librarySuffix()
    local targets = require("nupp.compiler.aot.target")
    local host = assert(targets.select(nil, nil), "this host is a modeled target")
    return aot.librarySuffix(host)
end

--- Which case is running, read back from the table the runner calls it out of.
local caseNames = nil

local function runningCase()
    if caseNames == nil then
        caseNames = {}
        for name, body in pairs(M) do
            if type(body) == "function" then
                caseNames[body] = name
            end
        end
    end
    for level = 2, 16 do
        local frame = debug.getinfo(level, "f")
        if frame == nil then
            break
        end
        local named = caseNames[frame.func]
        if named ~= nil then
            return named
        end
    end

    return "unknown"
end

--- Where `require` puts the library for the `native` target.
---
--- Every library a case is about to call is kept when the run asks for
--- artifacts, under the name of the case that built it. A worker killed by a
--- signal writes no report and, on Windows, no dump either -- the faulting
--- library disassembled beside a line saying which case held it is the whole
--- of the evidence, and which case that is is not known until it dies. The
--- copy costs a file per case and only when the run asks for one.
local function libraryPath(dir)
    local path = dir .. "/" .. aot.libraryPath("build/native", "native", librarySuffix())
    local artifacts = os.getenv("NUPP_TEST_AOT_ARTIFACTS")
    if artifacts ~= nil then
        local bytes = read(path)
        if bytes ~= nil then
            local case = runningCase()
            local saved = io.open(artifacts .. "/" .. case .. "-" .. path:match("[^/\\]+$"), "wb")
            if saved ~= nil then
                saved:write(bytes)
                saved:close()
            end
            local loaded = io.open(artifacts .. "/aot-libraries.txt", "ab")
            if loaded ~= nil then
                loaded:write(case, " ", path, " ", tostring(#bytes), "\n")
                loaded:close()
            end
        end
    end

    return path
end

--- `unused-binding` answers for the file as written, not for the one the AOT
--- policy rewrote.
---
--- A linking policy replaces each `@aot` declaration with the wrapper that calls
--- the compiled code, body and all, and the module build checks that text. Every
--- binding the removed body was the only reader of then looks unread, and the
--- report lands on a line the author can see still using the name. The verdict
--- reported is the one taken from the source as written, so a binding nothing
--- reads is still reported and one the body reads is not.
function M.unusedBindingJudgesTheSourceAsWrittenNotTheAotRewrite()
    local function report(dir)
        local out = build(dir)
        local found = {}
        for name in out:gmatch("nothing uses ([%a_][%w_]*)") do
            found[name] = true
        end

        return found, out
    end

    local function named(policy)
        return report(unusedProject(policy))
    end

    -- With no compilation the body is still there, so this is the plain answer.
    local interpreted = named("off")
    assert(interpreted.trulyUnused, "a binding nothing reads is reported")
    assert(not interpreted.READ_ONLY_IN_THE_BODY, "a constant the body reads is not")
    assert(not interpreted.valueBuilder, "a require the body uses is not")

    -- With the declaration replaced, the answer has to be the same one.
    local dir = unusedProject("require")
    local compiled, out = report(dir)
    assert(not compiled.READ_ONLY_IN_THE_BODY, "a constant the compiled body reads is not reported: " .. out)
    assert(not compiled.valueBuilder, "a require the compiled body uses is not reported: " .. out)
    assert(compiled.trulyUnused, "a binding nothing reads is still reported: " .. out)

    -- And again when nothing changed: a reused module record replays what the
    -- first build said, so it has to have kept the verdict for the file as
    -- written rather than the checker's answer for the rewritten text.
    local reused, again = report(dir)
    assert(not reused.READ_ONLY_IN_THE_BODY, "a reused record does not report the constant: " .. again)
    assert(not reused.valueBuilder, "a reused record does not report the require: " .. again)
    assert(reused.trulyUnused, "a reused record still reports the unread binding: " .. again)
end

require("jit").off(M.exactLoopReducersAgreeAcrossLuaScalarAndVectorExecution, true)

-- The oracle is LuaJIT's interpreted FFI conversion, independent of its trace
-- compiler's specialization of the changing ctype in this conversion matrix.
require("jit").off(M.numericSimdConversionsMatchLuaJitAndIndependentScalarResults, true)

function M.speciesIsOneLaneUnderAotOffAndVectorsIsNil()
    -- `aot = "off"` runs the body as Lua, where `simd.species` answers the
    -- one-lane species, so the vector loop runs a lane at a time and lands
    -- on the same answer; `simd.vectors` answers nil there, so a body that
    -- tests it takes the scalar continuation it wrote for that answer, and
    -- one that asserts it raises, with the message it gave.
    local body = [[
local span = require("nupp.mem.span")
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function scan(borrows cps: span.Span<uint32>): integer
    local cursor: uint32 = 0
    OPEN
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
    local driver = [[
local array = require("nupp.mem.array")
local kernel = require("kernel")

local m = {}

function m.answer(): (boolean, unknown)
    local values = array.scalar(array.uint32, 40)
    do
        local writable = values:write()
        for index = 1, 40 do
            writable[index] = 100
        end
        writable[37] = 3
        nupp.drop(writable)
    end
    return pcall(kernel.scan, values:read())
end

return m
]]
    local script = 'print(require("plain").answer())'

    local function answer(open)
        local dir = project("off")
        local handle = assert(io.open(dir .. "/src/kernel.nupp", "wb"))
        handle:write(
            (body:gsub("OPEN", function()
                return open
            end))
        )
        handle:close()
        handle = assert(io.open(dir .. "/src/plain.nupp", "wb"))
        handle:write(driver)
        handle:close()
        local out, code = build(dir)
        test.equal(code, 0, out)
        assert(not out:find("NUPP2903", 1, true), out)
        local pipe = assert(io.popen(("cd %q && luajit -e %q 2>&1"):format(dir, searchPathPrelude() .. script)))
        local text = pipe:read("*a")
        pipe:close()

        return (text:gsub("%s+$", ""))
    end

    test.equal(answer("if species = simd.vectors(array.uint32) then"), "true\t37")
    test.equal(answer("local species = simd.species(array.uint32)\n    do"), "true\t37", "one lane as Lua")
    local raised = answer('local species = assert(simd.vectors(array.uint32), "this scan needs vectors")\n    do')
    assert(raised:find("^false\t") and raised:find("this scan needs vectors", 1, true), raised)
end

require("jit").off(M.genericVocabularyOperationsAgreeAcrossLuaScalarAndLaneExecution, true)

require("jit").off(M.laneArithmeticAgreesAcrossLuaScalarAndLaneExecution, true)

require("jit").off(M.crossLaneOperationsAgreeWithTheirScalarExecutableSemantics, true)

return M
