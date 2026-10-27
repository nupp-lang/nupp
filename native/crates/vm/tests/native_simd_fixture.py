"""The native SIMD fixture: one doubling kernel per element kind and the
bench/simd11 kernels, shared by native-simd-smoke.py and nojit-gate.py."""


def native_source():
    source = '''module nupp.tests.vmnativesimd
const array = require("nupp.mem.array")
const span = require("nupp.mem.span")
const simd = require("nupp.simd")
const tasks = require("nupp.tasks")
const kernels = require("kernels")
'''
    cases = [
        ("uint8", "200", "144"), ("int8", "100", "-56"),
        ("uint16", "40000", "14464"), ("int16", "30000", "-5536"),
        ("uint32", "4000000000", "3705032704"), ("int32", "2000000000", "-294967296"),
        ("uint64", "9223372036854775809ULL", "2ULL"),
        ("int64", "-9223372036854775807LL", "2LL"),
        ("float32", "1.25", "2.5"), ("float64", "1.25", "2.5"),
    ]
    for kind, initial, expected in cases:
        source += f'''
local function double_{kind}(exclusive output: span.WriteSpan<{kind}>, borrows input: span.Span<{kind}>): nil
    if #output ~= #input then error("length mismatch", 2) end
    local species = assert(simd.species(array.{kind}, 3))
    local cursor: uint32 = 0
    while cursor + species.lanes <= #input do
        local value = species:load(input, cursor + 1)
        species:store(output, cursor + 1, value + value)
        cursor = cursor + species.lanes
    end
    if cursor < #input then
        local active = species:tail(#input - cursor)
        local value = species:load(input, cursor + 1, active)
        species:store(output, cursor + 1, value + value, active)
    end
end
local function check_{kind}(): nil
    for count = 0, 19 do
        const input = array.scalar(array.{kind}, count)
        const output = array.scalar(array.{kind}, count)
        do
            const writer = input:write()
            for i = 1, #writer do writer[i] = {initial} end
        end
        const reader = input:read()
        const writer = output:write()
        double_{kind}(writer, reader)
        for i = 1, #writer do assert(writer[i] == {expected}) end
    end
end
'''
    source += '''
local function checkedKernels(): nil
    const input = array.scalar(array.float64, 67)
    const output = array.scalar(array.float64, 67)
    do
        const writer = input:write()
        for i = 1, #writer do writer[i] = i end
    end
    const reader = input:read()
    const writer = output:write()
    kernels.explicitMap(writer, reader, 1.25, 2.0)
    for i = 1, #writer do assert(writer[i] == i * 1.25 + 2.0) end
    kernels.explicitRefine(writer, reader)
    for i = 1, #writer do
        local value, rounds = i as number, 0
        while value > 1 and rounds < 32 do value = value * 0.5; rounds = rounds + 1 end
        assert(writer[i] == value + rounds)
    end
    assert(kernels.explicitAlgebraic(reader, reader) == 102510)
    const small = array.scalar(array.float64, 2)
    const short = small:write()
    local ok, problem = pcall(function(): nil kernels.explicitMap(short, reader, 1.0, 0.0) end)
    assert(not ok and tostring(problem):find("length mismatch", 1, true) ~= nil)
end
local function rotatePair(borrows input: span.Span<float64>, x: float64, y: float64): float64
    local species = assert(simd.species(array.float64, 4))
    local accumulator = species:splat(0.0)
    local a, b = x, y
    local cursor: uint32 = 0
    while cursor + species.lanes <= #input do
        accumulator = accumulator + species:load(input, cursor + 1) * a
        a, b = b, a
        cursor = cursor + species.lanes
    end

    return simd.horizontal.algebraicSum(accumulator) + a * 10 + b
end
local function rotateSix(borrows input: span.Span<float64>, x: float64): float64
    local species = assert(simd.species(array.float64, 4))
    local accumulator = species:splat(0.0)
    local a, b, c, d, e, f = x, x + 1, x + 2, x + 3, x + 4, x + 5
    local rounds = 0
    local cursor: uint32 = 0
    while cursor + species.lanes <= #input do
        accumulator = accumulator + species:load(input, cursor + 1) * f
        if rounds < 3 then
            a, b, c, d, e, f = b, c, d, e, f, a
        else
            a, b, c, d, e, f = f, a, b, c, d, e
        end
        rounds = rounds + 1
        cursor = cursor + species.lanes
    end

    return simd.horizontal.algebraicSum(accumulator) + a + 10 * b + 100 * c + 1000 * d + 10000 * e + 100000 * f
end
local function checkedRotations(): nil
    -- A parallel assignment reads every right-hand side before it writes any
    -- target, so the loop-carried scalars rotate rather than collapse.
    const input = array.scalar(array.float64, 29)
    do
        const writer = input:write()
        for i = 1, #writer do writer[i] = i end
    end
    const reader = input:read()
    assert(rotatePair(reader, 2.0, 3.0) == 1018)
    assert(rotateSix(reader, 1.0) == 544434)
end
export function run(): number
'''
    for kind, _, _ in cases:
        source += f"    check_{kind}()\n"
    source += '''    checkedKernels()
    checkedRotations()
    return 42
end
export function workers(): number
    with scope = tasks.open() do
        local job = scope:fork(0, function(value: integer): integer
            require("nupp.mem.array")
            check_uint64()
            checkedKernels()
            return value + 42
        end)
        assert(job:await() == 42)
    end
    return 42
end
'''
    return source, cases
