local project = require("nupp.compiler.build.project")
local deps = require("nupp.compiler.build.deps")
local hash = require("nupp.compiler.build.hash")
local process = require("nupp.compiler.build.process")
local store = require("nupp.compiler.build.store")
local nativeStage = require("nupp.compiler.build.native")
local buildPlatform = require("nupp.compiler.build.platform")
local fs = require("nupp.compiler.fs")
local compilerEnv = require("nupp.compiler.env")
local json = require("testjson")
local buildSyntax = require("nupp.compiler.build.syntax")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function write(path, text)
   local dir = path:match("^(.*)/[^/]+$")
   if dir then os.execute("mkdir -p '" .. dir .. "'") end
   local f = assert(io.open(path, "wb"))
   f:write(text)
   f:close()
end

local function read(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return text
end

--- Where a project's content-keyed stores went.
---
--- Headers, formatting verdicts and type-function results answer about content rather
--- than about a project, so `NUPP_CACHE_DIR` may name one directory for all of them --
--- and the test runner sets it, because a run that makes a project per case would
--- otherwise start every one of them cold. A case about what those stores do has to
--- reach the file that was actually written. The check state is not one of them: it is
--- keyed by module name and stays with the project.
local function contentCacheDir(dir, outDir)
   return os.getenv("NUPP_CACHE_DIR") or (dir .. "/" .. outDir .. "/cache")
end

local function exists(path)
   local f = io.open(path, "rb")
   if not f then return false end
   f:close()
   return true
end

--- Skips a case that needs a Rust toolchain when the machine has none.
---
--- A cargo dependency is built by cargo, and a machine without one cannot say
--- whether the code that drives it is right. Reported as a skip with the reason,
--- the same way a case needing a C compiler or the HTTP provider is: a run that
--- silently passed would claim coverage it does not have.
local function requireCargo()
   local probe = io.popen("command -v cargo 2>/dev/null")
   local found = probe and probe:read("*l") or nil
   if probe then probe:close() end
   if found == nil or found == "" then
      require("assert").skip("cargo is unavailable")
   end
end

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   for name, text in pairs(files) do write(dir .. "/" .. name, text) end
   return dir
end

local function remove(dir)
   os.execute("rm -rf '" .. dir .. "'")
end

-- A directory that is neither a project nor one of its output trees, for
-- proving a tree runs from anywhere. This was spelled `/`, which is a
-- directory on POSIX and a switch to cmd's `cd`, so on Windows the run never
-- started and the tests read as though the tree had answered nothing.
local function elsewhere()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   return dir
end

local function libraryName(name)
   if jit.os == "Windows" then return name .. ".dll" end
   if jit.os == "OSX" then return "lib" .. name .. ".dylib" end
   return "lib" .. name .. ".so"
end

local function staticLibraryName(name)
   return "lib" .. name .. ".a"
end

local function executableName(name)
   return name .. (jit.os == "Windows" and ".exe" or "")
end

-- Loads an output tree in a fresh interpreter and reports what its entry module
-- answered. The tree is named absolutely and the working directory is somewhere
-- else, so no part of the answer can come from where the process was started.
local function answerFrom(tree, cwd)
   local here = assert(require("nupp.io.files").currentDirectory())
   here = here:gsub("^/([A-Za-z])(/)", "%1:%2")
   local script = ("package.path = %q .. %q .. package.path "
      .. "print('VALUE ' .. tostring(require('main')))")
      :format(tree .. "/?.lua;", here .. "/build/?.lua;")
   local code, out = process.capture({"luajit", "-e", script}, {cwd = cwd})
   if code ~= 0 then
      return out or ""
   end

   return out:match("VALUE ([^\r\n]+)") or out
end

local M = {}

function M.sha256KnownVectors()
   assertEq(hash.sha256(""),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
   assertEq(hash.sha256("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end

-- The published XXH64 answers. Cache keys never leave this machine, so
-- nothing forces the digest to be a particular function -- but a hand-rolled
-- one that is subtly wrong is a hand-rolled one nobody notices is wrong, and
-- these vectors are how a rewrite gets caught.
function M.xxh64KnownVectors()
   local function xxh(input, seed)
      -- `xxh64` carries its seed as two `uint32` halves, high then low, the
      -- same as everywhere else in this file; every seed below fits the low
      -- half.
      return hash.hex64(hash.xxh64(input, 0, seed))
   end
   assertEq(xxh("", 0), "ef46db3751d8e999")
   assertEq(xxh("a", 0), "d24ec4f1a98c6e5b")
   assertEq(xxh("abc", 0), "44bc2cf5ad770999")
   assertEq(xxh("abcd", 0), "de0327b0d25d92cc")
   assertEq(xxh("heiå", 0), "b9d3d990d2001a1a")
   assertEq(xxh("", 1), "d5afba1336a3be4b")
   assertEq(xxh("Nobody inspects the spammish repetition", 0),
      "fbcea83c8a378bf1")
end

-- The formatter reaches the same digest through native host services, so the
-- fast path must keep every durable cache key compatible with the portable
-- implementation. Exercise the stripe boundary, all tail branches, binary
-- bytes, and enough input for the performance-sensitive path.
function M.theNativeContentDigestMatchesThePortableOne()
   local nativeHash = require("nupp.compiler.hostservices").hash
   for _, input in ipairs({
      "",
      "a",
      "abc",
      ("x"):rep(31),
      ("y"):rep(32),
      ("z"):rep(33),
      string.char(0, 255, 128, 1, 7),
      ("Nobody inspects the spammish repetition\0"):rep(4096),
   }) do
      assertEq(nativeHash.digest(input), hash.digest(input))
   end
end

-- The eight bytes a stamped binary's trailer records. The Rust base provider
-- recomputes them on every run of that binary before handing a byte of the
-- payload to Lua, so this is one contract with two spellings and these are the
-- numbers both have to produce. The order matters as much as the value: the
-- field is little-endian so that a binary stamped on one machine verifies on
-- another, and a digest written the other way round would still be eight bytes
-- and still be wrong.
function M.theTrailerDigestIsLittleEndianXxh64()
   local function trailer(input)
      local bytes = hash.trailerDigest(input)
      local out = {}
      for index = 1, 8 do
         out[index] = ("%02x"):format(bytes:byte(index))
      end
      return table.concat(out)
   end

   -- The same published vectors as above, read back the other way round.
   assertEq(trailer(""), "99e9d85137db46ef")
   assertEq(trailer("a"), "5b6e8ca9f1c44ed2")
   assertEq(trailer("abc"), "990977adf52cbc44")

   -- Either side of the thirty-two byte stripe loop, and a tail that reaches
   -- the four-byte branch and then the byte one.
   assertEq(#hash.trailerDigest(("x"):rep(31)), 8)
   assertEq(trailer(("x"):rep(31)), "f0993b08010ddd60")
   assertEq(trailer(("y"):rep(32)), "66ce95341d1fda64")
   assertEq(trailer(("z"):rep(33)), "68024ec6531224c5")
   assertEq(trailer(string.char(0, 255, 128, 1, 7)), "950d048cbb3ee7b9")
end

-- Every tail branch and the stripe loop, at every length that reaches them.
-- The interesting failures here are off-by-one, not wrong constants: a digest
-- that ignores the last byte agrees with itself forever.
function M.digestSeparatesEveryLength()
   local seen = {}
   for n = 0, 200 do
      local input = ("abcdefgh"):rep(30):sub(1, n)
      local d = hash.digest(input)
      assertEq(#d, 32)
      assertEq(seen[d], nil)
      seen[d] = n
      assertEq(hash.digest(input), d)
   end
   -- A one-byte change anywhere has to move the answer, including in the
   -- final byte, which is the one a tail loop drops.
   for _, n in ipairs({1, 4, 7, 8, 15, 16, 31, 32, 33, 64, 100}) do
      local input = ("x"):rep(n)
      local flipped = input:sub(1, n - 1) .. "y"
      assert(hash.digest(input) ~= hash.digest(flipped),
         "digest ignored the last byte at length " .. n)
   end
end

-- The fingerprint identifies the compiler, not where it was found. It used to
-- hash each file's path as given, and `moduleDir` reports whatever
-- `package.path` was written as -- so the launcher's absolute path and a
-- harness's relative one described the same compiler two ways, and every
-- cache stamped with it discarded the other's work whenever they alternated.
function M.theToolFingerprintDoesNotDependOnHowTheCompilerWasFound()
   local function fingerprintUnder(prefix)
      local script = ("package.path=%q..package.path "
         .. "print(require('nupp.compiler.build.cache').toolFingerprint())")
         :format(prefix .. "build/?.lua;")
      local code, out = process.capture({"luajit", "-e", script})
      return code == 0 and out:match("[^\r\n]+") or nil
   end
   local here = assert(require("nupp.io.files").currentDirectory())
   here = here:gsub("^/([A-Za-z])(/)", "%1:%2")
   local relative = fingerprintUnder("")
   assert(relative and relative ~= "", "the relative run produced a digest")
   assertEq(fingerprintUnder(here .. "/"), relative,
      "the same compiler fingerprints the same either way")
end

function M.windowsMkdirUsesNativePathAndIsIdempotent()
   assertEq(fs.join("C:/one", "D:/two"), "D:/two",
      "joining an absolute Windows path does not prefix it")
   local command = process.mkdirCommand("build/nupp", true)
   assertEq(table.concat(command, " "),
      "cmd /d /c if not exist build\\nupp mkdir build\\nupp")

   local posix = process.mkdirCommand("build/nupp", false)
   assertEq(table.concat(posix, " "), "mkdir -p build/nupp")
end

function M.windowsAbsolutePathsAreNotModulesUnderTheCurrentRoot()
   local path = "C:/Users/runner/AppData/Local/Temp/backend/source/example.nupp"
   assertEq(compilerEnv.moduleNameInRoots({"."}, path), nil,
      "a drive path outside the project has no canonical module name")
   assert(not compilerEnv.isProjectPath({roots = {"."}, config = {}, rootDir = "."}, path),
      "a drive path outside the project is not project source")
   assertEq(compilerEnv.moduleNameInRoots({"."}, "source/example.nupp"), "source.example",
      "a relative path remains a module beneath the current root")
end

function M.isolatedProcessStopsAtItsWallClockDeadline()
   if jit.os == "Windows" then return end
   local code = process.captureIsolated(
      {"sh", "-c", "while :; do :; done"},
      {timeoutMs = 50}
   )
   assertEq(code, 124, "the process is killed at its deadline")
end

function M.isolatedProcessCapturesACompletedResponse()
   local code, output = process.captureIsolated(
      {"sh", "-c", "printf worker-ready"},
      {timeoutMs = 1000}
   )
   assertEq(code, 0, "the completed child succeeds")
   assertEq(output, "worker-ready", "the private output is returned")
end

function M.isolatedProcessAppliesAMemoryCeilingWhenSupported()
   if jit.os == "Windows" then return end
   local code, output = process.captureIsolated(
      {"sh", "-c", "printf memory-bounded"},
      {timeoutMs = 1000, memoryMb = 256}
   )
   assertEq(code, 0, "the bounded child succeeds")
   assertEq(output, "memory-bounded", "the bounded child returns its response")
end

function M.persistsVersionedMaterializationProductsAndObservations()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
      ["src/main.nupp"] = [[
const Matcher: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("'ok'")
end

return Matcher("ok")
]],
   })
   local cold, coldStats = {}, {}
   assertEq(project.build(dir, {produced = cold, stats = coldStats}), 0)
   assertEq(#cold.materializations, 1, "the cold build reports its materialization")
   local observation = cold.materializations[1]
   assertEq(observation.provider, "peg", "provider observation")
   assertEq(observation.schema, 5, "provider schema")
   assertEq(observation.backend, "auto", "selected backend")
   assert(observation.blueprintSize > 0 and observation.generatedSize > 0,
      "bounded sizes are reported")
   assertEq(observation.abis.runtimeExpression, 1, "runtime-expression ABI")
   assertEq(observation.blueprint, nil, "the public record omits the canonical payload")
   assertEq(observation.generated, nil, "the public record omits generated source")

   local state = json.decode(read(dir .. "/out/.nupp-state.json"))
   local cached = state.modules.main.materializations[1]
   assert(cached.blueprint and cached.blueprint.fingerprint == observation.fingerprint,
      "the manifest cache retains the canonical blueprint")
   assert(type(cached.generated) == "string" and #cached.generated > 0,
      "the manifest cache retains the backend output")
   local coldBytes = read(dir .. "/out/main.lua")

   local warm, warmStats = {}, {}
   assertEq(project.build(dir, {produced = warm, stats = warmStats}), 0)
   assertEq(warmStats.checkedModules, 0, "the cached build rechecks nothing")
   assertEq(warm.materializations[1].fingerprint, observation.fingerprint,
      "the cached build reports the same canonical product")
   assertEq(read(dir .. "/out/main.lua"), coldBytes,
      "cold and cached backend output is byte-identical")
   remove(dir)
end

function M.annotationChangesInvalidateReflectedMaterializations()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
      ["src/main.nupp"] = [[
local models = require("models")
const UserCodec: nupp.reflect.FieldCodec<models.User> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(models.User))
end
return UserCodec.fingerprint
]],
      ["src/models.nupp"] = [[
local models = {}
@annotation(targets = {"record"})
local record wire
    name: string
end

@wire(name = "users")
record models.User
    id: integer
end
return models
]],
   })
   local cold, coldStats = {}, {}
   assertEq(project.build(dir, {produced = cold, stats = coldStats}), 0)
   local first = assert(cold.materializations[1]).fingerprint

   local source = read(dir .. "/src/models.nupp")
   write(dir .. "/src/models.nupp", source:gsub('name = "users"', 'name = "accounts"'))
   local changed, changedStats = {}, {}
   assertEq(project.build(dir, {produced = changed, stats = changedStats}), 0)
   assertEq(changedStats.checkedModules, 2,
      "changing exported reflected metadata rechecks its dependent module")
   assert(first ~= assert(changed.materializations[1]).fingerprint,
      "annotation values participate in the materialization fingerprint")
   remove(dir)
end

function M.layoutTargetsSeparatePersistentComptimeResults()
   local function manifest(target)
      return ([=[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = %q}}
]=]):format(target)
   end
   local dir = tempProject({
      ["nupp.lua"] = manifest("x86_64-unknown-linux-gnu"),
      ["src/main.nupp"] = [[
local struct PointerSized
    tag: int8
    pointer: int8*
end
return comptime do return nupp.sizeof(PointerSized) end
]],
   })

   local lp64 = {}
   assertEq(project.build(dir, {stats = lp64}), 0)
   assertEq(lp64.checkedModules, 1, "the first target is checked")
   assert(read(dir .. "/out/main.lua"):find("return 16", 1, true),
      "the LP64 result was generated")

   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0)
   assertEq(warm.checkedModules, 0, "the same target reuses its result")

   write(dir .. "/nupp.lua", manifest("i686-unknown-linux-gnu"))
   local ilp32 = {}
   assertEq(project.build(dir, {stats = ilp32}), 0)
   assertEq(ilp32.checkedModules, 1, "changing the target invalidates the old result")
   assert(read(dir .. "/out/main.lua"):find("return 8", 1, true),
      "the ILP32 result replaces the LP64 result")
   remove(dir)
end

function M.exportedLayoutChangesInvalidateOnlyTheirReaders()
   local model = [[
local models = {}
struct models.Wire
    tag: int8
    value: int32
end
function models.body(): number return 1 end
return models
]]
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = "x86_64-unknown-linux-gnu"}}
]],
      ["src/main.nupp"] = [[
local models = require("models")
return comptime do return nupp.sizeof(models.Wire) end
]],
      ["src/models.nupp"] = model,
   })

   local cold = {}
   assertEq(project.build(dir, {stats = cold}), 0)
   assertEq(cold.checkedModules, 2, "the layout reader and declaration check cold")
   assert(read(dir .. "/out/main.lua"):find("return 8", 1, true),
      "the first layout was folded")

   write(dir .. "/src/models.nupp", model:gsub("return 1", "return 2"))
   local body = {}
   assertEq(project.build(dir, {stats = body}), 0)
   assertEq(body.checkedModules, 1, "a body edit checks only its module")
   assertEq(body.reusedModules, 1, "the layout reader cuts off at the interface")

   write(dir .. "/src/models.nupp", model:gsub("value: int32", "value: number"))
   local changed = {}
   assertEq(project.build(dir, {stats = changed}), 0)
   assertEq(changed.checkedModules, 2, "a field layout edit rechecks its reader")
   assert(read(dir .. "/out/main.lua"):find("return 16", 1, true),
      "the changed layout replaced the old folded result")
   remove(dir)
end

function M.manifestValidationRejectsInvalidReferencesAndCycles()
   local missing = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {native = {kind = "c", sources = {"native.c"}}},
   build = {entries = {"main"}, dependencies = {"missing"}},
}
]],
   })
   local config, err = project.loadManifest(missing)
   assertEq(config, nil, "unknown target dependency rejects the manifest")
   assert(err:find("references unknown dependency missing", 1, true), err)
   remove(missing)

   local cyclic = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {
      first = {kind = "c", dependencies = {"second"}},
      second = {kind = "c", dependencies = {"first"}},
   },
   build = {entries = {"main"}},
}
]],
   })
   config, err = project.loadManifest(cyclic)
   assertEq(config, nil, "dependency cycles reject the manifest")
   assert(err:find("dependency cycle involving", 1, true), err)
   remove(cyclic)
end

function M.manifestAcceptsSeveralPkgConfigPackages()
   local valid = tempProject({["nupp.lua"] = [[
return {dependencies = {native = {kind = "c",
   pkgConfig = {"simdjson", "luajit"}}}, build = {entries = {"main"}}}
]]})
   local config, err = project.loadManifest(valid)
   assert(config, err)
   assertEq(table.concat(config.dependencies.native.pkgConfig, ","), "simdjson,luajit")
   remove(valid)

   local invalid = tempProject({["nupp.lua"] = [[
return {dependencies = {native = {kind = "c", pkgConfig = {"simdjson", ""}}},
   build = {entries = {"main"}}}
]]})
   config, err = project.loadManifest(invalid)
   assertEq(config, nil, "an empty package name rejects the manifest")
   assert(err:find("pkgConfig%[2%] must be a non%-empty string"), err)
   remove(invalid)
end

function M.manifestValidatesCDependencyLinkage()
   for _, linkage in ipairs({"shared", "static", "both"}) do
      local valid = tempProject({["nupp.lua"] = ([[
return {dependencies = {native = {kind = "c", linkage = %q}},
   build = {entries = {"main"}}}
]]):format(linkage)})
      local config, err = project.loadManifest(valid)
      assert(config, err)
      assertEq(config.dependencies.native.linkage, linkage)
      remove(valid)
   end

   local invalid = tempProject({["nupp.lua"] = [[
return {dependencies = {native = {kind = "c", linkage = "dynamic"}},
   build = {entries = {"main"}}}
]]})
   local config, err = project.loadManifest(invalid)
   assertEq(config, nil, "an unknown C linkage rejects the manifest")
   assert(err:find('linkage must be "shared", "static", or "both"', 1, true), err)
   remove(invalid)

   local strayOutput = tempProject({["nupp.lua"] = [[
return {dependencies = {native = {kind = "c", staticOut = "native.a"}},
   build = {entries = {"main"}}}
]]})
   config, err = project.loadManifest(strayOutput)
   assertEq(config, nil, "a static output without static linkage rejects the manifest")
   assert(err:find('staticOut requires linkage = "static" or "both"', 1, true), err)
   remove(strayOutput)
end

function M.manifestValidatesStandaloneTargetsAndPrebuiltArtifacts()
   local host = require("nupp.compiler.targetlayout").hostKey()
   local valid = tempProject({["nupp.lua"] = ([=[
return {
   dependencies = {native = {kind = "c", linkage = "static", artifacts = {
      [%q] = {static = {path = "native.a", sha256 = %q, size = 8}},
   }}},
   build = {kind = "binary", stub = "nupp", standalone = true,
      entries = {"main"}, dependencies = {"native"}},
}
]=]):format(host, ("0"):rep(64))})
   local config, err = project.loadManifest(valid)
   assert(config, err)
   assertEq(config.build.standalone, true)
   remove(valid)

   local invalid = tempProject({["nupp.lua"] = [[
return {build = {kind = "bundle", standalone = true, entries = {"main"}}}
]]})
   config, err = project.loadManifest(invalid)
   assertEq(config, nil, "standalone is restricted to compiler-owned binaries")
   assert(err:find("standalone is only valid for a binary target", 1, true), err)
   remove(invalid)
end

function M.manifestValidatesTypeDependenciesSeparatelyFromTargets()
   local valid = tempProject({["nupp.lua"] = [[
return {
   dependencies = {
      host = {
         kind = "types",
         format = "luacats",
         source = {
            git = "https://example.invalid/host.git",
            rev = "0123456789012345678901234567890123456789",
         },
         path = "library",
      },
   },
   build = {entries = {"main"}},
}
]], ["main.nupp"] = "local value = 1\n"})
   assert(project.loadManifest(valid), "a pinned LuaCATS dependency is valid")
   remove(valid)

   local invalid = tempProject({["nupp.lua"] = [[
return {
   dependencies = {
      host = {kind = "types", format = "teal", source = {git = "https://example.invalid/host.git", rev = "short"}},
   },
}
]]})
   local _, err = project.loadManifest(invalid)
   assert(err and err:find("format", 1, true), "the importer format is validated")
   remove(invalid)
end

function M.manifestValidatesTheCompileTimeLayoutTarget()
   local valid = tempProject({["nupp.lua"] = [[
return {build = {entries = {"main"},
   layoutTarget = "aarch64-apple-darwin"}}
]]})
   local config, err = project.loadManifest(valid)
   assert(config, "a supported layout target is accepted: " .. tostring(err))
   assertEq(config.build.layoutTarget, "aarch64-apple-darwin")
   local described = assert(project.describeTasks(valid, "default"))
   assertEq(described.layoutTarget, "aarch64-apple-darwin",
      "task discovery reports the effective layout target")
   remove(valid)

   local invalid = tempProject({["nupp.lua"] = [[
return {build = {entries = {"main"}, layoutTarget = "mystery-cpu"}}
]]})
   config, err = project.loadManifest(invalid)
   assertEq(config, nil, "an unknown layout target rejects the manifest")
   assert(err:find("layoutTarget names unsupported target mystery-cpu", 1, true), err)
   assert(err:find("x86_64%-unknown%-linux%-gnu"), err)
   remove(invalid)
end

function M.manifestValidatesCrossTargetBinaryPlatforms()
   local validDir = tempProject({
      ["nupp.lua"] = [[return {build = {kind = "binary", stub = "nupp",
         entries = {"main"}, platforms = {"x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin", "x86_64-pc-windows-msvc"}}}]],
   })
   local config, err = project.loadManifest(validDir)
   assert(config, err)
   assertEq(#config.build.platforms, 3, "all catalog platforms are retained")
   remove(validDir)

   local cases = {
      {platforms = "{}", message = "must not be empty"},
      {
         platforms = '{"x86_64-unknown-linux-gnu", "x86_64-unknown-linux-gnu"}',
         message = "duplicates x86_64-unknown-linux-gnu",
      },
      {platforms = '{"aarch64-unknown-linux-gnu"}', message = "unsupported binary platform"},
   }
   for _, case in ipairs(cases) do
      local dir = tempProject({
         ["nupp.lua"] = ('return {build = {kind = "binary", stub = "nupp", entries = {"main"}, platforms = %s}}')
            :format(case.platforms),
      })
      local rejected, why = project.loadManifest(dir)
      assertEq(rejected, nil, "invalid cross-target manifest is rejected")
      assert(why:find(case.message, 1, true), why)
      remove(dir)
   end
end

function M.manifestRestrictsPortablePayloadOutputsToBinaryTargets()
   local validDir = tempProject({
      ["nupp.lua"] = [[return {build = {kind = "binary", stub = "host",
         entries = {"main"}, output = "app", payloadOutput = "app.lua"}}]],
   })
   local config, err = project.loadManifest(validDir)
   assert(config, err)
   assertEq(config.build.payloadOutput, "app.lua")
   remove(validDir)

   local invalidDir = tempProject({
      ["nupp.lua"] = [[return {build = {kind = "bundle", entries = {"main"},
         payloadOutput = "app.lua"}}]],
   })
   local rejected, why = project.loadManifest(invalidDir)
   assertEq(rejected, nil, "a bundle cannot claim a separately stamped payload")
   assert(why:find("payloadOutput is only valid for a binary target", 1, true), why)
   remove(invalidDir)
end

local function syntheticStub(platform)
   if platform == "x86_64-unknown-linux-gnu" then
      return "\127ELF" .. string.char(2) .. ("\0"):rep(13) .. string.char(62, 0) .. ("\0"):rep(44)
   end
   if platform == "aarch64-apple-darwin" then
      return "\207\250\237\254" .. string.char(12, 0, 0, 1) .. ("\0"):rep(56)
   end
   return "MZ" .. ("\0"):rep(58) .. string.char(64, 0, 0, 0)
      .. "PE\0\0" .. string.char(100, 134) .. ("\0"):rep(58)
end

function M.crossTargetBuildUsesVerifiedLocalStubsAndWritesPosixArchives()
   local platforms = {
      "x86_64-unknown-linux-gnu",
      "aarch64-apple-darwin",
      "x86_64-pc-windows-msvc",
   }
   local dir = tempProject({
      ["nupp.lua"] = [[return {build = {kind = "binary", stub = "nupp",
         entries = {"main"}, platforms = {"x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin", "x86_64-pc-windows-msvc"}}}]],
      ["main.g.nupp"] = "return true\n",
   })
   local stubDir = dir .. "/stubs"
   os.execute("mkdir -p '" .. stubDir .. "'")
   assertEq(project.check(dir, {platform = platforms[1]}), 0,
      "checking a selected platform needs no stub or network")
   local records = {}
   for _, platform in ipairs(platforms) do
      local suffix = platform == "x86_64-pc-windows-msvc" and ".exe" or ""
      local artifact = "nupp-host-" .. platform .. suffix
      local bytes = syntheticStub(platform)
      write(stubDir .. "/" .. artifact, bytes)
      records[platform] = {
         platform = platform,
         hostAbi = 1,
         artifact = artifact,
         sha256 = hash.sha256(bytes),
         size = #bytes,
         executableSuffix = suffix,
         hostFeatures = {},
         noticeArtifact = "notices-" .. platform .. ".tar",
      }
   end
   local catalogPath = dir .. "/catalog.json"
   write(catalogPath, json.encode({catalogRelease = "synthetic-1", hostAbi = 1, stubs = records}))
   local getenv = os.getenv
   os.getenv = function(name)
      if name == "NUPP_STUB_CATALOG" then return catalogPath end
      if name == "NUPP_STUB_DIR" then return stubDir end
      return getenv(name)
   end
   local produced = {}
   local ok, code = pcall(project.build, dir, {platform = "all", produced = produced})
   assert(ok, code)
   assertEq(code, 0, "all synthetic platforms stamp")
   assertEq(#produced.platforms, 3, "one result per platform")
   assertEq(produced.platforms[2].distributionReady, false,
      "an unsigned macOS output is not described as distributable")
   assert(produced.platforms[2].notice:find("must be signed", 1, true),
      produced.platforms[2].notice)
   for _, platform in ipairs(platforms) do
      local suffix = platform == "x86_64-pc-windows-msvc" and ".exe" or ""
      local output = dir .. "/build/default/" .. platform .. "/default" .. suffix
      assert(exists(output), platform .. " raw binary exists")
      if platform ~= "x86_64-pc-windows-msvc" then
         local archive = read(output .. ".tar")
         assertEq(archive:sub(101, 108), "0000755\0", platform .. " tar records executable mode")
      end
   end
   local linux = platforms[1]
   local linuxRecord = records[linux]
   local cached = dir .. "/.nupp/stubs/synthetic-1/1/" .. linux .. "/"
      .. linuxRecord.sha256 .. "/" .. linuxRecord.artifact
   assert(exists(cached), "a verified stub is installed in the content-addressed cache")
   write(cached, "corrupt")
   assertEq(project.build(dir, {platform = linux}), 0,
      "a corrupt cache entry is replaced from the verified local source")
   assertEq(read(cached), syntheticStub(linux), "the repaired cache contains authenticated bytes")
   local hiddenStubDir = stubDir .. "-hidden"
   assertEq(os.rename(stubDir, hiddenStubDir), true)
   assertEq(project.build(dir, {platform = linux}), 0,
      "a verified cache hit needs no source directory artifact")
   assertEq(os.rename(hiddenStubDir, stubDir), true)

   write(catalogPath, json.encode({catalogRelease = "synthetic-abi", hostAbi = 2, stubs = records}))
   assertEq(project.build(dir, {platform = linux}), 1,
      "a catalog for another host ABI is refused before stamping")
   write(catalogPath, json.encode({catalogRelease = "synthetic-1", hostAbi = 1, stubs = records}))

   local wrongBytes = syntheticStub("aarch64-apple-darwin")
   local wrongArtifact = "wrong-linux-host"
   write(stubDir .. "/" .. wrongArtifact, wrongBytes)
   local originalLinux = records[linux]
   records[linux] = {
      platform = linux,
      hostAbi = 1,
      artifact = wrongArtifact,
      sha256 = hash.sha256(wrongBytes),
      size = #wrongBytes,
      executableSuffix = "",
      hostFeatures = {},
      noticeArtifact = "notices-wrong.tar",
   }
   write(catalogPath, json.encode({catalogRelease = "synthetic-wrong", hostAbi = 1, stubs = records}))
   local wrongOk, wrongCode = pcall(project.build, dir, {platform = linux})
   assert(wrongOk, wrongCode)
   assertEq(wrongCode, 1, "a digest-valid stub for the wrong architecture is refused")
   records[linux] = originalLinux
   write(catalogPath, json.encode({catalogRelease = "synthetic-1", hostAbi = 1, stubs = records}))

   write(dir .. "/main.g.nupp", 'local lpeg = require("lpeg")\nreturn lpeg\n')
   assertEq(project.build(dir, {platform = linux}), 1,
      "a payload feature absent from the selected stub is refused")
   write(dir .. "/main.g.nupp", "return true\n")

   local windowsOutput = dir .. "/build/default/x86_64-pc-windows-msvc/default.exe"
   os.remove(windowsOutput)
   records["aarch64-apple-darwin"] = nil
   write(catalogPath, json.encode({catalogRelease = "synthetic-2", hostAbi = 1, stubs = records}))
   local partial = {}
   local partialCode = project.build(dir, {platform = "all", produced = partial})
   os.getenv = getenv
   assertEq(partialCode, 1, "one missing platform makes the aggregate fail")
   assertEq(partial.platforms[1].status, "built", "the first platform still builds")
   assertEq(partial.platforms[2].status, "failed", "the missing platform is reported")
   assertEq(partial.platforms[3].status, "built", "later independent platforms still build")
   assert(exists(windowsOutput), "a platform after the failure was restamped")
   local removed = {}
   assertEq(project.clean(dir, {
      target = "default",
      platform = "x86_64-pc-windows-msvc",
      removed = removed,
   }), 0, "one platform can be cleaned")
   assertEq(removed[1], "build/default/x86_64-pc-windows-msvc/default.exe",
      "clean reports the selected platform output")
   assert(not exists(windowsOutput), "the selected Windows output was removed")
   assert(exists(dir .. "/build/default/x86_64-unknown-linux-gnu/default"),
      "another platform output remains")
   remove(dir)
end

function M.crossTargetBuildRefusesSidecarOnlyProvidersBeforeCargoRuns()
   local dir = tempProject({})
   local outputs, err = nativeStage.build(
      dir,
      "out",
      { ["native.http"] = true },
      "x86_64-pc-windows-msvc"
   )
   assertEq(outputs, nil, "a compiler-host HTTP sidecar is not staged")
   assert(err:find("sidecar-only native feature http", 1, true), err)
   remove(dir)
end

function M.taskDescriptionsUseEffectiveTargetConfiguration()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   build = {
      outDir = "out",
      entries = {"shared.main"},
      default = "other",
      targets = {
         default = {description = "The task named default"},
         other = {entries = {"other.main"}},
      },
   },
}
]],
   })
   local task, err = project.describeTasks(dir, "default")
   assert(task, err)
   assertEq(task.name, "default", "named default task is queried literally")
   assertEq(task.default, false, "query reports the configured default accurately")
   assertEq(task.outDir, "out", "task inherits the output directory")
   assertEq(task.entries[1], "shared.main", "task inherits shared entries")
   remove(dir)
end

-- The generator reads a dozen keys the build's own validation knows nothing
-- about, so a misspelling used to configure nothing and say nothing about it.
function M.aMisspelledDocsKeyIsRejectedWithTheNameItMeant()
   local function reject(target, wanted)
      local dir = tempProject({["nupp.lua"] =
         "return {include = {\"src\"}, build = {targets = {site = "
         .. target .. "}}}\n"})
      local config, err = project.loadManifest(dir)
      assertEq(config, nil, "a key that configures nothing is refused")
      assert(err:find(wanted, 1, true), wanted .. " not in: " .. tostring(err))
      remove(dir)
   end
   reject('{kind = "docs", sources = {"src"}, titel = "x"}',
      'has no key "titel"; did you mean "title"?')
   reject('{kind = "docs", sources = {"src"}, pages = {{titel = "x"}}}',
      'pages[1] has no key "titel"; did you mean "title"?')
   reject('{kind = "docs", sources = {"src"}, pages = {{glob = "docs/**.md", '
      .. 'exlude = {"docs/style.md"}}}}',
      'pages[1] has no key "exlude"; did you mean "exclude"?')
   -- A page names what it publishes one way or the other, and one that names
   -- neither a route nor a pattern is a page nothing can place.
   reject('{kind = "docs", sources = {"src"}, pages = {{source = "docs/x.md"}}}',
      'pages[1].path must be a string')
   reject('{kind = "docs", sources = {"src"}, pages = {{glob = 1}}}',
      'pages[1].glob must be an array')
   -- Nothing near enough to guess at is still named, without one.
   reject('{kind = "docs", sources = {"src"}, wibble = 1}',
      'has no key "wibble"')
end

-- `fmt` gets the same treatment as any other manifest table: a typo names
-- itself rather than configuring nothing.
function M.fmtManifestKeyIsValidated()
   local function loadFmt(fmt)
      local dir = tempProject({["nupp.lua"] =
         'return {include = {"src"}, fmt = ' .. fmt .. '}\n'})
      local config, err = project.loadManifest(dir)
      remove(dir)
      return config, err
   end

   local config = loadFmt('{methodParens = false}')
   assert(config, "a valid fmt table is accepted")
   assertEq(config.fmt.methodParens, false, "and its value survives")

   local _, err = loadFmt('"off"')
   assert(err and err:find("fmt must be a table", 1, true), err)

   local _, typeErr = loadFmt('{methodParens = "no"}')
   assert(typeErr and typeErr:find("fmt.methodParens must be a boolean", 1, true),
      typeErr)

   local _, nameErr = loadFmt('{methodParen = false}')
   assert(nameErr and nameErr:find(
      'fmt has no key "methodParen"; did you mean "methodParens"?', 1, true),
      nameErr)
end

-- A docs target is still a build target, so what any target takes belongs on
-- one too. This project's declares the rocks `nupp doc` renders with.
function M.aDocsTargetKeepsTheKeysEveryTargetTakes()
   local dir = tempProject({["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {lunamark = {kind = "luarocks", rock = "lunamark",
      version = "0.6.0-1"}},
   build = {targets = {site = {
      kind = "docs", sources = {"src"}, dependencies = {"lunamark"},
      format = "both", name = "N", github = "https://example.com",
      logo = "l.svg", public = "p", customCss = "c.css", lexers = "lx",
      includePrivate = true, all = true,
      pages = {{path = "", title = "H", layout = "home", source = "i.md",
         redirects = {"old"}}, {glob = {"docs/**.md"}, base = "docs",
         exclude = {"docs/style.md"}}},
   }}},
}
]]})
   local config, err = project.loadManifest(dir)
   assert(config, "every documented key is accepted: " .. tostring(err))
   remove(dir)
end

function M.nativeFeatureOverridesAreValidatedAndReported()
   local function load(features)
      local dir = tempProject({["nupp.lua"] = [[
return {include = {"src"}, build = {targets = {app = {
   entries = {"main"}, nativeFeatures = ]] .. features .. [[
}}}}
]]})
      local config, err = project.loadManifest(dir)
      local task = config and project.describeTasks(dir, "app") or nil
      remove(dir)
      return config, err, task
   end

   local config, err, task = load("{lpeg = true, path = true, uuid = false}")
   assert(config, "boolean native feature overrides are accepted: " .. tostring(err))
   assertEq(task.nativeFeatures.lpeg, true, "task reports forced inclusion")
   assertEq(task.nativeFeatures.path, true, "new native providers can be forced in")
   assertEq(task.nativeFeatures.uuid, false, "new native providers can be forced out")

   local _, unknown = load("{jsoon = true}")
   assert(unknown and unknown:find("nativeFeatures names no feature jsoon", 1, true),
      tostring(unknown))
   local _, wrongType = load("{lpeg = 'yes'}")
   assert(wrongType and wrongType:find(
      "nativeFeatures.lpeg must be true or false", 1, true), tostring(wrongType))
end

function M.dialectsAreValidatedInheritedReportedAndCacheSeparately()
   local function load(dialect)
      local dir = tempProject({["nupp.lua"] = [[
return {include = {"src"}, build = {targets = {app = {
   entries = {"main"}, dialect = ]] .. dialect .. [[
}}}}
]]})
      local config, err = project.loadManifest(dir)
      remove(dir)
      return config, err
   end

   assert(load('"luajit"'), "the native dialect is accepted")
   assert(load('"luajit-compat"'), "the compatibility LuaJIT dialect is accepted")
   assert(load('"lua51"'), "the portable dialect is accepted")
   local _, unsupported = load('"lua54"')
   assert(unsupported and unsupported:find(
      'build.targets.app.dialect must be "luajit", "luajit-compat" or "lua51"', 1, true),
      tostring(unsupported))
   local _, wrongType = load("true")
   assert(wrongType and wrongType:find(
      'build.targets.app.dialect must be "luajit", "luajit-compat" or "lua51"', 1, true),
      tostring(wrongType))

   local inherited = tempProject({["nupp.lua"] = [[
return {build = {dialect = "lua51", targets = {
   portable = {entries = {"main"}},
   native = {entries = {"main"}, dialect = "luajit"},
}}}
]]})
   local portableTask = assert(project.describeTasks(inherited, "portable"))
   local nativeTask = assert(project.describeTasks(inherited, "native"))
   assertEq(portableTask.dialect, "lua51", "a target inherits the build dialect")
   assertEq(nativeTask.dialect, "luajit", "a target overrides the build dialect")
   remove(inherited)

   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   dialect = "lua51"}}
]],
      ["src/main.nupp"] = "return 42\n",
   })
   local produced = {}
   assertEq(project.build(dir, {produced = produced}), 0, "the configured dialect builds")
   assertEq(produced.dialect, "lua51", "build reporting names the manifest dialect")
   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0, "the same dialect reuses its build")
   assertEq(warm.generatedModules, 0, "an unchanged dialect regenerates nothing")

   local changed, overridden = {}, {}
   assertEq(project.build(dir, {dialect = "luajit", stats = changed, produced = overridden}), 0,
      "a command-level dialect overrides the manifest")
   assertEq(overridden.dialect, "luajit", "build reporting names the override")
   assert(changed.generatedModules > 0, "changing dialect invalidates generated artifacts")

   local checked = {}
   assertEq(project.check(dir, {dialect = "lua51", produced = checked}), 0,
      "check accepts the same dialect axis")
   assertEq(checked.dialect, "lua51", "check reporting names its resolved dialect")
   remove(dir)
end

function M.backendsAreValidatedAndReported()
   local function load(selected)
      local dir = tempProject({["nupp.lua"] = [[
return {include = {"src"}, build = {targets = {app = {
   entries = {"main"}, backends = ]] .. selected .. [[
}}}}
]]})
      local config, err = project.loadManifest(dir)
      local task = config and project.describeTasks(dir, "app") or nil
      remove(dir)
      return config, err, task
   end

   local config, err, task = load("{'acme.portable'}")
   assert(config, "a named backend module is accepted: " .. tostring(err))
   assertEq(task.backends[1], "acme.portable",
      "task output reports the backend requirement")

   local _, wrongType = load("{true}")
   assert(wrongType and wrongType:find(
      "backends[1] must be a non-empty module name", 1, true), tostring(wrongType))
   local _, keyed = load("{json = 'acme.portable'}")
   assert(keyed and keyed:find(
      "backends must be an array of module names", 1, true), tostring(keyed))
   local _, duplicate = load("{'acme.portable', 'acme.portable'}")
   assert(duplicate and duplicate:find(
      "names backend module acme.portable more than once", 1, true), tostring(duplicate))

   local retired = tempProject({["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"},
   runtimeProviders = {json = "acme.portable_json"}}}
]]})
   local _, retiredError = project.loadManifest(retired)
   remove(retired)
   assert(retiredError and retiredError:find("runtimeProviders", 1, true),
      "the temporary provider registry is rejected by name: " .. tostring(retiredError))
end

function M.selectedRuntimeBackendBuildsAndRuns()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   backends = {"portablebackend"}}}
]],
      ["src/main.nupp"] = [[
local json = require("nupp.data.json")
return json.encode({answer = 42})
]],
      ["src/portablebackend.nupp"] = [[
module portablebackend

const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")

export = Backend.new("portable", {
   JSON.seam("portable_json"),
})
]],
   })
   local produced = {}
   assertEq(project.build(dir, {produced = produced}), 0, "the backend-selected project builds")
   assertEq(produced.backends[1].module, "portablebackend",
      "build output reports the statically resolved backend module")
   assertEq(produced.backends[1].seams[1].name, "data.json",
      "build output reports the resolved seam")
   assertEq(produced.backends[1].seams[1].version, 2,
      "build output reports the seam contract version")
   assertEq(#produced.backendResolution, 1,
      "build output reports only the reached seam resolution")
   assertEq(produced.backendResolution[1].name, "data.json",
      "the reached resolution names its exact seam")
   assertEq(produced.backendResolution[1].binding, "runtime",
      "the reached resolution records when its module binds")
   write(dir .. "/out/portable_json.lua", [[
local json = {NULL = {}, EMPTY_ARRAY = {}, EMPTY_OBJECT = {}}
local function same(value) return value end
json.arrayOf, json.asArray, json.asObject = same, same, same
function json.isArray(value) return type(value) == "table" and #value > 0 end
json.decode, json.pull = same, same
function json.encode(value) return "portable:" .. tostring(value.answer) end
json.serialize = json.encode
json.encoded, json.encodedString = same, same
json.verified, json.verifiedString = same, same
json.writer = same
return json
]])

   local generated = read(dir .. "/out/main.lua")
   assert(generated:find("portablebackend", 1, true),
      "the reached standard module installs the selected backend")
   assert(generated:find("nupp%-backends: resolved=data.json", 1),
      "the artifact itself records the same reached seam")
   assert(not generated:find("%z"), "artifact metadata contains a printable source digest")
   assert(generated:find("portable_json", 1, true),
      "artifact metadata records the exact third-party runtime module")
   assert(not generated:find("JSON.seam", 1, true),
      "the entry contains no generated adapter implementation")
   local backend = read(dir .. "/out/portablebackend.lua")
   assert(backend:find("portable_json", 1, true),
      "the checked backend source owns its exact runtime dependency")
   local script = ("package.path=%q..package.path;io.write(require('main'))")
      :format(dir .. "/out/?.lua;")
   local status, output = process.capture({"luajit", "-e", script})
   assertEq(status, 0, "the built artifact loads the runtime backend: " .. tostring(output))
   assertEq(output, "portable:42", "the backend seam delegates to the selected provider")
   remove(dir)
end

function M.aWarmBuildBehindAProjectedModuleRecompilesNothing()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   dialect = "lua51", backends = {"nupp.runtime.backend.browser"}}}
]],
      ["src/main.nupp"] = [[
local data = require("nupp.data")

return function(): string
   return data.uuid4()
end
]],
   })
   local cold = {}
   assertEq(project.build(dir, {stats = cold}), 0, "a browser-backend project builds")
   assert(cold.checkedModules > 0, "the cold build checks the entry")
   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0)
   -- The facade behind the backend has no record of its own, and a dependent
   -- that looked one up would be recompiled on every build for want of it.
   assertEq(warm.checkedModules, 0, "a reader of a projected module is reused unchanged")
   remove(dir)
end

function M.installedBrowserBackendTypesExactAndProjectedModules()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   dialect = "lua51", backends = {"nupp.runtime.backend.browser"}}}
]],
      ["src/main.nupp"] = [[
local crypto = require("nupp.browser.crypto")
local storage = require("nupp.browser.storage")
local time = require("nupp.time")
local data = require("nupp.data")
local hmac = require("nupp.data.hmac")
local path = require("nupp.io.path")

local function platform(): string
   assert(path.newPath("src", "app", "..", "main.nupp"):normalize():toString() == "src/main.nupp")
   assert(path.currentDirectory() == nil)
   time.sleep(1)
   storage.set("digest", data.sha256(crypto.randomBytes(16)))
   return hmac.hex("key", assert(storage.get("digest"))) .. data.uuid4()
end

return platform
]],
   })
   local produced, diagnostics = {}, {}
   assertEq(project.build(dir, {produced = produced, diagnostics = diagnostics}), 0,
      "an installed compiler supplies its checked browser backend: "
         .. tostring(diagnostics[1] and diagnostics[1].msg))
   assertEq(#diagnostics, 0,
      "exact browser modules and the projected data facade type through providers")
   assertEq(produced.backends[1].module, "nupp.runtime.backend.browser",
      "build accounting names the built-in backend module")
   assert(read(dir .. "/out/nupp/runtime/backend/browser.lua"),
      "the checked built-in backend is materialized into the application")
   assert(read(dir .. "/out/nupp/io/path.lua"),
      "the compiler-owned path implementation is materialized into the application")
   assert(read(dir .. "/out/nupp/runtime/provider/browserpath.lua"),
      "the browser backend supplies only the path environment")
   assert(not exists(dir .. "/out/nupp/runtime/nativev2.lua"),
      "portable path arithmetic does not carry the native binding")
   assert(not exists(dir .. "/out/nupp/data.lua"),
      "the native data implementation is not compiled behind a projected facade")
   local generated = read(dir .. "/out/main.lua")
   assert(generated:find("nupp.runtime.backend.browser", 1, true),
      "the application installs its selected browser backend")
   assert(generated:find('require ( "nupp.data" )', 1, true),
      "the standard facade remains the source-level runtime module")
   remove(dir)
end

function M.invalidBackendSelectionReportsAStructuredDiagnostic()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"},
   backends = {"missing.backend"}}}
]],
      ["src/main.nupp"] = "return true\n",
   })
   local diagnostics = {}
   assertEq(project.build(dir, {checkOnly = true, diagnostics = diagnostics}), 1,
      "a missing selected backend refuses the build")
   assertEq(diagnostics[1] and diagnostics[1].code, "NUPP3008",
      "backend resolution failures have a stable diagnostic code")
   assert(diagnostics[1].msg:find("missing.backend", 1, true),
      "the structured diagnostic names the selected module")
   remove(dir)
end

function M.lua51BitopsRequireAndUseACheckedBackendSeam()
   local withoutBackend = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   dialect = "lua51"}}
]],
      ["src/main.nupp"] = [[
local function combine(a: integer, b: integer): integer
   return (~a) & (b << 2)
end
return combine
]],
   })
   local missing = {}
   assertEq(project.check(withoutBackend, {diagnostics = missing}), 1,
      "a portable project without the bitops seam is refused")
   assertEq(missing[1].code, "NUPP3006", "the source operator owns the capability diagnostic")
   remove(withoutBackend)

   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   dialect = "lua51", backends = {"portablebackend"}}}
]],
      ["src/main.nupp"] = [[
local function combine(a: integer, b: integer): integer
   local value = (~a) & (b | (a << 2))
   value ~= b
   return value
end
return combine
]],
      ["src/portablebackend.nupp"] = [[
module portablebackend

const Backend = require("nupp.runtime.backend")
const Bitops = require("nupp.runtime.seam.bitops")

export = Backend.new("portable", {
   Bitops.seam("bit"),
})
]],
   })
   local produced, diagnostics = {}, {}
   assertEq(project.build(dir, {produced = produced, diagnostics = diagnostics}), 0,
      "the checked bitops backend satisfies the lua51 build")
   assertEq(#diagnostics, 0, "the selected capability resolves before project checking")
   assertEq(produced.backends[1].seams[1].name, "numeric.bitops",
      "build output accounts for the selected bitops seam")

   local generated = read(dir .. "/out/main.lua")
   assert(generated:find("__nuppBitops.band", 1, true),
      "portable source lowers through the runtime seam")
   assert(generated:find("portablebackend", 1, true),
      "the reached seam installs its checked backend module")
   assert(not generated:find("Bitops.seam", 1, true),
      "the entry embeds no adapter source")
   local script = ("package.path=%q..package.path;local f=require('main');io.write(f(240,60))")
      :format(dir .. "/out/?.lua;")
   local status, output = process.capture({"luajit", "-e", script})
   assertEq(status, 0, "the portable artifact runs through the selected BitOp module: " .. tostring(output))
   assertEq(tonumber(output), bit.bxor(
      bit.band(bit.bnot(240), bit.bor(60, bit.lshift(240, 2))), 60
   ),
      "portable lowering has the native LuaJIT result")
   remove(dir)
end

function M.backendMetadataIsStaticAndInvalidatesGeneratedSelection()
   local function backendSource(runtimeModule)
      return ([[
module portablebackend

const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")

error("a build must not execute backend source")
export = Backend.new("portable", {
   JSON.seam(%q),
})
]]):format(runtimeModule)
   end

   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   backends = {"portablebackend"}}}
]],
      ["src/main.nupp"] = [[
local json = require("nupp.data.json")
return json.encode({answer = 42})
]],
      ["src/portablebackend.nupp"] = backendSource("first_json"),
   })
   assertEq(project.build(dir, {}), 0, "static backend metadata builds without execution")
   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0, "the unchanged backend is reusable")
   assertEq(warm.generatedModules, 0, "the unchanged backend regenerates nothing")

   write(dir .. "/src/portablebackend.nupp", backendSource("second_json"))
   local changed = {}
   assertEq(project.build(dir, {stats = changed}), 0, "changed backend metadata rebuilds")
   assert(changed.generatedModules >= 2,
      "a descriptor change invalidates generated selection, got " .. tostring(changed.generatedModules))
   assert(read(dir .. "/out/portablebackend.lua"):find("second_json", 1, true),
      "the rebuilt backend carries its new exact runtime dependency")
   remove(dir)
end

function M.subprocessPreservesEmptyArguments()
   local dir = tempProject({
      ["argv.lua"] = [[io.write(#arg, "|", arg[1], "|", arg[2])]],
   })
   local status, output = process.capture({"luajit", dir .. "/argv.lua", "", "tail"})
   remove(dir)
   assertEq(status, 0, output)
   assertEq(output, "2||tail", "an empty argv entry reaches the child process")
end

function M.nativeFacilitiesSharingAProviderBuildAsOneUnion()
   local originalCapture, originalCopy = process.capture, fs.copyFile
   local originalCompilerRoot = compilerEnv.compilerRoot
   local calls, copies = {}, {}
   -- The driver answers with the path it built, which is the last line it
   -- writes; anything before that is progress.
   process.capture = function(argv)
      calls[#calls + 1] = argv
      return 0, "/built/libnupp_native_v2.dylib\n"
   end
   fs.copyFile = function(source, destination)
      copies[#copies + 1] = {source, destination}
      return true
   end
   compilerEnv.compilerRoot = function() return "." end
   local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {
      ["native.path"] = true,
      ["native.uuid"] = true,
   })
   process.capture, fs.copyFile = originalCapture, originalCopy
   compilerEnv.compilerRoot = originalCompilerRoot
   assert(ok, outputs)
   assert(outputs, problem)
   assertEq(#calls, 1, "one provider union is built once")
   assertEq(#copies, 2, "the shared library and path runtime are staged")
   local command = "\n" .. table.concat(calls[1], "\n") .. "\n"
   assert(command:find("\nnative%-rust\nfilesystem,uuid\n"),
      "path and UUID select one sorted Rust feature union")
   assertEq(copies[1][1], "/built/libnupp_native_v2.dylib",
      "the Rust provider union has one source artifact")
   assert(copies[1][2]:find("out/lib/nupp_native_v2", 1, true),
      "the Rust provider union keeps its stable sidecar name")
end

function M.nativeFacilityCanSelectItsProviderDriver()
   local originalCapture, originalCopy = process.capture, fs.copyFile
   local originalCompilerRoot = compilerEnv.compilerRoot
   local calls, copies = {}, {}
   process.capture = function(argv)
      calls[#calls + 1] = argv
      return 0, "/built/libnupp_native_v2.dylib\n"
   end
   fs.copyFile = function(source, destination)
      copies[#copies + 1] = {source, destination}
      return true
   end
   compilerEnv.compilerRoot = function() return "." end
   local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {
      ["native.gpu"] = true,
   })
   process.capture, fs.copyFile = originalCapture, originalCopy
   compilerEnv.compilerRoot = originalCompilerRoot
   assert(ok, outputs)
   assert(outputs, problem)
   assertEq(#calls, 1, "the facility selects one provider build")
   local command = "\n" .. table.concat(calls[1], "\n") .. "\n"
   assert(command:find("\nnative%-rust\n"),
      "the feature's provider driver is passed to the toolchain")
   assert(command:find("\ngpu\n", 1, true),
      "the selected driver receives the provider feature union")
   assertEq(copies[1][1], "/built/libnupp_native_v2.dylib")
   assert(copies[1][2]:find("out/lib/nupp_native_v2", 1, true),
      "the Rust provider has an independent sidecar name")
end

function M.aTargetKeepsTheRuntimeModuleItAlreadyBuilt()
   local originalCopy = fs.copyFile
   local originalCompilerRoot = compilerEnv.compilerRoot
   local copies = {}
   fs.copyFile = function(source, destination)
      copies[#copies + 1] = {source, destination}
      return true
   end
   compilerEnv.compilerRoot = function() return "/compiler" end
   local output = "/project/out/nupp/suspension.lua"
   local ok, outputs, problem = pcall(nativeStage.build,
      "/project", "out", {['runtime.suspension'] = true}, nil,
      {[output] = true})
   fs.copyFile = originalCopy
   compilerEnv.compilerRoot = originalCompilerRoot
   assert(ok, outputs)
   assert(outputs, problem)
   assertEq(#copies, 0, "native staging preserves the target's generated runtime")
   assert(outputs[output], "the preserved runtime remains a staged output")

   copies = {}
   fs.copyFile = function(source, destination)
      copies[#copies + 1] = {source, destination}
      return true
   end
   compilerEnv.compilerRoot = function() return "/compiler" end
   ok, outputs, problem = pcall(nativeStage.build,
      "/project", "out", {['runtime.suspension'] = true})
   fs.copyFile = originalCopy
   compilerEnv.compilerRoot = originalCompilerRoot
   assert(ok, outputs)
   assert(outputs, problem)
   assertEq(#copies, 1, "an application still receives the compiler runtime")
   assertEq(copies[1][1], "/compiler/build/nupp/suspension.lua")
   assertEq(copies[1][2], output)
end

-- A docs target with no outDir does not land in the manifest's default
-- directory; the generator has its own, and for markdown it is not even under
-- it. `nupp clean` removes what the task table names, so naming the wrong
-- place left the output behind and took an unrelated directory with it.
function M.aDocsTaskReportsWhereTheGeneratorWillWrite()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {targets = {
      site = {kind = "docs", sources = {"src"}},
      api = {kind = "docs", sources = {"src"}, format = "markdown"},
      chosen = {kind = "docs", sources = {"src"}, outDir = "elsewhere"},
   }},
}
]],
   })
   local site = assert(project.describeTasks(dir, "site"))
   assertEq(site.outDir, "build/docs", "a site target defaults below build")
   local api = assert(project.describeTasks(dir, "api"))
   assertEq(api.outDir, "docs/api.md", "a markdown target defaults to a file")
   local chosen = assert(project.describeTasks(dir, "chosen"))
   assertEq(chosen.outDir, "elsewhere", "an explicit outDir still wins")
   remove(dir)
end

-- `all` and `includePrivate` include different things, and the task table
-- reported the first under the second's name while never mentioning the second.
function M.docsTaskReportsBothInclusionSettingsSeparately()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {targets = {site = {
      kind = "docs", sources = {"src"}, all = true, includePrivate = false,
   }}},
}
]],
   })
   local task = assert(project.describeTasks(dir, "site"))
   assertEq(task.all, true, "all is reported as itself")
   assertEq(task.includePrivate, false, "and includePrivate as itself")
   remove(dir)
end

function M.strictnessFollowsTheFileExtensionThroughTheProject()
   -- The old shape of this test asked whether a flag reached the incremental
   -- checker. The flag is no longer what decides: the extension is, and it has to
   -- survive the whole path from the file on disk to the checker.
   local gradualDir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
      ["src/main.g.nupp"] = "return unknown_project_value\n",
   })
   local strictDir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
      ["src/main.nupp"] = "return unknown_project_value\n",
   })
   local errorPath = os.tmpname()
   local originalStderr = io.stderr
   io.stderr = assert(io.open(errorPath, "wb"))
   local gradual = project.check(gradualDir)
   local forced = project.check(gradualDir, {strict = true})
   local strict = project.check(strictDir)
   io.stderr:close()
   io.stderr = originalStderr
   os.remove(errorPath)
   assertEq(gradual, 0, ".g.nupp permits unknown globals")
   assertEq(forced, 1, "--strict audits a .g.nupp anyway")
   assertEq(strict, 1, ".nupp holds the floor with nothing asked for")
   remove(gradualDir)
   remove(strictDir)
end

function M.theRetiredStrictManifestKeyIsRefusedByName()
   -- A key nothing reads takes effect silently, which is the one way a
   -- configuration file can lie to the person who wrote it. `strict` set the
   -- floor for a whole project before the extension answered that per file, so a
   -- manifest still carrying it is describing a build that no longer happens.
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, strict = true, build = {entries = {"main"}}}
]],
      ["src/main.nupp"] = "return true\n",
   })
   local config, err = project.loadManifest(dir)
   assertEq(config, nil, "a retired key is refused rather than ignored")
   assert(err:find("no longer a manifest key", 1, true), err)
   assert(err:find(".g.nupp", 1, true), "and says what replaced it: " .. err)
   remove(dir)
end

function M.manifestBuildDiscoversModulesAndPreservesPaths()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"},
      resources = {"src/app/*.d.nupp",
         {source = "src/schema.nupp", output = "app/data/schema.nupp"}}},
}
]],
      ["src/app/main.nupp"] = "local lib = require('lib.util')\nreturn lib\n",
      ["src/lib/util.nupp"] = "return { answer = 42 }\n",
      ["src/app/data.d.nupp"] = "return { ok: boolean }\n",
      ["src/schema.nupp"] = "return { version = 1 }\n",
   })
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/app/main.lua"), "entry output keeps module path")
   assert(exists(dir .. "/out/lib/util.lua"), "dependency closure is emitted")
   assert(exists(dir .. "/out/app/data.d.nupp"), "resources keep include-relative path")
   assert(exists(dir .. "/out/app/data/schema.nupp"),
      "resource tables use their explicit target-relative output")
   assert(exists(dir .. "/out/.nupp-state.json"), "persistent state is written")
   assert(exists(dir .. "/out/.nupp-complete"), "the completion marker is published")
   assert(not exists(dir .. "/out/.nupp-complete.pending"),
      "the stamp it was written to is renamed into place rather than left beside it")
   -- The launcher rebuilds whenever a source is newer than this marker, so the marker
   -- has to date from before the sources were read. Stamped when the build finished it
   -- covered every edit made while the build was running: an edit that landed too late
   -- to be compiled was also too old to ask for another build, and the tree stayed one
   -- edit behind until something unrelated happened to move.
   assertEq(os.execute(("test ! '%s/out/.nupp-complete' -nt '%s/out/lib/util.lua'")
      :format(dir, dir)), 0,
      "the completion marker must not be newer than what the build wrote")
   local before = read(dir .. "/out/lib/util.lua")
   assertEq(project.build(dir), 0, "warm build succeeds")
   assertEq(read(dir .. "/out/lib/util.lua"), before, "warm artifact is unchanged")
   write(dir .. "/out/.nupp-state.json", "not json")
   assertEq(project.build(dir), 0, "corrupt state degrades to a cold build")
   assertEq(read(dir .. "/out/lib/util.lua"), before,
      "cold rebuild preserves identical artifacts")
   remove(dir)
end

-- Advice about a program is not a reason to refuse to compile it. A note and a
-- warning are said and stepped over; only an error withholds the generated Lua
-- and fails the build.
function M.onlyAnErrorStopsAManifestBuild()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"}},
}
]],
      ["src/app/main.nupp"] = table.concat({
         "local type Color = 'red' | 'green' | 'blue'",
         "local function name(c: Color): string",
         "    if c == 'red' then",
         "        return 'r'",
         "    end",
         "end",
         "return { name = name }",
      }, "\n") .. "\n",
   })
   assertEq(project.build(dir), 0, "a warning does not fail the build")
   assert(exists(dir .. "/out/app/main.lua"),
      "a warning does not withhold the generated Lua")

   -- the same lint, turned up by the project, does stop it
   write(dir .. "/nupp.lua", [[
return {
   include = {"src"},
   lints = {["exhaustiveness"] = "error"},
   build = {outDir = "out", entries = {"app.main"}},
}
]])
   remove(dir .. "/out")
   assert(project.build(dir) ~= 0, "raised to an error, it stops the build")
   assert(not exists(dir .. "/out/app/main.lua"),
      "and the generated Lua is withheld")
   remove(dir)
end

function M.moduleBuildCacheUsesDependencyInterfaces()
   local depV1 = table.concat({
      "local function answer(): number",
      "   return 1",
      "end",
      "return { answer = answer }",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local lib = require('lib')",
         "local value: number = lib.answer()",
         "return value",
      }, "\n"),
      ["src/lib.nupp"] = depV1,
   })

   local cold = {}
   assertEq(project.build(dir, {stats = cold}), 0)
   assertEq(cold.checkedModules, 2, "cold build checks the closure")

   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0)
   assertEq(warm.checkedModules, 0, "warm build checks no modules")
   assertEq(warm.generatedModules, 0, "warm build generates no modules")
   assertEq(warm.reusedModules, 2, "warm build reuses the closure")

   write(dir .. "/src/lib.nupp", depV1:gsub("return 1", "return 2"))
   local bodyEdit = {}
   assertEq(project.build(dir, {stats = bodyEdit}), 0)
   assertEq(bodyEdit.checkedModules, 1,
      "body edit checks only the changed dependency")
   assertEq(bodyEdit.reusedModules, 1,
      "body edit reuses the dependent after interface cutoff")

   write(dir .. "/src/lib.nupp", table.concat({
      depV1:gsub("return 1", "return 2"),
      "-- Change the returned module interface without breaking consumers.",
   }, "\n"):gsub("return { answer = answer }",
      "return { answer = answer, label = 'answer' }"))
   local interfaceEdit = {}
   assertEq(project.build(dir, {stats = interfaceEdit}), 0)
   assertEq(interfaceEdit.checkedModules, 2,
      "interface edit rechecks the dependency and dependent")
   assertEq(interfaceEdit.reusedModules, 0,
      "changed interface invalidates the dependent record")
   remove(dir)
end

function M.moduleBuildCacheIncludesDeprecationMetadata()
   local lib = table.concat({
      "local M = {}",
      "function M.answer(): number",
      "   return 42",
      "end",
      "return M",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local lib = require('lib')",
         "return lib.answer()",
      }, "\n"),
      ["src/lib.nupp"] = lib,
   })

   assertEq(project.check(dir, {stats = {}, diagnostics = {}}), 0)
   write(dir .. "/src/lib.nupp", lib:gsub("function M.answer",
      '@deprecated(replacement = "lib.currentAnswer")\nfunction M.answer'))
   local stats, diagnostics = {}, {}
   assertEq(project.check(dir, {stats = stats, diagnostics = diagnostics}), 0)
   assertEq(stats.checkedModules, 2,
      "deprecation metadata invalidates the persistent dependent cache")
   local sawDeprecated = false
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.code == "NUPP2513" then
         sawDeprecated = true
      end
   end
   assert(sawDeprecated, "the rebuilt dependent reports the deprecated API")

   remove(dir)
end

function M.warmBuildInvalidatesOnlyReadersOfAChangedProjectType()
   local model = table.concat({
      "global record ReflectedModel",
      "   name: string",
      "end",
      "return {}",
   }, "\n")
   local unrelated = table.concat({
      "global record UnrelatedModel",
      "   value: number",
      "end",
      "return {}",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/model.nupp"] = model,
      ["src/unrelated.nupp"] = unrelated,
      ["src/main.nupp"] = table.concat({
         "const SUMMARY = comptime do",
         "   local info = nupp.reflect(ReflectedModel)",
         "   return info.fields[1].name",
         "end",
         "return SUMMARY",
      }, "\n"),
   })

   local cold = {}
   assertEq(project.build(dir, {stats = cold}), 0)
   assertEq(cold.checkedModules, 3, "cold build checks every project module")

   local warm = {}
   assertEq(project.build(dir, {stats = warm}), 0)
   assertEq(warm.checkedModules, 0, "unchanged project is warm")

   write(dir .. "/src/unrelated.nupp",
      unrelated:gsub("value: number", "value: string"))
   local unrelatedEdit = {}
   assertEq(project.build(dir, {stats = unrelatedEdit}), 0)
   assertEq(unrelatedEdit.checkedModules, 1,
      "unrelated export edit checks only its declaring module")
   assertEq(unrelatedEdit.reusedModules, 2,
      "the reflecting module remains reusable")

   write(dir .. "/src/model.nupp",
      model:gsub("name: string", "name: string\n   count: integer"))
   local reflectedEdit = {}
   assertEq(project.build(dir, {stats = reflectedEdit}), 0)
   assertEq(reflectedEdit.checkedModules, 2,
      "reflected field edit checks its declaration and reader")
   assertEq(reflectedEdit.reusedModules, 1,
      "unrelated module remains reusable")
   remove(dir)
end

function M.buildPropagatesOnlyCompleteConstModulePaths()
   local lib = table.concat({
      "local M = {}",
      "const... M.bar = {BAZ = 123, nested = {name = 'nupp'}}",
      "M.replaceable = {const BAZ = 456}",
      "local function ping(value: integer): integer return value + 1 end",
      "const... M.api = {ping = ping}",
      "return M",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "const lib = require('lib')",
         "lib.api.ping(1)",
         "lib.api.ping(2)",
         "return lib.bar.BAZ, lib.bar.nested.name, lib.replaceable.BAZ",
      }, "\n"),
      ["src/lib.nupp"] = lib,
   })

   assertEq(project.build(dir, {optLevel = 1}), 0)
   local output = read(dir .. "/out/main.lua")
   assert(output:find("return 123 , \"nupp\"", 1, true), output)
   assert(output:find("lib . replaceable . BAZ", 1, true), output)
   assert(output:find("const __nupp_call_1= lib . api . ping", 1, true), output)
   assertEq(select(2, output:gsub("lib . api . ping", "")), 1,
      "the built consumer resolves its immutable callable once")

   write(dir .. "/src/lib.nupp", lib:gsub("BAZ = 123", "BAZ = 124"))
   local changed = {}
   assertEq(project.build(dir, {optLevel = 1, stats = changed}), 0)
   assertEq(changed.checkedModules, 2,
      "changing an exported literal invalidates its consumer")
   output = read(dir .. "/out/main.lua")
   assert(output:find("return 124 , \"nupp\"", 1, true), output)
   remove(dir)
end

function M.storeKeepsWhatItWasGivenAndForgetsNothingLive()
   local dir = "/tmp/nupp-store-test-" .. tostring(process.mkdirCommand and 1 or 1)
   os.execute("rm -rf '" .. dir .. "'")
   local path = dir .. "/s.buf"

   local first = store.open(path, "stamp-1")
   assertEq(first.get("a"), nil, "an unopened store has nothing in it")
   first.put("a", {n = 1, list = {"x", "y"}})
   first.put("b", {n = 2})
   first.save()

   local second = store.open(path, "stamp-1")
   assertEq(second.get("a").n, 1, "a value survives the round trip")
   assertEq(second.get("a").list[2], "y", "including what is nested in it")
   assertEq(second.get("b").n, 2)
   assertEq(second.stats.hits, 3, "three hits, three lookups")

   -- A different stamp is a different compiler or a different project. There
   -- is no way to tell which of the entries it would have changed, so none of
   -- them are kept.
   local restamped = store.open(path, "stamp-2")
   assertEq(restamped.get("a"), nil, "a restamped store starts empty")

   -- Every way the file can be wrong is a miss, never an error.
   for _, damage in ipairs({"", "garbage", "\0\1\2\3", ("x"):rep(5000)}) do
      write(path, damage)
      local damaged = store.open(path, "stamp-1")
      assertEq(damaged.get("a"), nil, "a damaged store has nothing in it")
      damaged.put("a", {n = 9})
      damaged.save()
      assertEq(store.open(path, "stamp-1").get("a").n, 9,
         "and is overwritten by the next run")
   end

   -- A store with nowhere to live still works; it just never hits.
   local nowhere = store.open(nil, "stamp-1")
   nowhere.put("a", {n = 1})
   nowhere.save()
   assertEq(nowhere.get("a").n, 1, "within one run it still answers")
   assertEq(store.open(nil, "stamp-1").get("a"), nil, "and never persists")

   -- The single-value store, under the same rules.
   local vpath = dir .. "/v.buf"
   local value = store.openValue(vpath, "stamp-1")
   assertEq(value.value, nil)
   value.set({modules = {m = {sourceHash = "abc"}}})
   value.save()
   assertEq(store.openValue(vpath, "stamp-1").value.modules.m.sourceHash, "abc")
   assertEq(store.openValue(vpath, "stamp-2").value, nil,
      "a restamped value store is empty")
   write(vpath, "not a buffer")
   assertEq(store.openValue(vpath, "stamp-1").value, nil,
      "a damaged value store is empty")

   os.execute("rm -rf '" .. dir .. "'")
end

-- `nupp check` reuses on the same terms a build does, and the thing that has
-- to be true for that to be allowed is that reuse still says what checking
-- would have said. A check whose only output is diagnostics cannot get faster
-- by producing fewer of them.
function M.checkReusesUnchangedModulesAndStillReportsThem()
   local libV1 = table.concat({
      "local function answer(): number",
      "   return 1",
      "end",
      "return { answer = answer }",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local lib = require('lib')",
         "local value: number = lib.answer()",
         "return value",
      }, "\n"),
      ["src/lib.nupp"] = libV1,
   })

   local cold = {}
   assertEq(project.check(dir, {stats = cold, diagnostics = {}}), 0)
   assertEq(cold.checkedModules, 2, "a cold check checks the closure")

   local warm = {}
   assertEq(project.check(dir, {stats = warm, diagnostics = {}}), 0)
   assertEq(warm.checkedModules, 0, "a warm check checks nothing")
   assertEq(warm.reusedModules, 2, "a warm check reuses the closure")

   -- A body edit stops at the unchanged interface, exactly as a build does.
   write(dir .. "/src/lib.nupp", libV1:gsub("return 1", "return 2"))
   local bodyEdit = {}
   assertEq(project.check(dir, {stats = bodyEdit, diagnostics = {}}), 0)
   assertEq(bodyEdit.checkedModules, 1,
      "a body edit checks only the changed module")
   assertEq(bodyEdit.reusedModules, 1,
      "and reuses the dependent behind the unchanged interface")

   -- Breaking the interface has to reach the dependent even though the
   -- dependent's own bytes did not move.
   write(dir .. "/src/lib.nupp", table.concat({
      "local function answer(): string",
      "   return 'one'",
      "end",
      "return { answer = answer }",
   }, "\n"))
   local broken = {}
   assert(project.check(dir, {stats = broken, diagnostics = {}}) ~= 0,
      "a broken interface fails the check")
   assertEq(broken.checkedModules, 2,
      "the dependent is rechecked against the changed interface")

   -- The error is still an error on the next run, when the whole project is
   -- unchanged and every module is a candidate for reuse. This is the
   -- failure the whole design has to not have.
   local again = {}
   local diags = {}
   assert(project.check(dir, {stats = again, diagnostics = diags}) ~= 0,
      "a failing check still fails when nothing has changed since")
   local errors = 0
   for _, d in ipairs(diags) do
      if d.severity == "error" then errors = errors + 1 end
   end
   assert(errors > 0, "and still says what is wrong, from the record")
   assertEq(again.checkedModules, 0, "without checking anything again")

   remove(dir)
end

-- Checking a named file is the project's own check started somewhere smaller,
-- so it has to reuse like one, answer like one, and cost the whole-project
-- check that follows it nothing.
function M.checkOfNamedFilesReusesAndReportsOnlyThem()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local lib = require('lib')",
         "local value: number = lib.answer()",
         "return value",
      }, "\n"),
      ["src/lib.nupp"] = table.concat({
         "local function answer(): number",
         "   return 1",
         "end",
         "return { answer = answer }",
      }, "\n"),
      -- Nothing requires this one, and it is wrong.
      ["src/loose.nupp"] = table.concat({
         "local loose = {}",
         "local x: number = 'text'",
         "return loose",
      }, "\n"),
   })

   -- What the named file requires is checked, because the named file's answer
   -- depends on it. What nothing asked about is not.
   local cold = {}
   local coldDiags = {}
   assertEq(project.check(dir, {paths = {dir .. "/src/main.nupp"},
      stats = cold, diagnostics = coldDiags}), 0,
      "a named file that is well typed passes though the project is not")
   assertEq(cold.checkedModules, 2, "the named file and what it requires")
   assertEq(#coldDiags, 0, "the loose module's error is not this question")

   local warm = {}
   assertEq(project.check(dir, {paths = {dir .. "/src/main.nupp"},
      stats = warm, diagnostics = {}}), 0)
   assertEq(warm.checkedModules, 0, "a second narrow check checks nothing")
   assertEq(warm.reusedModules, 2, "and reuses what the first one recorded")

   -- Naming the broken file is how you hear about it.
   local named = {}
   local namedDiags = {}
   assert(project.check(dir, {paths = {dir .. "/src/loose.nupp"},
      stats = named, diagnostics = namedDiags}) ~= 0,
      "naming the broken module fails")
   local errors = 0
   for _, d in ipairs(namedDiags) do
      if d.severity == "error" then errors = errors + 1 end
   end
   assert(errors > 0, "and says what is wrong with it")

   -- The narrow runs recorded what they checked and left the rest of the stored
   -- state alone, so the whole-project check that follows starts warm rather
   -- than from nothing.
   local whole = {}
   assert(project.check(dir, {stats = whole, diagnostics = {}}) ~= 0,
      "the project still has the loose module's error in it")
   assertEq(whole.checkedModules, 0,
      "and every module was already recorded by the narrow checks")
   assertEq(whole.reusedModules, 3, "all three of them")

   remove(dir)
end

-- A path the project does not reach is not an error, it is a different
-- question: the caller gets it back to ask on its own terms.
function M.checkOfNamedFilesHandsBackWhatTheProjectDoesNotReach()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = "return 1",
      ["src/surface.d.nupp"] = "declare function elsewhere(): integer\n",
   })

   local unchecked = {}
   assertEq(project.check(dir, {
      paths = {dir .. "/src/main.nupp", dir .. "/src/surface.d.nupp"},
      unchecked = unchecked, diagnostics = {}}), 0)
   assertEq(#unchecked, 1, "the declaration file is not a module of the walk")
   assertEq(unchecked[1], dir .. "/src/surface.d.nupp", "and it is named back")

   remove(dir)
end

function M.exportedComptimeTypeFunctionsInvalidateAndPersistSafely()
   local optional = table.concat({
      "local M = {}",
      "local comptime function AddNil(T: type): type",
      "   return nupp.types.optional(T)",
      "end",
      "comptime function M.Maybe(T: type): type",
      "   return AddNil(T)",
      "end",
      "return M",
   }, "\n")
   local main = table.concat({
      "local gen = require('gen')",
      "local direct: gen.Maybe(string) = nil",
      "local function choose<T>(value: T, fallback: gen.Maybe(T)): gen.Maybe(T)",
      "   return fallback",
      "end",
      "local answer: string? = choose('yes', nil)",
      "return answer, direct",
   }, "\n")
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
      ["src/gen.nupp"] = optional,
      ["src/main.nupp"] = main,
   })

   assertEq(project.check(dir, {stats = {}, diagnostics = {}}), 0,
      "a consumer executes closed and inferred exported type calls")
   local cache = contentCacheDir(dir, "out") .. "/type-functions.buf"
   assert(exists(cache), "the type-function result store is persisted")

   -- Rechecking a changed consumer admits a validated persisted result. Damage is a
   -- miss, never a different type answer.
   write(dir .. "/src/main.nupp", main .. "\n-- force a consumer check\n")
   assertEq(project.check(dir, {stats = {}, diagnostics = {}}), 0,
      "a fresh checker accepts persisted blueprints")
   write(cache, "not a type-function store")
   write(dir .. "/src/main.nupp", main .. "\n-- force another consumer check\n")
   assertEq(project.check(dir, {stats = {}, diagnostics = {}}), 0,
      "a damaged result store falls back to evaluation")

   -- The sealed helper closure is part of the exported interface. Changing its
   -- behavior rechecks the unchanged consumer and changes the generated answer.
   write(dir .. "/src/gen.nupp", optional:gsub(
      "return nupp.types.optional%(T%)",
      "return T"
   ))
   local diagnostics = {}
   assert(project.check(dir, {stats = {}, diagnostics = diagnostics}) ~= 0,
      "a semantic private-helper edit invalidates the consumer")
   local sawArgumentFailure = false
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.code == "NUPP2006" then sawArgumentFailure = true end
   end
   assert(sawArgumentFailure, "the consumer observes the changed generated type")

   remove(dir)
end

-- A cache is only ever an optimization, so every way of damaging it has to
-- land on the same answer as not having one.
function M.checkSurvivesADamagedCache()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local lib = require('lib')",
         "local value: string = lib.answer()",
         "return value",
      }, "\n"),
      ["src/lib.nupp"] = table.concat({
         "local function answer(): number",
         "   return 1",
         "end",
         "return { answer = answer }",
      }, "\n"),
   })

   local function answerOf()
      local diags = {}
      local code = project.check(dir, {stats = {}, diagnostics = diags})
      local parts = {tostring(code)}
      for _, d in ipairs(diags) do
         parts[#parts + 1] = ("%s@%d:%d %s"):format(
            tostring(d.code), d.line or 0, d.col or 0, tostring(d.msg))
      end
      return table.concat(parts, "\n")
   end

   local cold = answerOf()
   assert(cold:sub(1, 1) ~= "0", "the fixture is meant to have an error in it")
   assertEq(answerOf(), cold, "a warm cache gives the cold answer")

   for _, damage in ipairs({"not a buffer at all", "", "\0\0\0\0"}) do
      write(contentCacheDir(dir, "out") .. "/headers.buf", damage)
      write(dir .. "/out/cache/checks.buf", damage)
      assertEq(answerOf(), cold, "a damaged cache gives the cold answer")
   end

   remove(contentCacheDir(dir, "out"))
   remove(dir .. "/out/cache")
   assertEq(answerOf(), cold, "no cache at all gives the cold answer")
   remove(dir)
end

function M.ownershipContractsInvalidateIncrementalInterfaces()
   local function library(mode)
      return table.concat({
         "cdef function inspect(" .. mode .. " value: cstring)",
         "return { inspect = inspect }",
      }, "\n")
   end
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
      ["src/lib.nupp"] = library("borrows"),
   })

   assertEq(project.build(dir), 0)
   write(dir .. "/src/lib.nupp", library("takes"))
   local changed = {}
   assertEq(project.build(dir, {stats = changed}), 0)
   assertEq(changed.checkedModules, 2,
      "ownership-mode interface changes recheck dependents")
   remove(dir)
end

function M.namedCleanupsInvalidateIncrementalInterfaces()
   local function library(cleanup)
      return table.concat({
         "cdef function create_c(): voidptr",
         "cdef function first_cleanup(takes value: voidptr)",
         "cdef function second_cleanup(takes value: voidptr)",
         "local function create(): affine(voidptr, " .. cleanup .. ")",
         "   return create_c()",
         "end",
         "return { create = create }",
      }, "\n")
   end
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
      ["src/lib.nupp"] = library("first_cleanup"),
   })

   assertEq(project.build(dir), 0)
   write(dir .. "/src/lib.nupp", library("second_cleanup"))
   local changed = {}
   assertEq(project.build(dir, {stats = changed}), 0)
   assertEq(changed.checkedModules, 2,
      "a changed cleanup rechecks dependents")
   remove(dir)
end

function M.cDependencyBuildsSharedLibraryAndBindings()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
      ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
   })
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/lib/" .. libraryName("tiny")), "C shared library emitted")
   local binding = read(dir .. "/out/generated/tiny.nupp")
   assert(binding:find("module tiny", 1, true), "C binding is a declared module")
   assert(binding:find("export = {", 1, true), "C binding exports its collected declarations")
   assert(binding:find("cdef function tiny_add", 1, true), "typed binding generated")
   write(dir .. "/native/tiny.h", table.concat({
      "int tiny_add(int a, int b);",
      "int tiny_sub(int a, int b);",
   }, "\n"))
   write(dir .. "/native/tiny.c", table.concat({
      "int tiny_add(int a, int b) { return a + b; }",
      "int tiny_sub(int a, int b) { return a - b; }",
   }, "\n"))
   assertEq(project.build(dir), 0, "changed native input rebuilds")
   assert(read(dir .. "/out/generated/tiny.nupp")
      :find("cdef function tiny_sub", 1, true), "header change reimports bindings")
   remove(dir)
end

function M.cDependencyBuildsStaticArchive()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", linkage = "static", sources = {"native/tiny.c"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
      ["native/main.c"] = table.concat({
         "int tiny_add(int a, int b);",
         "int main(void) { return tiny_add(2, 3) == 5 ? 0 : 1; }",
      }, "\n"),
   })
   assertEq(project.build(dir), 0)
   local archive = dir .. "/out/lib/" .. staticLibraryName("tiny")
   assert(exists(archive), "C static archive emitted")
   assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")),
      "a static dependency does not emit a shared library")

   local executable = dir .. "/native/static-consumer"
      .. (jit.os == "Windows" and ".exe" or "")
   assertEq(process.run({"cc", dir .. "/native/main.c", archive, "-o", executable}), 0,
      "the emitted archive links into a C executable")
   assertEq(process.run({executable}), 0, "the linked archive supplies its symbols")
   remove(dir)
end

function M.cDependencyBuildsSharedAndStaticArtifactsTogether()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", linkage = "both", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
      ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
   })
   assertEq(project.build(dir), 0)
   local shared = dir .. "/out/lib/" .. libraryName("tiny")
   local archive = dir .. "/out/lib/" .. staticLibraryName("tiny")
   assert(exists(shared), "both linkage emits the shared library")
   assert(exists(archive), "both linkage emits the static archive")
   assertEq(answerFrom(dir .. "/out", dir), "5",
      "the generated binding loads the shared artifact")

   os.remove(archive)
   assertEq(project.build(dir), 0, "a missing static half is rebuilt")
   assert(exists(archive), "the rebuilt dependency restores its static archive")
   remove(dir)
end

function M.cDependencyUsesTargetIndexedPrebuiltStaticArtifact()
   local producer = tempProject({
      ["nupp.lua"] = [[return {dependencies = {tiny = {kind = "c", linkage = "static",
         sources = {"tiny.c"}}}, build = {entries = {"main"}, dependencies = {"tiny"}}}]],
      ["main.g.nupp"] = "return true\n",
      ["tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
   })
   assertEq(project.build(producer), 0)
   local archive = producer .. "/build/lib/" .. staticLibraryName("tiny")
   local bytes = read(archive)
   local host = assert(require("nupp.compiler.targetlayout").hostKey())
   local consumer = tempProject({
      ["nupp.lua"] = ([=[
return {
   include = {"src"},
   dependencies = {tiny = {kind = "c", linkage = "static",
      bindings = {header = "native/tiny.h"}, artifacts = {
         [%q] = {static = {path = %q, sha256 = %q, size = %d}},
      }}},
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]=]):format(host, archive, hash.sha256(bytes), #bytes),
      ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add\n",
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
   })
   assertEq(project.build(consumer), 0, "a verified prebuilt artifact is selected for this target")
   assertEq(read(consumer .. "/out/lib/" .. staticLibraryName("tiny")), bytes,
      "the selected target artifact is staged byte-for-byte")
   write(archive, ("x"):rep(#bytes))
   assertEq(project.build(consumer), 1, "a digest-valid manifest refuses changed prebuilt bytes")
   remove(consumer)
   remove(producer)
end

function M.standaloneBinaryLinksCDependencyIntoItsOwnHost()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {tiny = {kind = "c", sources = {"native/tiny.c"},
      bindings = {header = "native/tiny.h"}}},
   build = {kind = "binary", stub = "nupp", standalone = true,
      outDir = "out", output = "out/app", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = [[local tiny = require("tiny")
print(tiny.tiny_add(2, 3))
]],
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
      ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
   })
   assertEq(project.build(dir), 0)
   local output = executableName(dir .. "/out/app")
   assert(exists(output), "the standalone executable is emitted")
   assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")),
      "the standalone build has no shared FFI sidecar")
   local code, text = process.capture({output})
   assertEq(code, 0, text)
   assertEq(text:match("[^\r\n]+"), "5", "the executable resolves FFI from its own symbols")
   remove(dir)
end

function M.standaloneBinaryLinksRustFilesystemIntoItsOwnHost()
   local dir = tempProject({
      ["nupp.lua"] = [[return {include = {"src"}, build = {kind = "binary",
   stub = "nupp", standalone = true, outDir = "out", output = "out/app",
   entries = {"main"}}}]],
      ["src/main.nupp"] = [[
const files = require("nupp.io.files")
assert(files.isFile("Cargo.toml"))
local contents = assert(files.read("Cargo.toml"))
assert(contents:find("[workspace]", 1, true))
print("rust-files-ok")
]],
   })
   assertEq(project.build(dir), 0)
   local output = executableName(dir .. "/out/app")
   assert(exists(output), "the standalone filesystem executable is emitted")
   assert(not exists(dir .. "/out/lib/nupp_native_v2"),
      "the standalone filesystem build retains no Rust sidecar")
   local code, text = process.capture({output})
   assertEq(code, 0, text)
   assertEq(text:match("[^\r\n]+"), "rust-files-ok",
      "the executable resolves Rust filesystem FFI from its own symbols")
   remove(dir)
end

function M.windowsStandaloneIntermediateHostHasAnExecutableSuffix()
   local dir = tempProject({
      ["nupp.lua"] = [[return {include = {"src"}, build = {kind = "binary",
   stub = "nupp", standalone = true, outDir = "out", entries = {"main"}}}]],
      ["src/main.nupp"] = "return 1\n",
   })
   local oldHostKey, oldLinkHost = buildPlatform.hostKey, nativeStage.linkHost
   local linkedOutput
   buildPlatform.hostKey = function() return "x86_64-pc-windows-msvc" end
   nativeStage.linkHost = function(_, _, _, output)
      linkedOutput = output
      return nil, "stop after observing the intermediate host path"
   end
   local ok, status = pcall(project.build, dir)
   buildPlatform.hostKey, nativeStage.linkHost = oldHostKey, oldLinkHost
   remove(dir)
   assert(ok, status)
   assertEq(status, 1)
   assert(linkedOutput and linkedOutput:match("standalone%-host%-binary%.exe$"),
      "the Windows linker output has no executable suffix: " .. tostring(linkedOutput))
end

function M.binaryFixpointReadsThePlatformNamedHostOutput()
   local dir = tempProject({
      ["nupp.lua"] = [[return {include = {"src"}, build = {targets = {dist = {
   kind = "binary", stub = "nupp", output = "out/app", entries = {"main"},
}}}, selfHost = {binary = "dist"}}]],
      ["src/main.nupp"] = "return 1\n",
   })
   local output = dir .. "/out/app.exe"
   local oldBuild, oldRun, oldHostKey = project.build, process.run, buildPlatform.hostKey
   project.build = function(_, opts)
      write(output, "same stamped bytes")
      opts.produced.artifact = output
      return 0
   end
   process.run = function(argv)
      assertEq(argv[1], output .. ".stage1", "fixpoint executes the platform-named stage")
      write(output, "same stamped bytes")
      return 0
   end
   buildPlatform.hostKey = function() return "x86_64-pc-windows-msvc" end
   local ok, status = pcall(project.binaryFixpoint, dir, {result = {}})
   project.build, process.run, buildPlatform.hostKey = oldBuild, oldRun, oldHostKey
   remove(dir)
   assert(ok, status)
   assertEq(status, 0, "the Windows executable suffix is shared with the build")
end

function M.standaloneBinaryLinksAotIntoItsOwnHost()
   local dir = tempProject({
      ["src/main.nupp"] = [[
@aot(lanes = false)
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do
      result = result + index
   end
   return result
end

print(triangular(4))
]],
   })
   write(dir .. "/nupp.lua", ([=[return {include = {"src"}, build = {kind = "binary",
      stub = "nupp", standalone = true, aot = "require", outDir = %q,
      output = %q, entries = {"main"}}}]=]):format(dir .. "/out", dir .. "/out/app"))
   if require("nupp.compiler.build.aot").toolchain() == nil then
      remove(dir)
      return require("assert").skip("C compiler is unavailable")
   end
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/lib/libdefault_aot.a"), "standalone AOT emits a static archive")
   assert(not exists(dir .. "/out/lib/" .. libraryName("default_aot")),
      "standalone AOT emits no loadable sidecar")
   local code, text = process.capture({dir .. "/out/app"})
   assertEq(code, 0, text)
   assertEq(text:match("[^\r\n]+"), "10", "the executable resolves its AOT entry internally")
   remove(dir)
end

function M.staticAotComponentProducesAnArchiveAndDefaultNamespaceBinding()
   local dir = tempProject({
      ["src/main.nupp"] = [[
@aot(lanes = false)
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do result = result + index end
   return result
end
return {triangular = triangular}
]],
   })
   write(dir .. "/nupp.lua", ([=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", outDir = %q,
      output = %q, entries = {"main"}}}]=]):format(dir .. "/out", dir .. "/out/component.lua"))
   if require("nupp.compiler.build.aot").toolchain() == nil then remove(dir); return require("assert").skip("C compiler is unavailable") end
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/lib/libdefault_aot.a"), "static component AOT emits an archive")
   assert(not read(dir .. "/out/component.lua"):find('from"@lib/', 1, true), "static component binds through ffi.C")
   remove(dir)
end

function M.staticAotComponentRegistersLuaBuildersThroughTheHost()
   local dir = tempProject({["src/main.nupp"] = [[
@aot(lanes = false)
local function make(): {string: any} return {ready = true} end
return {make = make}
]]})
   write(dir .. "/nupp.lua", ([=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", outDir = %q,
      output = %q, entries = {"main"}}}]=]):format(dir .. "/out", dir .. "/out/component.lua"))
   if require("nupp.compiler.build.aot").toolchain() == nil then remove(dir); return require("assert").skip("C compiler is unavailable") end
   assertEq(project.build(dir), 0)
   local component = read(dir .. "/out/component.lua")
   assert(component:find("__nuppAotBuilderModules", 1, true), "static builder reads host registration")
   assert(not component:find("package.loadlib", 1, true), "static builder does not dynamically load")

   -- The host calls a tier-spelled registrar and registers what it returns
   -- under the unsuffixed key the wrapper reads. The manifest names both.
   local link = json.decode(assert(read(dir .. "/out/aot/link.json")))
   assertEq(#link.builders, 1, "the one Lua-building entry is a registration the host owes")
   local builder = link.builders[1]
   assertEq(builder.entry, "make", "named after the entry it stands for")
   assert(component:find(builder.key, 1, true), "the wrapper reads the registry key")
   assert(builder.symbols[1]:find(builder.key, 1, true)
      and builder.symbols[1] ~= builder.key,
      "and the host calls a tier spelling of it: " .. builder.symbols[1])
   remove(dir)
end

function M.staticAotComponentCarriesAProbeAndALinkManifest()
   local dir = tempProject({
      ["src/main.nupp"] = [[
@aot(lanes = false)
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do result = result + index end
   return result
end
return {triangular = triangular}
]],
   })
   write(dir .. "/nupp.lua", ([=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", outDir = %q,
      output = %q, entries = {"main"}}}]=]):format(dir .. "/out", dir .. "/out/component.lua"))
   if require("nupp.compiler.build.aot").toolchain() == nil then remove(dir); return require("assert").skip("C compiler is unavailable") end
   assertEq(project.build(dir), 0)

   local link = json.decode(assert(read(dir .. "/out/aot/link.json")))
   assertEq(link.schemaVersion, 1, "the host handoff is versioned")
   assertEq(link.component, "default", "and names the component it describes")
   assertEq(link.archive, "lib/libdefault_aot.a", "and the archive to retain")
   local probe = link.fingerprint.symbol
   assert(probe:find("^ks_aot_archive_"), probe)
   assertEq(link.symbols.probe, probe, "the probe is among the symbols to export")
   assert(#link.symbols.kernels > 0, "so is every kernel")
   assert(#link.retain.forceLoad > 0,
      "a desktop linker extracts nothing from an archive nothing references")

   local c = assert(read(dir .. "/out/aot/archive.c"))
   assert(c:find("uint64_t " .. probe .. "(void)", 1, true), c)
   assert(c:find("return UINT64_C(" .. ("%d"):format(link.fingerprint.value) .. ");", 1, true),
      "the probe returns exactly what the manifest says it does")

   -- The check stands ahead of every declaration in the module, because a
   -- kernel `cdef` binds eagerly too and would raise LuaJIT's own message first.
   local module = assert(read(dir .. "/out/main.lua"))
   local at = module:find(probe, 1, true)
   local kernel = module:find("ks_[0-9a-f]+_triangular")
   assert(at and kernel and at < kernel, "the archive probe is checked first")
   assert(module:find("was not linked into the host", 1, true),
      "a missing probe says the archive was not linked")
   assert(module:find("is not the one this module was compiled against", 1, true),
      "and a mismatched one says which failure it is")
   remove(dir)
end

function M.staticAotIsRefusedForATargetThatHasNoArchiveToLink()
   local dir = tempProject({
      ["src/main.nupp"] = [[
@aot(lanes = false)
local function double(value: number): number return value * 2.0 end
return {double = double}
]],
   })
   write(dir .. "/nupp.lua", ([=[return {include = {"src"}, build = {kind = "component",
      aot = "require", aotLinkage = "static", aotTarget = "wasm32-unknown-emscripten",
      outDir = %q, output = %q, entries = {"main"}}}]=]):format(dir .. "/out", dir .. "/out/component.lua"))
   local errorPath = os.tmpname()
   local originalStderr = io.stderr
   io.stderr = assert(io.open(errorPath, "wb"))
   local code = project.build(dir)
   io.stderr:close()
   io.stderr = originalStderr
   local reported = read(errorPath) or ""
   os.remove(errorPath)
   assert(code ~= 0, "a target with no static archive cannot take static linkage")
   assert(reported:find("produces static AOT archives", 1, true), reported)
   remove(dir)
end

function M.cDependencyLinksAStaticClosureIntoItsSharedLibrary()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      base = {kind = "c", linkage = "static", sources = {"native/base.c"}},
      core = {kind = "c", linkage = "static", dependencies = {"base"},
         sources = {"native/core.c"}},
      tiny = {kind = "c", dependencies = {"core"}, sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
      ["native/base.c"] = "int base_add(int a, int b) { return a + b; }\n",
      ["native/core.c"] = table.concat({
         "int base_add(int a, int b);",
         "int core_add(int a, int b) { return base_add(a, b); }",
      }, "\n"),
      ["native/tiny.c"] = table.concat({
         "int core_add(int a, int b);",
         "int tiny_add(int a, int b) { return core_add(a, b); }",
      }, "\n"),
   })
   assertEq(project.build(dir), 0)
   assertEq(answerFrom(dir .. "/out", dir), "5",
      "the shared parent contains its transitive static implementation")
   remove(dir)
end

-- A project whose entry actually calls through the binding, so what is being
-- tested is a load rather than the spelling of a string.
local function callingProject()
   return tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "local tiny = require('tiny')\nreturn tiny.tiny_add(2, 3)\n",
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
      ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
   })
end

-- A C dependency's library is the other thing a build produces and ships, and
-- it used to be named by the path the build wrote: absolute, which runs on one
-- machine, or relative to where the build ran, which runs from one directory.
-- It is now marked the way `@aot` code has always marked its library.
function M.cDependencyNamesItsLibraryRelativeToTheModuleThatLoadsIt()
   local dir = callingProject()
   assertEq(project.build(dir), 0)

   local binding = read(dir .. "/out/generated/tiny.nupp")
   assert(binding:find('from "@lib/' .. libraryName("tiny") .. '"', 1, true),
      "the binding names the library relative to the output tree: " .. binding)
   assert(not binding:find(dir, 1, true),
      "and the build directory does not appear in it: " .. binding)

   -- The ordinary case first: a project built and run where it was built has to
   -- go on loading, since this changes how every existing one names its library.
   assertEq(answerFrom(dir .. "/out", dir), "5",
      "an ordinary C dependency loads where the build left it")
   remove(dir)
end

function M.cDependencyOutputTreeRunsWhereverItIsCopied()
   local dir = callingProject()
   assertEq(project.build(dir), 0)

   local moved = dir .. "/moved"
   assertEq(os.execute(("cp -r %q %q"):format(dir .. "/out", moved)), 0)
   -- Run from a directory that is neither the project nor the copy. Naming the
   -- library the way the build did answered here only from the project root.
   local away = elsewhere()
   assertEq(answerFrom(moved, away), "5",
      "a copied output tree runs from anywhere")
   remove(away)
   remove(dir)
end

-- A bundle is one file someone moves somewhere. The library its binding names
-- lives in the build directory the bundle was assembled in, which is not where
-- the bundle ends up, so the build puts a copy beside it -- exactly as it
-- already does for compiled `@aot` code.
function M.aBundleCarriesTheLibraryItsBindingNames()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", sources = {"native/tiny.c"},
         bindings = {header = "native/tiny.h"}},
   },
   build = {
      targets = {
         app = {
            kind = "bundle",
            entries = {"main"},
            outDir = "out",
            output = "dist/app.lua",
            dependencies = {"tiny"},
         },
      },
   },
}
]],
      ["src/main.nupp"] = "local tiny = require('tiny')\n"
         .. "print('VALUE ' .. tostring(tiny.tiny_add(2, 3)))\n",
      ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
      ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
   })
   assertEq(project.build(dir, {target = "app"}), 0)
   assert(exists(dir .. "/dist/lib/" .. libraryName("tiny")),
      "the library went with the bundle rather than staying in the build directory")

   -- A bundle runs with nothing beside it but the library, and from anywhere.
   local away = elsewhere()
   local code, out = process.capture({"luajit", dir .. "/dist/app.lua"}, {cwd = away})
   assertEq(code, 0, out)
   assert(out:find("VALUE 5", 1, true), "the bundle called through its binding: " .. out)
   remove(away)
   remove(dir)
end

-- A library the build did not put in the output tree is not part of what
-- travels with it, so it keeps the name it was given. `load` names a library
-- for the platform loader to find, and marking that would send the runtime
-- looking for a file beside a module instead.
function M.aPreexistingLibraryKeepsTheNameItWasGiven()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", load = "m", bindings = {header = "native/tiny.h"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["native/tiny.h"] = "double tiny_scale(double value);\n",
   })
   assertEq(project.build(dir), 0)
   local binding = read(dir .. "/out/generated/tiny.nupp")
   assert(binding:find('from "m"', 1, true),
      "a platform library name is left exactly as it was: " .. binding)
   remove(dir)
end

function M.cDependencyBuildsHeaderOnlyBridges()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", cppflags = {"-DTINY_SCALE=3"}, bindings = {
         header = "native/tiny.h",
         bridge = true,
         macros = {
            TINY_CLAMP = {parameters = {"int32", "int32", "int32"},
               result = "int32"},
            TINY_IGNORE = {parameters = {"int32"}},
         },
      }},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = table.concat({
         "local tiny = require('tiny')",
         "local tripled: int32 = tiny.tiny_triple(14)",
         "local clamped: int32 = tiny.TINY_CLAMP(20, 2, 8)",
         "tiny.TINY_IGNORE(clamped)",
         "return tripled",
      }, "\n"),
      ["native/tiny.h"] = [[
#include <stdint.h>
#ifndef TINY_SCALE
#define TINY_SCALE 1
#endif
static inline int32_t tiny_triple(int32_t value) { return value * TINY_SCALE; }
#define TINY_CLAMP(value, low, high) \
   ((value) < (low) ? (low) : ((value) > (high) ? (high) : (value)))
#define TINY_IGNORE(value) ((void)(value))
]],
   })
   assertEq(project.build(dir), 0)
   local library = dir .. "/out/lib/" .. libraryName("tiny")
   assert(exists(library), "header-only bridge shared library emitted")
   assert(exists(dir .. "/out/generated/tiny_bridge.c"),
      "deterministic bridge source emitted")
   local binding = read(dir .. "/out/generated/tiny.nupp")
   assert(binding:find("local tiny_triple = __nupp_bridge_", 1, true),
      "inline exported under its logical name")
   assert(binding:find("local TINY_CLAMP = __nupp_bridge_", 1, true),
      "macro exported under its logical name")
   assert(binding:find("local TINY_IGNORE = __nupp_bridge_", 1, true),
      "void macro exported under its logical name")

   local triple = binding:match("cdef function (__nupp_bridge_[%da-f]+)%(value: int32%)")
   assert(triple, "physical inline symbol recorded")
   local clamp = binding:match(
      "cdef function (__nupp_bridge_[%da-f]+)%(arg0: int32, arg1: int32, arg2: int32%)")
   assert(clamp, "physical macro symbol recorded")
   local ffi = require("ffi")
   ffi.cdef(("int32_t %s(int32_t); int32_t %s(int32_t, int32_t, int32_t);")
      :format(triple, clamp))
   local native = ffi.load(library)
   assertEq(native[triple](4), 12,
      "bridge compilation receives the dependency's preprocessor flags")
   assertEq(native[clamp](20, 2, 8), 8)
   remove(dir)
end

function M.cDependencyRejectsInvalidMacroBridgeRecipes()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "c", bindings = {
         header = "native/tiny.h",
         macros = {
            TINY_ADD = {parameters = {"int32"}, result = "int32"},
         },
      }},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["native/tiny.h"] = "#define TINY_ADD(a, b) ((a) + (b))\n",
   })
   assert(project.build(dir) ~= 0,
      "a requested macro with the wrong arity must fail the dependency build")
   assert(not exists(dir .. "/out/generated/tiny.nupp"),
      "an invalid recipe is not installed as a partial binding")
   remove(dir)
end

function M.cargoDependencyBuildsCdylib()
   requireCargo()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny_rust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tiny_rust"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["native/Cargo.toml"] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
      ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
   })
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/lib/" .. libraryName("tiny_rust")),
      "Cargo cdylib copied into output")
   remove(dir)
end

function M.cargoCbindgenBindingsPreserveExplicitOwnership()
   requireCargo()
   local command, cbindgen
   if jit.os == "Windows" then
      command = "cbindgen.cmd"
      -- One redirect per line rather than one around a block: `cmd` ends a
      -- parenthesised block at the first unescaped `)`, and every line here has
      -- one, so the block closed inside the first declaration and the rest went
      -- to the console instead of the file. Leading redirects also keep the
      -- space before `>` out of what is written.
      cbindgen = [[
@echo off
if not "%1"=="--output" exit /b 2
> "%2" echo typedef struct TinyBox { int value; } TinyBox;
>> "%2" echo void tiny_destroy(TinyBox *value);
>> "%2" echo TinyBox *tiny_create(int value);
>> "%2" echo int tiny_drops(void);
]]
   else
      command = "./cbindgen"
      cbindgen = [[#!/bin/sh
if [ "$1" != "--output" ] || [ -z "$2" ]; then exit 2; fi
printf '%s\n' \
  'typedef struct TinyBox { int value; } TinyBox;' \
  'void tiny_destroy(TinyBox *value);' \
  'TinyBox *tiny_create(int value);' \
  'int tiny_drops(void);' > "$2"
]]
   end
   local manifest = ([[
return {
   include = {"src"},
   dependencies = {
      tinyrust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false,
         bindings = {
            cbindgen = true,
            command = %q,
            ownership = {
               returns = {tiny_create = "tiny_destroy"},
               takes = {tiny_destroy = {1}},
            },
         },
      },
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tinyrust"}},
}
]]):format(command)
   local dir = tempProject({
      ["nupp.lua"] = manifest,
      ["src/main.nupp"] = [[
local tiny = require("tinyrust")
do
   local _box = tiny.tiny_create(41)
end
return tiny.tiny_drops()
]],
      ["native/" .. command:gsub("^%./", "")] = cbindgen,
      ["native/Cargo.toml"] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
      ["native/src/lib.rs"] = [[
use std::sync::atomic::{AtomicI32, Ordering};

#[repr(C)]
pub struct TinyBox { value: i32 }

static DROPS: AtomicI32 = AtomicI32::new(0);

#[no_mangle]
pub extern "C" fn tiny_create(value: i32) -> Box<TinyBox> {
    Box::new(TinyBox { value })
}

#[no_mangle]
pub extern "C" fn tiny_destroy(value: *mut TinyBox) {
    if !value.is_null() {
        DROPS.fetch_add(1, Ordering::SeqCst);
        unsafe { drop(Box::from_raw(value)); }
    }
}

#[no_mangle]
pub extern "C" fn tiny_drops() -> i32 { DROPS.load(Ordering::SeqCst) }
]],
   })
   if jit.os ~= "Windows" then
      assertEq(os.execute(("chmod +x %q"):format(dir .. "/native/cbindgen")), 0)
   end
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/out/generated/tinyrust.h"),
      "the configured cbindgen command wrote its header")
   local binding = read(dir .. "/out/generated/tinyrust.nupp")
   assert(binding:find("cdef function tiny_destroy(takes ", 1, true),
      "the configured terminal consumes its pointer: " .. binding)
   assert(binding:find("affine(TinyBox*, tiny_destroy)", 1, true),
      "the configured constructor returns a non-null affine pointer: " .. binding)
   assert(binding:find('from "@lib/' .. libraryName("tiny_rust") .. '"', 1, true),
      "the cbindgen import names the copied cdylib relatively: " .. binding)
   assertEq(answerFrom(dir .. "/out", dir), "1",
      "leaving the returned Box at scope end calls its Rust destructor once")
   remove(dir)
end

-- A crate's cdylib is copied into the same `lib/` a C dependency's library is
-- built into, so it travels with the build and is named the same way.
function M.cargoDependencyNamesItsLibraryRelativeToTheModuleThatLoadsIt()
   requireCargo()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tinyrust = {kind = "cargo", manifest = "native/Cargo.toml",
         library = "tiny_rust", locked = false,
         bindings = {header = "tiny_rust.h"}},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"tinyrust"}},
}
]],
      ["src/main.nupp"] = "local tiny = require('tinyrust')\n"
         .. "return tiny.tiny_double(21)\n",
      ["native/tiny_rust.h"] = "int tiny_double(int value);\n",
      ["native/Cargo.toml"] = [[
[package]
name = "tiny_rust"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
]],
      ["native/src/lib.rs"] = [[
#[no_mangle]
pub extern "C" fn tiny_double(value: i32) -> i32 { value * 2 }
]],
   })
   assertEq(project.build(dir), 0)

   local binding = read(dir .. "/out/generated/tinyrust.nupp")
   assert(binding:find('from "@lib/' .. libraryName("tiny_rust") .. '"', 1, true),
      "the binding names the cdylib relative to the output tree: " .. binding)
   assert(not binding:find(dir, 1, true),
      "and the build directory does not appear in it: " .. binding)

   assertEq(answerFrom(dir .. "/out", dir), "42",
      "a Cargo dependency loads where the build left it")
   local moved = dir .. "/moved"
   assertEq(os.execute(("cp -r %q %q"):format(dir .. "/out", moved)), 0)
   local away = elsewhere()
   assertEq(answerFrom(moved, away), "42",
      "and its output tree runs wherever it is copied")
   remove(away)
   remove(dir)
end

-- A rock that is already in the source tree, so what is proved here is the
-- provider rather than the network: `luarocks make` builds what is there.
local TINY_ROCKSPEC = [[
package = "tinyrock"
version = "1.0-1"
source = { url = "file://tinyrock.lua" }
description = { summary = "A rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = { type = "builtin", modules = { tinyrock = "tinyrock.lua" } }
]]

local function tinyRockFiles()
   return {
      ["vendor/tinyrock/tinyrock.lua"] = "return {answer = 42}\n",
      ["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC,
      ["src/main.nupp"] = "return true\n",
   }
end

function M.packagedGeneratorsAndRuntimeServicesUseSeparateDependencyRoles()
   local rockspec = [[
rockspec_format = "3.0"
package = "providerrock"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Generator and service provider fixture." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = {
      ["provider.codegen"] = "codegen.lua",
      ["provider.codec"] = "codec.lua",
   },
   copy_directories = { "nupp" },
}
]]
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      provider = {kind = "luarocks", path = "vendor/provider",
         rockspec = "vendor/provider/providerrock-1.0-1.rockspec"},
   },
   generators = {
      api = {using = "provider/codegen", inputs = {"model/*.txt"},
         options = {prefix = "generated"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"provider"}},
}
]],
      ["src/main.nupp"] = [[
local generated = require("fixture.generated")
local services = require("nupp.services")
local codec = services.require("nupp.codec", "fixture")
return generated.value .. ":" .. codec.name
]],
      ["model/value.txt"] = "answer\n",
      ["vendor/provider/providerrock-1.0-1.rockspec"] = rockspec,
      ["vendor/provider/codegen.lua"] = [[
return function(request)
   local value = request.read("model/value.txt"):match("%S+")
   request.write("fixture/generated.nupp", "return {value = "
      .. string.format("%q", request.options.prefix .. "-" .. value) .. "}\n")
end
]],
      ["vendor/provider/codec.lua"] = "return {codec = {name = 'codec'}}\n",
      ["vendor/provider/nupp/capabilities.json"] = [[
{"schema":1,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"},
 {"kind":"service","service":"nupp.codec","name":"fixture","api":1,
  "entry":"provider.codec","member":"codec"}
]}
]],
      ["vendor/provider/nupp/provider/codec.d.nupp"] = [[
local codec: {name: string}
return {codec = codec}
]],
   })
   assertEq(project.build(dir), 0, "a packaged generator and runtime service build")
   assert(exists(dir .. "/out/generated/api/fixture/generated.nupp"),
      "the generator publishes beneath its instance module root")
   local state = json.decode(read(dir .. "/out/.nupp-state.json"))
   assertEq(state.dependencies["tool:provider"].usage, "tool",
      "generator discovery installs a host-tool record")
   assertEq(state.dependencies.provider.usage, "target",
      "runtime discovery keeps a distinct target record")
   assert(exists(dir .. "/out/nupp/service/registry/g.lua")
      or exists(dir .. "/out/nupp/service/registry.lua"),
      "the build compiles a deterministic service registry")

   local script = ("package.path=%q..package.path;io.write(require('main'))")
      :format(dir .. "/out/?.lua;" .. dir .. "/.rocks/share/lua/5.1/?.lua;")
   local status, output = process.capture({"luajit", "-e", script})
   assertEq(status, 0, "the generated module and service load: " .. tostring(output))
   assertEq(output, "generated-answer:codec")

   assertEq(project.build(dir), 0, "unchanged generator output is reusable")
   write(dir .. "/model/value.txt", "changed\n")
   assertEq(project.build(dir), 0, "an input change reruns the generator")
   assert(read(dir .. "/out/generated/api/fixture/generated.nupp"):find("generated%-changed"),
      "the published output follows the changed input")
   remove(dir)
end

function M.compileDependenciesOptInWithoutChangingOldTypeManifests()
   local legacyDir = tempProject({
      ["nupp.lua"] = [[
return {dependencies = {types = {kind = "types", format = "luacats",
 source = {git = "https://example.invalid/types", rev = string.rep("a", 40)}}},
 build = {entries = {"main"}}}
]],
      ["main.nupp"] = "return true\n",
   })
   local legacy = assert(project.loadManifest(legacyDir))
   assertEq(legacy.build.compileDependencies, nil,
      "omission preserves ambient type dependency compatibility")
   remove(legacyDir)

   local explicitDir = tempProject({
      ["nupp.lua"] = [[
return {dependencies = {types = {kind = "types", format = "luacats",
 source = {git = "https://example.invalid/types", rev = string.rep("a", 40)}}},
 build = {entries = {"main"}, compileDependencies = {}}}
]],
      ["main.nupp"] = "return true\n",
   })
   local explicit = assert(project.loadManifest(explicitDir))
   assertEq(#explicit.build.compileDependencies, 0,
      "an explicit empty list opts out of ambient type dependencies")
   remove(explicitDir)
end

function M.aFailingGeneratorReportsWhatItPrinted()
   local rockspec = [[
rockspec_format = "3.0"
package = "providerrock"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Generator fixture." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = { ["provider.codegen"] = "codegen.lua" },
   copy_directories = { "nupp" },
}
]]
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      provider = {kind = "luarocks", path = "vendor/provider",
         rockspec = "vendor/provider/providerrock-1.0-1.rockspec"},
   },
   generators = {api = {using = "provider/codegen", inputs = {"model/*.txt"}}},
   build = {outDir = "out", entries = {"main"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["model/value.txt"] = "answer\n",
      ["vendor/provider/providerrock-1.0-1.rockspec"] = rockspec,
      -- Leaves through the exit rather than the worker's own reply, so the
      -- only evidence is what it wrote before going.
      ["vendor/provider/codegen.lua"] = [[
return function(request)
   io.stdout:write("codegen: model is on fire\n")
   io.stdout:flush()
   os.exit(3)
end
]],
      ["vendor/provider/nupp/capabilities.json"] = [[
{"schema":1,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"}
]}
]],
   })
   local errorPath = os.tmpname()
   local originalStderr = io.stderr
   io.stderr = assert(io.open(errorPath, "wb"))
   local code = project.build(dir)
   io.stderr:close()
   io.stderr = originalStderr
   local reported = read(errorPath) or ""
   os.remove(errorPath)
   assertEq(code, 1, "a generator that dies fails the build")
   assert(reported:find("codegen: model is on fire", 1, true),
      "the worker's captured output is reported: " .. reported)
   assert(reported:find("generator api failed: worker failed", 1, true), reported)
   assert(not exists(dir .. "/out/generated/api.nupp-staged"), "the staging directory is removed")
   remove(dir)
end

function M.shellEntryPointsRefuseBoundedOptions()
   local ok, err = pcall(process.run, {"true"}, {timeoutMs = 1000})
   assert(not ok and tostring(err):find("captureIsolated", 1, true),
      "run refuses a timeout it cannot honour: " .. tostring(err))
   ok, err = pcall(process.capture, {"true"}, {memoryMb = 64})
   assert(not ok and tostring(err):find("captureIsolated", 1, true),
      "capture refuses a memory ceiling it cannot honour: " .. tostring(err))
   assertEq(process.run({"true"}, {cwd = "."}), 0, "cwd is still honoured")
end

function M.generatorDeclarationsAreClosedAndPlainData()
   local unknown = tempProject({
      ["nupp.lua"] = [[
return {generators = {api = {using = "missing/codegen"}},
 build = {entries = {"main"}}}
]],
      ["main.nupp"] = "return true\n",
   })
   local _, unknownErr = project.loadManifest(unknown)
   assert(tostring(unknownErr):find("references unknown dependency missing", 1, true),
      "a generator must select a declared provider dependency: " .. tostring(unknownErr))
   remove(unknown)

   local cyclic = tempProject({
      ["nupp.lua"] = [[
local options = {}
options.self = options
return {
 dependencies = {provider = {kind = "luarocks", path = "provider"}},
 generators = {api = {using = "provider/codegen", options = options}},
 build = {entries = {"main"}},
}
]],
      ["main.nupp"] = "return true\n",
   })
   local _, cyclicErr = project.loadManifest(cyclic)
   assert(tostring(cyclicErr):find("must not contain cycles", 1, true),
      "generator options must be serializable plain data: " .. tostring(cyclicErr))
   remove(cyclic)

   local compile = tempProject({
      ["nupp.lua"] = [[
return {build = {entries = {"main"}, compileDependencies = {"missing"}}}
]],
      ["main.nupp"] = "return true\n",
   })
   local _, compileErr = project.loadManifest(compile)
   assert(tostring(compileErr):find("references unknown dependency missing", 1, true),
      "compile dependencies are checked by name: " .. tostring(compileErr))
   remove(compile)
end

function M.docsDoNotInstallUnrunGeneratorTools()
   local dir = tempProject({})
   local config = {
      dependencies = {
         provider = {kind = "luarocks", path = "not-present"},
      },
      generators = {
         api = {using = "provider/codegen"},
      },
   }
   local built, err = deps.build(dir, "out", config, {}, {kind = "docs", dependencies = {}})
   assert(built, "a docs dependency pass ignores unrun generators: " .. tostring(err))
   assertEq(next(built), nil, "no generator tool is installed for docs")
   remove(dir)
end

function M.canonicalPathsFollowLinksAndKeepMissingOnesObservable()
   local dir = tempProject({["real/file.txt"] = "x\n"})
   local real = fs.canonical(dir .. "/real/file.txt")
   assert(real:sub(1, 1) == "/" or real:match("^%a:/"), "a canonical path is absolute: " .. real)
   assert(read(real) == "x\n", "the canonical path names the same file")
   assertEq(fs.canonical(dir .. "/real/../real/./file.txt"), real, "dot segments are resolved")
   local missing = fs.canonical(dir .. "/real/absent.txt")
   assertEq(missing, fs.absolute(dir .. "/real/absent.txt"),
      "a missing path keeps its absolute spelling")
   if jit.os ~= "Windows" then
      assertEq(process.run({"ln", "-s", "real", dir .. "/link"}), 0)
      assertEq(fs.canonical(dir .. "/link/file.txt"), real, "a symbolic link is followed")
      local _, printed = process.capture({"realpath", dir .. "/link/file.txt"})
      assertEq(real, (printed:gsub("%s+$", "")), "the answer agrees with realpath")
      assertEq(fs.canonical(dir .. "/link/absent.txt"), fs.absolute(dir .. "/link/absent.txt"),
         "a missing path behind a link keeps its spelling")
   end
   remove(dir)
end

function M.luarocksDependencyInstallsIntoTheProjectTree()
   local files = tinyRockFiles()
   files["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
   local dir = tempProject(files)
   assertEq(project.build(dir), 0)
   assert(exists(dir .. "/.rocks/share/lua/5.1/tinyrock.lua"),
      "the rock is installed into a tree the project owns")
   local state = json.decode(read(dir .. "/out/.nupp-state.json"))
   assertEq(#state.dependencies.tiny.key, 32,
      "a rock's cache key is the build digest, not the trailer's SHA-256")
   -- And into the running process's search path: a build that installs a
   -- renderer is a build that may render with it a moment later.
   assert(package.path:find(dir .. "/.rocks/share/lua/5.1/?.lua", 1, true),
      "the tree is added to the search path this process is using")

   -- A rock already in the tree at the version asked for is left alone, which
   -- is what keeps a warm build from reaching for the network.
   assertEq(project.build(dir), 0, "an installed rock rebuilds")
   remove(dir)
end

function M.rockDependenciesCanBeOwnedByTheManifest()
   local files = tinyRockFiles()
   files["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC:gsub(
      'dependencies = { "lua >= 5.1" }',
      'dependencies = { "lua >= 5.1", "dependency-nupp-does-not-install >= 1" }'
   )
   files["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec",
         rockDependencies = false},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
   local dir = tempProject(files)
   assertEq(project.build(dir), 0,
      "an explicitly owned rock dependency list is not resolved by LuaRocks")
   assert(exists(dir .. "/.rocks/share/lua/5.1/tinyrock.lua"),
      "disabling transitive resolution still installs the selected rock")
   remove(dir)
end

-- A rock's `nupp` directory is copied into its versioned installation beside the
-- rockspec. It is not on Lua's runtime path; Nupp alone reads the declaration that
-- mirrors the module LuaRocks installed.
function M.installedRocksProvideTypedModuleDeclarations()
   local rockspec = [[
rockspec_format = "3.0"
package = "typedrock"
version = "1.0-1"
source = { url = "file://typedrock.lua" }
description = { summary = "A typed rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = { typedrock = "typedrock.lua" },
   copy_directories = { "nupp" },
}
]]
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      typedrock = {kind = "luarocks", path = "vendor/typedrock",
         rockspec = "vendor/typedrock/typedrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"typedrock"}},
}
]],
      ["src/main.nupp"] = [[
local typedrock = require("typedrock")
local answer: integer = typedrock.answer
print(answer)
]],
      ["vendor/typedrock/typedrock.lua"] = "return {answer = 42}\n",
      ["vendor/typedrock/nupp/typedrock.d.nupp"] = [[
local answer: integer
return {answer = answer}
]],
      ["vendor/typedrock/typedrock-1.0-1.rockspec"] = rockspec,
   })
   local first = {}
   assertEq(project.build(dir, {checkOnly = true, stats = first}), 0,
      "the installed declaration is a valid module surface")
   local warm = {}
   assertEq(project.build(dir, {checkOnly = true, stats = warm}), 0,
      "an unchanged rock declaration is warm")
   assertEq(warm.reusedModules, 2,
      "the project module and external declaration are both reusable")

   write(dir .. "/vendor/typedrock/nupp/typedrock.d.nupp", [[
local answer: string
return {answer = answer}
]])
   local diagnostics = {}
   assertEq(project.build(dir, {checkOnly = true, diagnostics = diagnostics}), 1,
      "changing the installed declaration invalidates its consumer")
   assertEq(diagnostics[1] and diagnostics[1].code, "NUPP2001",
      "the rock's changed string surface rejects an integer binding")
   assert(exists(dir .. "/.rocks/lib/luarocks/rocks-5.1/typedrock/1.0-1/"
      .. "nupp/typedrock.d.nupp"), "LuaRocks carried the Nupp declaration")
   remove(dir)
end

function M.targetDependencyCanSupplyAnHmacProvider()
   local rockspec = [[
rockspec_format = "3.0"
package = "acme-crypto"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Target-selected crypto backend fixture." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = {
      ["acme.hmac_sha256"] = "provider.lua",
   },
   copy_directories = { "nupp" },
}
]]
   local provider = [[
local expected = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
local function hex(key, message)
   if key == "key" and message == "The quick brown fox jumps over the lazy dog" then
      return expected
   end
   assert(key == "" and message == "")
   return "b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad"
end
local function digest(key, message)
   local encoded = hex(key, message)
   return encoded:gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)
end
return {digest = digest, hex = hex}
]]
   local declaration = [[
module acme.cryptobackend
const Backend = require("nupp.runtime.backend")
const Hmac = require("nupp.runtime.seam.hmacsha256")
export = Backend.new("acme.crypto", {Hmac.seam("acme.hmac_sha256")})
]]
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {crypto = {kind = "luarocks", path = "vendor/crypto",
      rockspec = "vendor/crypto/acme-crypto-1.0-1.rockspec"}},
   build = {targets = {
      portable = {outDir = "out", entries = {"main"}, dialect = "lua51",
         dependencies = {"crypto"}, backends = {"acme.cryptobackend"}},
      native = {outDir = "native", entries = {"main"}, dialect = "luajit"},
   }},
}
]],
      ["src/main.nupp"] = [[
local hmac = require("nupp.data.hmac")
return hmac.hex("key", "The quick brown fox jumps over the lazy dog")
]],
      ["vendor/crypto/acme-crypto-1.0-1.rockspec"] = rockspec,
      ["vendor/crypto/provider.lua"] = provider,
      ["vendor/crypto/nupp/acme/cryptobackend.nupp"] = declaration,
   })
   local task = assert(project.describeTasks(dir, "portable"))
   assertEq(task.dependencies[1], "crypto", "the portable target owns its crypto rock")
   assertEq(task.backends[1], "acme.cryptobackend", "the same target owns its backend")
   local produced = {}
   assertEq(project.build(dir, {target = "portable", produced = produced}), 0,
      "a checked backend can name a provider from its target dependency")
   assertEq(produced.backendResolution[1].name, "crypto.hmac_sha256",
      "requiring HMAC reaches the dependency-backed seam")
   assertEq(produced.backendResolution[1].runtimeDependency.package, "acme-crypto",
      "artifact accounting names the provider package rather than its manifest alias")
   assertEq(produced.backendResolution[1].runtimeDependency.version, "1.0-1",
      "artifact accounting pins the provider package version")
   assert(exists(dir .. "/.rocks/lib/luarocks/rocks-5.1/acme-crypto/1.0-1/"
      .. "nupp/acme/cryptobackend.nupp"),
      "the target dependency carries the checked backend source")
   assert(exists(dir .. "/out/acme/cryptobackend.lua"),
      "the selected dependency backend is compiled for the consuming target")
   assert(exists(dir .. "/out/nupp/runtime/seam/hmacsha256.lua"),
      "the artifact carries the compiler-owned runtime support its backend requires")
   local script = ("package.path=%q..package.path;io.write(require('main'))")
      :format(dir .. "/out/?.lua;" .. dir .. "/.rocks/share/lua/5.1/?.lua;")
   local status, output = process.capture({"luajit", "-e", script})
   assertEq(status, 0, "the dependency-backed artifact loads its target rock: " .. tostring(output))
   assertEq(output, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
   remove(dir)
end

function M.rockDependenciesAreRefusedUnlessTheyArePinned()
   local loose = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {lunamark = {kind = "luarocks"}},
   build = {entries = {"main"}},
}
]],
   })
   local config, err = project.loadManifest(loose)
   assertEq(config, nil, "a rock naming no version is refused")
   assert(err:find("must pin the rock", 1, true), err)
   remove(loose)

   local nested = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {
      native = {kind = "c", sources = {"native.c"}},
      lunamark = {kind = "luarocks", version = "0.6.0-1",
         dependencies = {"native"}},
   },
   build = {entries = {"main"}},
}
]],
   })
   config, err = project.loadManifest(nested)
   assertEq(config, nil, "a rock does not declare what LuaRocks resolves")
   assert(err:find("LuaRocks resolves", 1, true), err)
   remove(nested)

   local wrongMode = tempProject({
      ["nupp.lua"] = [[
return {
   dependencies = {lunamark = {kind = "luarocks", version = "0.6.0-1",
      rockDependencies = "no"}},
   build = {entries = {"main"}},
}
]],
   })
   config, err = project.loadManifest(wrongMode)
   assertEq(config, nil, "the rock dependency policy is a boolean")
   assert(err:find("rockDependencies must be a boolean", 1, true), err)
   remove(wrongMode)
end

-- A version in the manifest and a version in the rockspec are two claims about
-- one rock, and a build that installed whichever it read last would be pinned
-- to neither.
function M.rockVersionMustAgreeWithItsRockspec()
   local files = tinyRockFiles()
   files["nupp.lua"] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", version = "2.0-1",
         path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
   local dir = tempProject(files)
   assertEq(project.build(dir), 1, "a disagreeing version fails the build")
   assert(not exists(dir .. "/.rocks"), "and installs nothing")
   remove(dir)
end

-- A bundle carries modules, not files, so what a rock's files are called on the
-- way in is what `require` calls them on the way out.
function M.bundledRockModulesAreNamedTheWayRequireFindsThem()
   local dir = tempProject({
      [".rocks/share/lua/5.1/lunamark.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/lunamark/util.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/lunamark/writer/html.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/cosmo/init.lua"] = "return {}\n",
      [".rocks/share/lua/5.1/unasked.lua"] = "return {}\n",
   })
   local config = {
      dependencies = {
         lunamark = {
            kind = "luarocks", version = "0.6.0-1",
            bundle = {"lunamark.lua", "lunamark/**.lua", "cosmo/init.lua"},
         },
      },
   }
   local carried = deps.rockModules(dir, config, {dependencies = {"lunamark"}})
   local names = {}
   for _, module in ipairs(carried) do names[#names + 1] = module.name end
   assertEq(table.concat(names, " "),
      "cosmo lunamark lunamark.util lunamark.writer.html",
      "a directory module keeps its init, a nested one keeps its path")

   assertEq(deps.rockModules(dir, config, {dependencies = {}})[1], nil,
      "a target that asks for no rock carries none")
   local unasked = {
      dependencies = {lunamark = {kind = "luarocks", version = "0.6.0-1"}},
   }
   assertEq(deps.rockModules(dir, unasked, {dependencies = {"lunamark"}})[1], nil,
      "and a rock with no bundle globs is installed rather than carried")
   remove(dir)
end

-- What a test command has to be told, since it is a fresh interpreter that has
-- never heard of the tree the build installed into.
function M.rockPathsNameTheTreesATargetDependsOn()
   local config = {
      dependencies = {
         tiny = {kind = "luarocks", version = "1.0-1", tree = "vendor/rocks"},
         native = {kind = "c", sources = {"native.c"}},
      },
   }
   local paths = deps.rockPaths("/project", config,
      {dependencies = {"tiny", "native"}})
   assertEq(paths.path, "/project/vendor/rocks/share/lua/5.1/?.lua;"
      .. "/project/vendor/rocks/share/lua/5.1/?/init.lua",
      "the tree's Lua templates, in the order require reads them")
   assertEq(paths.cpath, "/project/vendor/rocks/lib/lua/5.1/"
      .. (jit.os == "Windows" and "?.dll" or "?.so"))
   assertEq(paths.typeRoots[1], "/project/vendor/rocks/lib/luarocks/"
      .. "rocks-5.1/tiny/1.0-1/nupp",
      "the pinned rock version names its declaration root without installing it")
   assertEq(deps.rockPaths("/project", config, {dependencies = {"native"}}), nil,
      "a target with no rocks needs nothing added to its path")
end

function M.testCommandBuildsThenRunsArgv()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
   test = {argv = {"luajit", "test.lua"}},
}
]],
      ["src/main.nupp"] = "return true\n",
      ["test.lua"] = "local f=assert(io.open('test-ran','wb')); f:write('yes'); f:close()\n",
   })
   assertEq(project.test(dir), 0)
   assertEq(read(dir .. "/test-ran"), "yes")
   assert(exists(dir .. "/out/main.lua"), "test builds first")
   remove(dir)
end

-- Unlike test, a task only builds when it names a target -- most won't, since
-- most of what a task runs (a dev server, a release script) isn't "the code
-- under test" the way a test command's subject always is.
function M.namedTaskRunsItsArgvWithoutBuildingByDefault()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   tasks = {
      greet = {argv = {"luajit", "greet.lua"}},
   },
}
]],
      ["greet.lua"] = "local f=assert(io.open('task-ran','wb')); f:write('hi'); f:close()\n",
   })
   assertEq(project.runTask(dir, "greet"), 0)
   assertEq(read(dir .. "/task-ran"), "hi")
   assert(not exists(dir .. "/build"), "a task with no build key builds nothing")
   remove(dir)
end

function M.namedTaskBuildsFirstWhenItNamesATarget()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", default = "app",
      targets = {app = {entries = {"main"}}}},
   tasks = {
      greet = {build = "app", argv = {"luajit", "greet.lua"}},
   },
}
]],
      ["src/main.nupp"] = "return true\n",
      ["greet.lua"] = "local f=assert(io.open('task-ran','wb')); f:write('hi'); f:close()\n",
   })
   assertEq(project.runTask(dir, "greet"), 0)
   assert(exists(dir .. "/out/main.lua"), "a task naming a build target builds first")
   remove(dir)
end

function M.namedTaskAppendsTrailingArgsToItsArgv()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {
   include = {"src"},
   tasks = {greet = {argv = {"luajit", "greet.lua"}}},
}
]],
      ["greet.lua"] = [[
local f = assert(io.open('task-args', 'wb'))
f:write(table.concat(arg, ','))
f:close()
]],
   })
   assertEq(project.runTask(dir, "greet", {"a", "b"}), 0)
   assertEq(read(dir .. "/task-args"), "a,b")
   remove(dir)
end

function M.unknownTaskNameFails()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, tasks = {greet = {argv = {"echo", "hi"}}}}
]],
   })
   local errorPath = os.tmpname()
   local originalStderr = io.stderr
   io.stderr = assert(io.open(errorPath, "wb"))
   local status = project.runTask(dir, "nonexistent")
   io.stderr:close()
   io.stderr = originalStderr
   os.remove(errorPath)
   assertEq(status, 1, "an unconfigured task name fails rather than running nothing quietly")
   remove(dir)
end

function M.pkgConfigFlagsUseShellWordQuotingWithoutRunningAShell()
   local words = assert(buildSyntax.shellWords:match(
      [[-I"include dir" '-DNAME=two words' plain\ flag "" ab"cd"'ef']]))
   assertEq(table.concat(words, "\0"),
      table.concat({"-Iinclude dir", "-DNAME=two words", "plain flag", "", "abcdef"}, "\0"))
   assertEq(#assert(buildSyntax.shellWords:match(" \t\n")), 0)
   local malformed = buildSyntax.shellWords:match([["unclosed]])
   assertEq(malformed, nil)
end

function M.makeDepfilesPreserveEscapedPathsAndContinuations()
   local paths = assert(buildSyntax.depfile:match(
      "nupp_header: one.h two\\ three.h \\\n four\\#five.h one.h # ignored\n"))
   assertEq(table.concat(paths, "\0"),
      table.concat({"one.h", "two three.h", "four#five.h", "one.h"}, "\0"))
   assertEq(buildSyntax.depfile:match("not a depfile"), nil)
end

function M.buildGlobsTreatDoubleStarAsZeroOrMoreDirectories()
   local component = buildSyntax.glob("src/*/file?.nupp")
   assert(component("src/one/file1.nupp"))
   assert(not component("src/one/two/file1.nupp"))
   assert(not component("src/one/file12.nupp"))
   local directories = buildSyntax.glob("src/**/file.nupp")
   assert(directories("src/file.nupp"))
   assert(directories("src/one/two/file.nupp"))
   assert(not directories("src/one/two/not-file.nupp"))

   local dir = tempProject({
      ["src/root.nupp"] = "return 1\n",
      ["src/nested/child.nupp"] = "return 2\n",
      ["src/nested/child.lua"] = "return 3\n",
   })
   local matches = deps.expandGlob(dir, "src/**/*.nupp")
   table.sort(matches)
   assertEq(#matches, 2)
   assertEq(matches[1], dir .. "/src/nested/child.nupp")
   assertEq(matches[2], dir .. "/src/root.nupp")
   remove(dir)
end

return M
