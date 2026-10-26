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

local function compileFixture(name)
    local clif = lower.compile(ROOT, {FIXTURES .. "/" .. name .. ".nupp"}, {include = {"src", "tests/fixtures/native"}})
    local path = tempDirectory() .. "/" .. name .. ".clif"
    write(path, clif)
    return path
end

local function run(clif, name, args)
    local words = {}
    for index, arg in ipairs(args) do
        words[index] = quote(arg)
    end
    local status, output = capture(("%s native jit %s %s %s"):format(quote(glueTool()), quote(clif), quote(name), table.concat(words, " ")))
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
    {"fib", {0}, "0"}, {"fib", {1}, "1"}, {"fib", {20}, tostring(fib(20))},
    {"sum", {0}, "0"}, {"sum", {100}, "5050"},
    {"gcd", {48, 18}, "6"}, {"gcd", {17, 5}, "1"}, {"gcd", {"9223372036854775814", 9}, "1"},
    {"clamp", {0.5, 0.0, 1.0}, 0.5}, {"clamp", {-3.25, 0.0, 1.0}, 0.0}, {"clamp", {7.0, 0.0, 1.0}, 1.0},
    {"triangle", {10}, "55"}, {"triangle", {0}, "0"},
    {"countdown", {5}, "5"}, {"countdown", {0}, "0"},
    {"collatz", {27}, tostring(collatz(27))}, {"collatz", {1}, "0"},
    {"firstSquareAbove", {50}, "8"}, {"firstSquareAbove", {0}, "1"},
    {"findBreak", {100.0}, findBreak(100) + 0.0}, {"findBreak", {1e12}, -1.0},
    {"both", {"true", "true"}, true}, {"both", {"true", "false"}, false},
    {"either", {"false", "false"}, false}, {"either", {"false", "true"}, true},
    {"neither", {"false", "false"}, true}, {"neither", {"true", "false"}, false},
    {"floorMod", {7, 3}, "1"}, {"floorMod", {-7, 3}, "2"}, {"floorMod", {7, -3}, "-2"},
    {"floorMod", {-7, -3}, "-1"}, {"floorMod", {6, 3}, "0"}, {"floorMod", {-6, 3}, "0"},
    {"floorDiv", {7, 3}, "2"}, {"floorDiv", {-7, 3}, "-3"}, {"floorDiv", {7, -3}, "-3"},
    {"floorDiv", {-7, -3}, "2"}, {"floorDiv", {-6, 3}, "-2"},
    -- (((a & b) | (a ^ b)) << 1 & mask) >> 1 is a | b with the top bit cleared.
    {"bits", {12, 10}, "14"}, {"bits", {"9223372036854775808", 1}, "1"},
    {"mean", {1.0, 2.0}, 1.5}, {"mean", {-1.0, 0.0}, -0.5},
    {"scaled", {2.0}, 2.75}, {"scaled", {0.0}, -0.25},
    {"negate", {5}, "-5"}, {"negate", {"-9223372036854775808"}, "-9223372036854775808"},
    {"compound", {1}, "18"}, {"compound", {-5}, "6"},
    {"nestedLoops", {10}, tostring(nested(10))}, {"nestedLoops", {0}, "0"},
}

local STRUCTS = {
    {"total", {"buffer:320", 10}, "450"}, {"total", {"buffer:32", 0}, "0"},
    {"weight", {"buffer:320", 10}, 2.5}, {"weight", {"buffer:320", 3}, 1.0},
    {"counts", {"buffer:320", 10}, "70"},
    {"words", {"buffer:64", 8}, "24"},
}

-- (a + b) * (c + d) over seven nodes written into the buffer; `chain` links
-- cells holding every other leaf and sums what they hold.
local TAGGED = {
    {"evaluate", {"buffer:512", 1, 2, 3, 4}, "21"}, {"evaluate", {"buffer:512", -5, 5, 7, 0}, "0"},
    {"evaluate", {"buffer:512", 10, 20, 3, 4}, "210"},
    {"leaves", {"buffer:512", 1, 2, 3, 4}, "4"}, {"sums", {"buffer:512", 1, 2, 3, 4}, "2"},
    {"tagOf", {"buffer:512", 0}, "3"}, {"tagOf", {"buffer:512", 1}, "2"}, {"tagOf", {"buffer:512", 2}, "2"},
    {"chain", {"buffer:512", 6}, "60"}, {"chain", {"buffer:512", 1}, "0"}, {"chain", {"buffer:512", 0}, "0"},
}

-- Operations dispatched through a table of function pointers in the buffer.
local POINTERS = {
    {"dispatch", {"buffer:64", 0, 7, 3}, "10"}, {"dispatch", {"buffer:64", 1, 7, 3}, "4"},
    {"dispatch", {"buffer:64", 2, 7, 3}, "21"}, {"dispatch", {"buffer:64", 3, 7, 3}, "7"},
    {"dispatch", {"buffer:64", 4, 7, 3}, "0"}, {"dispatch", {"buffer:64", -1, 7, 3}, "0"},
    {"compose", {0, 5, 2}, "9"}, {"compose", {1, 5, 2}, "20"},
    {"installed", {"buffer:64", 3}, true}, {"installed", {"buffer:64", 0}, false},
    {"chosen", {0, 6, 4}, "10"}, {"chosen", {1, 6, 4}, "2"}, {"chosen", {2, 6, 4}, "24"},
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

-- Handler modules written against a temporary include root beside `src`, so
-- the intrinsics declaration resolves as it does for the runtime sources.
local PARAMS = "pc: voidptr, regs: voidptr, ints: voidptr, floats: voidptr, context: voidptr, frame: voidptr"
local PREFIX = 'module nupp.runtime.vm.negative\nconst native = require("nupp.runtime.vm.intrinsics")\n'
local SUFFIX = "\n"
local HELPER = ("local function leave(%s, extra: int64): uint64\nreturn native.slow(pc, regs, ints, floats, context, frame)\nend\n"):format(PARAMS)
local RECURSIVE = ("local function again(%s, extra: int64): uint64\nreturn again(pc, regs, ints, floats, context, frame, extra)\nend\n"):format(PARAMS)
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
    write(path, PREFIX .. (preamble or "") .. ("export function IAdd(%s): uint64\n%s\nend\n"):format(PARAMS, body) .. SUFFIX)
    return dir, path
end

local function compileHandlers(body, preamble)
    local dir, path = handlerModule(body, preamble)
    return lower.compile(ROOT, {path}, {handlers = true, layouts = layouts(), include = {"src", dir}})
end

local REJECTED = {
    {"allocation", "local x = {}\nreturn native.load64(regs, 0)", "unsupported expression"},
    {"pointer-return", "return pc", "NUPP"},
    {"fallthrough", "native.store64(regs, 0, native.load64(regs, 8))", "NUPP2002"},
    {"ordinary-call", 'print("no native fallback")\nreturn native.load64(regs, 0)', "only direct calls"},
    {"bad-layout", 'local x = native.layout("unknown")\nreturn native.dispatch(native.offset(pc, x), regs, ints, floats, context, frame)', "unknown context field"},
    {"transfer-as-value", "return native.reenter() + 1", "is a transfer"},
    {"helper-as-value", "local x = leave(pc, regs, ints, floats, context, frame, 1)\nreturn x", "tail%-called", HELPER},
    {"recursive-helper", "return again(pc, regs, ints, floats, context, frame, 1)", "recursive helper", RECURSIVE},
    {"helper-fallthrough", "return fall(pc, regs, ints, floats, context, frame, 1)", "NUPP2002", FALLING},
    {"changed-representation", "local x: int64 = native.load8(pc, 1)\nx = native.load64(regs, 0)\nreturn native.dispatch(pc, regs, ints, floats, context, frame)", "NUPP"},
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
    local ok, problem = pcall(lower.compile, ROOT, {path}, {handlers = true, layouts = layouts(), include = {"src", dir}})
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
    local status, output = capture(("%s native object %s %s"):format(quote(glueTool()), quote(dir .. "/bad.clif"), quote(dir .. "/bad.o")))
    assert(status ~= 0, name .. ": the glue accepted it")
    assert(output:find(expected, 1, true), name .. ": expected " .. expected .. ", got " .. output)
end

function M.theGlueChecksTheHandlerContractOnTheParsedFunction()
    local iadd = functionText(coreClif(), "IAdd")
    assert(iadd:find("return_call_indirect sig0, ", 1, true), "IAdd dispatches through the table")
    rejectsObject("call", iadd:gsub("    return_call_indirect sig0, ", "    v99 = call_indirect sig0, ", 1):gsub("%)\n}", ")\n    return v99\n}"),
        "only dispatch or leave")
    rejectsObject("changed-context", (iadd:gsub(", v4, v5%)", ", v1, v5)")), "dispatch must preserve the context")
    rejectsObject("signature", (iadd:gsub("%) %-> i64 tail {", ") -> i64 apple_aarch64 {", 1)), "handler signature required")
    rejectsObject("symbol", (iadd:gsub("    sig0 =", "    gv0 = symbol colocated %%native_runtime_table\n    sig0 =", 1)), "reference no symbols")
    rejectsObject("syntax", (iadd:gsub("uload8.i64", "uload8.i65", 1)), "expected")
end

function M.theRuntimeCoreCompilesToOneObjectWithItsSidecar()
    local dir = tempDirectory()
    write(dir .. "/runtime.clif", coreClif())
    local status, output = capture(("%s native object %s %s"):format(quote(glueTool()), quote(dir .. "/runtime.clif"), quote(dir .. "/runtime.o")))
    assert(status == 0, "native object failed: " .. output)
    local sidecar = read(dir .. "/runtime.o.rs")
    for _, name in ipairs({"IAdd", "CallK", "CallDyn", "Ret", "GetField", "NewRecord"}) do
        assert(sidecar:find("table[Code::" .. name .. " as usize] = native_segment", 1, true), name .. " is not in the dispatch table")
    end
    assert(not sidecar:find("Code::Slow as usize] = native_segment", 1, true), "Slow stays Rust by definition")
end

return M
