local profiles = require("nupp.compiler.targetprofile")
local packs = require("nupp.compiler.build.compilerpacks")
local layouts = require("nupp.compiler.targetlayout")
local hash = require("nupp.compiler.build.hash")
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local json = require("testjson")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local M = {}

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function write(path, text)
   local directory = path:match("^(.*)/[^/]+$")
   if directory then os.execute("mkdir -p '" .. directory .. "'") end
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function tool(path, bytes)
   write(path, bytes)
   return {path = path:match("([^/]+)$"), sha256 = hash.sha256(bytes), size = #bytes}
end

-- A capability set with every field stated, which is what a descriptor owes.
local function capabilities(overrides)
   local stated = {
      dynamicLoader = true,
      tracingJit = true,
      ffiCallbacks = true,
      staticSymbolResolver = true,
      staticAot = true,
   }
   for name, value in pairs(overrides or {}) do stated[name] = value end
   return stated
end

local function descriptor(overrides)
   return {
      layoutModel = "x86_64-unknown-linux-gnu",
      os = "linux",
      capabilities = capabilities(overrides),
      link = {forceLoad = {}, export = {}},
   }
end

function M.everyModelledTripleHasABuiltInProfile()
   for _, key in ipairs(layouts.keys()) do
      local profile, err = profiles.resolve(key)
      assert(profile, key .. ": " .. tostring(err))
      assertEq(profile.target, key, "the profile names its target")
      assertEq(profile.origin, "built-in", "a modelled triple needs no descriptor")
      assertEq(profile.layoutModel, key, "a modelled triple is its own layout model")
   end
end

function M.hostedTargetsAdmitEverythingAndNameTheirLinker()
   local darwin = assert(profiles.resolve("aarch64-apple-darwin"))
   assert(darwin.dynamicLoader and darwin.tracingJit and darwin.ffiCallbacks)
   assert(darwin.staticSymbolResolver and darwin.staticAot)
   assertEq(darwin.os, "darwin", "the triple classifies its os")
   assertEq(darwin.forceLoad[1], "-Wl,-force_load,<archive>",
      "Darwin retains an archive by forcing it in")
   assertEq(darwin.export[1], "-Wl,-export_dynamic", "and publishes what it kept")

   local linux = assert(profiles.resolve("x86_64-unknown-linux-gnu"))
   assertEq(linux.forceLoad[1], "-Wl,--whole-archive", "GNU ld brackets the archive")
   assertEq(linux.forceLoad[3], "-Wl,--no-whole-archive", "and closes the bracket")

   local windows = assert(profiles.resolve("x86_64-pc-windows-msvc"))
   assertEq(windows.export[1], "-Wl,--export-all-symbols",
      "Windows exports nothing by default")
end

function M.wasmHasNoTracingJitAndNoArchiveToLink()
   local wasm = assert(profiles.resolve("wasm32-unknown-emscripten"))
   assert(wasm.dynamicLoader, "Emscripten loads side modules")
   assert(not wasm.tracingJit, "there is no trace compiler to promise")
   assert(not wasm.staticAot, "and no native archive for a host to link")
   assert(not wasm.staticSymbolResolver, "nor a process image to resolve out of")
end

function M.anUndescribedTargetIsRefusedRatherThanGuessed()
   local profile, err = profiles.resolve("aarch64-vendor-console")
   assertEq(profile, nil, "nothing describes a private triple by itself")
   assert(err:find("no target profile describes", 1, true), err)
end

function M.aDescriptorAdmitsAPrivateTripleThroughAModelledLayout()
   local profile, err = profiles.fromDescriptor("aarch64-vendor-console",
      descriptor({dynamicLoader = false, tracingJit = false, ffiCallbacks = false}),
      "pack.json")
   assert(profile, err)
   assertEq(profile.target, "aarch64-vendor-console", "the profile is the private target's")
   assertEq(profile.layoutModel, "x86_64-unknown-linux-gnu",
      "its layout is referenced rather than invented")
   assert(not profile.dynamicLoader and not profile.tracingJit)
   assert(profile.staticAot, "which is the point of describing it")
   assertEq(profile.origin, "pack.json", "a diagnostic can say where this came from")
end

function M.aDescriptorMustStateEveryCapability()
   local stated = descriptor()
   stated.capabilities.tracingJit = nil
   local profile, err = profiles.fromDescriptor("aarch64-vendor-console", stated, "pack.json")
   assertEq(profile, nil, "an omitted capability is one nobody verified")
   assert(err:find("boolean tracingJit", 1, true), err)
end

function M.aDescriptorMustReferenceAModelledLayout()
   local stated = descriptor()
   stated.layoutModel = "aarch64-vendor-console"
   local profile, err = profiles.fromDescriptor("aarch64-vendor-console", stated, "pack.json")
   assertEq(profile, nil, "admitting a triple may not also open a layout model")
   assert(err:find("modelled layoutModel", 1, true), err)
end

function M.staticAotWithoutAResolverIsRefusedInTheDescriptor()
   local stated = descriptor({staticSymbolResolver = false})
   local profile, err = profiles.fromDescriptor("aarch64-vendor-console", stated, "pack.json")
   assertEq(profile, nil, "an archive nothing can resolve out of is not static AOT")
   assert(err:find("without a static symbol resolver", 1, true), err)
end

-- Runs `body` with a compiler pack for the host installed, carrying `profile`.
local function withPack(profile, body)
   local host = assert(layouts.hostKey())
   local root = os.tmpname()
   os.remove(root)
   local directory = root .. "/" .. host .. "/" .. host
   os.execute("mkdir -p '" .. directory .. "'")
   write(directory .. "/pack.json", json.encode({
      schemaVersion = 1,
      host = host,
      target = host,
      version = "synthetic-1",
      cc = tool(directory .. "/cc", "synthetic compiler"),
      ar = tool(directory .. "/ar", "synthetic archiver"),
      profile = profile,
   }))
   local getenv = os.getenv
   os.getenv = function(name)
      if name == "NUPP_COMPILER_PACK_DIR" then return root end
      return getenv(name)
   end
   local ok, result = pcall(body, host)
   os.getenv = getenv
   os.execute("rm -rf '" .. root .. "'")
   if not ok then error(result, 0) end
   return result
end

function M.aPackDescriptorWinsOverTheBuiltInAnswer()
   local profile = withPack(descriptor({dynamicLoader = false}), function(host)
      return assert(packs.profile(host))
   end)
   assert(not profile.dynamicLoader,
      "a vendor port of a public triple is still that vendor's port")
   assert(profile.origin:find("pack.json", 1, true), profile.origin)
end

function M.aPackWithoutADescriptorLeavesTheBuiltInProfileInPlace()
   local profile = withPack(nil, function(host)
      return assert(packs.profile(host))
   end)
   assertEq(profile.origin, "built-in", "a toolchain-only pack describes no capabilities")
   assert(profile.dynamicLoader, "and changes nothing about the target")
end

local function codesFor(source, target)
   local env = envMod.new(HERE .. "/..", {
      cache = false,
      config = {build = {entries = {"main"}, layoutTarget = target}},
   })
   local result = parser.parse(source, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local out = {}
   for _, diagnostic in ipairs(check.check(result, "test.g.nupp", env)) do
      out[#out + 1] = diagnostic.code
   end
   return table.concat(out, " ")
end

local JIT_SOURCE = [[
@jit
local function hot(scale: number): number
    return scale * 2.0
end

return {hot = hot}
]]

function M.jitIsRefusedOnATargetWithNoTraceCompiler()
   assertEq(codesFor(JIT_SOURCE, "wasm32-unknown-emscripten"), "NUPP2904",
      "@jit asserts a contract Wasm cannot meet")
   assertEq(codesFor(JIT_SOURCE, "x86_64-unknown-linux-gnu"), "",
      "and is ordinary everywhere a trace compiler exists")
   assertEq(codesFor(JIT_SOURCE, nil), "",
      "a target nothing describes refuses nothing")
end

local LIBRARY_SOURCE = [[
cdef function ks_scale(value: float): float from"@lib/kernels.so"

return {ks_scale = ks_scale}
]]

function M.aNamedLibraryIsRefusedOnATargetWithNoLoader()
   local refused = withPack(descriptor({dynamicLoader = false}), function(host)
      return codesFor(LIBRARY_SOURCE, host)
   end)
   assertEq(refused, "NUPP2904", "a named library needs something to load it")

   local accepted = withPack(descriptor(), function(host)
      return codesFor(LIBRARY_SOURCE, host)
   end)
   assertEq(accepted, "", "and is ordinary where a loader exists")
end

-- Permitted by `unsafe`, and reported anyway where the VM allocates no
-- trampoline: `unsafe` says the author accepts what a callback costs, not that
-- the destination can make one.
local CALLBACK_SOURCE = table.concat({
   "unsafe do",
   "   local callback = function() end",
   "   local cb = ffi.cast<voidptr>(callback)",
   "   local handle = pin(cb, callback)",
   "end",
   "",
   "return {}",
}, "\n")

function M.anFfiCallbackIsRefusedOnATargetThatAllocatesNoTrampoline()
   local refused = withPack(descriptor({ffiCallbacks = false}), function(host)
      return codesFor(CALLBACK_SOURCE, host)
   end)
   assert(refused:find("NUPP2904", 1, true),
      "a port with no executable pages has no trampoline: " .. refused)

   local accepted = withPack(descriptor(), function(host)
      return codesFor(CALLBACK_SOURCE, host)
   end)
   assert(not accepted:find("NUPP2904", 1, true),
      "and is ordinary where one exists: " .. accepted)
end

return M
