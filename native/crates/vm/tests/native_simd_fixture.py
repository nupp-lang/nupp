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
        ("float", "1.25", "2.5"), ("number", "1.25", "2.5"),
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
    const input = array.scalar(array.number, 67)
    const output = array.scalar(array.number, 67)
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
    const small = array.scalar(array.number, 2)
    const short = small:write()
    local ok, problem = pcall(function(): nil kernels.explicitMap(short, reader, 1.0, 0.0) end)
    assert(not ok and tostring(problem):find("length mismatch", 1, true) ~= nil)
end
export function run(): number
'''
    for kind, _, _ in cases:
        source += f"    check_{kind}()\n"
    source += '''    checkedKernels()
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
