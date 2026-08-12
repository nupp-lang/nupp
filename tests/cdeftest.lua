local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")
local windows = require("ffi").os == "Windows"
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
   assertEq(#diags, 0, "check diagnostics"
      .. (diags[1] and (": " .. diags[1].msg) or ""))
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

function M.ownRequiresPointer()
   assertEq((diagsOf(
      "@owned(free) cdef function bad(): int32")), "NUPP2203:1")
   assertClean("@owned(free) cdef function good(): voidptr")
   assertClean("cdef struct blob\n   n: int32\nend\n"
      .. "@owned(release) cdef function mk(): blob*\n"
      .. "cdef function release(b: blob*)")
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
      "@owned(free)",
      "cdef function malloc(n: uint64): voidptr",
      "local p = malloc(64)",
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
