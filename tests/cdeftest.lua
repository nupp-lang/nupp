local parser = require("nupp.parser")
local check = require("nupp.check")
local gen = require("nupp.gen")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors"
      .. (result.errors[1] and (": " .. result.errors[1].msg) or ""))
   local diags = check.check(result, "test")
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
      "cdef function getpid(): int32",
      "return getpid() > 0",
   }, "\n")), true)
end

function M.cdefStructRuntime()
   assertEq(run(table.concat({
      "cdef struct nuppTestPair",
      "   a: int32",
      "   b: int32",
      "end",
      "local p = new nuppTestPair {a = 3, b = 9}",
      "return p.a + p.b",
   }, "\n")), 12)
end

function M.ownIsStaticAndDisposeIsExplicit()
   assertEq(run(table.concat({
      "cdef function free(takes p: voidptr)",
      "@owned(free)",
      "cdef function malloc(n: uint64): voidptr",
      "local p = malloc(64)",
      "local ok = p ~= nil",
      "dispose(p)",
      "return ok",
   }, "\n")), true)
end

function M.fromClauseBindsNamedLibrary()
   -- symbols resolve through a cached ffi.load instead of the default
   -- namespace; zlib is not linked into the luajit binary
   assertClean("cdef function crc32(crc: uint64, buf: cstring, len: uint32): uint64 from \'z\'")
   local code = compile(
      "cdef function crc32(crc: uint64, buf: cstring, len: uint32): uint64 from 'z'")
   assert(code:find("__nuppLib('z')", 1, true), "binds through ffi.load:\n" .. code)
   assert(code:find("__nuppLibCache", 1, true), "load is cached")
   -- and it actually calls the library
   assertEq(run(table.concat({
      "cdef function crc32(crc: uint64, buf: cstring, len: uint32): uint64 from 'z'",
      "return tonumber(crc32(0, 'hello, world', 12))",
   }, "\n")), 4289425978)
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
