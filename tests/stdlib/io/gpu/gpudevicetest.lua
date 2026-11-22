-- The native GPU device over wgpu-native: its range, handle and SPIR-V checks,
-- the cost output, and, where the machine has an adapter, real dispatches.
-- NUPP_REQUIRE_GPU turns a missing adapter from a skip into a failure, which is
-- how the GPU conformance jobs run it; NUPP_EXPECT_GPU_BACKEND and
-- NUPP_EXPECT_GPU_ADAPTER name the device those jobs must have found.
local memory = require("nupp.runtime.provider.wgpumemory")
local assertions = require("assert")
local device = require("nupp.runtime.provider.gpudevice")
local costs = require("nupp.runtime.provider.gpucosts")
local json = require("nupp.codec.json.provider")

local function upload(context, buffer, offset, source, length)
    return device.upload(context, buffer, offset, memory.raw(source), length)
end

local function readdownload(context, buffer, offset, size, destination)
    return device.readdownload(context, buffer, offset, size, memory.raw(destination))
end

local function dispatch(context, binding, work, uniforms, length)
    return device.dispatch(context, binding, work, memory.raw(uniforms), length)
end

local M = {}

local function fails(body, message)
    local ok, problem = pcall(body)
    assert(not ok, "expected a failure containing " .. message)
    local text = type(problem) == "table" and problem.message or tostring(problem)
    assert(text:find(message, 1, true), text)
end

local function temporary(name)
    local directory = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    return (
        directory:gsub("\\", "/")
    ) .. "/nupp-gpu-" .. name .. "-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 1000000)) .. ".jsonl"
end

local function lines(path)
    local rows = {}
    local file = assert(io.open(path, "rb"))
    for line in file:lines() do
        rows[#rows + 1] = line
    end
    file:close()

    return rows
end

-- A device, or a skip when the machine has none and none is required.
local function open()
    local context, problem = device.open()
    if context == nil then
        assert(os.getenv("NUPP_REQUIRE_GPU") == nil, "required GPU adapter is unavailable: " .. tostring(problem))
        assertions.suite.skip("no GPU adapter: " .. tostring(problem))
    end

    return context
end

local ROUND_TRIP = [[
@group(1) @binding(0)
var<storage, read_write> values: array<u32>;

@compute @workgroup_size(1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    values[id.x] = values[id.x] + 1u;
}
]]

local NO_UNIFORMS = memory.new("uint8_t[1]")

local function check(value, problem)
    assert(problem == nil, problem)
    return value
end

function M.invalidTimestampIntervalsDoNotClaimDeviceDuration()
    local first, last = memory.new("uint64_t", 10), memory.new("uint64_t", 1010)
    assert(device.timestampmilliseconds(first, last, 2.0) == 0.002)
    local _, equal = device.timestampmilliseconds(memory.new("uint64_t", 0), memory.new("uint64_t", 0), 1.0)
    assert(equal == "equal-timestamps")
    local _, reversed = device.timestampmilliseconds(memory.new("uint64_t", 10), memory.new("uint64_t", 9), 1.0)
    assert(reversed == "reversed-timestamps")
    for _, period in ipairs({0.0, -1.0, 0 / 0, math.huge}) do
        local _, reason = device.timestampmilliseconds(memory.new("uint64_t", 10), memory.new("uint64_t", 20), period)
        assert(reason == "invalid-timestamp-period", tostring(period))
    end
end

function M.resourceTablesRejectWrongAndStaleHandles()
    local table = device.resources()
    local buffer = device.insert(table, "buffer", 11)
    fails(
        function()
            device.remove(table, buffer, "kernel")
        end,
        "is a buffer, not a kernel"
    )
    assert(device.remove(table, buffer, "buffer") == 11)
    fails(
        function()
            device.remove(table, buffer, "buffer")
        end,
        "unknown or released GPU handle " .. buffer
    )
end

function M.publicHandlesDoNotCrossContexts()
    local left, right = device.resources(), device.resources()
    local handle = device.insert(left, "buffer", true)
    fails(
        function()
            device.lookup(right, handle, "buffer")
        end,
        "unknown or released GPU handle"
    )
    assert(handle ~= device.insert(right, "buffer", true))
end

function M.rangeChecksRejectOverflowAndOverrun()
    device.checkedrange("test", 4, 4, 8)
    fails(
        function()
            device.checkedrange("test", 5, 4, 8)
        end,
        "test range 5..9 exceeds buffer size 8"
    )
    fails(
        function()
            device.checkedrange("test", 2 ^ 53, 2, 2 ^ 53)
        end,
        "exceeds buffer size"
    )
end

function M.aRangeThatEndsTheBufferMayEndPartwayThroughAWord()
    assert(device.copyextent("upload", 0, 8, 8) == 8)
    assert(device.copyextent("upload", 0, 3, 3) == 4)
    assert(device.copyextent("upload", 4, 3, 7) == 4)
    fails(
        function()
            device.copyextent("upload", 0, 3, 8)
        end,
        "does not end the buffer"
    )
    fails(
        function()
            device.copyextent("upload", 2, 2, 4)
        end,
        "offset 2 is not aligned"
    )
end

function M.oneAllocationIsNotBoundForReadingAndWriting()
    local slot = {buffer = 7, offset = 0, size = 4}
    assert(device.binds({false, slot}, 7))
    assert(not device.binds({false, slot}, 8))
    assert(not device.binds({false, false}, 7))
end

local function words(values)
    local bytes = {}
    for _, value in ipairs(values) do
        bytes[
            #bytes + 1
        ] = string.char(
            value % 256,
            math.floor(value / 256) % 256,
            math.floor(value / 65536) % 256,
            math.floor(value / 16777216) % 256
        )
    end

    return table.concat(bytes)
end

local function moduleWithLocalSize(x, y, z)
    -- OpEntryPoint GLCompute %4 "main"; OpExecutionMode %4 LocalSize x y z
    return {0x07230203, 0x00010300, 0, 20, 0, 5 * 65536 + 15, 5, 4, 0x6e69616d, 0, 6 * 65536 + 16, 4, 17, x, y, z,}
end

function M.spirvIngestionIsBoundedAndEndianChecked()
    fails(
        function()
            device.spirvwords("")
        end,
        "complete 32-bit words"
    )
    fails(
        function()
            device.spirvwords("\3\2\35")
        end,
        "complete 32-bit words"
    )
    fails(
        function()
            device.spirvwords("\7\35\2\3")
        end,
        "invalid magic word or byte order"
    )
    local spirv, count = device.spirvwords("\3\2\35\7")
    assert(count == 1 and spirv[0] == 0x07230203)
end

function M.aDeclaredWorkgroupSizeMustBeTheCompiledOne()
    local module = moduleWithLocalSize(64, 1, 1)
    local spirv, count = device.spirvwords(words(module))
    device.checkworkgroupsize(spirv, count, "main", {64, 1, 1})
    fails(
        function()
            device.checkworkgroupsize(spirv, count, "main", {128, 1, 1})
        end,
        "declares workgroup size [128, 1, 1], but main is compiled for [64, 1, 1]"
    )
    device.checkworkgroupsize(spirv, count, "other", {128, 1, 1})
    local truncated, short = device.spirvwords(words({unpack(module, 1, #module - 1)}))
    fails(
        function()
            device.checkworkgroupsize(truncated, short, "main", {64, 1, 1})
        end,
        "invalid length"
    )
end

-- A valid compute module with one word changed: its 32-bit integer type
-- declares 367 bits, and naga's SPIR-V front end panics laying that out.
local function nagaPanicModule()
    local file = assert(io.open(require("helpers.paths").tests .. "/fixtures/naga-panic.spv", "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end

local function layoutOf(module)
    local spirv, count = device.spirvwords(words(module))
    device.checklayout(spirv, count)
end

-- A header, then %1 = OpTypeInt 32 0 and %2 = OpConstant %1 length, then
-- whatever array declarations follow.
local function moduleWithArrays(length, ...)
    local module = {0x07230203, 0x00010300, 0, 20, 0, 4 * 65536 + 21, 1, 32, 0, 4 * 65536 + 43, 1, 2, length}
    for _, word in ipairs({...}) do
        module[#module + 1] = word
    end

    return module
end

function M.typesNagaCannotLayOutAreRefused()
    local spirv, count = device.spirvwords(nagaPanicModule())
    fails(
        function()
            device.checklayout(spirv, count)
        end,
        "SPIR-V type %3 has an unsupported 367-bit width"
    )
    for _, bits in ipairs({8, 16, 32, 64}) do
        layoutOf({0x07230203, 0x00010300, 0, 20, 0, 4 * 65536 + 21, 1, bits, 1, 3 * 65536 + 22, 2, bits})
    end
    fails(
        function()
            layoutOf({0x07230203, 0x00010300, 0, 20, 0, 4 * 65536 + 21, 1, 0, 0})
        end,
        "SPIR-V type %1 has an unsupported 0-bit width"
    )
    fails(
        function()
            layoutOf({0x07230203, 0x00010300, 0, 20, 0, 3 * 65536 + 22, 1, 24})
        end,
        "SPIR-V type %1 has an unsupported 24-bit width"
    )
end

function M.arraysPastTheTypeSizeLimitAreRefused()
    -- %3 = OpTypeArray %1 %2: 2^28 four-byte elements are exactly 1 GiB.
    layoutOf(moduleWithArrays(0x10000000, 4 * 65536 + 28, 3, 1, 2))
    fails(
        function()
            layoutOf(moduleWithArrays(0x10000001, 4 * 65536 + 28, 3, 1, 2))
        end,
        "SPIR-V array type %3 is larger than the 1073741824-byte type limit"
    )
    -- %4 = OpTypeArray %3 %2: an array of arrays multiplies the sizes.
    fails(
        function()
            layoutOf(moduleWithArrays(0x8000, 4 * 65536 + 28, 3, 1, 2, 4 * 65536 + 28, 4, 3, 2))
        end,
        "SPIR-V array type %4 is larger than"
    )
    -- OpDecorate %3 ArrayStride 0x40000001 on %3 = OpTypeRuntimeArray %1.
    fails(
        function()
            layoutOf(moduleWithArrays(1, 4 * 65536 + 71, 3, 6, 0x40000001, 3 * 65536 + 29, 3, 1))
        end,
        "SPIR-V array type %3 is larger than"
    )
    -- %3 = struct { %1 at offset 0x3ffffffc } spans exactly 1 GiB, so an
    -- array of two is too large.
    fails(
        function()
            layoutOf(
                moduleWithArrays(2, 5 * 65536 + 72, 3, 0, 35, 0x3ffffffc, 3 * 65536 + 30, 3, 1, 4 * 65536 + 28, 4, 3, 2)
            )
        end,
        "SPIR-V array type %4 is larger than"
    )
    -- naga reads an ArrayStride of 0 as the natural stride, here 4 bytes.
    fails(
        function()
            layoutOf(moduleWithArrays(0x10000001, 4 * 65536 + 71, 3, 6, 0, 4 * 65536 + 28, 3, 1, 2))
        end,
        "SPIR-V array type %3 is larger than"
    )
end

-- One SPIR-V instruction: its opcode, then its operand words.
local function op(code, ...)
    local operands = {...}
    local result = {(#operands + 1) * 65536 + code}
    for _, value in ipairs(operands) do
        result[#result + 1] = value
    end

    return result
end

-- `instruction` grown to also span a hidden %60 = OpTypeInt 24 and a struct
-- of it, which naga reads as instructions of their own.
local function hiding(instruction)
    local result = {instruction[1] + 7 * 65536, unpack(instruction, 2)}
    for _, word in ipairs({4 * 65536 + 21, 60, 24, 0, 3 * 65536 + 30, 61, 60}) do
        result[#result + 1] = word
    end

    return result
end

-- A compute module whose entry point %10 runs `parts.body` after its label
-- %11. Ids: %1 void, %2 its function type, %3 int, %4 uint, %5 float, %6 bool,
-- %7 int vec2, %8 uint vec4, %9 struct {int, float}, %20 int 7, %21 uint 0,
-- %22 float 1.0, %23 uint 1, %24 true. `parts.modes`, `parts.annotations` and
-- `parts.declarations` go in their sections; `parts.bound` raises the id bound
-- from 200.
local function kernel(parts)
    local sections = {
        {op(17, 1), op(14, 0, 1), op(15, 5, 10, 0x6e69616d, 0), op(16, 10, 17, 1, 1, 1)},
        parts.modes or {},
        parts.annotations or {},
        {
            op(19, 1),
            op(33, 2, 1),
            op(21, 3, 32, 1),
            op(21, 4, 32, 0),
            op(22, 5, 32),
            op(20, 6),
            op(23, 7, 3, 2),
            op(23, 8, 4, 4),
            op(30, 9, 3, 5),
            op(43, 3, 20, 7),
            op(43, 4, 21, 0),
            op(43, 5, 22, 0x3f800000),
            op(43, 4, 23, 1),
            op(41, 6, 24),
        },
        parts.declarations or {},
        {op(54, 1, 10, 0, 2), op(248, 11)},
        parts.body or {},
        {op(253), op(56)},
    }
    local module = {0x07230203, 0x00010300, 0, parts.bound or 200, 0}
    for _, section in ipairs(sections) do
        for _, instruction in ipairs(section) do
            for _, word in ipairs(instruction) do
                module[#module + 1] = word
            end
        end
    end

    return module
end

-- %36, a storage buffer in group 1 holding a runtime array %34 of `element`,
-- with %37 a pointer to a uint in it.
local function storage(element, stride)
    return {
        annotations = {
            op(71, 34, 6, stride),
            op(72, 33, 0, 35, 0),
            op(71, 33, 2),
            op(71, 36, 34, 1),
            op(71, 36, 33, 0),
        },
        declarations = {op(29, 34, element), op(30, 33, 34), op(32, 35, 12, 33), op(59, 35, 36, 12), op(32, 37, 12, 4)},
    }
end

local function withBody(parts, body)
    return {annotations = parts.annotations, declarations = parts.declarations, body = body}
end

-- %32, a private int variable.
local PRIVATE = {op(32, 31, 6, 3), op(59, 31, 32, 6)}

-- Modules naga's front end panics on, each with the refusal that keeps it from
-- wgpu-native.
local PANICS = {
    smodOfAStruct = {
        kernel({
            body = {op(139, 9, 30, 20, 20)}
        }),
        "SPIR-V instruction 139 at word 77 needs a scalar, vector or matrix result"
    },
    negationOfAStruct = {
        kernel({
            body = {op(126, 9, 30, 20)}
        }),
        "SPIR-V instruction 126 at word 77 needs a scalar, vector or matrix result"
    },
    bitfieldOffsetOfAPointer = {
        kernel({
            declarations = PRIVATE,
            body = {op(203, 3, 30, 20, 32, 20)}
        }),
        "SPIR-V instruction 203 at word 85 needs a scalar, vector or matrix where %32 is not one"
    },
    switchOnAnUndefinedSelector = {
        kernel({
            body = {op(247, 40, 0), op(251, 99, 40), op(248, 40)}
        }),
        "SPIR-V OpSwitch at word 80 needs an integer selector of at most 32 bits defined before it"
    },
    switchOnAFloat = {
        kernel({
            body = {op(247, 40, 0), op(251, 22, 40), op(248, 40)}
        }),
        "SPIR-V OpSwitch at word 80 needs an integer selector of at most 32 bits defined before it"
    },
    constructionOfNothing = {
        kernel({
            body = {op(80, 8, 30)}
        }),
        "SPIR-V OpCompositeConstruct at word 77 has no constituents"
    },
    insertionPastAVector = {
        kernel({
            body = {op(80, 7, 30, 20, 20), op(82, 7, 31, 20, 30, 5)}
        }),
        "SPIR-V OpCompositeInsert at word 82 selects element 5 of %7, which has 2"
    },
    phiOfAnUndefinedValue = {
        kernel({
            body = {op(249, 40), op(248, 40), op(245, 3, 30, 99, 11)}
        }),
        "SPIR-V OpPhi at word 81 takes %99, which is no value of its function"
    },
    phiFromAType = {
        kernel({
            body = {op(249, 40), op(248, 40), op(245, 3, 30, 20, 3)}
        }),
        "SPIR-V OpPhi at word 81 names %3, which is no label of its function"
    },
    phiFromALabelOnlyBranchedTo = {
        kernel({
            body = {op(247, 42, 0), op(250, 24, 40, 41), op(248, 40), op(249, 42), op(248, 42), op(245, 3, 30, 20, 41),}
        }),
        "SPIR-V branch at word 80 goes to %41, which is no label of its function"
    },
    voidValueSpilledForAPhi = {
        kernel({
            body = {
                op(247, 42, 0),
                op(250, 24, 40, 41),
                op(248, 40),
                op(128, 1, 30, 20, 20),
                op(249, 42),
                op(248, 41),
                op(249, 42),
                op(248, 42),
                op(245, 3, 31, 30, 41),
            }
        }),
        "SPIR-V instruction at word 86 has result type %1, which is not a value type"
    },
    callOfNoFunction = {kernel({body = {op(57, 1, 30, 99)}}), "SPIR-V call at word 77 names %99, which is no function"},
    shortLocalSize = {
        kernel({
            modes = {op(16, 10, 17, 1)}
        }),
        "SPIR-V instruction 16 at word 21 has a word count naga reads differently"
    },
    atomicOnAVectorComponent = {
        kernel(
            withBody(storage(8, 16), {
                op(65, 37, 30, 36, 21, 21, 21),
                op(234, 4, 31, 30, 23, 21, 23),
            })
        ),
        "SPIR-V atomic at word 122 indexes something other than a struct or an array"
    },
    atomicOnAStruct = {
        kernel(
            withBody(storage(4, 4), {
                op(83, 37, 30, 36),
                op(234, 4, 31, 30, 23, 21, 23)
            })
        ),
        "SPIR-V atomic at word 119 does not reach an integer or a float"
    },
    atomicThroughARelabelledPointer = {
        kernel(
            {
                annotations = {
                    op(72, 50, 0, 35, 0),
                    op(71, 50, 2),
                    op(72, 51, 0, 35, 0),
                    op(72, 51, 1, 35, 4),
                    op(72, 51, 2, 35, 8),
                    op(71, 51, 2),
                    op(71, 54, 34, 1),
                    op(71, 54, 33, 0),
                },
                declarations = {
                    op(43, 4, 25, 2),
                    op(30, 50, 4),
                    op(30, 51, 4, 4, 4),
                    op(32, 52, 12, 50),
                    op(32, 53, 12, 51),
                    op(59, 52, 54, 12),
                    op(32, 55, 12, 4),
                },
                -- %54 holds a one-member struct; %30 calls it a three-member one.
                body = {op(83, 53, 30, 54), op(65, 55, 31, 30, 25), op(234, 4, 32, 31, 23, 21, 23)},
            }
        ),
        "SPIR-V atomic at word 148 selects no member of struct %50"
    },
    typeHiddenInADecoration = {
        kernel({
            annotations = {hiding(op(71, 9, 14))}
        }),
        "SPIR-V instruction 71 at word 21 has a word count naga reads differently"
    },
    typeHiddenInAString = {
        kernel({
            modes = {hiding(op(7, 70, 0x78))}
        }),
        "SPIR-V instruction 7 at word 21 has a word count naga reads differently"
    },
    typeHiddenInAConstant = {
        kernel({
            declarations = {hiding(op(43, 3, 71, 5))}
        }),
        "SPIR-V instruction 43 at word 70 has a word count naga reads differently"
    },
    quadSwapInAnUnknownDirection = {
        kernel({
            declarations = {op(43, 4, 26, 3)},
            body = {op(366, 4, 30, 26, 21, 26)}
        }),
        "SPIR-V instruction 366 at word 81 uses images, samplers or quads, which GPU kernels do not support"
    },
    imageReadAtAPointer = {
        kernel({
            declarations = {op(25, 62, 5, 1, 0, 0, 0, 2, 1), op(32, 63, 0, 62), op(59, 63, 64, 0), op(23, 65, 5, 4),},
            body = {op(61, 62, 30, 64), op(98, 65, 31, 30, 64)},
        }),
        "SPIR-V instruction 25 at word 70 uses images, samplers or quads, which GPU kernels do not support"
    },
}

-- Modules naga compiles, which the structural check must let through.
local ACCEPTED = {
    empty = kernel({}),
    branchesAPhiAndASwitch = kernel({
        body = {
            op(247, 42, 0),
            op(250, 24, 40, 41),
            op(248, 40),
            op(249, 42),
            op(248, 41),
            op(249, 42),
            op(248, 42),
            op(245, 3, 30, 20, 40, 20, 41),
            op(247, 43, 0),
            op(251, 20, 43, 7, 44),
            op(248, 44),
            op(249, 43),
            op(248, 43),
        }
    }),
    atomicOnAStorageElement = kernel(
        withBody(storage(4, 4), {
            op(65, 37, 30, 36, 21, 21),
            op(234, 4, 31, 30, 23, 21, 23),
        })
    ),
}

local function structureOf(module)
    local spirv, count = device.spirvwords(words(module))
    device.checkstructure(spirv, count)
end

function M.modulesNagaWouldPanicOnAreRefusedStructurally()
    for name, case in pairs(PANICS) do
        local ok, problem = pcall(structureOf, case[1])
        assert(not ok, name .. " was accepted")
        assert(problem.message == case[2], name .. ": " .. tostring(problem.message))
    end
    for name, module in pairs(ACCEPTED) do
        local ok, problem = pcall(structureOf, module)
        assert(ok, name .. ": " .. tostring(type(problem) == "table" and problem.message or problem))
    end
end

function M.idsAndResultTypesAreOnesNagaRecords()
    local function refuses(body, message)
        fails(
            function()
                structureOf(kernel({body = body}))
            end,
            message
        )
    end

    refuses({op(124, 3, 0, 20)}, "SPIR-V id %0 at word 77 is outside the module's bound 200")
    refuses({op(124, 3, 200, 20)}, "SPIR-V id %200 at word 77 is outside the module's bound 200")
    refuses({op(124, 3, 20, 20)}, "SPIR-V id %20 is defined twice")
    refuses({op(83, 2, 30, 20)}, "SPIR-V instruction at word 77 has result type %2, which is not a value type")
    refuses({op(83, 99, 30, 20)}, "SPIR-V instruction at word 77 has result type %99, which is not a value type")
end

function M.instructionsSpanExactlyTheWordsNagaReads()
    local function refuses(parts, message)
        fails(
            function()
                structureOf(kernel(parts))
            end,
            message
        )
    end

    -- Flag decorations and SpecId, and an extended instruction with no number.
    refuses({annotations = {op(71, 9, 24, 0)}}, "instruction 71 at word 21 has a word count")
    refuses({annotations = {op(72, 9, 0, 24, 0)}}, "instruction 72 at word 21 has a word count")
    refuses({annotations = {op(71, 20, 1, 0, 0)}}, "instruction 71 at word 21 has a word count")
    refuses({body = {op(12, 3, 30, 99)}}, "instruction 12 at word 77 has a word count")
    -- A constant's words follow its type's width.
    refuses({declarations = {op(43, 3, 30, 1, 0)}}, "instruction 43 at word 70 has a word count")
    refuses({declarations = {op(21, 30, 64, 0), op(43, 30, 31, 1)}}, "instruction 43 at word 74 has a word count")
    structureOf(kernel({declarations = {op(21, 30, 64, 0), op(43, 30, 31, 1, 0)}}))
    -- A string ends in its last word.
    refuses({modes = {op(7, 70, 0x78, 0)}}, "instruction 7 at word 21 has a word count")
    refuses({modes = {op(4, 0x78787878)}}, "instruction 4 at word 21 has a word count")
    structureOf(kernel({modes = {op(7, 70, 0x78787878, 0)}}))
    -- An OpPhi's and an OpSwitch's operands come in pairs; a derivative has one.
    refuses(
        {body = {op(249, 40), op(248, 40), op(245, 3, 30, 20, 11, 0)}},
        "instruction 245 at word 81 has a word count"
    )
    refuses({body = {op(247, 40, 0), op(251, 20, 40, 7), op(248, 40)}}, "instruction 251 at word 80 has a word count")
    refuses({body = {op(207, 5, 30, 22, 0)}}, "instruction 207 at word 77 has a word count")
end

function M.switchSelectorsAreNarrowIntegersDefinedBeforeThem()
    local function switchOn(declarations, selector)
        structureOf(kernel({declarations = declarations, body = {op(247, 40, 0), op(251, selector, 40), op(248, 40)}}))
    end

    switchOn({}, 20)
    fails(
        function()
            switchOn({op(21, 30, 64, 1), op(43, 30, 31, 1, 0)}, 31)
        end,
        "needs an integer selector"
    )
    fails(
        function()
            switchOn(PRIVATE, 32)
        end,
        "needs an integer selector"
    )
    fails(
        function()
            switchOn({}, 10)
        end,
        "needs an integer selector"
    )
end

function M.compositeInsertionsStayInsideTheirTypes()
    local function insert(declarations, body)
        structureOf(kernel({declarations = declarations, body = body}))
    end

    insert({}, {op(80, 7, 30, 20, 20), op(82, 7, 31, 20, 30, 1)})
    fails(
        function()
            insert({}, {op(80, 9, 30, 20, 22), op(82, 9, 31, 20, 30, 2)})
        end,
        "selects element 2 of %9, which has 2"
    )
    -- %31 = int[65537]; naga would build an expression for every element.
    fails(
        function()
            insert({op(43, 4, 30, 65537), op(28, 31, 3, 30), op(46, 31, 32)}, {op(82, 31, 33, 20, 32, 0)})
        end,
        "indexes an array of 65537 elements; at most 65536 are supported"
    )
end

function M.callsNameFunctions()
    local callee = {op(54, 1, 40, 0, 2), op(248, 41), op(253), op(56)}
    local module = kernel({body = {op(57, 1, 30, 40)}})
    for _, instruction in ipairs(callee) do
        for _, word in ipairs(instruction) do
            module[#module + 1] = word
        end
    end
    structureOf(module)
    fails(
        function()
            structureOf(kernel({body = {op(57, 1, 30, 20)}}))
        end,
        "names %20, which is no function"
    )
end

-- The entry point with `depth` selections nested inside one another, ids from
-- %1000. Without `merged`, the conditional branches have no OpSelectionMerge,
-- and each one's second target returns at once; naga nests them all the same.
local function nestedSelections(depth, merged)
    local body = {}
    for level = 1, depth do
        local yes, no = 1000 + 2 * level, 1001 + 2 * level
        if merged then
            body[#body + 1] = op(247, no, 0)
        end
        body[#body + 1] = op(250, 24, yes, no)
        if not merged then
            body[#body + 1] = op(248, no)
            body[#body + 1] = op(253)
        end
        body[#body + 1] = op(248, yes)
    end
    for level = merged and depth or 0, 1, -1 do
        body[#body + 1] = op(249, 1001 + 2 * level)
        body[#body + 1] = op(248, 1001 + 2 * level)
    end

    return kernel({body = body, bound = 1100 + 2 * depth})
end

-- `count` selections one after another, each merging before the next.
local function consecutiveSelections(count)
    local body = {}
    for index = 1, count do
        local yes, merge = 1000 + 2 * index, 1001 + 2 * index
        body[#body + 1] = op(247, merge, 0)
        body[#body + 1] = op(250, 24, yes, merge)
        body[#body + 1] = op(248, yes)
        body[#body + 1] = op(249, merge)
        body[#body + 1] = op(248, merge)
    end

    return kernel({body = body, bound = 1100 + 2 * count})
end

-- The entry point with `depth` loops nested inside one another, each leaving
-- through its merge block on its first pass. Loop n's header, body, continue
-- and merge blocks are %(1000 + 4n) to %(1003 + 4n).
local function nestedLoops(depth)
    local function label(level, part)
        return 1000 + 4 * level + part
    end

    local body = {op(249, label(1, 0))}
    for level = 1, depth do
        body[#body + 1] = op(248, label(level, 0))
        body[#body + 1] = op(246, label(level, 3), label(level, 2), 0)
        body[#body + 1] = op(249, label(level, 1))
        body[#body + 1] = op(248, label(level, 1))
        body[#body + 1] = op(249, level < depth and label(level + 1, 0) or label(level, 3))
    end
    for level = depth, 1, -1 do
        body[#body + 1] = op(248, label(level, 2))
        body[#body + 1] = op(249, label(level, 0))
        body[#body + 1] = op(248, label(level, 3))
        if level > 1 then
            body[#body + 1] = op(249, label(level - 1, 3))
        end
    end

    return kernel({body = body, bound = 1100 + 4 * depth})
end

-- `count` loops one after another, each leaving through its merge block on its
-- first pass and the next starting there, with the same labels as
-- `nestedLoops`.
local function consecutiveLoops(count)
    local function label(index, part)
        return 1000 + 4 * index + part
    end

    local body = {}
    for index = 1, count do
        local header, merge = label(index, 0), label(index, 3)
        body[#body + 1] = op(249, header)
        body[#body + 1] = op(248, header)
        body[#body + 1] = op(246, merge, label(index, 2), 0)
        body[#body + 1] = op(249, label(index, 1))
        body[#body + 1] = op(248, label(index, 1))
        body[#body + 1] = op(249, merge)
        body[#body + 1] = op(248, label(index, 2))
        body[#body + 1] = op(249, header)
        body[#body + 1] = op(248, merge)
    end

    return kernel({body = body, bound = 1100 + 4 * count})
end

-- A private variable whose type is an int inside `depth` structs (or arrays
-- of one element), from %1001, loaded in the entry point. Its pointer type
-- adds no level.
local function nestedTypes(depth, array)
    local declarations = {}
    for level = 1, depth do
        local inner = level == 1 and 3 or 999 + level
        declarations[level] = array and op(28, 1000 + level, inner, 23) or op(30, 1000 + level, inner)
    end
    local outer = 1000 + depth
    declarations[#declarations + 1] = op(32, outer + 1, 6, outer)
    declarations[#declarations + 1] = op(59, outer + 1, outer + 2, 6)

    return kernel({declarations = declarations, body = {op(61, outer, 30, outer + 2)}, bound = 1100 + depth})
end

-- Modules at the nesting bound, and one level past it.
local NESTING = {
    selections = {nestedSelections(128, true), nestedSelections(129, true), "SPIR-V control flow at word"},
    loops = {nestedLoops(128), nestedLoops(129), "SPIR-V control flow at word"},
    structs = {nestedTypes(128), nestedTypes(129), "SPIR-V type %1129"},
    arrays = {nestedTypes(128, true), nestedTypes(129, true), "SPIR-V type %1129"},
}
local PAST_THE_BOUND = " nests 129 deep; at most 128 levels are supported"

function M.blocksAndTypesNestedPastTheBoundAreRefused()
    for name, case in pairs(NESTING) do
        local ok, problem = pcall(structureOf, case[1])
        assert(ok, name .. ": " .. tostring(type(problem) == "table" and problem.message or problem))
        fails(
            function()
                structureOf(case[2])
            end,
            case[3]
        )
        fails(
            function()
                structureOf(case[2])
            end,
            PAST_THE_BOUND
        )
    end
    -- naga nests a conditional branch's targets whether or not it merges.
    structureOf(nestedSelections(128, false))
    fails(
        function()
            structureOf(nestedSelections(129, false))
        end,
        PAST_THE_BOUND
    )
    -- Constructs one after another do not nest.
    structureOf(consecutiveSelections(1000))
end

local function loopsPastTheBound(loops)
    return (" nests %d loops deep; at most %d nested loops are supported"):format(loops + 1, loops)
end

-- DX12's shader compiler unrolls nested loops in time that grows with each
-- level, so loops nest less deeply there than other blocks do.
function M.loopsNestedPastADx12BoundAreRefusedThere()
    local dx12 = device.loopnesting("dx12")
    assert(dx12 == device.MAX_DX12_LOOP_NESTING and dx12 < 128, tostring(dx12))
    assert(device.loopnesting("vulkan") == 128 and device.loopnesting("metal") == 128)

    local function structure(module, loops)
        local spirv, count = device.spirvwords(words(module))
        device.checkstructure(spirv, count, loops)
    end

    structure(nestedLoops(dx12), dx12)
    fails(
        function()
            structure(nestedLoops(dx12 + 1), dx12)
        end,
        "SPIR-V loop at word "
    )
    fails(
        function()
            structure(nestedLoops(dx12 + 1), dx12)
        end,
        loopsPastTheBound(dx12)
    )
    -- Loops one after another do not nest, and other blocks keep their bound.
    structure(consecutiveLoops(dx12 + 1), dx12)
    structure(nestedSelections(128, true), dx12)
    structure(nestedTypes(128), dx12)
    -- Without a loop bound, loops nest as deep as any block.
    structure(nestedLoops(128))
    fails(
        function()
            structure(nestedLoops(129))
        end,
        PAST_THE_BOUND
    )
end

function M.closingAfterAWriteErrorPreservesTheErrorAndResetsTheSink()
    local path = temporary("close")
    assert(costs.configure(path) == nil)
    costs.injectfailure("injected write failure")
    costs.setsequence(7)
    assert(costs.configure(nil) == "injected write failure")
    local state = costs.state()
    assert(not state.open, "failed close retained the output file")
    assert(state.failure == nil and not state.initialized and not state.active and not state.configured)
    assert(state.sequence == 7, "the sequence runs on across destinations")
    os.remove(path)
end

function M.aFailedOutputStillGivesWayToTheNextOne()
    local path = temporary("next")
    costs.injectfailure("injected write failure")
    assert(costs.configure(path) == "injected write failure")
    assert(io.open(path, "rb"), "the new destination was not opened"):close()
    assert(costs.enabled())
    assert(costs.configure(nil) == nil)
    os.remove(path)
end

function M.recordsAreJsonAndKeepHostAndGpuTimesDistinct()
    local line = costs.encode(
        7,
        "kernel",
        {sourceFile = "a\"b\\c.nupp", hostMs = 1.0, gpuMs = costs.NULL, gpuTiming = "unavailable"},
        1
    )
    local row = assert(json.decode(line:gsub("\n$", ""), json.NULL))
    assert(row.sourceFile == "a\"b\\c.nupp")
    assert(row.gpuMs == json.NULL)
    assert(row.hostMs == 1.0 and row.sequence == 1 and row.context == 7 and row.target == "gpu")
    assert(line:find('"gpuMs":null', 1, true), line)
end

function M.narrowBuffersMoveBytesThatEndPartwayThroughAWordWhenAvailable()
    local gpu = open()
    local buffer = check(device.createbuffer(gpu, 3))
    check(upload(gpu, buffer, 0, memory.new("uint8_t[3]", {1, 2, 3}), 3))
    check(device.queuedownload(gpu, buffer, 0, 3))
    check(device.synchronize(gpu))
    local bytes = memory.new("uint8_t[3]")
    check(readdownload(gpu, buffer, 0, 3, bytes))
    assert(bytes[0] == 1 and bytes[1] == 2 and bytes[2] == 3)
    local kernel = check(device.createwgslkernel(gpu, ROUND_TRIP, {1, 1, 1}))
    local bindings = check(device.createbindings(gpu, kernel))
    check(device.setbuffer(gpu, bindings, true, 0, buffer, 0, 3))
    check(device.releasebindings(gpu, bindings))
    check(device.releasekernel(gpu, kernel))
    check(device.releasebuffer(gpu, buffer))
    check(device.close(gpu))
end

function M.anUnreadDownloadSaysSoWhenAvailable()
    local gpu = open()
    local buffer = check(device.createbuffer(gpu, 16))
    check(device.queuedownload(gpu, buffer, 0, 16))
    local _, pending = device.queuedownload(gpu, buffer, 0, 16)
    assert(pending == "gpu: buffer " .. buffer .. " already has a queued download", pending)
    local _, held = device.releasebuffer(gpu, buffer)
    assert(held == pending, held)
    check(device.synchronize(gpu))
    local _, unread = device.queuedownload(gpu, buffer, 0, 16)
    assert(unread == "gpu: buffer " .. buffer .. " has a synchronized download that has not been read yet", unread)
    local _, mismatch = readdownload(gpu, buffer, 4, 12, memory.new("uint8_t[12]"))
    assert(mismatch == "gpu: downloaded range 0..16 does not match requested range 4..16", mismatch)
    check(readdownload(gpu, buffer, 0, 16, memory.new("uint8_t[16]")))
    local _, missing = readdownload(gpu, buffer, 0, 16, memory.new("uint8_t[16]"))
    assert(missing == "gpu: buffer " .. buffer .. " has no synchronized download", missing)
    check(device.queuedownload(gpu, buffer, 0, 16))
    check(device.synchronize(gpu))
    check(device.releasebuffer(gpu, buffer))
    check(device.close(gpu))
end

function M.aCostOutputFailureLeavesAConsumedDownloadReadWhenAvailable()
    local gpu = open()
    local buffer = check(device.createbuffer(gpu, 16))
    check(upload(gpu, buffer, 0, memory.new("uint8_t[16]", {9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9}), 16))
    check(device.queuedownload(gpu, buffer, 0, 16))
    check(device.synchronize(gpu))
    costs.injectfailure("injected write failure")
    local bytes = memory.new("uint8_t[16]")
    check(readdownload(gpu, buffer, 0, 16, bytes))
    assert(bytes[0] == 9 and bytes[15] == 9)
    assert(costs.check() == "injected write failure")
    check(device.releasebuffer(gpu, buffer))
    check(device.close(gpu))
end

function M.submittedWorkIsAnsweredWithoutBlockingWhenAvailable()
    local gpu = open()
    local kernel = check(device.createwgslkernel(gpu, ROUND_TRIP, {1, 1, 1}))
    local buffer = check(device.createbuffer(gpu, 65536))
    local bindings = check(device.createbindings(gpu, kernel))
    check(device.setbuffer(gpu, bindings, true, 0, buffer, 0, 65536))
    for _ = 1, 8 do
        check(dispatch(gpu, bindings, {16384, 1, 1}, NO_UNIFORMS, 0))
    end
    local deadline = os.time() + 30
    while not check(device.workdone(gpu)) do
        assert(os.time() < deadline, "GPU work never finished")
        device.pause(1)
    end
    assert(check(device.workdone(gpu)))
    check(device.synchronize(gpu))
    check(device.close(gpu))
end

function M.invalidSpirvIsAValidationFailureWhenAvailable()
    local gpu = open()
    local module = moduleWithLocalSize(64, 1, 1)
    local _, problem = device.createkernel(gpu, words(module), "main", 0, 1, 0, {64, 1, 1})
    assert(problem and problem:find("^gpu: GPU validation: "), tostring(problem))
    local buffer = check(device.createbuffer(gpu, 16))
    check(device.releasebuffer(gpu, buffer))
    check(device.close(gpu))
end

function M.aModuleNagaWouldPanicOnFailsWithoutEndingTheProcessWhenAvailable()
    local gpu = open()
    local _, problem = device.createkernel(gpu, nagaPanicModule(), "main", 1, 1, 16, {64, 1, 1})
    assert(problem == "gpu: SPIR-V type %3 has an unsupported 367-bit width", tostring(problem))
    local other = check(device.open())
    local buffer = check(device.createbuffer(other, 16))
    check(device.releasebuffer(other, buffer))
    check(device.close(other))
    check(device.close(gpu))
end

function M.modulesNagaWouldPanicOnFailWithoutEndingTheProcessWhenAvailable()
    local gpu = open()
    for name, case in pairs(PANICS) do
        local _, problem = device.createkernel(gpu, words(case[1]), "main", 0, 1, 0, {1, 1, 1})
        assert(problem == "gpu: " .. case[2], name .. ": " .. tostring(problem))
    end
    for name, module in pairs(ACCEPTED) do
        local kernel, problem = device.createkernel(gpu, words(module), "main", 0, 1, 0, {1, 1, 1})
        assert(kernel, name .. ": " .. tostring(problem))
        check(device.releasekernel(gpu, kernel))
    end
    check(device.close(gpu))
end

-- wgpu-native answers a module naga refuses with an empty one, and panics if a
-- pipeline is created from that.
function M.aModuleNagaRefusesFailsWithoutEndingTheProcessWhenAvailable()
    local gpu = open()
    -- An OpIAdd one operand short.
    local module = words(kernel({body = {op(128, 3, 30, 20)}}))
    local _, problem = device.createkernel(gpu, module, "main", 0, 1, 0, {1, 1, 1})
    assert(problem and problem:find("^gpu: GPU validation: "), tostring(problem))
    local buffer = check(device.createbuffer(gpu, 16))
    check(device.releasebuffer(gpu, buffer))
    check(device.close(gpu))
end

-- naga's validator overflows the stack at about 1360 nested selections on a
-- 2 MiB stack, and an NVIDIA Vulkan driver at about 14000 nested structs. Both
-- ended the process with no message. On DX12, the shader compiler takes
-- minutes over a dozen nested loops, so loops stop at that backend's bound.
function M.modulesAtTheNestingBoundCompileWithoutEndingTheProcessWhenAvailable()
    local gpu = open()
    local loops = device.loopnesting(device.description(gpu):match("^([^:]*)"))
    local cases = {}
    for name, case in pairs(NESTING) do
        cases[name] = case
    end
    local loopsRefused = PAST_THE_BOUND
    if loops < 128 then
        loopsRefused = loopsPastTheBound(loops)
        cases.loops = {nestedLoops(loops), nestedLoops(loops + 1), "SPIR-V loop at word"}
    end
    local deep = {
        {nestedSelections(2000, true), PAST_THE_BOUND},
        {nestedLoops(2000), loopsRefused},
        {nestedTypes(20000), PAST_THE_BOUND},
    }
    for index, module in ipairs(deep) do
        local _, refused = device.createkernel(gpu, words(module[1]), "main", 0, 1, 0, {1, 1, 1})
        assert(
            refused and refused:find("^gpu: ") and refused:find(module[2], 1, true),
            index .. ": " .. tostring(refused)
        )
    end
    for name, case in pairs(cases) do
        local kernel, problem = device.createkernel(gpu, words(case[1]), "main", 0, 1, 0, {1, 1, 1})
        assert(kernel, name .. ": " .. tostring(problem))
        check(device.releasekernel(gpu, kernel))
        local _, refused = device.createkernel(gpu, words(case[2]), "main", 0, 1, 0, {1, 1, 1})
        local past = name == "loops" and loopsRefused or PAST_THE_BOUND
        assert(
            refused and refused:find("^gpu: ") and refused:find(case[3], 1, true) and refused:find(past, 1, true),
            name .. ": " .. tostring(refused)
        )
    end
    check(device.close(gpu))
end

function M.adapterComputeRoundTripWhenAvailable()
    local path = temporary("integration")
    assert(costs.configure(path) == nil)
    local gpu, problem = device.open()
    if gpu == nil then
        assert(costs.configure(nil) == nil)
        os.remove(path)
        assert(os.getenv("NUPP_REQUIRE_GPU") == nil, "required GPU adapter is unavailable: " .. tostring(problem))
        assertions.suite.skip("no GPU adapter: " .. tostring(problem))
    end
    local description = device.description(gpu)
    local backend, adapter = os.getenv("NUPP_EXPECT_GPU_BACKEND"), os.getenv("NUPP_EXPECT_GPU_ADAPTER")
    assert(backend == nil or description:find("^" .. backend .. ": "), description)
    assert(adapter == nil or description:lower():find(adapter:lower(), 1, true), description)
    local contextId = device.costid(gpu)
    local timestamps = device.timestamps(gpu)
    local kernel = check(device.createwgslkernel(gpu, ROUND_TRIP, {1, 1, 1}))
    check(
        device.metadata(gpu, kernel, true, {
            sourceFile = "round-trip.nupp",
            sourceLine = 8,
            artifactId = "fixture",
            writableNames = {"values"}
        })
    )
    local buffer = check(device.createbuffer(gpu, 16))
    check(device.metadata(gpu, buffer, false, {format = "uint32", shape = {4}, elementBytes = 4}))
    check(upload(gpu, buffer, 0, memory.new("uint32_t[4]", {1, 2, 3, 4}), 16))
    local bindings = check(device.createbindings(gpu, kernel))
    check(device.setbuffer(gpu, bindings, true, 0, buffer, 0, 16))
    check(device.metadata(gpu, buffer, false, {shape = {2, 2}, strides = {2, 1}}))
    check(dispatch(gpu, bindings, {4, 1, 1}, NO_UNIFORMS, 0))
    check(dispatch(gpu, bindings, {4, 1, 1}, NO_UNIFORMS, 0))
    check(device.queuedownload(gpu, buffer, 0, 16))
    -- This upload is ordered after the queued copy; its version must not
    -- replace the downloaded snapshot's provenance.
    check(device.metadata(gpu, buffer, false, {shape = {1, 4}, strides = {4, 1}}))
    check(upload(gpu, buffer, 0, memory.new("uint32_t[4]"), 16))
    check(device.synchronize(gpu))
    local values = memory.new("uint32_t[4]")
    check(readdownload(gpu, buffer, 0, 16, values))
    assert(values[0] == 3 and values[1] == 4 and values[2] == 5 and values[3] == 6)
    -- Hardware without timestamp support, even on an adapter that has it: no
    -- host duration may masquerade as device time.
    device.timestamps(gpu, false)
    check(dispatch(gpu, bindings, {4, 1, 1}, NO_UNIFORMS, 0))
    check(device.synchronize(gpu))
    assert(costs.configure(nil) == nil)
    -- A retained device keeps its capability, but disabling costs must stop
    -- allocating and resolving queries on later dispatches.
    device.timestamps(gpu, timestamps)
    check(dispatch(gpu, bindings, {4, 1, 1}, NO_UNIFORMS, 0))
    assert(device.pendingtimestamps(gpu) == 0)
    check(device.synchronize(gpu))
    local rows = {}
    for _, line in ipairs(lines(path)) do
        local row = assert(json.decode(line, json.NULL))
        if row.context == contextId then
            rows[#rows + 1] = row
        end
    end

    local function find(operation)
        for _, row in ipairs(rows) do
            if row.operation == operation then
                return row
            end
        end
    end

    assert(find("adapterDevice"))
    local dispatches = {}
    for _, row in ipairs(rows) do
        if row.operation == "dispatch" then
            dispatches[#dispatches + 1] = row
        end
    end
    assert(#dispatches == 3, #dispatches)
    assert(dispatches[3].gpuTiming == "unavailable" and dispatches[3].gpuMs == json.NULL)
    assert(dispatches[1].phase == "first-use" and dispatches[2].phase == "steady-state")
    assert(dispatches[1].bindingsReused == false)
    assert(dispatches[2].bindingsReused == true, "absent layouts do not count as cache misses")
    assert(dispatches[2].write[1].version == 3)
    assert(
        dispatches[1].write[1].layout.shape[1] == 4 and #dispatches[1].write[1].layout.shape == 1,
        "bindings retain their own view shape"
    )
    assert(dispatches[1].metadata.writableNames[1] == "values")
    for _, operation in ipairs({"downloadQueue", "downloadMapCopy", "downloadHostCopy"}) do
        local row = assert(find(operation), operation)
        assert(row.version == 3, operation .. " keeps the queued snapshot version")
        assert(row.bytes == 16)
        assert(row.layout.shape[1] == 2 and row.layout.shape[2] == 2, operation .. " keeps queued layout")
    end
    if timestamps then
        local timings = {}
        for _, row in ipairs(rows) do
            if row.operation == "kernelExecution" then
                timings[#timings + 1] = row
            end
        end
        assert(#timings == 2, #timings)
        for _, timing in ipairs(timings) do
            local first = memory.new("uint64_t", tonumber(timing.gpuTicksBegin))
            local last = memory.new("uint64_t", tonumber(timing.gpuTicksEnd))
            local _, reason = device.timestampmilliseconds(first, last, timing.gpuTickPeriodNs)
            if reason == nil then
                assert(timing.gpuTiming == "timestamp-query" and type(timing.gpuMs) == "number")
                assert(timing.gpuTimingReason == json.NULL)
            else
                assert(timing.gpuTiming == "unavailable" and timing.gpuMs == json.NULL)
                assert(timing.gpuTimingReason == reason)
            end
        end
    else
        assert(dispatches[1].gpuTiming == "unavailable")
    end
    os.remove(path)
    check(device.releasebindings(gpu, bindings))
    check(device.releasekernel(gpu, kernel))
    check(device.releasebuffer(gpu, buffer))
    local _, stale = device.releasebuffer(gpu, buffer)
    assert(stale == "gpu: unknown or released GPU handle " .. buffer, stale)
    check(device.close(gpu))
end

return M
