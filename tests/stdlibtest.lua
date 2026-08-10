local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local native = require("nupp.compiler.native")
local optimize = require("nupp.compiler.optimize")

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

local function diagsOf(src, opts)
   sharedEnv.loaded = {}
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", sharedEnv, opts)
   local out = {}
   for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
   return table.concat(out, " "), diags
end

local function assertClean(src, opts)
   local got, diags = diagsOf(src, opts)
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

function M.mathRandomOverloadsMatchLuaJitArities()
   assertClean(table.concat({
      "local unit: number = math.random()",
      "local upper: number = math.random(10)",
      "local range: number = math.random(1.5, 4.5)",
   }, "\n"))
   assertEq((diagsOf("math.random(nil, 2)")), "NUPP2125:1")

   local unit = math.random()
   local upper = math.random(10)
   local fractional = math.random(1.5, 4.5)
   assert(type(unit) == "number" and type(upper) == "number"
      and type(fractional) == "number",
      "every documented math.random arity returns a Lua number")
   assertEq(pcall(math.random, nil, 2), false,
      "the rejected nil hole also fails in LuaJIT")
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

function M.nativeFeaturesAreResolvedEffects()
   local function effectsOf(source)
      local result = parser.parse(source, "native-effects")
      assertEq(#result.errors, 0, "native-effects source parses")
      check.check(result, "native-effects", sharedEnv)
      return result.effects or {}
   end

   local regex = effectsOf("local expression = nupp.regex.compile('a+')")
   assert(regex["native.regex"], "nupp.regex records its native effect")
   assertClean(table.concat({
      "local library: nupp.Regex.Library = nupp.regex",
      "local expression: nupp.Regex = nupp.regex.compile('a+')",
      "local match: nupp.Regex.Match? = expression:find('aaa')",
      "local captures: nupp.Regex.Captures? = expression:captures('aaa')",
   }, "\n"))
   assertEq((diagsOf("local expression: NuppRegex")), "NUPP2101:1",
      "regex nominals do not leak into the ambient type namespace")

   local lpeg = effectsOf("local parser = require('lpeg')")
   assert(lpeg["native.lpeg"], "require('lpeg') records its native effect")

   local cjson = effectsOf("local json = require('cjson')")
   assert(cjson["native.cjson"], "require('cjson') records its native effect")
   local safe = effectsOf("local json = require('cjson.safe')")
   assert(safe["native.cjson"], "cjson.safe shares cjson's native effect")

   local utf8 = effectsOf("local utf8 = require('lua-utf8')")
   assert(utf8["native.lua_utf8"],
      "require('lua-utf8') records its native effect")

   local shadowed = effectsOf(table.concat({
      "local nupp = {regex = {compile = function() end}}",
      "nupp.regex.compile()",
   }, "\n"))
   assert(not shadowed["native.regex"], "a local nupp is not the global facility")

   local shadowedRequire = effectsOf(table.concat({
      "local require = function(_) return {} end",
      "require('lpeg')",
   }, "\n"))
   assert(not shadowedRequire["native.lpeg"],
      "a local require is not the native module loader")

   local expected = {
      ["nupp.data.encodeJSON({answer = 42})"] = "native.cjson",
      ["nupp.data.encodeKeepBuffer(false)"] = "native.cjson",
      ["nupp.data.utf8.length('hello')"] = "native.lua_utf8",
      ["nupp.io.newBuffer('hello')"] = "stdlib.io",
      ["nupp.math.lerp(10, 20, 0.25)"] = "stdlib.math",
      ["nupp.math.vec2.length(3, 4)"] = "stdlib.math",
      ["nupp.data.fnv1a64('hello')"] = "stdlib.fnv1a64",
      ["nupp.data.crc32('hello')"] = "stdlib.checksums",
      ["nupp.io.Path.new('hello')"] = "native.path",
      ["nupp.io.URI.new('https://example.com')"] = "native.uri",
      ["nupp.data.uuid7()"] = "native.uuid",
      ["nupp.data.sha256('hello')"] = "native.sha256",
   }
   for source, effect in pairs(expected) do
      local found = effectsOf(source)
      assert(found[effect], source .. " records " .. effect)
      local count = 0
      for _ in pairs(found) do count = count + 1 end
      assertEq(count, 1, source .. " records only its own facility")
   end

   assertClean(table.concat({
      "local paths: nupp.Path.Library = nupp.io.Path",
      "local library: nupp.URI.Library = nupp.io.URI",
      "local components: nupp.URI.Components = nil as any",
      "local uri: nupp.URI? = library.new(components)",
   }, "\n"))

   local aliased = effectsOf(table.concat({
      "local data = nupp.data",
      "local digest = data.sha256",
      "digest('hello')",
   }, "\n"))
   assert(aliased["native.sha256"], "aliases retain exact feature identity")
   assert(not aliased["native.uuid"], "equal function signatures do not share effects")

   local namespaceOnly = effectsOf("local data = nupp.data")
   assert(next(namespaceOnly) == nil, "reaching a namespace alone has no effect")
end

function M.optimizedDeadCodeDropsItsNativeFeatures()
   local source = table.concat({
      "if false then",
      "    print(nupp.data.sha256('unreachable'))",
      "else",
      "    print(nupp.data.uuid4())",
      "end",
   }, "\n")
   local result = parser.parse(source, "dead-native-feature")
   check.check(result, "dead-native-feature", sharedEnv)
   assert(result.effects["native.sha256"] and result.effects["native.uuid"],
      "checking sees both source-level uses")
   optimize.run(result, {level = 1})
   local live = optimize.liveEffects(result)
   assert(not live["native.sha256"], "a folded-away branch loses its provider")
   assert(live["native.uuid"], "the selected branch retains its provider")
end

function M.compilerProvidedPureLibraries()
   local bootstrap = native.bootstrap({
      ["stdlib.io"] = true,
      ["stdlib.math"] = true,
      ["stdlib.fnv1a64"] = true,
      ["stdlib.checksums"] = true,
   })
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(bootstrap .. [[
      local buffer = nupp.io.newBuffer("hello")
      local writer = buffer:newWriter()
      assert(writer:write("world"))
      assert(buffer:getString() == "world")
      local viewReader = buffer:view():newReader()
      assert(viewReader:read(0) == "w")
      local reader = buffer:newReader()
      assert(reader:read(3) == "wor")
      assert(reader:read(8) == "ld")
      assert(reader:read(1) == "")
      assert(reader:read(0) == "")
      local x, y = nupp.math.vec2.normalize(3, 4)
      assert(math.abs(x - 0.6) < 0.000001 and math.abs(y - 0.8) < 0.000001)
      assert(nupp.math.lerp(10, 20, 0) == 10)
      assert(nupp.math.lerp(10, 20, 0.25) == 12.5)
      assert(nupp.math.lerp(10, 20, 1) == 20)
      assert(nupp.math.lerp(10, 20, 1.5) == 25)
      assert(nupp.data.fnv1a64("hello") == "a430d84680aabd0b")
      assert(nupp.data.adler32("Wikipedia") == 300286872)
      assert(nupp.data.crc32("123456789") == 3421780262)
      assert(not pcall(nupp.data.crc32, "bytes", 4294967296))
   ]]))
   local ok, problem = pcall(chunk)
   _G.nupp = previous
   assert(ok, problem)
end

function M.openFilesAreOwnersOverTheSharedReaderContract()
   local gen = require("nupp.compiler.gen")

   assertClean(table.concat({
      "local files = nupp.io.files",
      "do",
      "    local file = files.open('input.txt') as nupp.Files.File",
      "    local reader: nupp.Reader = file:newReader()",
      "    local writer: nupp.Writer = file:newWriter()",
      "    local bytes: string? = reader:read(16)",
      "    local wrote: boolean = writer:write('x')",
      "end",
   }, "\n"))

   assertClean(table.concat({
      "local buffer = nupp.io.newBuffer()",
      "local reader = nupp.io.newStringReader('abc')",
      "local moved: integer? = reader:readInto(buffer)",
      "local info = nupp.io.files.info('x')",
      "local size: integer? = info and info.size",
   }, "\n"))

   assertEq((diagsOf("local n: number = nupp.io.files.read('x')")), "NUPP2001:1")
   assertEq((diagsOf("nupp.io.files.info(42)")), "NUPP2006:1")
   -- An owner nobody binds has nowhere to be cleaned up from, and `open` is the
   -- first prelude member for which that is true.
   assertEq((diagsOf("nupp.io.files.open('x')")), "NUPP2605:1")
   assertEq((diagsOf("nupp.io.files.createTemporaryFile()")), "NUPP2605:1")

   -- The prelude marks `open` and the temporaries `@owned`, so a binding the
   -- program drops is disposed where it goes out of scope rather than leaking.
   local source = table.concat({
      "local file = nupp.io.files.open('input.txt') as nupp.Files.File",
      "print(file)",
   }, "\n")
   local parsed = parser.parse(source, "owned.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors in the ownership fragment")
   sharedEnv.loaded = {}
   check.check(parsed, "owned.g.nupp", sharedEnv)
   local code = gen.generate(parsed, "owned")
   assert(code:find(":close()", 1, true),
      "an open file is disposed at the end of its scope")
end

function M.bufferAppendsInAmortizedConstantTime()
   local bootstrap = native.bootstrap({["stdlib.io"] = true})
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(bootstrap .. [[
      local buffer = nupp.io.newBuffer()
      local writer = buffer:newWriter()
      local piece = string.rep("x", 64)
      for _ = 1, 100000 do assert(writer:write(piece)) end
      assert(buffer:length() == 6400000, "every write landed")
      assert(buffer:capacity() >= buffer:length(), "capacity covers the length")
      assert(buffer:getString(6399936, 64) == piece, "the last write is intact")
      buffer:clear()
      assert(buffer:length() == 0 and buffer:capacity() >= 6400000,
         "clearing keeps the reserved bytes")
      buffer:setString("tail", 6)
      assert(buffer:getString() == string.char(0):rep(6) .. "tail",
         "a gap past the length reads as zeros, not as stale bytes")
   ]]))
   local ok, problem = pcall(chunk)
   _G.nupp = previous
   assert(ok, problem)
end

function M.hiddenDataDependenciesLoadLazily()
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local bootstrap = native.bootstrap({
      ["native.cjson"] = true,
      ["native.lua_utf8"] = true,
   })
   local chunk = assert(loadstring(bootstrap .. [=[
      assert(package.loaded.cjson == nil)
      assert(package.loaded["lua-utf8"] == nil)
      assert(nupp.data.encodeJSON({answer = 42}):find('"answer":42', 1, true))
      local codec = nupp.data.newJSON()
      local cjson = require("cjson")
      local cjsonCodec = cjson.new()
      local renamed = {
         {"emptyArray", "empty_array"},
         {"arrayMt", "array_mt"},
         {"emptyArrayMt", "empty_array_mt"},
         {"encodeEmptyTableAsObject", "encode_empty_table_as_object"},
         {"decodeArrayWithArrayMt", "decode_array_with_array_mt"},
         {"decodeAllowComment", "decode_allow_comment"},
         {"encodeSparseArray", "encode_sparse_array"},
         {"encodeMaxDepth", "encode_max_depth"},
         {"decodeMaxDepth", "decode_max_depth"},
         {"encodeNumberPrecision", "encode_number_precision"},
         {"encodeKeepBuffer", "encode_keep_buffer"},
         {"encodeInvalidNumbers", "encode_invalid_numbers"},
         {"decodeInvalidNumbers", "decode_invalid_numbers"},
         {"encodeEscapeForwardSlash", "encode_escape_forward_slash"},
         {"encodeSkipUnsupportedValueTypes", "encode_skip_unsupported_value_types"},
         {"encodeIndent", "encode_indent"},
      }
      for _, names in ipairs(renamed) do
         assert(nupp.data[names[1]] == cjson[names[2]], names[1])
         assert(nupp.data[names[2]] == nil, names[2])
         assert((codec[names[1]] ~= nil) == (cjsonCodec[names[2]] ~= nil), names[1])
         assert(codec[names[2]] == nil, names[2])
      end
      assert(nupp.data.utf8.length("A€") == 2)
      return package.loaded.cjson ~= nil, package.loaded["lua-utf8"] ~= nil
   ]=]))
   package.loaded.cjson = nil
   package.loaded["lua-utf8"] = nil
   local ok, jsonLoaded, utf8Loaded = pcall(chunk)
   _G.nupp = previous
   assert(ok, jsonLoaded)
   assert(jsonLoaded and utf8Loaded, "access loads the hidden implementation modules")
end

function M.nativeGlobalMembersLoadOnFirstAccess()
   local bootstrap = native.bootstrap({["native.regex"] = true})
   assert(bootstrap:find("__nuppLoaders.regex=function", 1, true),
      "regex is registered as a lazy global member")
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(bootstrap
      .. " return nupp, rawget(nupp, 'regex')"))
   local namespace, regex = chunk()
   assert(type(namespace) == "table", "nupp is always present")
   assertEq(regex, nil, "registering regex does not load its native dependency")

   local loadedFFI = package.loaded.ffi
   package.loaded.ffi = {
      cdef = function() end,
      load = function() return {} end,
   }
   assert(type(_G.nupp.regex.compile) == "function",
      "reading regex dispatches its registered lazy loader")
   package.loaded.ffi = loadedFFI

   _G.nupp = nil
   loadedFFI = package.loaded.ffi
   package.loaded.ffi = nil
   local pathChunk = assert(loadstring(native.bootstrap({["native.path"] = true})
      .. " return rawget(nupp.io, 'Path')"))
   assertEq(pathChunk(), nil, "registering Path does not load its Rust provider")
   assertEq(package.loaded.ffi, nil, "native FFI initializes only on first access")
   package.loaded.ffi = loadedFFI
   _G.nupp = previous
end

function M.pureAndNativeRuntimeFeaturesComposeAsLua()
   local bootstrap = native.bootstrap({
      ["stdlib.peg"] = true,
      ["native.regex"] = true,
   })
   assert(not bootstrap:find(";;", 1, true),
      "adjacent runtime installers do not emit an empty Lua statement")
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(bootstrap
      .. " return type(nupp.peg.vm), rawget(nupp, 'regex')"))
   local machine, regex = chunk()
   _G.nupp = previous
   assertEq(machine, "function", "the pure PEG runtime is installed")
   assertEq(regex, nil, "the native regex runtime stays lazy")
end

function M.nativeFeatureOverridesAreTriState()
   local automatic = { ["native.regex"] = true, ["native.cjson"] = true }
   local resolved = native.resolve(automatic, {regex = false, lua_utf8 = true})
   assert(not resolved["native.regex"], "false removes a detected feature")
   assert(resolved["native.cjson"], "an absent override remains automatic")
   assert(resolved["native.lua_utf8"], "true adds an undetected feature")

   local external = native.sourceEffects(table.concat({
      "local lpeg = require('lpeg')",
      "local utf8 = require('lua-utf8')",
   }, "\n"), "rock.lua", sharedEnv)
   assert(external["native.lpeg"], "bundled Lua contributes LPeg")
   assert(external["native.lua_utf8"], "bundled Lua contributes lua-utf8")
end

function M.selectOverloadsSeparateCountFromPackSelection()
   assertClean(table.concat({
      "local count: integer = select('#', 1, 'two', true)",
      "local text, flag = select(2, 1, 'two', true)",
      "local s: string = text",
      "local b: boolean = flag",
   }, "\n"))
   assertEq((diagsOf("select('bad', 1, 2)")), "NUPP2125:1")

   assertEq(select("#", 1, "two", true), 3,
      "the count overload matches LuaJIT")
   local text, flag = select(2, 1, "two", true)
   assertEq(text, "two", "the numeric overload starts at its index")
   assertEq(flag, true, "and preserves the rest of the pack")
   assertEq(pcall(select, "bad", 1, 2), false,
      "the rejected selector also fails in LuaJIT")
end

function M.collectgarbageOverloadsTrackResultKinds()
   assertClean(table.concat({
      "local collected: number = collectgarbage()",
      "local size: number = collectgarbage('count')",
      "local oldPause: number = collectgarbage('setpause', 200)",
      "local stepped: boolean = collectgarbage('step', 0)",
      "local running: boolean = collectgarbage('isrunning')",
   }, "\n"))
   assertEq((diagsOf("collectgarbage('unknown')")), "NUPP2125:1")

   assertEq(type(collectgarbage()), "number",
      "the default collection reports a number")
   assertEq(type(collectgarbage("count")), "number",
      "count reports a number")
   assertEq(type(collectgarbage("step", 0)), "boolean",
      "step reports a boolean")
   assertEq(type(collectgarbage("isrunning")), "boolean",
      "isrunning reports a boolean")
   assertEq(pcall(collectgarbage, "unknown"), false,
      "the rejected operation also fails in LuaJIT")
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
   assertClean("local t = table.new(16, 0)\ntable.clear(t)")
   assertEq((diagsOf("table.clear = function() end")), "NUPP2009:1")
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
      "local function render(out: buffer.Buffer): buffer.Buffer borrows out",
      "   return out:putf('%d', 1)",
      "end",
      "local b = buffer.new(64)",
      "local s: string = render(b):tostring()",
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
      "do",
      "   local ptr, len = b:reserve(8)",
      "end",
      "b:commit(0)",
      "do",
      "   local base, size = b:ref()",
      "   local n: integer = #b",
      "   local all: string = b:tostring()",
      "end",
      "local text: string = b:get(1)",
      "b:free()",
      "local encoded: string = buffer.encode(decoded)",
      "local back = buffer.decode(encoded)",
      "local ffi = require('ffi')",
      "b:putcdata(ffi.new('uint8_t[4]'), 4)",
   }, "\n"))
end

function M.stringBufferBorrowBlocksInvalidation()
   assertEq((diagsOf(table.concat({
      "local buffer = require('string.buffer')",
      "local b = buffer.new()",
      "local base, size = b:ref()",
      "b:reset()",
      "print(base, size)",
   }, "\n"))), "NUPP2602:4")
end

-- Pointer/length pairs are rooted by the buffer, then made bounds-carrying before
-- indexing. Ending the pointer scope before commit/skip proves invalidation is safe.
function M.stringBufferPointersBecomeCheckedSpans()
   assertClean(table.concat({
      "local buffer = require('string.buffer')",
      "local spans = require('nupp.span')",
      "local b = buffer.new()",
      "local available: uint64 = 0",
      "do",
      "   local ptr, reserved = b:reserve(64)",
      "   available = reserved",
      "   do",
      "      local writable = spans.write_carray(ptr, reserved as integer)",
      "      writable:set(1, 65)",
      "   end",
      "end",
      "b:commit(1)",
      "local len: uint64 = 0",
      "do",
      "   local base, readable = b:ref()",
      "   len = readable",
      "   local view = spans.from_carray(base, readable as integer)",
      "   local first: integer = view:get(1)",
      "end",
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
   local diags = check.check(result, "consumer.g.nupp", env)
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

function M.moduleUnresolvedIsAnyUnlessStrict()
   local src = "local value: number = require('no.such.module')"
   assertClean(src)
   assertEq((diagsOf(src, {strict = true})), "NUPP2001:1")
   assertClean("local value = require('no.such.module') as number",
      {strict = true})
end

return M
