local parser = require("nupp.parser")
local check = require("nupp.check")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- One shared env for all stdlib tests (prelude loads once); module tests
-- get an env rooted at the tests directory so fixtures resolve.
local sharedEnv = envMod.new(HERE)

local function diagsOf(src)
   sharedEnv.loaded = {}
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test", sharedEnv)
   local out = {}
   for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
   return table.concat(out, " "), diags
end

local function assertClean(src)
   local got, diags = diagsOf(src)
   assertEq(got, "", "expected clean check for:\n" .. src
      .. (diags[1] and ("\nfirst: " .. diags[1].msg) or ""))
end

local M = {}

function M.stringLibrary()
   assertClean("local s: string = string.format('%d', 3)")
   assertEq((diagsOf("local n: number = string.format('%d', 3)")),
      "NUPP2001:1")
   assertEq((diagsOf("string.formt('%d', 3)")), "NUPP2004:1")
   assertClean("local a, b = string.find('abc', 'b')\nlocal x: integer? = a")
end

function M.stringMethods()
   assertClean("local s: string = ('abc'):sub(1, 2)")
   assertClean("local s: string\nlocal u: string = s:upper()")
   assertEq((diagsOf("local s: string\ns:sub('bad')")), "NUPP2006:2")
end

function M.mathAndBit()
   assertClean("local i: integer = math.floor(1.7)")
   assertClean("local n: number = math.max(1, 2, 3)")
   assertClean("local i: integer = bit.band(0xFF, 0x0F)")
   assertEq((diagsOf("math.floor('x')")), "NUPP2006:1")
end

-- min and max are one homogeneous bounded type in, the same type out, so
-- comparing integers gives an integer rather than widening to number.
function M.mathMinMaxKeepIntegers()
   assertClean(table.concat({
      "local xs: {string} = {'a', 'b'}",
      "local n: integer = math.min(#xs, 2)",
      "local m: integer = math.max(1, n)",
      "local s: string = xs[math.min(#xs, 2)]",
   }, "\n"))
   assertClean("local w: number = math.min(1.5, 2)")
   -- a float argument leaves the result non-integral
   assertEq((diagsOf("local bad: integer = math.min(1.5, 2.5)")),
      "NUPP2001:1")
   -- the `N is number` bound is what refuses a non-number
   assertEq((diagsOf("math.min('nope', 1)")), "NUPP2116:1")
end

-- A declared vararg element type is checked at every argument past the
-- last named parameter, and an untyped `...` still accepts anything.
function M.typedVarargElements()
   assertClean(table.concat({
      "local function sum(...: integer): integer",
      "    return 0",
      "end",
      "sum(1, 2, 3)",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local function sum(...: integer): integer",
      "    return 0",
      "end",
      "sum(1, 'two')",
   }, "\n"))), "NUPP2006:4")
   assertEq((diagsOf("string.char(65, 'B')")), "NUPP2006:1")
   assertClean(table.concat({
      "local function anything(...) end",
      "anything(1, 'two', {})",
   }, "\n"))
end

function M.coreFunctions()
   assertClean("print('hello', 42)")
   assertClean("local t: string = type({})")
   assertClean("local n: number? = tonumber('42')")
   assertClean("local v: number = assert(tonumber('42'))")
   assertClean("local ok, err = pcall(function() end)\nlocal b: boolean = ok")
   assertClean("local t = setmetatable({}, {__index = {}})")
end

function M.pairsTyping()
   assertClean(table.concat({
      "local m: {[string]: number} = {}",
      "for k, v in pairs(m) do",
      "   local s: string = k",
      "   local n: number = v",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "local list: {string} = {}",
      "for i, s in ipairs(list) do",
      "   local n: integer = i",
      "   local t: string = s",
      "end",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local m: {[string]: number} = {}",
      "for k, v in pairs(m) do",
      "   local n: number = k",
      "end",
   }, "\n"))), "NUPP2001:3")
end

function M.tableLibrary()
   assertClean("local t: {number} = {}\ntable.insert(t, 5)")
   assertClean("local s: string = table.concat({'a', 'b'}, ',')")
   assertClean("local t = table.new(16, 0)")
end

function M.stringBufferModule()
   assertClean(table.concat({
      "local buffer = require('string.buffer')",
      "local b = buffer.new()",
      "b:put('a', 1):put('b')",
      "local s: string = b:tostring()",
      "local joined: string = b .. 'x'",
      "local size: integer = #b",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local buffer = require('string.buffer')",
      "local b = buffer.new()",
      "b:putt('x')",
   }, "\n"))), "NUPP2004:3")
   assertEq((diagsOf(table.concat({
      "local buffer = require('string.buffer')",
      "local n: number = buffer.encode({})",
   }, "\n"))), "NUPP2001:2")
end

-- A declaration file names the types its own API is written in, so code that
-- passes those values around has to be able to name them too.
function M.stringBufferTypeIsNameable()
   assertClean(table.concat({
      "local buffer = require('string.buffer')",
      "local function render(out: buffer.Buffer): buffer.Buffer",
      "   return out:putf('%d', 1)",
      "end",
      "local s: string = render(buffer.new(64)):tostring()",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local buffer = require('string.buffer')",
      "local b: buffer.Buffer = buffer.new()",
      "local n: number = b",
   }, "\n"))), "NUPP2001:3")
end

-- Every method the module actually exposes, so a gap in the declarations
-- shows up here rather than as a spurious NUPP2004 in someone's code.
function M.stringBufferCoversTheWholeApi()
   assertClean(table.concat({
      "local buffer = require('string.buffer')",
      "local b = buffer.new(64, {dict = {'k'}})",
      "b:reset():put('a', 1):putf('%s', 'x'):skip(1)",
      "b:set('abc')",
      "b:encode({1})",
      "local decoded = b:decode()",
      "local ptr, len = b:reserve(8)",
      "b:commit(0)",
      "local base, size = b:ref()",
      "local n: integer = #b",
      "local text: string = b:get(1)",
      "local all: string = b:tostring()",
      "b:free()",
      "local encoded: string = buffer.encode(decoded)",
      "local back = buffer.decode(encoded)",
      "local ffi = require('ffi')",
      "b:putcdata(ffi.new('uint8_t[4]'), 4)",
   }, "\n"))
end

-- reserve/ref hand out the byte view the zero-copy loops in LuaJIT's manual
-- are written against, so it has to be indexable rather than an opaque
-- pointer: `ptr[i] = 0x40` is the whole point of reserving space.
function M.stringBufferPointersAreIndexable()
   assertClean(table.concat({
      "local buffer = require('string.buffer')",
      "local b = buffer.new()",
      "local ptr, available = b:reserve(64)",
      "ptr[0] = 65",
      "b:commit(1)",
      "local base, len = b:ref()",
      "local first: integer = base[0]",
      "b:skip(len)",
      "local total: uint64 = available + len",
   }, "\n"))
end

function M.cjsonModule()
   assertClean(table.concat({
      "local cjson = require('cjson')",
      "local text: string = cjson.encode({1, 2, 3})",
      "local value = cjson.decode(text)",
   }, "\n"))
   -- decode yields any, so it flows anywhere
   assertClean(table.concat({
      "local cjson = require('cjson')",
      "local n: number = cjson.decode('1')",
   }, "\n"))
   -- encode returns a string, not a number
   assertEq((diagsOf(table.concat({
      "local cjson = require('cjson')",
      "local n: number = cjson.encode({})",
   }, "\n"))), "NUPP2001:2")
   -- decode takes text
   assertEq((diagsOf(table.concat({
      "local cjson = require('cjson')",
      "cjson.decode(42)",
   }, "\n"))), "NUPP2006:2")
   -- misspelled members are caught against the declared surface
   assertEq((diagsOf(table.concat({
      "local cjson = require('cjson')",
      "cjson.encde({})",
   }, "\n"))), "NUPP2004:2")
end

function M.cjsonSentinelsAndConfig()
   assertClean(table.concat({
      "local cjson = require('cjson')",
      "local nul: userdata = cjson.null",
      "local mt: table = cjson.array_mt",
      "local depth: integer = cjson.encode_max_depth(20)",
      "local keep: boolean = cjson.encode_keep_buffer()",
      "local name: string = cjson._VERSION",
   }, "\n"))
   -- new() hands back the same interface, so it chains
   assertClean(table.concat({
      "local cjson = require('cjson')",
      "local instance = cjson.new()",
      "local text: string = instance.encode({})",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local cjson = require('cjson')",
      "local s: string = cjson.null",
   }, "\n"))), "NUPP2001:2")
end

function M.cjsonSafeModule()
   -- the safe variant reports failure instead of raising: encode is optional
   assertClean(table.concat({
      "local cjson = require('cjson.safe')",
      "local text: string? = cjson.encode({})",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local cjson = require('cjson.safe')",
      "local text: string = cjson.encode({})",
   }, "\n"))), "NUPP2001:2")
   assertClean(table.concat({
      "local cjson = require('cjson.safe')",
      "local value = cjson.decode('{}')",
   }, "\n"))
end

function M.projectFilesShadowBundledDeclarations()
   -- a project shipping its own cjson description wins over the bundled one
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local f = assert(io.open(dir .. "/cjson.d.nupp", "wb"))
   f:write("local encode: function(v: any): integer\nreturn {encode = encode}\n")
   f:close()
   local env = envMod.new(dir)
   local result = parser.parse(
      "local cjson = require('cjson')\nlocal n: integer = cjson.encode({})",
      "consumer")
   assertEq(#result.errors, 0, "consumer parses")
   local diags = check.check(result, "consumer", env)
   assertEq(#diags, 0, "the project's own declaration is used: "
      .. (diags[1] and diags[1].msg or ""))
   os.execute("rm -rf '" .. dir .. "'")
end

function M.moduleRequireTyped()
   assertClean(table.concat({
      "local geom = require('fixtures.geom')",
      "local p = geom.make(1, 2)",
      "local d: number = geom.dist2(p)",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local geom = require('fixtures.geom')",
      "geom.make('a', 2)",
   }, "\n"))), "NUPP2006:2")
   assertEq((diagsOf(table.concat({
      "local geom = require('fixtures.geom')",
      "geom.nope()",
   }, "\n"))), "NUPP2004:2")
end

function M.moduleRequireDeclarationFile()
   assertClean(table.concat({
      "local clib = require('fixtures.clib')",
      "local n: number = clib.add(1, 2)",
      "local s: string = clib.greet('hi')",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local clib = require('fixtures.clib')",
      "clib.add('x', 2)",
   }, "\n"))), "NUPP2006:2")
end

function M.moduleUnresolvedIsAny()
   assertClean("local mystery = require('no.such.module')\nmystery.anything(1)")
end

return M
