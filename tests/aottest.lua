local testAssert = require("nupp.test")
-- The `@aot` annotation's source contract.
--
-- `@aot` says a whole function compiles ahead of time rather than being left to
-- LuaJIT. Before any of that can be true there has to be an agreement about what
-- the annotation attaches to and what its body may contain, and that agreement is
-- what these check: the annotation exists, it refuses a body two compilers were
-- promised, it refuses a member that is not a whole function, and it names every
-- construct the AOT IR has no representation for.
--
-- See docs/learn/performance/ahead-of-time/index.md.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local scalarIR = require("nupp.compiler.aot.scalar")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

-- One environment for the whole suite: every case checks against one built
-- exactly this way, and building one means checking the prelude from source.
local sharedEnv = envMod.new(HERE .. "/..")
local gpuEnv = envMod.new(HERE .. "/..", {config = {include = {"src"}, _target = {aot = "require"}},})
local browserGpuEnv = envMod.new(HERE .. "/..", {
    config = {include = {"src"}, _target = {aot = "require-wasm", host = "browser"}},
})

local M = {}

function M.privateSymbolsPreserveDistinctSourceNames()
    assert(
        scalarIR.privateSymbol("fooBar") ~= scalarIR.privateSymbol("foo_bar"),
        "camel-case and underscore names have distinct symbols"
    )
    assert(
        scalarIR.privateSymbol("httpServer") ~= scalarIR.privateSymbol("HTTPServer"),
        "acronym capitalization has distinct symbols"
    )
end

local function codesOf(source)
    local result = parser.parse(source, "test.nupp")
    if #result.errors > 0 then
        error("syntax: " .. result.errors[1].message, 2)
    end
    local out = {}
    for _, diagnostic in ipairs(check.check(result, "test.nupp", sharedEnv)) do
        out[#out + 1] = diagnostic.code
    end

    return table.concat(out, " ")
end

--- Asserts that `source` reports `want` and nothing else.
local function reports(source, want, label)
    testAssert.equal(codesOf(source), want, label)
end

local function diagnosticCodes(source)
    local out = {}
    for _, environment in ipairs({gpuEnv, browserGpuEnv}) do
        local result = parser.parse(source, "test.nupp")
        for _, diagnostic in ipairs(check.check(result, "test.nupp", environment)) do
            out[#out + 1] = diagnostic.code
        end
    end
    return table.concat(out, " ")
end

local function reportsGpu(source, want, label)
    for _, environment in ipairs({gpuEnv, browserGpuEnv}) do
        local result = parser.parse(source, "test.nupp")
        if #result.errors > 0 then
            error("syntax: " .. (result.errors[1].message or result.errors[1].msg), 2)
        end
        local out = {}
        for _, diagnostic in ipairs(check.check(result, "test.nupp", environment)) do
            out[#out + 1] = diagnostic.code
        end
        testAssert.equal(table.concat(out, " "), want, label)
    end
end

function M.anAdmittedBodyReportsNothing()
    -- The whole point of the subset is that ordinary Nupp is inside it. A body of
    -- arithmetic over admitted scalars is the smallest thing that has to pass, and
    -- if it does not then nothing below is a subset check, it is a syntax error.
    reports(
        [[
@aot
local function scale(value: number, by: number): number
    local scaled = value * by
    if scaled < 0.0 then
        return 0.0
    end

    return scaled
end

return {scale = scale}
]],
        "",
        "arithmetic over admitted scalars is admitted"
    )
end

function M.loopsAndBranchesAreAdmitted()
    -- Structured control flow is the reason the annotation exists; a subset that
    -- refused a numeric loop would have nothing left to compile.
    reports(
        [[
@aot
local function accumulate(count: integer): number
    local total = 0.0
    for i = 1, count do
        if i % 2 == 0 then
            total = total + 1.0
        else
            total = total - 1.0
        end
    end

    return total
end

return {accumulate = accumulate}
]],
        "",
        "numeric loops and branches are admitted"
    )
end

function M.reducerRegionsFollowEveryNestedDoBlock()
    local prefix = [[
local array = require("nupp.mem.array")
local simd = require("nupp.simd")

@aot
local function total(flag: boolean): number
    local species = assert(simd.species(array.number, 2))
    local fold = simd.reducer.pairwiseSum(0.0)
]]
    local suffix = [[
    return fold:value()
end

return total
]]

    reports(
        prefix
        .. [[
    if flag then
        do
            fold:add(species:splat(1.0), species:tail(2))
        end
    end
]]
        .. suffix,
        "",
        "a do block nested under control flow remains a reducer region"
    )
    reports(
        prefix
        .. [[
    do
        fold:add(species:splat(1.0), species:tail(2))
        do
            fold:add(species:splat(2.0), species:tail(2))
        end
    end
]]
        .. suffix,
        "NUPP2904",
        "nested do blocks are distinct reducer regions"
    )
    reports(
        prefix
        .. [[
    if flag then
        local nested = simd.reducer.pairwiseSum(0.0)
        do
            nested:add(species:splat(1.0), species:tail(2))
        end
    end
    fold:add(1.0)
]]
        .. suffix,
        "NUPP2904",
        "a reducer declared in nested control flow still needs finalization"
    )
end

function M.numericSwitchLocalIsAdmitted()
    reports(
        [[
@aot
local function classify(value: number): number
    local selected = switch value do
        case 0 -> 1.0
        case 1, 2 -> value + 1.0
        else -> 0.0
    end

    return selected
end

return {classify = classify}
]],
        "",
        "an integer-valued switch initializer lowers to scalar control flow"
    )

    reports(
        [[
@aot
local function constantClass(): number
    local selected = switch 0 do
        case 0 -> 1.0
    end
    return selected
end

return {constantClass = constantClass}
]],
        "",
        "a checker-exhaustive native switch does not require else"
    )
end

function M.ordinaryLoopShapesCompile()
    -- A map loop, a loop-free body, and several loops are all ordinary `@aot`
    -- functions.
    reports(
        [[
local span = require("nupp.mem.span")

@aot
local function map(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    for i = 1, #input do
        output[i] = input[i]
    end
end
return {map = map}
]],
        "",
        "the map-loop shape compiles"
    )

    reports(
        [[
@aot
local function missing(value: number): number
    return value
end

return {missing = missing}
]],
        "",
        "a body with no loop is an ordinary AOT function"
    )

    reports(
        [[
@aot
local function two(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end
    for i = 1, count do
        total = total - i
    end

    return total
end

return {two = two}
]],
        "",
        "two loops compile"
    )

    reports(
        [[
@aot
local function scalar(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end

    return total
end

return {scalar = scalar}
]],
        "",
        "an ordinary body remains scalar"
    )
end

function M.gpuIsAnExecutionTargetRatherThanALaneWidth()
    reports(
        [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function map(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    for i = 1, #input do
        output[i] = input[i]
    end
end
return {map = map}
]],
        "",
        "a GPU map is an admitted AOT body"
    )

    reports(
        [[
@aot(target = "accelerator")
local function wrong(value: number): number
    return value
end
return {wrong = wrong}
]],
        "NUPP2115",
        "the execution target is a closed vocabulary"
    )
end

function M.gpuTargetBindsACompilerGeneratedTypedObject()
    reportsGpu(
        [[
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local array = require("nupp.mem.array")

@aot(target = "gpu")
local function scale(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    by: float
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do output[i] = input[i] * by end
end

local context = gpu.open()
local input = context:buffer(array.float, 16)
local output = context:buffer(array.float, 16)
local kernel = scale:compile(context)
local invocation = kernel:bind(output, input)
invocation:dispatch(2.0)
return true
]],
        "",
        "the authored source sees the generated kernel and binding types"
    )

    reportsGpu(
        [[
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")

local struct Input value: float end
local struct Output value: float end

@aot(target = "gpu")
local function convert(
    exclusive output: span.WriteSpan<Output>,
    borrows input: span.Span<Input>
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do output[i].value = input[i].value end
end

local function wrong(
    borrows context: gpu.Context,
    borrows input: gpu.Buffer<Input>,
    borrows output: gpu.Buffer<Output>
): nil
    local kernel = convert:compile(context)
    local invocation = kernel:bind(input, output)
    invocation:dispatch()
end
return wrong
]],
        "NUPP2006 NUPP2006",
        "the generated binding rejects buffers in the wrong positions"
    )
end

function M.gpuResourcesAreClosableChildrenOfTheirContext()
    local header = [[
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local array = require("nupp.mem.array")

@aot(target = "gpu")
local function double(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do output[i] = input[i] * 2.0 end
end
]]
    reportsGpu(
        header .. [[
local function run(): integer
    if not gpu.available() then
        return 0
    end
    with context = gpu.open() do
        with input = context:buffer(array.float, 16), output = context:buffer(array.float, 16) do
            with kernel = double:compile(context) do
                with binding = kernel:bind(output, input) do
                    binding:dispatch()
                end
            end
            context:synchronize()
            return output.count
        end
    end
end
return run
]],
        "",
        "a context, its buffers, its kernel and its binding each have one exact extent"
    )
    reportsGpu(
        header .. [[
local context = gpu.open()
local buffer = context:buffer(array.float, 16)
nupp.drop(buffer)
print(buffer.count)
return true
]],
        "NUPP2601",
        "a buffer used after it was closed is refused"
    )
    reportsGpu(
        header .. [[
local context = gpu.open()
local input = context:buffer(array.float, 16)
local output = context:buffer(array.float, 16)
local kernel = double:compile(context)
nupp.drop(kernel)
local binding = kernel:bind(output, input)
binding:dispatch()
return true
]],
        "NUPP2601",
        "a kernel used after it was closed is refused"
    )
    local closedContext = diagnosticCodes(header .. [[
local function run(): nil
    local context = gpu.open()
    local buffer = context:buffer(array.float, 16)
    nupp.drop(context)
    print(buffer.count)
end
return run
]])
    assert(closedContext ~= "", "closing a context while a buffer borrows it is refused")
end

function M.gpuBuffersExposeCheckedTensorLayouts()
    reportsGpu(
        [[
local gpu = require("nupp.gpu")
local array = require("nupp.mem.array")

local context = gpu.open()
local tensor = context:tensor(array.float, {4, 8})
local bytes: gpu.Buffer<int8>? = nil
local row = tensor:subview({2, 0}, {1, 8})
local tensorLayout: gpu.Layout = tensor:layout()
local layout = require("nupp.gpu.layout")
local columns = tensor:view(layout.transpose(tensorLayout, {2, 1}))
local repeated = row:view(layout.broadcast(row:layout(), {4, 8}))
local gapped = tensor:subview({0, 0}, {4, 4})
local dimensions = row:dimensions()
local strides = row:strides()
assert(row.count == 8 and bytes == nil and dimensions[1] == 1 and dimensions[2] == 8)
assert(strides[1] == 8 and strides[2] == 1)
assert(row:isDense() and row:isInjective())
assert(not columns:isDense() and columns:isInjective())
assert(not repeated:isDense() and not repeated:isInjective())
assert(not gapped:isDense() and gapped:isInjective())
return true
]],
        "",
        "resident tensors expose checked dense, strided, transposed, and broadcast views"
    )
    reportsGpu(
        [[
local gpu = require("nupp.gpu")
local array = require("nupp.mem.array")

local context = gpu.open()
local tensor = context:tensor(array.float, {4, 8})
print(gpu.bufferIsDense(tensor))
return true
]],
        "NUPP2004 NUPP2611",
        "a buffer answers for itself; the free-function duplicates are gone"
    )
    reportsGpu(
        [[
local gpu = require("nupp.gpu")
local array = require("nupp.mem.array")

local struct Pair
    left: float
    right: float
end

local function pairCount(borrows buffer: gpu.Buffer<Pair>): integer
    return buffer.count
end

local function wordCount(borrows buffer: gpu.Buffer<uint32>): integer
    return buffer.count
end

local context = gpu.open()
local couples = context:buffer(Pair, 4)
local words = context:tensor(array.uint32, {2, 2})
print(pairCount(couples), wordCount(words))
return true
]],
        "",
        "an array witness names a scalar element and a struct declaration names itself"
    )
    reportsGpu(
        [[
local gpu = require("nupp.gpu")
local array = require("nupp.mem.array")

local function wordCount(borrows buffer: gpu.Buffer<uint32>): integer
    return buffer.count
end

local context = gpu.open()
local words = context:buffer(array.float, 4)
print(wordCount(words))
return true
]],
        "NUPP2006",
        "the witness decides the buffer's element type"
    )
end

function M.gpuTargetWithoutRequiredLinkingRemainsAnOrdinaryFunction()
    reports(
        [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function copy(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    if #output ~= #input then error("length mismatch", 2) end
    for i = 1, #output do output[i] = input[i] end
end

local use: function(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil = copy
return use
]],
        "",
        "a GPU body is unchanged unless aot=require installs its generated object"
    )
end

function M.gpuTargetRequiresALocalFunctionDeclaration()
    reports(
        [[
local m = {}

@aot(target = "gpu")
function m.copy(value: float): float
    return value
end

return m
]],
        "NUPP2902",
        "a generated GPU specification needs one local binding to replace"
    )
end

function M.aotRequiresALocalFunctionDeclaration()
    reports(
        [[
local m = {}

@aot
function m.copy(value: float): float
    return value
end

return m
]],
        "NUPP2902",
        "an AOT entry needs the local binding lowering replaces"
    )
end

function M.simdAcceptsOnlyTheRequiredSetting()
    reports(
        [[
@aot(simd = false)
local function map(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end
    return total
end

return {map = map}
]],
        "NUPP2115",
        "SIMD is a requirement rather than a writable preference"
    )
end

function M.spanMethodCallsAreAdmitted()
    -- The span operations are the memory boundary the whole feature is built on,
    -- and they are written as method calls. Refusing the syntax structurally would
    -- refuse the subset's own vocabulary, so whether a call resolves is left to the
    -- pass that knows the receiver's type.
    reports(
        [[
local span = require("nupp.mem.span")

@aot
local function total(values: span.Span<float>): number
    local sum = 0.0
    for i = 1, #values do
        sum = sum + values[i]
    end

    return sum
end

return {total = total}
]],
        "",
        "a span read is admitted"
    )

    reports(
        [[
local span = require("nupp.mem.span")

@aot
local function double(exclusive values: span.WriteSpan<float>): nil
    for i = 1, #values do
        values[i] = values[i] * 2.0
    end
end

return {double = double}
]],
        "",
        "a span write is admitted"
    )
end

function M.jitAndAotAreMutuallyExclusive()
    -- Two compilers for one body is not a preference to resolve, so it is refused
    -- whichever order the two are written in.
    reports(
        [[
@jit
@aot
local function hot(scale: number): number
    return scale * 2.0
end

return {hot = hot}
]],
        "NUPP2901",
        "@jit then @aot"
    )

    reports(
        [[
@aot
@jit
local function hot(scale: number): number
    return scale * 2.0
end

return {hot = hot}
]],
        "NUPP2901",
        "@aot then @jit"
    )
end

function M.aotIsRefusedOnARecordMember()
    -- A member's annotations never reach the pragma handler, so this is the case
    -- that regresses silently if the refusal lives in only one place.
    reports(
        [[
local record Point
    x: float
    @aot
    constructor(self, x: float)
        self.x = x
    end
end

return {Point = Point}
]],
        "NUPP2902",
        "a constructor is not a whole function"
    )
end

function M.aotOnANestedFunctionIsRefused()
    -- Discovery walks the chunk's own statements, so before this refusal the
    -- annotation inside another body was simply never found: the contract was not
    -- applied, `nupp aot` said no @aot function was there, and checking said
    -- nothing at all.
    reports(
        [[
local function outer(scale: number): number
    @aot
    local function inner(value: number): number
        return value * 2.0
    end

    return inner(scale)
end

return {outer = outer}
]],
        "NUPP2902",
        "an annotation inside another function is refused rather than ignored"
    )
end

function M.aNestedFunctionIsRefused()
    reports(
        [[
@aot
local function total(scale: number): number
    local function double(x: number): number
        return x * 2.0
    end

    return double(scale)
end

return {total = total}
]],
        "NUPP2903",
        "a closure has no AOT IR representation"
    )
end

function M.freshTableConstructionIsStructurallyAdmitted()
    reports(
        [[
@aot
local function build(scale: number): number
    local values = {scale}

    return values[1]
end

return {build = build}
]],
        "",
        "a fresh table has a VM-aware AOT representation"
    )

end

function M.primitiveStringConstructionIsStructurallyAdmitted()
    reports(
        [[
@aot
local function label(name: string): string
    return name .. "!"
end

return {label = label}
]],
        "",
        "primitive concatenation has a VM-aware AOT representation"
    )
end

function M.arbitraryJumpsAreRefused()
    -- `goto` waits until AOT IR source maps can represent every existing rule, so
    -- both halves of one are named rather than only the jump.
    reports(
        [[
@aot
local function jump(scale: number): number
    goto done
    ::done::

    return scale
end

return {jump = jump}
]],
        "NUPP2903 NUPP2903",
        "goto and its label"
    )
end

function M.aRefusedConstructIsReportedOnce()
    -- The walk does not descend into what it refused. A closure holding three
    -- tables is one problem with one fix, and three more diagnostics inside a
    -- function that cannot be there at all would bury it.
    reports(
        [[
@aot
local function total(scale: number): number
    local function build(): number
        local a = {1.0}
        local b = {2.0}

        return a[1] + b[1]
    end

    return build() + scale
end

return {total = total}
]],
        "NUPP2903",
        "the closure is named and its contents are not"
    )
end

function M.anUnannotatedFunctionIsUnaffected()
    -- Removing `@aot` from accepted source preserves its ordinary Nupp answer, so
    -- the same body without the annotation reports nothing at all.
    reports(
        [[
local function total(scale: number): number
    local function double(x: number): number
        return x * 2.0
    end

    return double(scale)
end

return {total = total}
]],
        "",
        "the subset applies only where it was asked for"
    )
end

return M
