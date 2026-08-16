local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")
local windows = require("ffi").os == "Windows"
local hostOs = require("ffi").os
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors"
      .. (result.errors[1] and (": " .. result.errors[1].msg) or ""))
   local diags = check.check(result, "test.g.nupp", envMod.new(HERE .. "/.."))
   local code, genDiags = gen.generate(result, "test")
   return code, diags, genDiags
end

local function diagsOf(src)
   local _, diags = compile(src)
   local out = {}
   for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
   return table.concat(out, " "), diags
end

local function assertClean(src)
   local got, diags = diagsOf(src)
   assertEq(got, "", "expected clean check:\n" .. src
      .. ((diags and diags[1]) and ("\nfirst: " .. diags[1].msg) or ""))
end

local function run(src)
   local code, diags, genDiags = compile(src)
   local messages = {}
   for _, diagnostic in ipairs(diags) do
      messages[#messages + 1] = diagnostic.code .. ":" .. diagnostic.line
         .. ": " .. diagnostic.msg
   end
   assertEq(#diags, 0, "check diagnostics"
      .. (#messages > 0 and (":\n" .. table.concat(messages, "\n")
         .. "\n--- source ---\n" .. src) or ""))
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@cdeftest")
   if not chunk then
      error("generated code does not load: " .. tostring(err)
         .. "\n---\n" .. code, 2)
   end
   return chunk()
end

local M = {}

function M.cdefFunctionTyping()
   assertClean("cdef function strlen(s: cstring): uint64\nstrlen('hi')")
   assertEq((diagsOf(
      "cdef function strlen(s: cstring): uint64\nstrlen(42)")), "NUPP2006:2")
   assertEq((diagsOf(
      "cdef function strlen(s: cstring): uint64\nstrlen('a', 'b')")), "NUPP2007:2")
   -- non-C types are rejected in signatures
   assertEq((diagsOf(
      "cdef function bad(t: {number}): int32")), "NUPP2203:1")
   assertEq((diagsOf(
      "cdef function bad2(): {[string]: number}")), "NUPP2203:1")
end

function M.countedPointersBuildOneCheckedWrapperOverThePhysicalBinding()
   local source = table.concat({
      "local spans = require('nupp.span')",
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
      "writable:commit()",
   }, "\n")
   assertClean(source)
   local code, diags, genDiags = compile(source)
   assertEq(#diags, 0)
   assertEq(#genDiags, 0)
   assert(code:find("positions.count~=velocities.count", 1, true), code)
   assert(code:find("positions:ref()", 1, true), code)
   assert(code:find("velocities:ref()", 1, true), code)
   assert(code:find("__nuppFfi.C.counted_integrate", 1, true), code)
   assert(not code:find("if positions.count==0", 1, true), "zero count must still call C:\n" .. code)
end

function M.countedPointersExecuteBoundsOffsetsCountsAndSharedDowngrades()
   if windows then return end
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local suffix = hostOs == "OSX" and ".dylib" or ".so"
   local library = dir .. "/libcounted_pointer" .. suffix
   local shared = hostOs == "OSX" and "-dynamiclib" or "-shared"
   local fixture = HERE .. "/fixtures/counted_pointer.c"
   local built = os.execute((
      "clang -std=c11 -O2 -Wall -Wextra -Werror -fPIC %s '%s' -o '%s'"
   ):format(shared, fixture, library))
   assertEq(built, 0, "build counted-pointer fixture")

   local declaration = table.concat({
      "local spans = require('nupp.span')",
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
   }, "\n")
   local source = declaration .. "\n" .. table.concat({
      "local input = ffi.new<int32[6]>()",
      "local output = ffi.new<int32[6]>()",
      "for i = 0, 5 do input[i] = (i + 1) as int32 end",
      "counted_pointer_reset()",
      "do",
      "   local writer = spans.writeCarray(output, 6)",
      "   do",
      "      local parts = writer:splitAt(1)",
      "      local readable = spans.fromCarray(input, 6):slice(2, 6)",
      "      counted_pointer_transform(parts.right, readable)",
      "   end",
      "   writer:commit()",
      "end",
      "local offsetFirst, offsetLast: int32, int32",
      "do",
      "   local transformed = spans.fromCarray(output, 6)",
      "   offsetFirst, offsetLast = transformed:get(2), transformed:get(6)",
      "end",
      "local transformCalls = counted_pointer_call_count()",
      "counted_pointer_reset()",
      "do",
      "   local emptyOutput = spans.writeCarray(output, 0)",
      "   local emptyInput = spans.fromCarray(input, 0)",
      "   counted_pointer_transform(emptyOutput, emptyInput)",
      "   emptyOutput:commit()",
      "end",
      "local zeroCalls = counted_pointer_call_count()",
      "counted_pointer_reset()",
      "do",
      "   local independentOutput = spans.writeCarray(output, 3)",
      "   local independentInput = spans.fromCarray(input, 5)",
      "   counted_pointer_independent(independentOutput, independentInput)",
      "   independentOutput:commit()",
      "end",
      "local outputCount, inputCount, inputFirst: int32, int32, int32",
      "do",
      "   local independent = spans.fromCarray(output, 3)",
      "   outputCount, inputCount, inputFirst = independent:get(1), independent:get(2), independent:get(3)",
      "end",
      "local sharedStorage = ffi.new<int32[2]>()",
      "local sharedOutput = ffi.new<int32[2]>()",
      "sharedStorage[0], sharedStorage[1] = 7 as int32, 8 as int32",
      "do",
      "   local sourceWriter = spans.writeCarray(sharedStorage, 2)",
      "   local destinationWriter = spans.writeCarray(sharedOutput, 2)",
      "   do",
      "      local sourceReader = sourceWriter:shared()",
      "      counted_pointer_transform(destinationWriter, sourceReader)",
      "   end",
      "   destinationWriter:commit()",
      "   sourceWriter:commit()",
      "end",
      "local sharedRead = spans.fromCarray(sharedOutput, 2)",
      "return offsetFirst, offsetLast, transformCalls, zeroCalls,",
      "   outputCount, inputCount, inputFirst, sharedRead:get(1), sharedRead:get(2)",
   }, "\n")

   local ok, a, b, calls, zeroCalls, outputCount,
      inputCount, inputFirst, sharedFirst, sharedLast = pcall(run, source)
   if not ok then
      os.execute("rm -rf '" .. dir .. "'")
      error(a, 0)
   end
   assertEq(tonumber(a), 12, "sliced input starts at its adjusted pointer")
   assertEq(tonumber(b), 16, "partitioned output reaches its adjusted last element")
   assertEq(tonumber(calls), 1, "ordinary counted call reaches C once")
   assertEq(tonumber(zeroCalls), 1, "zero-count call reaches C exactly once")
   assertEq(tonumber(outputCount), 3, "first independent count reaches C")
   assertEq(tonumber(inputCount), 5, "second independent count reaches C")
   assertEq(tonumber(inputFirst), 1, "independent read pointer reaches C")
   assertEq(tonumber(sharedFirst), 17, "a shared downgrade is accepted as const input")
   assertEq(tonumber(sharedLast), 18, "shared downgrade preserves its full range")

   local transform = run(declaration .. "\nreturn counted_pointer_transform")
   local spans = require("nupp.span")
   local ffi = require("ffi")
   local output = ffi.new("int32_t[1]")
   local input = ffi.new("int32_t[2]")
   local shortOutput = spans.writeCarray(output, 1)
   local longInput = spans.fromCarray(input, 2)
   local reset = ffi.load(library).counted_pointer_reset
   local callCount = ffi.load(library).counted_pointer_call_count
   reset()
   local unequalOk = pcall(transform, shortOutput, longInput)
   assertEq(unequalOk, false, "unequal shared counts raise before C")
   assertEq(tonumber(callCount()), 0, "unequal shared counts never enter C")
   shortOutput:commit()
   os.execute("rm -rf '" .. dir .. "'")
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
   local got = diagsOf("@spanabi(read = { values = 'count' })\n"
      .. "cdef function old(borrows values: const int32*, count: uint64)")
   assert(got:find("NUPP2111", 1, true), got)
end
function M.cdefCallbackParameter()
   local source = "cdef function each(fn: function(int32), n: int32)"
   assertClean(source)
   local code, _, genDiags = compile(source)
   assertEq(#genDiags, 0, "callback signature generates cleanly")
   assert(code:find("void each(void (*)(int32_t), int32_t);", 1, true),
      "function type lowers to a C callback pointer:\n" .. code)
end

function M.nullableCallbacksWorkInEveryCDeclaratorPosition()
   local source = table.concat({
      "cdef struct callback_holder",
      "   callback: function(int32)?",
      "end",
      "cdef function callback_get(): function(int32)?",
      "cdef function callback_set(callback: function(int32)?)",
   }, "\n")
   assertClean(source)
   local code, _, genDiags = compile(source)
   assertEq(#genDiags, 0, "nullable callback declarations generate cleanly")
   assert(code:find("void (*callback)(int32_t);", 1, true),
      "callback field lowers to a function pointer:\n" .. code)
   assert(code:find("void (*callback_get(void))(int32_t);", 1, true),
      "callback result lowers to a function pointer:\n" .. code)
end

function M.fixedArrayFieldsKeepTheirCDeclaratorOrder()
   local source = table.concat({
      "cdef struct array_holder",
      "   values: int32[4]",
      "   callbacks: function(int32)?[2]",
      "end",
   }, "\n")
   assertClean(source)
   local code, _, genDiags = compile(source)
   assertEq(#genDiags, 0, "fixed arrays generate cleanly")
   assert(code:find("int32_t values[4];", 1, true),
      "array field name precedes its bound:\n" .. code)
   assert(code:find("void (*callbacks[2])(int32_t);", 1, true),
      "array-of-callback declarator nests correctly:\n" .. code)
end

function M.cdefStructTyping()
   assertClean(table.concat({
      "cdef struct timeval",
      "   tv_sec: int64",
      "   tv_usec: int64",
      "end",
      "local tv = new timeval()",
      "local s: number = tv.tv_sec",
   }, "\n"))
   -- cstring fields are legal in C structs (unlike GC-managed structs)
   assertClean("cdef struct entry\n   name: cstring\n   next: entry*?\nend")
   assertEq((diagsOf("local struct S\n   name: cstring\nend")), "NUPP2201:2")
   assertEq((diagsOf("cdef struct S\n   t: {number}\nend")), "NUPP2203:2")
end

function M.cdefBindingsAndHelpersUseConstWherePossible()
   local code, diags, genDiags = compile(table.concat({
      "cdef struct timeval",
      "   tv_sec: int64",
      "end",
      "cdef function clock_gettime(clock: int32, value: timeval*): int32",
   }, "\n"))
   assertEq(#diags, 0, "check diagnostics")
   assertEq(#genDiags, 0, "gen diagnostics")
   assert(code:find("const timeval = __nuppFfi.typeof", 1, true), code)
   assert(code:find("const clock_gettime = __nuppFfi.C.clock_gettime", 1, true),
      code)

   local libraryCode = compile(
      "cdef function crc32(crc: uint64, buf: cstring, len: uint32): uint64 from 'z'")
   assert(libraryCode:find("const __nuppLibCache", 1, true), libraryCode)
   assert(libraryCode:find("const function __nuppLib", 1, true), libraryCode)
   assert(libraryCode:find("local l = __nuppLibCache[n]", 1, true), libraryCode)
end

-- Ownership is optional on a C return, and what it wraps still has to be a C
-- pointer: an owned `int32` is nothing the caller could discharge.
function M.ownershipOnACdefReturnRequiresAPointer()
   assertClean("cdef function good(): voidptr")
   assertClean("cdef struct blob\n   n: int32\nend\n"
      .. "cdef function release(takes b: blob*)\n"
      .. "cdef function mk(): affine(blob*, release)")
   -- Not a pointer, and so nothing `free` could accept either.
   assertEq((diagsOf(
      "cdef function free(takes value: voidptr)\n"
      .. "cdef function bad(): affine(int32, free)")), "NUPP2615:2 NUPP2203:2")
end

function M.stringToCstringConversion()
   assertClean("cdef function puts2(s: cstring): int32\nputs2('hello')")
   -- but a cstring result is NOT a Lua string
   assertEq((diagsOf(
      "cdef function nm(): cstring\nlocal s: string = nm()")), "NUPP2001:2")
end

function M.pointerConversions()
   -- nil is NULL; a struct converts to T* implicitly (address-of)
   assertClean(table.concat({
      "cdef struct tval",
      "   sec: int64",
      "end",
      "cdef function fill(t: tval*, z: voidptr?): int32",
      "local t = new tval()",
      "fill(t, nil)",
   }, "\n"))
   -- and a non-null pointer refuses NULL, which is why both spellings exist
   assertEq((diagsOf(table.concat({
      "cdef struct tv3",
      "   sec: int64",
      "end",
      "cdef function needs(t: tv3*): int32",
      "needs(nil)",
   }, "\n"))), "NUPP2006:5")
   assertEq((diagsOf(table.concat({
      "cdef struct tval2",
      "   sec: int64",
      "end",
      "cdef struct other",
      "   n: int32",
      "end",
      "cdef function fill2(t: tval2*): int32",
      "fill2(new other())",
   }, "\n"))), "NUPP2006:8")
end

function M.realLibcCall()
   -- an actual C call through a typed declaration, end to end
   assertEq(run(table.concat({
      "cdef function strlen(s: cstring): uint64",
      "return tonumber(strlen('hello, C'))",
   }, "\n")), 8)
   assertEq(run(table.concat({
      windows and "cdef function _getpid(): int32"
         or "cdef function getpid(): int32",
      windows and "return _getpid() > 0" or "return getpid() > 0",
   }, "\n")), true)
end

function M.cdefStructRuntime()
   assertEq(run(table.concat({
      "cdef struct nuppTestPair",
      "   a: int32",
      "   b: int32",
      "end",
      "local p = new nuppTestPair(3, 9)",
      "return p.a + p.b",
   }, "\n")), 12)
end

function M.cdefUnionsAndBitfieldsKeepTheirCLayout()
   assertEq(run(table.concat({
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
   }, "\n")), 13)
   assertEq((diagsOf(table.concat({
      "cdef struct nuppBadBits",
      "   field: number : 2",
      "end",
   }, "\n"))), "NUPP2203:2")
end

function M.ownIsStaticAndDropIsExplicit()
   assertEq(run(table.concat({
      "cdef function free(takes p: voidptr)",
      "cdef function malloc(n: uint64): voidptr",
      "local function ownedMalloc(n: uint64): affine(voidptr, free)",
      "   return malloc(n)",
      "end",
      "local p = ownedMalloc(64)",
      "local ok = p ~= nil",
      "drop(p)",
      "return ok",
   }, "\n")), true)
end

function M.fromClauseBindsNamedLibrary()
   -- symbols resolve through a cached ffi.load instead of the default
   -- namespace; zlib is not linked into the luajit binary
   local declaration = windows
      and "cdef function GetCurrentProcessId(): uint32 from 'kernel32'"
      or "cdef function crc32(crc: uint64, buf: cstring, len: uint32): uint64 from 'z'"
   local library = windows and "kernel32" or "z"
   assertClean(declaration)
   local code = compile(declaration)
   assert(code:find("__nuppLib('" .. library .. "')", 1, true),
      "binds through ffi.load:\n" .. code)
   assert(code:find("__nuppLibCache", 1, true), "load is cached")
   -- and it actually calls the library
   if windows then
      assert(run(declaration .. "\nreturn GetCurrentProcessId()") > 0)
   else
      assertEq(run(table.concat({
         declaration,
         "return tonumber(crc32(0, 'hello, world', 12))",
      }, "\n")), 4289425978)
   end
end

function M.defaultNamespaceStillUsedWithoutFrom()
   local code = compile("cdef function getpid(): int32")
   assert(code:find("__nuppFfi.C.getpid", 1, true),
      "no library named: default namespace:\n" .. code)
   assert(not code:find("__nuppLib(", 1, true), "no ffi.load emitted")
end

function M.levelZeroCdefNameUntouched()
   -- 'cdef' stays an ordinary identifier when not followed by a
   -- declaration form
   assertClean("local cdef = 5\nlocal x: number = cdef")
   assertClean("local from = 1\nlocal x: number = from")
   assertClean("local t = { cdef = 1 }\nprint(t.cdef)")
end

return M
