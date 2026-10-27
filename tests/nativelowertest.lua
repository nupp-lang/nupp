-- The native lowering: ordinary typed Nupp compiled to CLIF by
-- `nupp.compiler.clif.lower`, run just in time by the glue
-- (`nupp-vm native jit`) and compared with answers computed here; and what the
-- lowering and the glue refuse. The glue is `nupp-vm` built with its code
-- generator, which `scripts/vm-cli glue` builds into the shared target
-- directory and names.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local FIXTURES = ROOT .. "/tests/fixtures/native"

local lower = require("nupp.compiler.clif.lower")
local helpercontract = require("nupp.compiler.vm.helpercontract")
local slotcontract = require("nupp.compiler.vm.slotcontract")
local programcontract = require("nupp.compiler.vm.programcontract")

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local glue = nil

local function glueTool()
    if not glue then
        local status, output = capture(("cd %s && python3 scripts/vm-cli glue"):format(quote(ROOT)))
        assert(status == 0, "scripts/vm-cli glue failed: " .. output)
        glue = assert(output:match("([^\r\n]+)%s*$"), "scripts/vm-cli glue named no tool")
    end

    return glue
end

local function tempDirectory()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. quote(dir)) == 0)
    return dir
end

local function write(path, text)
    local sub = path:match("^(.*)/[^/]+$")
    if sub then
        assert(os.execute("mkdir -p " .. quote(sub)) == 0)
    end
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

-- A fixture, with the runtime modules it requires compiled beside it.
local function compileFixture(name, runtimeModules)
    local paths = {FIXTURES .. "/" .. name .. ".nupp"}
    for _, module in ipairs(runtimeModules or {}) do
        paths[#paths + 1] = ROOT .. "/src/nupp/runtime/vm/" .. module .. ".nupp"
    end
    local clif = lower.compile(ROOT, paths, {include = {"src", "tests/fixtures/native"}})
    local path = tempDirectory() .. "/" .. name .. ".clif"
    write(path, clif)

    return path
end

local function run(clif, name, args)
    local words = {}
    for index, arg in ipairs(args) do
        words[index] = quote(arg)
    end
    local status, output = capture(
        ("%s native jit %s %s %s"):format(quote(glueTool()), quote(clif), quote(name), table.concat(words, " "))
    )
    assert(status == 0, ("%s(%s): %s"):format(name, table.concat(args, ", "), output))

    return (output:gsub("%s+$", ""))
end

local function fib(n)
    return n < 2 and n or fib(n - 1) + fib(n - 2)
end

local function collatz(n)
    local steps = 0
    while n ~= 1 do
        n = n % 2 == 0 and n / 2 or 3 * n + 1
        steps = steps + 1
    end

    return steps
end

local function nested(n)
    local count = 0
    for i = 1, n do
        for j = 0, i - 1 do
            if (i + j) % 3 == 0 then
                count = count + 1
            end
        end
    end

    return count
end

local function findBreak(limit)
    for i = 1, 1000 do
        if i ^ 3 > limit then
            return i
        end
    end

    return -1
end

-- The scalar cases: {function, arguments, expected}. Integers are compared as
-- text so 64-bit values survive; floats as numbers; booleans as words.
local SCALARS = {
    {"fib", {0}, "0"},
    {"fib", {1}, "1"},
    {"fib", {20}, tostring(fib(20))},
    {"sum", {0}, "0"},
    {"sum", {100}, "5050"},
    {"gcd", {48, 18}, "6"},
    {"gcd", {17, 5}, "1"},
    {"gcd", {"9223372036854775814", 9}, "1"},
    {"clamp", {0.5, 0.0, 1.0}, 0.5},
    {"clamp", {-3.25, 0.0, 1.0}, 0.0},
    {"clamp", {7.0, 0.0, 1.0}, 1.0},
    {"triangle", {10}, "55"},
    {"triangle", {0}, "0"},
    {"countdown", {5}, "5"},
    {"countdown", {0}, "0"},
    {"collatz", {27}, tostring(collatz(27))},
    {"collatz", {1}, "0"},
    {"firstSquareAbove", {50}, "8"},
    {"firstSquareAbove", {0}, "1"},
    {"findBreak", {100}, findBreak(100)},
    {"findBreak", {"1000000000000"}, -1},
    {"both", {"true", "true"}, true},
    {"both", {"true", "false"}, false},
    {"either", {"false", "false"}, false},
    {"either", {"false", "true"}, true},
    {"neither", {"false", "false"}, true},
    {"neither", {"true", "false"}, false},
    {"floorMod", {7, 3}, "1"},
    {"floorMod", {-7, 3}, "2"},
    {"floorMod", {7, -3}, "-2"},
    {"floorMod", {-7, -3}, "-1"},
    {"floorMod", {6, 3}, "0"},
    {"floorMod", {-6, 3}, "0"},
    {"floorDiv", {7, 3}, "2"},
    {"floorDiv", {-7, 3}, "-3"},
    {"floorDiv", {7, -3}, "-3"},
    {"floorDiv", {-7, -3}, "2"},
    {"floorDiv", {-6, 3}, "-2"},
    -- (((a & b) | (a ^ b)) << 1 & mask) >> 1 is a | b with the top bit cleared.
    {"bits", {12, 10}, "14"},
    {"bits", {"9223372036854775808", 1}, "1"},
    {"mean", {1.0, 2.0}, 1.5},
    {"mean", {-1.0, 0.0}, -0.5},
    {"scaled", {2.0}, 2.75},
    {"scaled", {0.0}, -0.25},
    {"negate", {5}, "-5"},
    {"negate", {"-9223372036854775808"}, "-9223372036854775808"},
    {"compound", {1}, "18"},
    {"compound", {-5}, "6"},
    {"nestedLoops", {10}, tostring(nested(10))},
    {"nestedLoops", {0}, "0"},
}

local STRUCTS = {
    {"total", {"buffer:320", 10}, "450"},
    {"total", {"buffer:32", 0}, "0"},
    {"weight", {"buffer:320", 10}, 2.5},
    {"weight", {"buffer:320", 3}, 1.0},
    {"counts", {"buffer:320", 10}, "70"},
    {"words", {"buffer:64", 8}, "24"},
}

-- (a + b) * (c + d) over seven nodes written into the buffer; `chain` links
-- cells holding every other leaf and sums what they hold.
local TAGGED = {
    {"evaluate", {"buffer:512", 1, 2, 3, 4}, "21"},
    {"evaluate", {"buffer:512", -5, 5, 7, 0}, "0"},
    {"evaluate", {"buffer:512", 10, 20, 3, 4}, "210"},
    {"leaves", {"buffer:512", 1, 2, 3, 4}, "4"},
    {"sums", {"buffer:512", 1, 2, 3, 4}, "2"},
    {"tagOf", {"buffer:512", 0}, "3"},
    {"tagOf", {"buffer:512", 1}, "2"},
    {"tagOf", {"buffer:512", 2}, "2"},
    {"chain", {"buffer:512", 6}, "60"},
    {"chain", {"buffer:512", 1}, "0"},
    {"chain", {"buffer:512", 0}, "0"},
}

-- Operations dispatched through a table of function pointers in the buffer.
local POINTERS = {
    {"dispatch", {"buffer:64", 0, 7, 3}, "10"},
    {"dispatch", {"buffer:64", 1, 7, 3}, "4"},
    {"dispatch", {"buffer:64", 2, 7, 3}, "21"},
    {"dispatch", {"buffer:64", 3, 7, 3}, "7"},
    {"dispatch", {"buffer:64", 4, 7, 3}, "0"},
    {"dispatch", {"buffer:64", -1, 7, 3}, "0"},
    {"compose", {0, 5, 2}, "9"},
    {"compose", {1, 5, 2}, "20"},
    {"installed", {"buffer:64", 3}, true},
    {"installed", {"buffer:64", 0}, false},
    {"chosen", {0, 6, 4}, "10"},
    {"chosen", {1, 6, 4}, "2"},
    {"chosen", {2, 6, 4}, "24"},
}

-- Arenas over pages the glue maps: 65472 bytes asked for is one 64 KiB mapping
-- on every page size up to 64 KiB, so the counts below hold on each.
local ARENAS = {
    {"listSum", {10}, "45"},
    {"listSum", {0}, "0"},
    {"listSum", {1000}, "499500"},
    {"usedAfter", {3, 100}, "308"},
    {"usedAfter", {0, 100}, "0"},
    {"fillFixed", {1000}, "65"},
    {"fillFixed", {65472}, "1"},
    {"fillFixed", {65473}, "0"},
    {"fillGrowable", {1000, 200}, "200"},
    {"fillGrowable", {65472, 3}, "3"},
    {"resetReuses", {}, true},
    {"poolReuses", {}, true},
    {"nested", {5}, "50"},
    {"nested", {0}, "0"},
}

-- Thirty-two bit arithmetic wraps; narrow fields load as the width they hold
-- and a store narrows a wider source: 300 in a byte is 44.
local FIXED = {
    {"wrapAdd", {4294967295, 1}, "0"},
    {"wrapAdd", {4000000000, 500000000}, "205032704"},
    {"wrapMul", {65536, 65536}, "0"},
    {"wrapMul", {123456789, 1000}, "3197704712"},
    {"signedWrap", {2147483647, 1}, "-2147483648"},
    {"signedWrap", {-2147483648, -1}, "2147483647"},
    {"signedDifference", {-2147483648, 1}, "2147483647"},
    {"fnv", {0}, "2615243109"},
    {"fnv", {1}, "1048580676"},
    {"fnv", {"72623859790382856"}, "3011442293"},
    {"fnv", {"18446744073709551615"}, "1823345245"},
    {"rotateLeft", {2147483649, 1}, "3"},
    {"rotateLeft", {305419896, 8}, "878082066"},
    {"rotateLeft", {1, 0}, "1"},
    {"shiftRight", {-8, 1}, "2147483644"},
    {"arithmeticShift", {-8, 1}, "-4"},
    {"shiftRight", {1, 33}, "0"},
    {"complement", {0}, "4294967295"},
    {"complement", {252645135}, "4042322160"},
    {"below", {1, 4294967295}, true},
    {"signedBelow", {1, -1}, false},
    {"signedBelow", {-1, 1}, true},
    {"widen", {-5}, -5.0},
    {"widenUnsigned", {4294967295}, 8589934590.0},
    {"brightness", {"buffer:16", 10, 20, 30}, "60"},
    {"brightness", {"buffer:16", 300, 0, 0}, "44"},
    {"signedSum", {"buffer:16", -3, 1000}, "997"},
    {"signedSum", {"buffer:16", 200, 70000}, "4408"},
    {"halfWord", {"buffer:16", 65535}, "65535"},
    {"halfWord", {"buffer:16", 65536}, "0"},
}

-- Struct values and aggregates: ((1+10dt)+(2+20dt)+(3+30dt)) + 2 at dt = 0.5 is 38;
-- the mesh is a 3-4-5 triangle plus the fourth corner, squared edges 9+16+9+16.
local AGGREGATES = {
    {"lengthSquared", {1.0, 2.0, 3.0}, 14.0},
    {"partial", {2.5}, 2.5},
    {"step", {"buffer:64", 0.5}, 38.0},
    {"step", {"buffer:64", 0.0}, 8.0},
    {"perimeter", {"buffer:128"}, 50.0},
    {"sumWords", {"buffer:80", 10}, "135"},
    {"sumWords", {"buffer:80", 0}, "0"},
    {"checksum", {"buffer:64", 10}, "378"},
    {"filled", {"buffer:64", 16, 300}, "704"},
}

-- Atomic words: 10 + rounds; the CAS loop counts up; a swap that misses leaves 5.
local ATOMICS = {
    {"counter", {"buffer:16", 100}, "110"},
    {"increment", {"buffer:16", 40, 5}, "45"},
    {"swapMiss", {"buffer:16"}, "505"},
    {"exchange", {"buffer:16", 3, 4}, "3004"},
    {"masks", {"buffer:16"}, "270"},
    {"flags", {"buffer:16"}, "1"},
    {"halves", {"buffer:16"}, "8589934593"},
}

local function check(clif, cases)
    for _, case in ipairs(cases) do
        local name, args, expected = case[1], case[2], case[3]
        local got = run(clif, name, args)
        local label = ("%s(%s)"):format(name, table.concat(args, ", "))
        if type(expected) == "boolean" then
            assert(got == tostring(expected), label .. ": expected " .. tostring(expected) .. ", got " .. got)
        elseif type(expected) == "number" then
            assert(tonumber(got) == expected, label .. ": expected " .. tostring(expected) .. ", got " .. got)
        else
            assert(got == expected, label .. ": expected " .. expected .. ", got " .. got)
        end
    end
end

function M.scalarFunctionsLowerAndRunAsPythonWouldCompute()
    check(compileFixture("scalars"), SCALARS)
end

function M.structFieldsLowerAtTheCompilersLayoutOffsets()
    check(compileFixture("structs"), STRUCTS)
end

function M.taggedUnionsOfStructPointersNarrowByTheirTagField()
    check(compileFixture("tagged"), TAGGED)
end

function M.functionPointersAreCalledStoredAndCompared()
    check(compileFixture("pointers"), POINTERS)
end

function M.fixedWidthArithmeticWrapsAndNarrowFieldsLoadAtTheirWidth()
    check(compileFixture("fixedwidth"), FIXED)
end

function M.structValuesArraysAndByteSpansLowerInPlace()
    local clif = compileFixture("aggregates", {"bytes"})
    check(clif, AGGREGATES)
    -- A checked access outside the span traps rather than reading.
    local status = capture(
        ("%s native jit %s %s %s %s"):format(quote(glueTool()), quote(clif), "outside", "buffer:64", 8)
    )
    assert(status ~= 0, "the checked access outside the span did not trap")
end

function M.atomicWordsAndHalvesLowerToAtomicInstructions()
    check(compileFixture("atomics"), ATOMICS)
end

function M.logicalSlotsKeepWindowsKindsAndBitsDistinct()
    check(compileFixture("slots"), {
        {"classes", {"buffer:512", 0}, true},
        {"classes", {"buffer:512", 8}, true},
        {"integerBits", {"buffer:128", 3, "9223372036854775808"}, true},
        {"integerBits", {"buffer:128", 1, "18446744073709551615"}, true},
        {"floatBits", {"buffer:128", 4, "9223372036854775808"}, true},
        {"floatBits", {"buffer:128", 2, "9221120237041090561"}, true},
    })
end

function M.varargSlotsDecodePackedCountsAndPreserveUnsignedValueWords()
    check(compileFixture("slots"), {
        {"varargWords", {"buffer:262144", 1, 0, "18446744073709551615"}, true},
        {"varargWords", {"buffer:262144", 16385, 0, "9223372036854775808"}, true},
        {"varargWords", {"buffer:262144", 16385, 16384, "18446744073709551615"}, true},
        {"varargWords", {"buffer:524288", 32767, 32766, "9221120237041090561"}, true}
    })
end

function M.logicalSlotsRequireClassifiedConsistentContracts()
    local function declaration(class, kind, write)
        return {
            annotations = {
                {
                    name = "vmSlotAccess",
                    arguments = {
                        {name = "class", kind = "value", value = class},
                        {name = "kind", kind = "value", value = kind},
                        {name = "write", kind = "value", value = write},
                    }
                }
            }
        }
    end

    for _, fields in ipairs({
        {"v", "number", false},
        {"f", "uint64", true},
        {"i", "int64", "false"},
        {"x", "uint64", false},
        {"vararg", "uint64", true},
        {"vararg", "int64", false}
    }) do
        assert(not pcall(slotcontract.read, declaration(unpack(fields)), "invalid"))
    end
    assert(not pcall(slotcontract.read, {}, "unclassified"))
    local access = slotcontract.read(declaration("i", "int64", false), "signed")
    assert(access.class == "i" and access.kind == "int64" and not access.write and access.width == 8)
    access = slotcontract.read(declaration("vararg", "uint64", false), "argument")
    assert(access.class == "vararg" and access.kind == "uint64" and not access.write and access.width == 8)
end

function M.programLoadsDecodeFrozenCodeAtDeclaredWidths()
    check(compileFixture("programloads"), {
        {"decode", {"buffer:16", 255, -2147483648, "18446744073709551615"}, true},
        {"decode", {"buffer:16", 128, 2147483647, "9223372036854775808"}, true},
        {"decode", {"buffer:16", 0, -1, "9221120237041090561"}, true},
        {"bodyIdentity", {"buffer:16", "buffer:16"}, true},
    })
end

function M.programLoadsRequireCompleteBodyScopedContracts()
    local function declaration(source, kind, lifetime)
        return {
            annotations = {
                {
                    name = "vmProgramLoad",
                    arguments = {
                        {name = "source", kind = "value", value = source},
                        {name = "kind", kind = "value", value = kind},
                        {name = "lifetime", kind = "value", value = lifetime},
                    }
                }
            }
        }
    end

    for _, fields in ipairs({
        {"function-table", "uint64", "body"},
        {"constants", "uint64", "body"},
        {"code", "voidptr", "body"},
        {"code", "uint64", "process"},
        {"code", "uint64", false},
    }) do
        assert(not pcall(programcontract.read, declaration(unpack(fields)), "invalid"))
    end
    assert(not pcall(programcontract.read, {}, "unclassified"))
    local missing = declaration("code", "uint64", "body")
    table.remove(missing.annotations[1].arguments)
    assert(not pcall(programcontract.read, missing, "missing"))
    for _, corruption in ipairs({"unknown", "duplicate", "nonliteral", "duplicate-contract"}) do
        local invalid = declaration("code", "uint64", "body")
        local arguments = invalid.annotations[1].arguments
        if corruption == "unknown" then
            arguments[#arguments + 1] = {name = "pure", kind = "value", value = true}
        elseif corruption == "duplicate" then
            arguments[#arguments + 1] = arguments[1]
        elseif corruption == "nonliteral" then
            arguments[1].kind = "type"
        else
            invalid.annotations[2] = invalid.annotations[1]
        end
        assert(not pcall(programcontract.read, invalid, corruption))
    end
    for _, kind in ipairs({"uint8", "int32", "uint64", "int64", "float64"}) do
        local access = programcontract.read(declaration("code", kind, "body"), kind)
        assert(access.source == "code" and access.kind == kind and access.lifetime == "body")
    end
end

-- The managed-fields measurement: both designs run; the numbers are read from
-- the report, not asserted, since they are the machine's.
function M.theManagedFieldsMeasurementRuns()
    local clif = compileFixture("managed")
    for _, case in ipairs({
        {"heapStores", {"buffer:200000", 100000, "true"}},
        {"heapStores", {"buffer:200000", 100000, "false"}},
        {"rootedStores", {"buffer:200000", 100000}},
        {"traceHeap", {"buffer:200000", 100}},
        {"walkRoots", {"buffer:200000", 100}}
    }) do
        local nanos = tonumber(run(clif, case[1], case[2]))
        assert(nanos and nanos > 0, case[1] .. " answered no time")
    end
end

function M.arenasOverMappedPagesOpenForAnExtentAndClose()
    check(compileFixture("arenas", {"arena"}), ARENAS)
end

-- An arena's lifetime is the checker's: a borrow of it cannot leave the
-- `with`, and resetting it needs the sole live view.
local ARENA_PREFIX = 'module escapes\nconst arena = require("nupp.runtime.vm.arena")\n'

local function compileArenaUse(body)
    local dir = tempDirectory()
    local path = dir .. "/escapes.nupp"
    write(path, ARENA_PREFIX .. body .. "\n")
    return lower.compile(ROOT, {path, ROOT .. "/src/nupp/runtime/vm/arena.nupp"}, {include = {"src", dir}})
end

function M.theCheckerKeepsArenaBorrowsInsideTheirExtent()
    local escaping = pcall(
        compileArenaUse,
        table.concat(
            {
                "local function escape(): voidptr?",
                "    with a = arena.open(4096) do",
                "        return arena.alloc(a, 8, 8)",
                "    end",
                "end",
            },
            "\n"
        )
    )
    assert(not escaping, "a borrow of the arena left its with")
    local resetting = pcall(
        compileArenaUse,
        table.concat(
            {
                "local function reset(): int64",
                "    with a = arena.open(4096) do",
                "        local raw = arena.alloc(a, 8, 8)",
                "        arena.reset(a)",
                "        if raw == nil then return 0 end",
                "        return 1",
                "    end",
                "end",
            },
            "\n"
        )
    )
    assert(not resetting, "the arena was reset under a live borrow")
    assert(
        compileArenaUse(
            table.concat(
                {
                    "local function fine(): int64",
                    "    with a = arena.open(4096) do",
                    "        local raw = arena.alloc(a, 8, 8)",
                    "        if raw == nil then return 0 end",
                    "        return 1",
                    "    end",
                    "end",
                },
                "\n"
            )
        )
            :find("function %fine", 1, true),
        "the ordinary use compiles"
    )
end

-- Handler modules written against a temporary include root beside `src`, so
-- the intrinsics declaration resolves as it does for the runtime sources.
local PARAMS = "pc: voidptr, regs: voidptr, ints: voidptr, floats: voidptr, context: voidptr, frame: voidptr"
local PREFIX = 'module nupp.runtime.vm.negative\nconst native = require("nupp.runtime.vm.intrinsics")\n'
local SUFFIX = "\n"
local HELPER = ("local function leave(%s, extra: int64): uint64\nreturn native.fail()\nend\n"):format(PARAMS)
local RECURSIVE = (
    "local function again(%s, extra: int64): uint64\nreturn again(pc, regs, ints, floats, context, frame, extra)\nend\n"
):format(PARAMS)
local FALLING = ("local function fall(%s, extra: int64): uint64\nnative.store64(regs, 0, 1ULL)\nend\n"):format(PARAMS)

local layoutsPath = nil

local function layouts()
    if not layoutsPath then
        layoutsPath = tempDirectory() .. "/layouts.json"
        local status, output = capture(("%s native layouts %s"):format(quote(glueTool()), quote(layoutsPath)))
        assert(status == 0, "native layouts failed: " .. output)
    end

    return layoutsPath
end

local function handlerModule(body, preamble)
    local dir = tempDirectory()
    local path = dir .. "/nupp/runtime/vm/negative.nupp"
    write(
        path,
        PREFIX .. (preamble or "") .. ("export function IAdd(%s): uint64\n%s\nend\n"):format(PARAMS, body) .. SUFFIX
    )

    return dir, path
end

local function compileHandlers(body, preamble)
    local dir, path = handlerModule(body, preamble)
    return lower.compile(ROOT, {path}, {handlers = true, layouts = layouts(), include = {"src", dir}})
end

function M.unclassifiedLogicalSlotsAreRefused()
    local module = "nupp.runtime.vm.unclassifiedslots"
    local dir, path = handlerModule(
        "slots.writeValue(frame, regs, 0, 1ULL)\n" .. "return native.dispatch(pc, regs, ints, floats, context, frame)",
        'const slots = require("' .. module .. '")\n'
    )
    write(
        dir .. "/nupp/runtime/vm/unclassifiedslots.d.nupp",
        "local record Slots\n"
        .. "writeValue: function(frame: voidptr, window: voidptr, slot: int64, value: uint64): nil\n"
        .. "end\nreturn Slots\n"
    )
    local original = lower.SLOTS
    lower.SLOTS = module
    local ok, problem = pcall(lower.compile, ROOT, {path}, {
        handlers = true,
        layouts = layouts(),
        include = {dir, "src"},
    })
    lower.SLOTS = original
    assert(not ok and tostring(problem):find("has no declared contract", 1, true), tostring(problem))
end

function M.unclassifiedNativeHelpersAreRefused()
    local module = "nupp.runtime.vm.unclassified"
    local dir, path = handlerModule(
        "local value = helpers.getField(context, 1ULL, 2ULL)\n"
        .. "return native.dispatch(pc, regs, ints, floats, context, frame)",
        'const helpers = require("' .. module .. '")\n'
    )
    write(
        dir .. "/nupp/runtime/vm/unclassified.d.nupp",
        "local record Helpers\n"
        .. "getField: function(context: voidptr, object: uint64, name: uint64): uint64\n"
        .. "end\nreturn Helpers\n"
    )
    lower.HELPER_MODULES[module] = "nupp_rt_"
    local ok, problem = pcall(lower.compile, ROOT, {path}, {
        handlers = true,
        layouts = layouts(),
        include = {dir, "src"},
    })
    lower.HELPER_MODULES[module] = nil
    assert(not ok and tostring(problem):find("has no declared effects", 1, true), tostring(problem))
end

function M.helperEffectsRequireCompleteAndConsistentSummaries()
    local function declaration(flags)
        local arguments = {}
        for name, value in pairs(flags) do
            arguments[#arguments + 1] = {name = name, kind = "value", value = value}
        end

        return {annotations = {{name = "vmHelperEffects", arguments = arguments}}}
    end

    local mutation = helpercontract.read(
        declaration({
            mayCollect = false,
            mayPark = false,
            mayRaise = false,
            pure = false,
        }),
        "mutation"
    )
    assert(not mutation.mayCollect and not mutation.pure)
    for _, effect in ipairs({"mayCollect", "mayPark", "mayRaise"}) do
        local flags = {mayCollect = false, mayPark = false, mayRaise = false, pure = true}
        flags[effect] = true
        local ok, problem = pcall(helpercontract.read, declaration(flags), "contradictory")
        assert(not ok and tostring(problem):find("is pure but may collect, park or raise", 1, true), tostring(problem))
    end
    for _, flags in ipairs({
        {mayCollect = false, mayPark = false, mayRaise = false},
        {mayCollect = false, mayPark = "false", mayRaise = false, pure = false},
        {mayCollect = false, mayPark = false, mayRaise = false, pure = false, hidden = false},
    }) do
        local ok = pcall(helpercontract.read, declaration(flags), "invalid")
        assert(not ok, "accepted an incomplete or malformed helper summary")
    end
end

local REJECTED = {
    {"retired-escape", "return native.slow(pc, regs, ints, floats, context, frame)", "slow"},
    {"allocation", "local x = {}\nreturn native.load64(regs, 0)", "unsupported expression"},
    {"pointer-return", "return pc", "NUPP"},
    {"fallthrough", "native.store64(regs, 0, native.load64(regs, 8))", "NUPP2002"},
    {"ordinary-call", 'print("no native fallback")\nreturn native.load64(regs, 0)', "only direct calls"},
    {
        "bad-layout",
        'local x = native.layout("unknown")\nreturn native.dispatch(native.offset(pc, x), regs, ints, floats, context, frame)',
        "unknown context field"
    },
    {"transfer-as-value", "return native.reenter() + 1", "is a transfer"},
    {
        "transfer-helper-as-value",
        "local x = leave(pc, regs, ints, floats, context, frame, 1)\nreturn x",
        "is a transfer",
        HELPER
    },
    {"recursive-helper", "return again(pc, regs, ints, floats, context, frame, 1)", "recursive helper", RECURSIVE},
    {"helper-fallthrough", "return fall(pc, regs, ints, floats, context, frame, 1)", "NUPP2002", FALLING},
    {
        "changed-representation",
        "local x: int64 = native.load8(pc, 1)\nx = native.load64(regs, 0)\nreturn native.dispatch(pc, regs, ints, floats, context, frame)",
        "NUPP"
    },
}

function M.theLoweringRefusesWhatIsNotNativeCode()
    for _, case in ipairs(REJECTED) do
        local name, body, expected, preamble = case[1], case[2], case[3], case[4]
        local ok, problem = pcall(compileHandlers, body, preamble)
        assert(not ok, name .. ": the lowering accepted it")
        assert(tostring(problem):find(expected), name .. ": expected " .. expected .. ", got " .. tostring(problem))
    end
end

function M.aHandlerModuleWithoutHandlersIsRefused()
    local dir = tempDirectory()
    local path = dir .. "/nupp/runtime/vm/negative.nupp"
    write(path, PREFIX .. "local function helper(x: int64): int64\nreturn x\nend\n" .. SUFFIX)
    local ok, problem = pcall(lower.compile, ROOT, {path}, {
        handlers = true,
        layouts = layouts(),
        include = {"src", dir}
    })
    assert(not ok and tostring(problem):find("no functions"), tostring(problem))
end

-- A function of the runtime's CLIF by name.
local function functionText(clif, name)
    for text in clif:gmatch("function %%[^\n]*%b{}") do
        if text:find("function %" .. name .. "(", 1, true) then
            return text .. "\n"
        end
    end
    error("no function " .. name)
end

local runtimeClif = nil

local function coreClif()
    if not runtimeClif then
        runtimeClif = lower.compileRuntime(ROOT, layouts())
    end
    return runtimeClif
end

local function rejectsObject(name, text, expected)
    local dir = tempDirectory()
    write(dir .. "/bad.clif", text)
    local status, output = capture(
        ("%s native object %s %s"):format(quote(glueTool()), quote(dir .. "/bad.clif"), quote(dir .. "/bad.o"))
    )
    assert(status ~= 0, name .. ": the glue accepted it")
    assert(output:find(expected, 1, true), name .. ": expected " .. expected .. ", got " .. output)
end

function M.theGlueChecksTheHandlerContractOnTheParsedFunction()
    local iadd = functionText(coreClif(), "IAdd")
    assert(iadd:find("return_call_indirect sig0, ", 1, true), "IAdd dispatches through the table")
    rejectsObject(
        "call",
        iadd:gsub("    return_call_indirect sig0, ", "    v99 = call_indirect sig0, ", 1)
            :gsub("%)\n}", ")\n    return v99\n}"),
        "only dispatch or leave"
    )
    local changedContext, replaced = iadd:gsub("(return_call_indirect sig0, [^\n]*, )(v%d+)(, v%d+%)\n)", "%1v1%3", 1)
    assert(replaced == 1, "the context mutation must change the dispatch")
    rejectsObject("changed-context", changedContext, "dispatch must preserve the context")
    rejectsObject(
        "signature",
        (iadd:gsub("%) %-> i64 tail {", ") -> i64 apple_aarch64 {", 1)),
        "handler signature required"
    )
    rejectsObject(
        "symbol",
        (iadd:gsub("    sig0 =", "    gv0 = symbol colocated %%native_runtime_table\n    sig0 =", 1)),
        "reference no symbols"
    )
    rejectsObject("syntax", (iadd:gsub("uload8.i64", "uload8.i65", 1)), "expected")
end

function M.wholeCoreHandlersUseTheNuppGraph()
    local clif = coreClif()
    for _, name in ipairs({
        "GetCell",
        "GetUpval",
        "Lt",
        "Le",
        "Len",
        "LenF",
        "Jmp",
        "JmpIfIZero",
        "JmpIf",
        "JmpIfNot",
        "K",
        "Move",
        "Nil",
        "Not",
        "Truthy",
        "BoolFromI",
        "IK",
        "IMov",
        "IAddK",
        "IMaskU32",
        "IAdd",
        "ISub",
        "IAnd",
        "IOr",
        "IXor",
        "INot",
        "IBswap32",
        "IShl",
        "IShrU",
        "ICmpEq",
        "ICmpNe",
        "ICmpLt",
        "ICmpLe",
        "ICmpSLt",
        "ICmpSLe",
        "FAdd",
        "FSub",
        "FMul",
        "FDiv",
        "FMod",
        "FK",
        "FMov",
        "FNeg",
        "IToF",
        "FToI",
        "FCmpEq",
        "FCmpNe",
        "FCmpLt",
        "FCmpLe",
        "FBox"
    }) do
        local text = functionText(clif, name)
        assert(text:find("Nupp native graph: " .. name, 1, true), name .. " bypassed the Nupp graph")
        assert(text:find("return_call_indirect sig0, ", 1, true), name .. " lost its dispatch")
        assert(not text:find("call %", 1, true), name .. " introduced a helper boundary")
    end
end

function M.wholeBoxingHandlersUseTheNuppGraph()
    local clif = coreClif()
    for _, name in ipairs({"TagCheckNum", "StrByte", "NewRecord"}) do
        local text = functionText(clif, name)
        assert(text:find("Nupp native graph: " .. name, 1, true), name .. " bypassed the Nupp graph")
        assert(text:find("return_call_indirect sig0, ", 1, true), name .. " lost its dispatch")
    end
end

function M.wholeModuleHandlersAndLoaderSupportUseTheNuppGraph()
    local clif = coreClif()
    for _, name in ipairs({"Require", "RequireV", "SetMethod", "requireSlow"}) do
        local text = functionText(clif, name)
        assert(text:find("Nupp native graph: " .. name, 1, true), name .. " bypassed the Nupp graph")
    end
    local slow = functionText(clif, "requireSlow")
    assert(slow:find("function %requireSlow(i64, i64, i64, i64, i64) -> i64 tail", 1, true))
    assert(slow:find("return_call_indirect sig0, ", 1, true))
end

function M.wholeStateHandlersUseTheNuppGraph()
    local clif = coreClif()
    for _, name in ipairs({"Disarm", "AffineMark", "AffineEnter", "Checkpoint", "Park", "VarargTable"}) do
        assert(
            functionText(clif, name):find("Nupp native graph: " .. name, 1, true),
            name .. " bypassed the Nupp graph"
        )
    end
end

function M.wholeControlHandlersUseTheNuppGraph()
    local clif = coreClif()
    for _, name in ipairs({
        "PCall",
        "Raise",
        "Defer",
        "DeferMethod",
        "CleanupLive",
        "DisarmAt",
        "RearmAt",
        "Unwind",
        "Switch"
    }) do
        local text = functionText(clif, name)
        assert(text:find("Nupp native graph: " .. name, 1, true), name .. " bypassed the Nupp graph")
    end
end

function M.theRuntimeCoreCompilesToOneObjectWithItsSidecar()
    local dir = tempDirectory()
    write(dir .. "/runtime.clif", coreClif())
    local status, output = capture(
        ("%s native object %s %s"):format(quote(glueTool()), quote(dir .. "/runtime.clif"), quote(dir .. "/runtime.o"))
    )
    assert(status == 0, "native object failed: " .. output)
    local sidecar = read(dir .. "/runtime.o.rs")
    -- The sidecar pins each handler's opcode number, which is how the glue's
    -- table and the handlers agree on who answers what.
    for _, name in ipairs({"IAdd", "CallK", "CallDyn", "Ret", "GetField", "NewRecord"}) do
        assert(sidecar:find("assert!(Code::" .. name .. " as u8 == ", 1, true), name .. " is not in the dispatch table")
    end
    assert(not sidecar:find("Code::Slow as u8", 1, true), "the retired Slow opcode must not be registered")
end

function M.floorKeepsExactIntegerMachineValues()
    local path = compileFixture("numericfloor")
    assert(run(path, "integerIdentity", {"9007199254740993"}) == "9007199254740993")
    assert(run(path, "integerIdentity", {"-9223372036854775808"}) == "-9223372036854775808")
    assert(run(path, "integerLiteral", {}) == "9007199254740993")
    assert(tonumber(run(path, "floating", {"-1.5"})) == -2)
    local clif = read(path)
    assert(not clif:find("fcvt_from_sint.f64", 1, true), "integer floor must retain all 64 bits")
    assert(clif:find("floor ", 1, true), "floating floor uses the machine operation")
    local dir = tempDirectory()
    local generic = dir .. "/generic.nupp"
    write(generic, "module generic\nlocal function floor(value: number): number return math.floor(value) end\n")
    local accepted = pcall(lower.compile, ROOT, {generic}, {include = {"src", dir}})
    assert(not accepted, "generic numeric values have no unboxed native ABI")
end

function M.floatConstantsNormalizeIntegerMinimumBeforeFormatting()
    local path = compileFixture("numericfloor")
    local clif = read(path)
    assert(clif:find("f64const -0x1.0000000000000p63", 1, true), "integer MIN must become exactly -2^63")
    assert(not clif:find("f64const -0xf.", 1, true), "negating integer MIN must not wrap during formatting")
    assert(tonumber(run(path, "minimumFloat", {})) == -9223372036854775808.0)
    assert(clif:find("f64const -0.0", 1, true), "normalizing a floating constant must preserve negative zero")
    assert(run(path, "negativeZero", {}) == "-0")
end

function M.integerFloatPromotionKeepsTheCheckedSignedness()
    local path = compileFixture("numericpromotions")
    assert(tonumber(run(path, "signed", {"-9223372036854775808"})) == -9223372036854775808.0)
    assert(tonumber(run(path, "unsigned", {"9223372036854775808"})) == 9223372036854775808.0)
    assert(tonumber(run(path, "unsigned", {"18446744073709551615"})) == 18446744073709551616.0)
end

return M
