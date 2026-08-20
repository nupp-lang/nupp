local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local backends = require("nupp.compiler.backends")
local runtimeBackend = require("nupp.runtime.backend")
local jsonSeam = require("nupp.runtime.seam.json")
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

function M.checkerRecordsTheResolvedDialect()
   local default = parser.parse("return 42\n", "default.nupp")
   check.check(default, "default.nupp", sharedEnv)
   assertEq(default.dialect, "luajit", "the checker defaults to the native dialect")

   local portable = parser.parse("return 42\n", "portable.nupp")
   check.check(portable, "portable.nupp", sharedEnv, {dialect = "lua51"})
   assertEq(portable.dialect, "lua51", "the checker records the selected dialect")
end

local function jsonResolution(backendModule)
   return {
      modules = {{name = "portable", module = backendModule}},
      seams = {['data.json'] = {module = backendModule}},
      byEffect = {['native.json'] = backendModule},
   }
end

function M.backendDescriptorsAreStaticCheckedMetadata()
   local parsed = parser.parse([[
module portablebackend

const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")

error("descriptor extraction executed the backend")
export = Backend.new("portable", {
   JSON.seam("portable_json"),
})
]], "portablebackend.nupp")
   assertEq(#parsed.errors, 0, "backend descriptor source parses")
   sharedEnv.loaded = {}
   local descriptorDiags = check.check(parsed, "portablebackend.nupp", sharedEnv)
   assertEq(#descriptorDiags, 0, "backend descriptor source checks")
   local descriptor, problem = backends.inspect(parsed.root, "portablebackend")
   assert(descriptor, problem)
   assertEq(descriptor.name, "portable", "the constant backend name is recorded")
   assertEq(descriptor.module, "portablebackend", "the selected module identity is recorded")
   assertEq(descriptor.seams[1].name, "data.json", "the seam identity is recorded")
   assertEq(descriptor.seams[1].version, 1, "the contract version is recorded")
   assertEq(descriptor.seams[1].runtimeModule, "portable_json",
      "the exact runtime dependency is static metadata")

   local second = assert(backends.inspect(parsed.root, "otherbackend"))
   local selectedByPath = {
      portablebackend = descriptor,
      otherbackend = second,
   }
   local resolved, conflict = backends.resolve({
      modulePath = function(name) return name .. ".nupp" end,
      checkFile = function(path)
         return {backend = selectedByPath[path:match("^(.*)%.nupp$")]}
      end,
   }, {"portablebackend", "otherbackend"})
   assert(not resolved and tostring(conflict):find(
      "backend seam conflict for data.json", 1, true),
      "two selected backends cannot silently compete: " .. tostring(conflict))

   local dynamic = parser.parse([[
module dynamicbackend
const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")
local name = "portable"
export = Backend.new(name, {JSON.seam("portable_json")})
]], "dynamicbackend.nupp")
   sharedEnv.loaded = {}
   check.check(dynamic, "dynamicbackend.nupp", sharedEnv)
   local missing, dynamicProblem = backends.inspect(dynamic.root, "dynamicbackend")
   assert(not missing and tostring(dynamicProblem):find("constant name", 1, true),
      "a descriptor cannot depend on executing a binding: " .. tostring(dynamicProblem))

   local shadowed = parser.parse([[
module shadowedbackend
local function require(name: string): any
   return name
end
const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")
export = Backend.new("portable", {JSON.seam("portable_json")})
]], "shadowedbackend.nupp")
   sharedEnv.loaded = {}
   check.check(shadowed, "shadowedbackend.nupp", sharedEnv)
   local spoofed = backends.inspect(shadowed.root, "shadowedbackend")
   assert(not spoofed, "a shadowed function named require is not static module metadata")
end

function M.runtimeJsonProviderIsOptInLazyAndChecked()
   local selected = "fixtures.portable_json"
   local backendModule = "fixtures.portable_backend"
   local resolution = jsonResolution(backendModule)
   local bootstrap = backends.bootstrap({["native.json"] = true}, resolution)
   assertEq(bootstrap, ('(require(%q)):install();'):format(backendModule),
      "generated output contains composition only, not adapter source")
   assertEq(backends.bootstrap({["native.json"] = true}, nil), "",
      "the default native path emits no backend bootstrap")
   assertEq(backends.bootstrap({}, resolution), "",
      "an unreachable seam emits no backend bootstrap")

   local oldRegistry = rawget(_G, "__nuppRuntimeProviders")
   local oldNative = package.loaded.jsonNative
   local oldNativePreload = package.preload.jsonNative
   local oldProvider = package.loaded[selected]
   local oldProviderPreload = package.preload[selected]
   local oldBackend = package.loaded[backendModule]
   local oldBackendPreload = package.preload[backendModule]
   local oldSuite = package.loaded[jsonSeam.suiteModuleName]
   _G.__nuppRuntimeProviders = nil
   package.loaded.jsonNative = nil
   package.preload.jsonNative = nil
   package.loaded[selected] = nil
   package.loaded[backendModule] = nil
   package.loaded[jsonSeam.suiteModuleName] = nil
   local sentinel = {}
   package.preload[selected] = function()
      local function same(value) return value end
      return {
         NULL = sentinel,
         EMPTY_ARRAY = {},
         EMPTY_OBJECT = {},
         arrayOf = same,
         asArray = same,
         asObject = same,
         decode = same,
         encode = same,
         pull = same,
         serialize = same,
         writer = same,
      }
   end
   package.preload[backendModule] = function()
      return jsonSeam.backend(selected)
   end

   local ok, problem = pcall(function()
      assert(loadstring(bootstrap))()
      assertEq(package.loaded[selected], nil, "installing the adapter is lazy")
      local json = require("jsonNative")
      assertEq(package.loaded[selected], json, "the boundary loads exactly the selected module")
      assertEq(json.NULL, sentinel, "the compatible provider is returned unchanged")
      assertEq(package.loaded[jsonSeam.suiteModuleName], nil,
         "installing and using a seam does not load its conformance suite")
   end)

   _G.__nuppRuntimeProviders = oldRegistry
   package.loaded.jsonNative = oldNative
   package.preload.jsonNative = oldNativePreload
   package.loaded[selected] = oldProvider
   package.preload[selected] = oldProviderPreload
   package.loaded[backendModule] = oldBackend
   package.preload[backendModule] = oldBackendPreload
   package.loaded[jsonSeam.suiteModuleName] = oldSuite
   assert(ok, problem)
end

function M.runtimeJsonSeamExposesItsOwnConformanceSuite()
   local conforming = "fixtures.conforming_json_backend"
   local broken = "fixtures.broken_json_backend"
   local oldConforming = package.loaded[conforming]
   local oldConformingPreload = package.preload[conforming]
   local oldBroken = package.loaded[broken]
   local oldBrokenPreload = package.preload[broken]
   local nativeJson = require("jsonNative")
   package.loaded[conforming] = nil
   package.loaded[broken] = nil
   package.preload[conforming] = function() return nativeJson end
   package.preload[broken] = function()
      local adapter = {}
      for name, value in pairs(nativeJson) do adapter[name] = value end
      adapter.encode = function() return 42 end
      return adapter
   end

   local ok, problem = pcall(function()
      local selected = jsonSeam.backend(conforming)
      assertEq(selected.name, "json:" .. conforming, "the backend has a stable name")
      assertEq(#selected.seams, 1, "the backend exposes its seams")
      assertEq(selected.seams[1].name, "data.json", "the JSON seam is named")
      assertEq(selected.seams[1].version, 1, "the JSON contract is versioned")
      local unique, duplicate = pcall(runtimeBackend.new, "duplicate", {
         selected.seams[1],
         selected.seams[1],
      })
      assert(not unique and tostring(duplicate):find("more than once", 1, true),
         "a backend cannot provide one seam twice")
      local nonempty, emptyProblem = pcall(runtimeBackend.new, "empty", {})
      assert(not nonempty and tostring(emptyProblem):find("at least one seam", 1, true),
         "a backend must expose at least one seam")
      local passed, why = selected:test()
      assert(passed, "the native adapter passes the same public suite: " .. tostring(why))

      local rejected, rejection = jsonSeam.backend(broken):test()
      assert(not rejected, "behavior, not just member names, is checked")
      assert(tostring(rejection):find("data.json contract 1", 1, true),
         "a failure identifies the seam contract: " .. tostring(rejection))
   end)

   package.loaded[conforming] = oldConforming
   package.preload[conforming] = oldConformingPreload
   package.loaded[broken] = oldBroken
   package.preload[broken] = oldBrokenPreload
   assert(ok, problem)
end

function M.missingRuntimeJsonProviderNamesTheDependency()
   local selected = "fixtures.provider_that_is_missing"
   local backendModule = "fixtures.missing_provider_backend"
   local oldRegistry = rawget(_G, "__nuppRuntimeProviders")
   local oldNative = package.loaded.jsonNative
   local oldNativePreload = package.preload.jsonNative
   local oldProvider = package.loaded[selected]
   local oldProviderPreload = package.preload[selected]
   local oldBackend = package.loaded[backendModule]
   local oldBackendPreload = package.preload[backendModule]
   _G.__nuppRuntimeProviders = nil
   package.loaded.jsonNative = nil
   package.preload.jsonNative = nil
   package.loaded[selected] = nil
   package.preload[selected] = nil
   package.loaded[backendModule] = nil
   package.preload[backendModule] = function()
      return jsonSeam.backend(selected)
   end

   local installed, installProblem = pcall(assert(loadstring(backends.bootstrap(
      {["native.json"] = true},
      jsonResolution(backendModule)
   ))))
   local ok, problem = pcall(function()
      local json = require("jsonNative")
      return json.NULL
   end)

   _G.__nuppRuntimeProviders = oldRegistry
   package.loaded.jsonNative = oldNative
   package.preload.jsonNative = oldNativePreload
   package.loaded[selected] = oldProvider
   package.preload[selected] = oldProviderPreload
   package.loaded[backendModule] = oldBackend
   package.preload[backendModule] = oldBackendPreload
   assert(installed, installProblem)
   assert(not ok and tostring(problem):find(selected, 1, true),
      "the runtime error names the absent provider: " .. tostring(problem))
   assert(tostring(problem):find("data.json", 1, true),
      "the runtime error names the standard contract: " .. tostring(problem))
end

function M.selectedRuntimeProviderSuppressesOnlyItsNativeFeature()
   local effects = {['native.json'] = true, ['native.sha256'] = true}
   backends.withoutNative(effects, jsonResolution("fixtures.portable_backend"))
   assert(not effects['native.json'], "the selected JSON adapter replaces native JSON")
   assert(effects['native.sha256'], "unrelated native features remain selected")
end

function M.generatedBackendSelectionDoesNotTouchDefaultOutput()
   local source = "local json = require('nupp.data.json')\nreturn json.encode({answer = 42})"
   local result = parser.parse(source, "runtime-provider.g.nupp")
   assertEq(#result.errors, 0, "provider source parses")
   check.check(result, "runtime-provider.g.nupp", sharedEnv)
   local ordinary, ordinaryDiags = gen.generate(result, "runtime-provider.g.nupp")
   local explicitNil, nilDiags = gen.generate(result, "runtime-provider.g.nupp", nil, nil, nil)
   local portable, portableDiags = gen.generate(
      result,
      "runtime-provider.g.nupp",
      nil,
      nil,
      jsonResolution("fixtures.portable_backend")
   )
   assertEq(#ordinaryDiags, 0, "ordinary source generates")
   assertEq(#nilDiags, 0, "explicit native selection generates")
   assertEq(#portableDiags, 0, "portable selection generates")
   assertEq(explicitNil, ordinary, "an absent provider is byte-identical")
   assert(not ordinary:find("__nuppRuntimeProviders", 1, true),
      "native output contains no compatibility registry")
   assert(portable:find("fixtures.portable_backend", 1, true),
      "portable output names the selected backend")
end

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

   -- Same shadow, one segment deeper: the qualified-path shortcut used to trust the
   -- path text alone and ignore the shadow entirely.
   local shadowedIO = effectsOf(table.concat({
      "local nupp = {io = {path = {separator = function() end}}}",
      "nupp.io.path.separator()",
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
      ["nupp.io.path.separator()"] = "native.path",
      ["nupp.io.uri.newURI('https://example.com')"] = "native.uri",
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
      "const {Path} = require('nupp.io.path')",
      "local source: nupp.io.path.Path = nupp.io.path.newPath('src', 'main.nupp')",
      "local components: nupp.io.uri.Components = nil as any",
      "local URIOf: function(",
      "    value: string | nupp.io.uri.Components",
      "): (nupp.io.uri.URI?, string?) = nupp.io.uri.newURI",
      "local address: nupp.io.uri.URI? = URIOf(components)",
      "print(source, address)",
   }, "\n"))

   -- A native provider is selected only when the relevant member is reached through
   -- the data module.
   local aliased = effectsOf(table.concat({
      "const data = require('nupp.data')",
      "data.sha256('hello')",
   }, "\n"))
   assert(aliased["native.sha256"], "requiring a facility records its feature")
   assert(not aliased["native.uuid"], "equal function signatures do not share effects")

   local namespaceOnly = effectsOf("local data = nupp.data")
   assert(next(namespaceOnly) == nil, "reaching a namespace alone has no effect")
end

function M.processViewsSatisfyTheSharedContracts()
   assertClean(table.concat({
      "local process = require('nupp.io.process')",
      "local child = new process.Process({args = {'true'}} as process.Options)",
      "local running = child",
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
      "local child = new process.Process({args = {'true'}} as process.Options)",
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
   -- Both facilities are members of one module. The live UUID keeps that module,
   -- while the folded branch no longer reaches the SHA member.
   assert(not code:find("sha256", 1, true),
      "the dead SHA-256 branch loses its member access")
   assert(code:find("uuid4", 1, true),
      "the live UUID branch keeps its member access")
end

-- What the bootstrap still installs, which is the maths and nothing else: buffers,
-- hashes and the rest are modules a program requires.
function M.compilerProvidedPureLibraries()
   local bootstrap = stdlib.bootstrap({["stdlib.math"] = true,})
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local chunk = assert(loadstring(bootstrap .. [[
      local io = require("nupp.io")
      local buffer = io.newBuffer("hello")
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
      -- Hashing lives directly on the data module.
      local data = require("nupp.data")
      assert(data.fnv1a64("hello") == "a430d84680aabd0b")
      assert(data.crc32("123456789") == 3421780262)
      assert(not pcall(data.crc32, "bytes", 4294967296))
      assert(data.sha256("abc") ==
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
      assert(data.uuid4():sub(15, 15) == "4")
      assert(data.uuid7():sub(15, 15) == "7")
   ]]))
   local ok, problem = pcall(chunk)
   _G.nupp = previous
   assert(ok, problem)
end

-- Bitset is the data module's nominal record. Plain-Lua tests call the constructor
-- implementation that checked `new data.Bitset(...)` lowers to.
function M.bitsetsReachTheCheckedModule()
   local chunk = assert(loadstring([[
      local data = require("nupp.data")
      local function bitset(bits) return data.Bitset.__nuppCtor1(bits) end
      local set = bitset(64)
      assert(set:count() == 0)
      set:set(5)
      set:setRange(40, 70)
      assert(set:count() == 32)
      assert(set:get(5) and set:get(70) and not set:get(71))

      local other = bitset(64)
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

      assert(data.WORD_BITS == 32)
      assert(set:wordAt(0) == 32)
      assert(bitset(8) ~= bitset(8))
   ]]))
   local ok, problem = pcall(chunk)
   assert(ok, problem)
end

function M.openFilesAreOwnersOverTheSharedReaderContract()
   local gen = require("nupp.compiler.gen")

   assertClean(table.concat({
      "const files = require('nupp.io.files')",
      "do",
      "    local file = files.open('input.txt') as nupp.io.files.File",
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
   -- An owner nobody binds has nowhere to be cleaned up from.
   assertEq((diagsOf("nupp.io.files.open('x')")), "NUPP2605:1")
   assertEq((diagsOf("nupp.io.files.createTemporaryFile()")), "NUPP2605:1")

   -- `open` and the temporaries answer owning results, so a binding the program drops
   -- is dropped where it goes out of scope rather than leaking.
   local source = table.concat({
      "local file = nupp.io.files.open('input.txt') as nupp.io.files.File",
      "print(file)",
   }, "\n")
   local parsed = parser.parse(source, "owned.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors in the ownership fragment")
   sharedEnv.loaded = {}
   check.check(parsed, "owned.g.nupp", sharedEnv)
   local code = gen.generate(parsed, "owned")
   -- The terminal belongs to the module that hands the owner out, so scope exit
   -- reaches it through the cleanup registry under that module's key rather than
   -- calling a method the prelude used to publish.
   assert(code:find("nupp.io.files#destroyOwner", 1, true),
      "an open file is dropped at the end of its scope, through its module's terminal")
end

function M.luaFilesAndPublicResourcesUseAffineConstructors()
   assertEq((diagsOf("io.open('input.txt')")), "NUPP2605:1")
   assertEq((diagsOf("io.popen('true')")), "NUPP2605:1")
   assertEq((diagsOf("io.tmpfile()")), "NUPP2605:1")
   assertClean(table.concat({
      "do",
      "    local file = assert(io.open('input.txt'))",
      "    local text: string? = file:read('*a')",
      "end",
   }, "\n"))

   local source = "do\n    local file = assert(io.open('input.txt'))\nend"
   local parsed = parser.parse(source, "lua-file-owner.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors in the Lua file ownership fragment")
   sharedEnv.loaded = {}
   check.check(parsed, "lua-file-owner.g.nupp", sharedEnv)
   local code = gen.generate(parsed, "lua-file-owner")
   assert(code:find("__nuppCloseFile", 1, true),
      "a Lua file is closed automatically at the end of its scope")

   assertClean(table.concat({
      "const http = require('nupp.io.http')",
      "const process = require('nupp.io.process')",
      "do local client = new http.Client() end",
      "do local child = new process.Process({args = {'true'}} as process.Options) end",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "const http = require('nupp.io.http')",
      "http.newClient()",
   }, "\n"))), "NUPP2004:2")
   assertEq((diagsOf(table.concat({
      "const process = require('nupp.io.process')",
      "process.new({args = {'true'}})",
   }, "\n"))), "NUPP2004:2")

   assertClean(table.concat({
      "const path = require('nupp.io.path')",
      "local source: path.Path = path.newPath('src', 'main.nupp')",
      "print(source)",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "const path = require('nupp.io.path')",
      "local value = new path.Path()",
   }, "\n"))), "NUPP2209:2")

   local path = require("nupp.io.path")
   local first = path.newPath("cache", "first")
   assert(rawequal(first, path.newPath("cache", "first")), "path.newPath interns equal path text")
   assert(path.Path.__nuppCtor1 == nil, "Path exposes no generated constructor")
   for index = 1, 1024 do
      path.newPath("cache", tostring(index))
   end
   assert(not rawequal(first, path.newPath("cache", "first")),
      "path.newPath evicts the least recently used path after 1024 entries")

   assertClean(table.concat({
      "const uri = require('nupp.io.uri')",
      "local endpoint: uri.URI = assert(uri.newURI('https://example.com/api'))",
      "print(endpoint)",
   }, "\n"))
   assertEq((diagsOf(table.concat({
      "const uri = require('nupp.io.uri')",
      "local value = new uri.URI()",
   }, "\n"))), "NUPP2209:2")

   local uri = require("nupp.io.uri")
   local firstURI = assert(uri.newURI("https://example.com/cache/first"))
   assert(rawequal(firstURI, assert(uri.newURI("https://example.com/cache/first"))),
      "uri.newURI interns equal normalized URI text")
   assert(uri.URI.__nuppCtor1 == nil, "URI exposes no generated constructor")
   local base = assert(uri.newURI("https://example.com/base"))
   assert(rawequal(base:withPath("/derived"), assert(uri.newURI("https://example.com/derived"))),
      "URI-producing operations share the uri.newURI cache")
   for index = 1, 1024 do
      assert(uri.newURI("https://example.com/cache/" .. tostring(index)))
   end
   assert(not rawequal(firstURI, assert(uri.newURI("https://example.com/cache/first"))),
      "uri.newURI evicts the least recently used URI after 1024 entries")
end

function M.bufferAppendsInAmortizedConstantTime()
   local chunk = assert(loadstring([[
      local io = require("nupp.io")
      local buffer = io.newBuffer()
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

-- Nothing native is a lazily installed field on an ambient table any more. A facility
-- is a module, so what used to be proved about the lazy loader is proved about the
-- require: naming the feature stages its provider, and nothing opens it until the
-- module is loaded.
function M.nativeProvidersOpenOnlyWhenTheirModuleLoads()
   local bootstrap = stdlib.bootstrap({["native.path"] = true})
   assert(not bootstrap:find("__nuppIO", 1, true),
      "the bootstrap no longer reserves an io namespace")
   assert(not bootstrap:find("nuppPathJoin", 1, true),
      "the path ABI belongs to the module that calls it")

   local loadedFFI = package.loaded.ffi
   local loadedPath = package.loaded["nupp.io.pathimpl"]
   package.loaded["nupp.io.pathimpl"] = nil
   local chunk = assert(loadstring(bootstrap .. " return package.loaded.ffi"))
   assertEq(chunk(), loadedFFI, "installing the bootstrap opens no provider")
   package.loaded["nupp.io.pathimpl"] = loadedPath
end

-- Two facilities still reach C through the bootstrap's shared loader, and each carries
-- only the declarations it calls. Everything else declares its own ABI in the module
-- that calls it, and the bootstrap carries nothing for it at all.
-- No native ABI reaches the bootstrap at all. Every facility declares the symbols it
-- calls in the module that calls them, so a program's prologue is the same whichever
-- native feature it selected -- which is also what makes the declarations trimmed
-- rather than assembled: nothing has to decide what to leave out.
function M.theBootstrapCarriesNoNativeAbi()
   local abi = {
      "nuppUuid4", "nuppSha256", "nuppPathJoin", "nuppUriParse", "NuppFileInfo",
      "nuppBytesData", "nuppProcessSpawnBegin", "nuppHttpClientCreate",
      "typedef struct NuppUri NuppUri",
   }
   for _, feature in ipairs({
      "native.uuid", "native.sha256", "native.path", "native.uri", "native.files",
      "native.process", "native.http",
   }) do
      local installed = stdlib.bootstrap({[feature] = true})
      for _, absent in ipairs(abi) do
         assert(not installed:find(absent, 1, true),
            feature .. " leaves " .. absent .. " to the module that calls it")
      end
   end
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
      .. " return type(nupp.peg), next(nupp.peg), rawget(nupp, 'io')"))
   local pegType, pegField, io = chunk()
   _G.nupp = previous
   assertEq(pegType, "table", "the pure PEG runtime is installed")
   assertEq(pegField, nil, "internal PEG helpers are not public fields")
   assertEq(io, nil, "selecting a native facility installs no ambient io namespace")
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
