local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")

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

   assertEq((diagsOf("local location: NuppPath")), "NUPP2101:1",
      "qualified nominals do not leak into the ambient type namespace")

   local lpeg = effectsOf("local parser = require('lpeg')")
   assert(lpeg["native.lpeg"],
      "require('lpeg') records its native effect")
   local re = effectsOf("local parser = require('re')")
   assert(re["stdlib.lpeg.re"],
      "require('re') records its reference-module effect")
   assert(native.expand(re)["native.lpeg"],
      "the re module brings native LPeg")

   local json = effectsOf("local json = require('jsonNative')")
   assert(json["native.json"], "require('jsonNative') records its native effect")

   local process = effectsOf("local process = require('nupp.io.process')")
   assert(process["native.process"], "the public process module selects its provider")
   local expanded = native.expand(process)
   assert(expanded["runtime.suspension"], "the process provider brings its waiting runtime")

   local workers = effectsOf("local workers = require('nupp.workers')")
   assert(workers["native.workers"], "the public workers module selects its host provider")
   local workerEffects = native.expand(workers)
   assert(workerEffects["runtime.suspension"], "workers bring their waiting runtime")

   local http = effectsOf("local http = require('nupp.io.http')")
   assert(http["native.http"], "the public HTTP module selects its provider")
   expanded = native.expand(http)
   assert(expanded["runtime.suspension"], "HTTP brings its waiting runtime")
   assert(expanded["native.uri"], "HTTP brings the URI provider")
   assert(expanded["stdlib.io"], "HTTP brings buffers and stream contracts")

   local utf8 = effectsOf("local utf8 = require('lua-utf8')")
   assert(utf8["native.lua_utf8"],
      "require('lua-utf8') records its native effect")

   local shadowed = effectsOf(table.concat({
      "local nupp = {data = {sha256 = function() end}}",
      "nupp.data.sha256()",
   }, "\n"))
   assert(not shadowed["native.sha256"], "a local nupp is not the global facility")

   -- Same shadow, through a qualified declaration nested deeper
   -- (nupp.io.Path.new) rather than an ordinary field (nupp.data.sha256) --
   -- the qualified-declaration shortcut in dotIndex used to trust the path
   -- text alone and ignore the shadow entirely.
   local shadowedIO = effectsOf(table.concat({
      "local nupp = {io = {Path = {new = function() end}}}",
      "nupp.io.Path.new()",
   }, "\n"))
   assert(not shadowedIO["native.path"], "a local nupp.io is not the global facility")

   local shadowedRequire = effectsOf(table.concat({
      "local require = function(_) return {} end",
      "require('lpeg')",
   }, "\n"))
   assert(not shadowedRequire["native.lpeg"],
      "a local require is not the native module loader")

   local expected = {
      ["nupp.data.json.encode({answer = 42})"] = "native.json",
      ["nupp.data.json.pull('{}', {answer = true})"] = "native.json",
      ["nupp.data.utf8.length('hello')"] = "native.lua_utf8",
      ["nupp.io.newBuffer('hello')"] = "stdlib.io",
      ["nupp.math.lerp(10, 20, 0.25)"] = "stdlib.math",
      ["nupp.math.vec2.length(3, 4)"] = "stdlib.math",
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
      "local newPath: function(first: string, ...: string): nupp.io.Path = nupp.io.Path.new",
      "local components: nupp.io.URI.Components = nil as any",
      "local newURI: function(value: string | nupp.io.URI.Components): (nupp.io.URI?, string?) = nupp.io.URI.new",
      "local uri: nupp.io.URI? = newURI(components)",
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

function M.processViewsSatisfyTheSharedContracts()
   assertClean(table.concat({
      "local process = require('nupp.io.process')",
      "local child, spawnReason = process.new({args = {'true'}})",
      "local running = assert(child, spawnReason)",
      "print(running.pid)",
   }, "\n"))
   assertClean(table.concat({
      "local process = require('nupp.io.process')",
      "local child = nil as process.Process",
      "local input = child.stdin as process.Writer",
      "local output = child.stdout as process.Reader",
      "local function useReader(borrows value: nupp.io.Reader) value:read(1) end",
      "local function useWriter(borrows value: nupp.io.Writer) value:write('x') end",
      "local reader = process.asReader(output)",
      "local writer = process.asWriter(input)",
      "useReader(reader)",
      "useWriter(writer)",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "local process = require('nupp.io.process')",
      "local child = nil as process.Process",
      "local output = child.stdout as process.Reader",
      "local leaked: nupp.io.Reader? = nil",
      "leaked = process.asReader(output)",
   }, "\n"))), "NUPP2608:5", "a view cannot escape its borrowed process stream")
   assertEq((diagsOf(table.concat({
      "local process = require('nupp.io.process')",
      "local impossible: process.ReaderView = nil as any",
   }, "\n"))), "NUPP2101:2", "the view constructor is not part of the public surface")
end

function M.processSurfaceIsBundledOutsideThisCheckout()
   local isolated = envMod.new(os.tmpname() .. "-nupp-process-surface")
   local source = table.concat({
      "local process = require('nupp.io.process')",
      "local child = process.new({args = {'true'}})",
      "assert(child:isRunning() or not child:isRunning())",
   }, "\n")
   local result = parser.parse(source, "outside.g.nupp")
   assertEq(#result.errors, 0, "the external consumer parses")
   local diags = check.check(result, "outside.g.nupp", isolated)
   assertEq(#diags, 0, "the shipped process source supplies its typed surface")
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

function M.generatedBootstrapFollowsWhatCodegenEmits()
   local source = table.concat({
      "if false then",
      "    print(nupp.data.sha256('unreachable'))",
      "else",
      "    print(nupp.data.uuid4())",
      "end",
   }, "\n")
   local result = parser.parse(source, "generated-runtime-features")
   assertEq(#result.errors, 0, "generated-runtime-features source parses")
   check.check(result, "generated-runtime-features", sharedEnv)
   assert(result.effects["native.sha256"] and result.effects["native.uuid"],
      "checking retains the complete source-level feature inventory")
   optimize.run(result, {level = 1})

   local code, diagnostics, _, emitted = gen.generate(result, "generated-runtime-features")
   assertEq(#diagnostics, 0, "the optimized feature fragment generates")
   assert(not emitted["native.sha256"] and emitted["native.uuid"],
      "generation reports only features whose consumers it wrote")
   assert(not code:find("nuppSha256", 1, true),
      "the first line omits the dead SHA-256 installer")
   assert(code:find("nuppUuid4", 1, true),
      "the first line retains the live UUID installer")
end

function M.compilerProvidedPureLibraries()
   local bootstrap = stdlib.bootstrap({
      ["stdlib.io"] = true,
      ["stdlib.math"] = true,
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
      -- Hashing is two ordinary modules rather than something the bootstrap
      -- installs, so these are required rather than read off the ambient table.
      local fnv1a64 = require("nupp.data.fnv1a64")
      local crc32 = require("nupp.data.crc32")
      assert(fnv1a64("hello") == "a430d84680aabd0b")
      assert(crc32("123456789") == 3421780262)
      assert(not pcall(crc32, "bytes", 4294967296))
   ]]))
   local ok, problem = pcall(chunk)
   _G.nupp = previous
   assert(ok, problem)
end

-- Bitsets are an ordinary module, so `nupp.data.bitset` in source is a qualified
-- module path rather than a field an installer publishes. Nothing is installed to
-- reach, and the module is what both spellings arrive at.
function M.bitsetsReachTheCheckedModule()
   local chunk = assert(loadstring([[
      local bitset = require("nupp.data.bitset")
      local set = bitset.create(64)
      assert(set:count() == 0)
      set:set(5)
      set:setRange(40, 70)
      assert(set:count() == 32)
      assert(set:get(5) and set:get(70) and not set:get(71))

      local other = bitset.create(64)
      other:setRange(0, 50)
      set:andWith(other)
      assert(set:count() == 12)
      assert(set:nextSetBit(0) == 5)

      local ffi = require("ffi")
      local target = ffi.new("int32_t[?]", 4)
      local written, resume = set:positionsInto(target, 4, 0)
      assert(written == 4, "positionsInto filled the destination")
      assert(target[0] == 5, "first position")
      assert(resume == 43, "and reported where to carry on")

      assert(bitset.WORD_BITS == 32)
      assert(set:wordAt(0) == 32)
      assert(bitset.create(8) ~= bitset.create(8))
   ]]))
   local ok, problem = pcall(chunk)
   assert(ok, problem)
end

function M.openFilesAreOwnersOverTheSharedReaderContract()
   local gen = require("nupp.compiler.gen")

   assertClean(table.concat({
      "local files = nupp.io.files",
      "do",
      "    local file = files.open('input.txt') as nupp.io.Files.File",
      "    local reader = file:newReader()",
      "    local writer = file:newWriter()",
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
   assertClean("local paths: {string} = assert(nupp.io.files.glob('src/**/*.nupp'))")
   assertEq((diagsOf("nupp.io.files.info(42)")), "NUPP2006:1")
   -- An owner nobody binds has nowhere to be cleaned up from, and `open` is the
   -- first prelude member for which that is true.
   assertEq((diagsOf("nupp.io.files.open('x')")), "NUPP2605:1")
   assertEq((diagsOf("nupp.io.files.createTemporaryFile()")), "NUPP2605:1")

   -- The prelude gives `open` and the temporaries owning results, so a binding the
   -- program drops is dropped where it goes out of scope rather than leaking.
   local source = table.concat({
      "local file = nupp.io.files.open('input.txt') as nupp.io.Files.File",
      "print(file)",
   }, "\n")
   local parsed = parser.parse(source, "owned.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors in the ownership fragment")
   sharedEnv.loaded = {}
   check.check(parsed, "owned.g.nupp", sharedEnv)
   local code = gen.generate(parsed, "owned")
   assert(code:find(":close()", 1, true),
      "an open file is dropped at the end of its scope")
end

function M.bufferAppendsInAmortizedConstantTime()
   local bootstrap = stdlib.bootstrap({["stdlib.io"] = true})
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

-- UTF-8 is a module rather than a lazily installed field, so what used to be proved
-- about the ambient table is proved about the require: the rock is loaded by loading
-- the module, not by touching a name on `nupp`.
function M.theUtf8ModuleOpensItsRockOnRequire()
   local loadedRock = package.loaded["lua-utf8"]
   local loadedModule = package.loaded["nupp.data.utf8"]
   package.loaded["lua-utf8"] = nil
   package.loaded["nupp.data.utf8"] = nil
   local ok, problem = pcall(function()
      local utf8 = require("nupp.data.utf8")
      assert(package.loaded["lua-utf8"] ~= nil, "requiring the module loaded the rock")
      assert(utf8.length("A\226\130\172") == 2)
      assert(utf8.isValid("A\226\130\172"))
      assert(not utf8.isValid("\255"))
      assert(utf8.encode(8364) == "\226\130\172")
      local codepoint, nextAt = utf8.decodeAt("A\226\130\172", 2)
      assert(codepoint == 8364 and nextAt == 5, "decodes the second codepoint")
      assert(utf8.truncate("A\226\130\172", 3) == "A", "never cuts through a codepoint")
   end)
   package.loaded["lua-utf8"] = package.loaded["lua-utf8"] or loadedRock
   package.loaded["nupp.data.utf8"] = package.loaded["nupp.data.utf8"] or loadedModule
   assert(ok, problem)
end

-- JSON is a module rather than a lazily installed field, so what used to be proved
-- about the ambient table is proved about the require: the host boundary is opened
-- by loading the module, not by touching a name on `nupp`.
function M.theJsonModuleOpensItsHostOnRequire()
   local loadedJson = package.loaded.jsonNative
   local loadedModule = package.loaded["nupp.data.json"]
   package.loaded.jsonNative = nil
   package.loaded["nupp.data.json"] = nil
   local ok, problem = pcall(function()
      local json = require("nupp.data.json")
      assert(package.loaded.jsonNative ~= nil, "requiring the module opened the host")
      assert(json.encode({answer = 42}):find('"answer":42', 1, true))
      assert(json.encode(json.EMPTY_ARRAY) == "[]")
      assert(json.encode(json.EMPTY_OBJECT) == "{}")
      assert(json.encode(json.asArray({})) == "[]")
      assert(json.decode("[1,null,2]")[2] == 2)
      assert(json.decode("null", json.NULL) == json.NULL)
   end)
   package.loaded.jsonNative = package.loaded.jsonNative or loadedJson
   package.loaded["nupp.data.json"] = package.loaded["nupp.data.json"] or loadedModule
   assert(ok, problem)
end

function M.nativeGlobalMembersLoadOnFirstAccess()
   local bootstrap = stdlib.bootstrap({["native.path"] = true})
   assert(bootstrap:find('__nuppLazy(__nuppIO,"Path"', 1, true),
      "Path is registered as a lazy global member")
   local previous = rawget(_G, "nupp")
   local loadedFFI = package.loaded.ffi
   _G.nupp = nil
   package.loaded.ffi = nil
   local chunk = assert(loadstring(bootstrap
      .. " return nupp, rawget(nupp.io, 'Path')"))
   local namespace, Path = chunk()
   assert(type(namespace) == "table", "nupp is always present")
   assertEq(Path, nil, "registering Path does not load its Rust provider")
   assertEq(package.loaded.ffi, nil, "native FFI initializes only on first access")

   package.loaded.ffi = {
      cdef = function() end,
      load = function() return {} end,
   }
   assert(type(_G.nupp.io.Path.new) == "function",
      "reading Path dispatches its registered lazy loader")
   package.loaded.ffi = loadedFFI
   _G.nupp = previous
end

function M.nativeBootstrapDeclaresOnlyTheSelectedAbi()
   local uuid = stdlib.bootstrap({["native.uuid"] = true})
   assert(uuid:find("nuppUuid4", 1, true), "UUID declares its own ABI")
   for _, absent in ipairs({
      "nuppSha256", "nuppPathJoin", "nuppUriParse", "NuppFileInfo",
      "nuppProcessSpawnBegin", "nuppBytesData",
   }) do
      assert(not uuid:find(absent, 1, true),
         "UUID omits unrelated native declaration " .. absent)
   end

   local files = stdlib.bootstrap({["native.files"] = true})
   assert(files:find("NuppFileInfo", 1, true), "files declares its own ABI")
   assert(files:find("nuppBytesData", 1, true),
      "files retains the byte-return dependency it uses")
   assert(not files:find("nuppProcessSpawnBegin", 1, true),
      "files omits the process ABI")
   assert(not files:find("nuppPathJoin", 1, true),
      "files omits the path ABI")

   local process = stdlib.bootstrap({["native.process"] = true})
   assert(process:find("nuppProcessSpawnBegin", 1, true),
      "process declares its own ABI")
   assert(not process:find("nuppBytesData", 1, true),
      "process omits the unused byte-return ABI and helper")
   assert(not process:find("NuppFileInfo", 1, true),
      "process omits the files ABI")

   local http = stdlib.bootstrap({["native.http"] = true})
   assert(http:find("typedef struct NuppUri NuppUri", 1, true),
      "HTTP retains the opaque URI dependency in its request ABI")
   assert(http:find("nuppHttpClientCreate", 1, true),
      "HTTP declares its own ABI")
   assert(not http:find("nuppUriParse", 1, true),
      "HTTP omits the URI implementation ABI")
   assert(not http:find("nuppProcessSpawnBegin", 1, true),
      "HTTP omits the process ABI")
end

function M.pureAndNativeRuntimeFeaturesComposeAsLua()
   local bootstrap = stdlib.bootstrap({
      ["stdlib.peg"] = true,
      ["native.path"] = true,
   })
   assert(not bootstrap:find(";;", 1, true),
      "adjacent runtime installers do not emit an empty Lua statement")
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(bootstrap
      .. " return type(nupp.peg), next(nupp.peg), rawget(nupp.io, 'Path')"))
   local pegType, pegField, path = chunk()
   _G.nupp = previous
   assertEq(pegType, "table", "the pure PEG runtime is installed")
   assertEq(pegField, nil, "internal PEG helpers are not public fields")
   assertEq(path, nil, "the native Path runtime stays lazy")
end

function M.lpegAndReUseTheNativeRuntime()
   local previousNupp = rawget(_G, "nupp")
   local previousLoaded = package.loaded.lpeg
   local previousPreload = package.preload.lpeg
   local previousReLoaded = package.loaded.re
   local previousRePreload = package.preload.re
   package.loaded.lpeg, package.loaded.re = nil, nil
   package.preload.lpeg, package.preload.re = nil, nil
   _G.nupp = nil
   local source = stdlib.bootstrap({["stdlib.lpeg.re"] = true}) .. [=[
local lpeg = require("lpeg")
local P, R, V = lpeg.P, lpeg.R, lpeg.V
local C, Cc, Cp, Ct, Cg, Cb, Cs =
    lpeg.C, lpeg.Cc, lpeg.Cp, lpeg.Ct, lpeg.Cg, lpeg.Cb, lpeg.Cs
local identifier = C((R("az", "AZ") + P("_"))
    * (R("az", "AZ", "09") + P("_"))^0)
local fields = Ct(C(R("09")^1) * (P(",") * C(R("09")^1))^0)
local same = Cg(C(R("az")^1), "word") * P(":") * Cb("word")
local grammar = P({"value", value = P("x") + P("(") * V("value") * P(")")})
local substitution = Cs((C(R("09")^1) / "[%0]" + P(1))^0)
local positions = Ct(Cp() * Cc("tag") * C(P("ok")) * Cp())
local re = require("re")
return identifier:match("name9"), fields:match("1,22,333"),
    same:match("echo:rest"), lpeg.match(grammar * -P(1), "((x))"),
    substitution:match("a12b"), positions:match("ok"), lpeg.version,
    re.match("item:42", "{[a-z]+} ':' {[0-9]+} !.")
]=]
   local identifier, fields, same, recursive, substitution, positions, version,
      reFirst, reSecond = assert(loadstring(source))()
   package.loaded.lpeg = previousLoaded
   package.preload.lpeg = previousPreload
   package.loaded.re = previousReLoaded
   package.preload.re = previousRePreload
   _G.nupp = previousNupp
   assertEq(identifier, "name9", "LPeg facade substring capture")
   assertEq(fields[3], "333", "LPeg facade table capture")
   assertEq(same, "echo", "LPeg facade back capture")
   assertEq(recursive, 6, "LPeg facade recursive grammar")
   assertEq(substitution, "a[12]b", "LPeg facade substitution")
   assertEq(positions[1], 1, "LPeg facade first position")
   assertEq(positions[4], 3, "LPeg facade final position")
   assertEq(version, "LPeg 1.1.0", "LPeg facade version field")
   assertEq(reFirst, "item", "bundled re first capture")
   assertEq(reSecond, "42", "bundled re second capture")
end

function M.nativeFeatureOverridesAreTriState()
   local automatic = { ["native.uri"] = true, ["native.json"] = true }
   local resolved = native.resolve(automatic, {uri = false, lua_utf8 = true})
   assert(not resolved["native.uri"], "false removes a detected feature")
   assert(resolved["native.json"], "an absent override remains automatic")
   assert(resolved["native.lua_utf8"], "true adds an undetected feature")

   local external = native.sourceEffects(table.concat({
      "local lpeg = require('lpeg')",
      "local utf8 = require('lua-utf8')",
   }, "\n"), "rock.lua", sharedEnv)
   assert(external["native.lpeg"],
      "bundled Lua contributes native LPeg")
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
      "local function render(out: buffer.Buffer): buffer.Buffer borrows (out)",
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
   }, "\n"))), "NUPP2607:4")
end

-- Pointer/length pairs are rooted by the buffer, then made bounds-carrying before
-- indexing. Ending the pointer scope before commit/skip proves invalidation is safe.
function M.stringBufferPointersBecomeCheckedSpans()
   assertClean(table.concat({
      "local buffer = require('string.buffer')",
      "local spans = require('nupp.mem.span')",
      "local b = buffer.new()",
      "local available: uint64 = 0",
      "do",
      "   local ptr, reserved = b:reserve(64)",
      "   available = reserved",
      "   do",
      "      local writable = spans.writeCarray(ptr, reserved as integer)",
      "      writable[1] = 65",
      "      drop writable",
      "   end",
      "end",
      "b:commit(1)",
      "local len: uint64 = 0",
      "do",
      "   local base, readable = b:ref()",
      "   len = readable",
      "   local view = spans.fromCarray(base, readable as integer)",
      "   local first: integer = view[1]",
      "end",
      "b:skip(len)",
      "local total: uint64 = available + len",
   }, "\n"))
end

function M.profileSessionProtocolPreservesItsReportType()
   assertClean(table.concat({
      "local profile = require('nupp.profile')",
      "local function finish<S is profile.Session>(session: S): S.Report",
      "   return session:stop()",
      "end",
      "local sample: profile.SampleReport = finish(profile.sample())",
      "local trace: profile.TraceReport = finish(profile.trace())",
   }, "\n"))

   assertEq((diagsOf(table.concat({
      "local profile = require('nupp.profile')",
      "local function finish<S is profile.Session>(session: S): S.Report",
      "   return session:stop()",
      "end",
      "local wrong: profile.TraceReport = finish(profile.sample())",
   }, "\n"))), "NUPP2001:5")
end

function M.jsonNativeModule()
   assertClean(table.concat({
      "local json = require('jsonNative')",
      "local text: string = json.encode({1, 2, 3})",
      "local value = json.decode(text)",
      "local stream = json.writer()",
      "local array: table = json.asArray({})",
   }, "\n"))
   -- decode yields any, so it flows anywhere
   assertClean(table.concat({
      "local json = require('jsonNative')",
      "local n: number = json.decode('1')",
   }, "\n"))
   -- encode returns a string, not a number
   assertEq((diagsOf(table.concat({
      "local json = require('jsonNative')",
      "local n: number = json.encode({})",
   }, "\n"))), "NUPP2001:2")
   -- decode takes text
   assertEq((diagsOf(table.concat({
      "local json = require('jsonNative')",
      "json.decode(42)",
   }, "\n"))), "NUPP2006:2")
   -- misspelled members are caught against the declared surface
   assertEq((diagsOf(table.concat({
      "local json = require('jsonNative')",
      "json.encde({})",
   }, "\n"))), "NUPP2004:2")
end

function M.jsonNativeConstantsAndWriter()
   assertClean(table.concat({
      "local json = require('jsonNative')",
      "local nul: any = json.NULL",
      "local array: table = json.EMPTY_ARRAY",
      "local object: table = json.EMPTY_OBJECT",
      "local writer = json.writer(nul)",
      "local text: string = writer:startArray():write(1):close():finish()",
   }, "\n"))
end

function M.projectFilesShadowBundledDeclarations()
   -- a project shipping its own jsonNative description wins over the bundled one
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local f = assert(io.open(dir .. "/jsonNative.d.nupp", "wb"))
   f:write("local encode: function(v: any): integer\nreturn {encode = encode}\n")
   f:close()
   local env = envMod.new(dir)
   local result = parser.parse(
      "local json = require('jsonNative')\nlocal n: integer = json.encode({})",
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
