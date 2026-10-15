local testAssert = require("nupp.test")
local assertions = require("helpers.assertions")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")
local windows = package.config:sub(1, 1) == "\\"
local darwin = (require("nupp.compiler.targetlayout").hostKey() or ""):find("apple-darwin", 1, true) ~= nil
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

-- One environment for the whole suite.
--
-- Every case checks against an environment built exactly this way, and
-- building one means checking the prelude from source. Per case that was
-- most of what this suite cost; the cases share it the way the other
-- checker suites do.
local sharedEnv = envMod.new(HERE .. "/..")

local function compile(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors" .. (result.errors[1] and (": " .. result.errors[1].msg) or ""))
    local diags = check.check(result, "test.nupp", sharedEnv)

    return result, diags
end

local function diagsOf(src)
    local _, diags = compile(src)
    local out = {}
    for j, d in ipairs(diags) do
        out[j] = d.code .. ":" .. d.line
    end

    return table.concat(out, " "), diags
end

local assertClean = assertions.check(diagsOf, function(src) return "expected clean check:\n" .. src end)

local function run(src)
    local result, diags = compile(src)
    local messages = {}
    for _, diagnostic in ipairs(diags) do
        messages[#messages + 1] = diagnostic.code .. ":" .. diagnostic.line .. ": " .. diagnostic.msg
    end
    testAssert.equal(
        #diags,
        0,
        "check diagnostics" .. (
            #messages > 0 and (":\n" .. table.concat(messages, "\n") .. "\n--- source ---\n" .. src) or ""
        )
    )

    return program.run(result, "cdeftest")
end

local M = {}

function M.cdefFunctionTyping()
    assertClean("cdef function strlen(s: cstring): uint64\nstrlen('hi')")
    testAssert.equal((diagsOf("cdef function strlen(s: cstring): uint64\nstrlen(42)")), "NUPP2006:2")
    testAssert.equal((diagsOf("cdef function strlen(s: cstring): uint64\nstrlen('a', 'b')")), "NUPP2007:2")
    -- non-C types are rejected in signatures
    testAssert.equal((diagsOf("cdef function bad(t: {number}): int32")), "NUPP2203:1")
    testAssert.equal((diagsOf("cdef function bad2(): {[string]: number}")), "NUPP2203:1")
end

function M.countedPointerCallsCheckAgainstSpans()
    local source = table.concat(
        {
            "local spans = require('nupp.mem.span')",
            "cdef struct CountedPosition",
            "   x: float",
            "end",
            "cdef struct CountedVelocity",
            "   x: float",
            "end",
            "local count = 'not the parameter'",
            "cdef function counted_integrate(",
            "   borrows positions: CountedPosition* countedBy(count),",
            "   borrows velocities: const CountedVelocity* countedBy(count),",
            "   count: uint64, dt: float",
            ")",
            "local p = ffi.new<CountedPosition[4]>()",
            "local v = ffi.new<CountedVelocity[4]>()",
            "local writable = spans.writeCarray(p, 4)",
            "local readable = spans.fromCarray(v, 4)",
            "counted_integrate(writable, readable, 0.5 as float)",
            "nupp.drop(writable)",
        },
        "\n"
    )
    assertClean(source)
end

function M.countedPointersExecuteBoundsOffsetsCountsAndSharedDowngrades()
    if windows then
        return
    end
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local suffix = darwin and ".dylib" or ".so"
    local library = dir .. "/libcounted_pointer" .. suffix
    local shared = darwin and "-dynamiclib" or "-shared"
    local fixture = HERE .. "/fixtures/counted_pointer.c"
    local built = os.execute(
        ("clang -std=c11 -O2 -Wall -Wextra -Werror -fPIC %s '%s' -o '%s'"):format(shared, fixture, library)
    )
    testAssert.equal(built, 0, "build counted-pointer fixture")

    local declaration = table.concat(
        {
            "cdef function counted_pointer_reset() from\"" .. library .. "\"",
            "cdef function counted_pointer_call_count(): uint64 from\"" .. library .. "\"",
            "cdef function counted_pointer_transform(",
            "   borrows output: int32* countedBy(count),",
            "   borrows input: const int32* countedBy(count),",
            "   count: uint64",
            ") from\"" .. library .. "\"",
            "cdef function counted_pointer_independent(",
            "   borrows output: int32* countedBy(outputCount), outputCount: uint64,",
            "   borrows input: const int32* countedBy(inputCount), inputCount: uint64",
            ") from\"" .. library .. "\"",
        },
        "\n"
    )
    local source = declaration .. "\n" .. table.concat(
        {
            "local array = require('nupp.mem.array')",
            "local input = array.scalar(array.int32, 6)",
            "local output = array.scalar(array.int32, 6)",
            "do",
            "   local values = input:write()",
            "   for i = 1, 6 do values[i] = i as int32 end",
            "   nupp.drop(values)",
            "end",
            "counted_pointer_reset()",
            "do",
            "   local writer = output:write()",
            "   do",
            "      local parts = writer:splitAt(1)",
            "      local readable = input:read():slice(2, 6)",
            "      counted_pointer_transform(parts.right, readable)",
            "   end",
            "   nupp.drop(writer)",
            "end",
            "local offsetFirst: int32, offsetLast: int32",
            "do",
            "   local transformed = output:read()",
            "   offsetFirst, offsetLast = transformed[2], transformed[6]",
            "end",
            "local transformCalls = counted_pointer_call_count()",
            "counted_pointer_reset()",
            "do",
            "   local writer = output:write()",
            "   do",
            "      local emptyOutput = writer:slice(1, 0)",
            "      local emptyInput = input:read():slice(1, 0)",
            "      counted_pointer_transform(emptyOutput, emptyInput)",
            "      nupp.drop(emptyOutput)",
            "   end",
            "   nupp.drop(writer)",
            "end",
            "local zeroCalls = counted_pointer_call_count()",
            "counted_pointer_reset()",
            "do",
            "   local writer = output:write()",
            "   do",
            "      local independentOutput = writer:slice(1, 3)",
            "      local independentInput = input:read():slice(1, 5)",
            "      counted_pointer_independent(independentOutput, independentInput)",
            "      nupp.drop(independentOutput)",
            "   end",
            "   nupp.drop(writer)",
            "end",
            "local outputCount: int32, inputCount: int32, inputFirst: int32",
            "do",
            "   local independent = output:read()",
            "   outputCount, inputCount, inputFirst = independent[1], independent[2], independent[3]",
            "end",
            "local sharedStorage = array.scalar(array.int32, 2)",
            "local sharedOutput = array.scalar(array.int32, 2)",
            "do",
            "   local sourceWriter = sharedStorage:write()",
            "   sourceWriter[1], sourceWriter[2] = 7 as int32, 8 as int32",
            "   local destinationWriter = sharedOutput:write()",
            "   do",
            "      local sourceReader = sourceWriter:shared()",
            "      counted_pointer_transform(destinationWriter, sourceReader)",
            "   end",
            "   nupp.drop(destinationWriter)",
            "   nupp.drop(sourceWriter)",
            "end",
            "local sharedRead = sharedOutput:read()",
            "local unequalOutput = array.scalar(array.int32, 1)",
            "local unequalInput = array.scalar(array.int32, 2)",
            "counted_pointer_reset()",
            "local unequalOk: boolean",
            "do",
            "   local shortOutput = unequalOutput:write()",
            "   local longInput = unequalInput:read()",
            "   unequalOk = pcall(counted_pointer_transform, shortOutput, longInput)",
            "   nupp.drop(shortOutput)",
            "end",
            "local unequalCalls = counted_pointer_call_count()",
            "return offsetFirst, offsetLast, transformCalls, zeroCalls,",
            "   outputCount, inputCount, inputFirst, sharedRead[1], sharedRead[2], unequalOk, unequalCalls",
        },
        "\n"
    )

    local ok, a, b, calls, zeroCalls, outputCount, inputCount, inputFirst, sharedFirst, sharedLast, unequalOk, unequalCalls =
        pcall(run, source)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(a, 0)
    end
    testAssert.equal(tonumber(a), 12, "sliced input starts at its adjusted pointer")
    testAssert.equal(tonumber(b), 16, "partitioned output reaches its adjusted last element")
    testAssert.equal(tonumber(calls), 1, "ordinary counted call reaches C once")
    testAssert.equal(tonumber(zeroCalls), 1, "zero-count call reaches C exactly once")
    testAssert.equal(tonumber(outputCount), 3, "first independent count reaches C")
    testAssert.equal(tonumber(inputCount), 5, "second independent count reaches C")
    testAssert.equal(tonumber(inputFirst), 1, "independent read pointer reaches C")
    testAssert.equal(tonumber(sharedFirst), 17, "a shared downgrade is accepted as const input")
    testAssert.equal(tonumber(sharedLast), 18, "shared downgrade preserves its full range")
    testAssert.equal(unequalOk, false, "unequal shared counts raise before C")
    testAssert.equal(tonumber(unequalCalls), 0, "unequal shared counts never enter C")
end

function M.countedPointersRejectContractsTheyCannotLowerSafely()
    local function one(declaration)
        local got = diagsOf(declaration)
        assert(got:find("NUPP2630", 1, true), got .. "\n" .. declaration)
    end

    one("cdef function bad(borrows values: int32 countedBy(count), count: uint64)")
    one("cdef function bad(borrows values: const int32* countedBy(missing), count: uint64)")
    one("cdef function bad(values: const int32* countedBy(count), count: uint64)")
    one("cdef function bad(borrows values: const int32* countedBy(count), count: uint32)")
    one("cdef function bad(borrows values: const int32* countedBy(count), exclusive count: uint64)")
    one("cdef function bad(borrows values: const int32* countedBy(count), count: uint64, ...)")
    one("cdef function bad(out values: int32** countedBy(count), count: uint64)")
end

function M.spanAbiAnnotationWasRemoved()
    local got = diagsOf(
        "@spanabi(read = { values = 'count' })\n" .. "cdef function old(borrows values: const int32*, count: uint64)"
    )
    assert(got:find("NUPP2111", 1, true), got)
end

function M.cdefCallbackParameter()
    assertClean("cdef function each(fn: function(int32), n: int32)")
end

function M.nullableCallbacksWorkInEveryCDeclaratorPosition()
    local source = table.concat(
        {
            "cdef struct callback_holder",
            "   callback: function(int32)?",
            "end",
            "cdef function callback_get(): function(int32)?",
            "cdef function callback_set(callback: function(int32)?)",
        },
        "\n"
    )
    assertClean(source)
end

function M.fixedArrayFieldsKeepTheirCDeclaratorOrder()
    local source = table.concat(
        {"cdef struct array_holder", "   values: int32[4]", "   callbacks: function(int32)?[2]", "end",},
        "\n"
    )
    assertClean(source)
end

function M.cdefStructTyping()
    assertClean(
        table.concat(
            {
                "cdef struct timeval",
                "   tv_sec: int64",
                "   tv_usec: int64",
                "end",
                "local tv = new timeval()",
                "local s: int64 = tv.tv_sec",
                "local n: number = tonumber(tv.tv_sec) or 0",
            },
            "\n"
        )
    )
    -- the field loads a boxed int64, which is not a Lua number
    testAssert.equal(
        (
            diagsOf(
                table.concat(
                    {
                        "cdef struct timeval",
                        "   tv_sec: int64",
                        "end",
                        "local tv = new timeval()",
                        "local s: number = tv.tv_sec",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:5"
    )
    -- cstring fields are legal in C structs (unlike GC-managed structs)
    assertClean("cdef struct entry\n   name: cstring\n   next: entry*?\nend")
    testAssert.equal((diagsOf("local struct S\n   name: cstring\nend")), "NUPP2201:2")
    testAssert.equal((diagsOf("cdef struct S\n   t: {number}\nend")), "NUPP2203:2")
end

-- Ownership is optional on a C return, and what it wraps still has to be a C
-- pointer: an owned `int32` is nothing the caller could discharge.
function M.ownershipOnACdefReturnRequiresAPointer()
    assertClean("cdef function good(): voidptr")
    assertClean(
        "cdef struct blob\n   n: int32\nend\n"
        .. "cdef function release(takes b: blob*)\n"
        .. "cdef function mk(): affine(blob*, release)"
    )
    -- Not a pointer, and so nothing `free` could accept either.
    testAssert.equal(
        (diagsOf("cdef function free(takes value: voidptr)\n" .. "cdef function bad(): affine(int32, free)")),
        "NUPP2615:2 NUPP2203:2"
    )
end

function M.stringToCstringConversion()
    assertClean("cdef function puts2(s: cstring): int32\nputs2('hello')")
    -- but a cstring result is NOT a Lua string
    testAssert.equal((diagsOf("cdef function nm(): cstring\nlocal s: string = nm()")), "NUPP2001:2")
end

function M.pointerConversions()
    -- nil is NULL; a struct converts to T* implicitly (address-of)
    assertClean(
        table.concat(
            {
                "cdef struct tval",
                "   sec: int64",
                "end",
                "cdef function fill(t: tval*, z: voidptr?): int32",
                "local t = new tval()",
                "fill(t, nil)",
            },
            "\n"
        )
    )
    -- and a non-null pointer refuses NULL, which is why both spellings exist
    testAssert.equal(
        (
            diagsOf(
                table.concat(
                    {"cdef struct tv3", "   sec: int64", "end", "cdef function needs(t: tv3*): int32", "needs(nil)",},
                    "\n"
                )
            )
        ),
        "NUPP2006:5"
    )
    testAssert.equal(
        (
            diagsOf(
                table.concat(
                    {
                        "cdef struct tval2",
                        "   sec: int64",
                        "end",
                        "cdef struct other",
                        "   n: int32",
                        "end",
                        "cdef function fill2(t: tval2*): int32",
                        "fill2(new other())",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2006:8"
    )
end

function M.realLibcCall()
    -- an actual C call through a typed declaration, end to end
    testAssert.equal(
        run(table.concat({"cdef function strlen(s: cstring): uint64", "return tonumber(strlen('hello, C'))",}, "\n")),
        8
    )
    testAssert.equal(
        run(
            table.concat(
                {
                    windows and "cdef function _getpid(): int32" or "cdef function getpid(): int32",
                    windows and "return _getpid() > 0" or "return getpid() > 0",
                },
                "\n"
            )
        ),
        true
    )
end

function M.cdefStructRuntime()
    testAssert.equal(
        run(
            table.concat(
                {
                    "cdef struct nuppTestPair",
                    "   a: int32",
                    "   b: int32",
                    "end",
                    "local p = new nuppTestPair(3, 9)",
                    "return p.a + p.b",
                },
                "\n"
            )
        ),
        12
    )
end

function M.cdefUnionsAndBitfieldsKeepTheirCLayout()
    testAssert.equal(
        run(
            table.concat(
                {
                    "cdef union nuppTestValue",
                    "   integer_value: int32",
                    "   number_value: number",
                    "end",
                    "cdef struct nuppTestBits",
                    "   ready: uint32 : 1",
                    "   mode: uint32 : 3",
                    "end",
                    "local value = new nuppTestValue()",
                    "value.integer_value = 7",
                    "local bits = new nuppTestBits()",
                    "bits.ready = 1",
                    "bits.mode = 5",
                    "return value.integer_value + bits.ready + bits.mode",
                },
                "\n"
            )
        ),
        13
    )
    testAssert.equal((diagsOf(table.concat({"cdef struct nuppBadBits", "   field: number : 2", "end",}, "\n"))), "NUPP2203:2")
end

-- C's `bool` is a bitfield base one bit wide, as it is for a plain struct, so an
-- imported C struct with a bool bitfield can be declared.
function M.cdefBooleanBitfieldsHoldOneBit()
    testAssert.equal(
        run(
            table.concat(
                {
                    "cdef struct nuppTestFlags",
                    "   ready: boolean : 1",
                    "   mode: uint32 : 3",
                    "end",
                    "local flags = new nuppTestFlags()",
                    "flags.ready = true",
                    "flags.mode = 5",
                    "return (flags.ready and 1 or 0) + flags.mode",
                },
                "\n"
            )
        ),
        6
    )
    testAssert.equal((diagsOf(table.concat({"cdef struct nuppWideFlag", "   ready: boolean : 2", "end",}, "\n"))), "NUPP2203:2")
end

function M.ownIsStaticAndDropIsExplicit()
    testAssert.equal(
        run(
            table.concat(
                {
                    "cdef function free(takes p: voidptr)",
                    "cdef function malloc(n: uint64): voidptr",
                    "local function ownedMalloc(n: uint64): affine(voidptr, free)",
                    "   return malloc(n)",
                    "end",
                    "local p = ownedMalloc(64ULL)",
                    "local ok = p ~= nil",
                    "nupp.drop(p)",
                    "return ok",
                },
                "\n"
            )
        ),
        true
    )
end

function M.fromClauseBindsNamedLibrary()
    -- symbols resolve through the named library instead of the default
    -- namespace; zlib is not linked into the runtime
    local declaration = windows and "cdef function GetCurrentProcessId(): uint32 from 'kernel32'"
        or "cdef function crc32(crc: uint64, buf: cstring, len: uint32): uint64 from 'z'"
    assertClean(declaration)
    if windows then
        assert(run(declaration .. "\nreturn GetCurrentProcessId()") > 0)
    else
        testAssert.equal(run(table.concat({declaration, "return tonumber(crc32(0, 'hello, world', 12))",}, "\n")), 4289425978)
    end
end

function M.levelZeroCdefNameUntouched()
    -- 'cdef' stays an ordinary identifier when not followed by a
    -- declaration form
    assertClean("local cdef = 5\nlocal x: number = cdef")
    assertClean("local from = 1\nlocal x: number = from")
    assertClean("local t = { cdef = 1 }\nprint(t.cdef)")
end

function M.luaStringCannotBeStoredInACstringField()
    -- a Lua string converts to const char * for the duration of a call, but a
    -- struct field outlives the call and the collector may move on from the
    -- string while the field still points at it
    local HOLDER = "cdef struct holder\n   name: cstring\nend\n"
    testAssert.equal((diagsOf(HOLDER .. "local h = new holder()\nlocal text = 'a' .. 'b'\nh.name = text")), "NUPP2604:6")
    testAssert.equal((diagsOf(HOLDER .. "local h = new holder('hi')")), "NUPP2604:4")
    -- inside unsafe the author vouches that the string outlives the slot
    assertClean(HOLDER .. "local h = new holder()\nlocal text = 'a' .. 'b'\n@unsafe do\n   h.name = text\nend")
    -- the call-scoped conversion is unchanged
    assertClean("cdef function strlen2(s: cstring): uint64\nstrlen2('hi')")
end

return M
