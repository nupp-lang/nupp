local project = require("nupp.compiler.build.project")
local deps = require("nupp.compiler.build.deps")
local hash = require("nupp.compiler.build.hash")
local process = require("nupp.compiler.build.process")
local store = require("nupp.compiler.build.store")
local nativeStage = require("nupp.compiler.build.native")
local fs = require("nupp.compiler.fs")
local compilerEnv = require("nupp.compiler.env")
local json = require("cjson").new()

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

local function exists(path)
   local f = io.open(path, "rb")
   if not f then return false end
   f:close()
   return true
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

local function libraryName(name)
   if jit.os == "Windows" then return name .. ".dll" end
   if jit.os == "OSX" then return "lib" .. name .. ".dylib" end
   return "lib" .. name .. ".so"
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
      return hash.hex64(hash.xxh64(input, seed))
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
      local pipe = assert(io.popen("luajit -e " .. ("%q"):format(script)))
      local out = pipe:read("*l")
      pipe:close()
      return out
   end
   local cwd = assert(io.popen("pwd"))
   local here = cwd:read("*l")
   cwd:close()
   local relative = fingerprintUnder("")
   assert(relative and relative ~= "", "the relative run produced a digest")
   assertEq(fingerprintUnder(here .. "/"), relative,
      "the same compiler fingerprints the same either way")
end

function M.windowsMkdirUsesNativePathAndIsIdempotent()
   local command = process.mkdirCommand("build/nupp", true)
   assertEq(table.concat(command, " "),
      "cmd /d /c if not exist build\\nupp mkdir build\\nupp")

   local posix = process.mkdirCommand("build/nupp", false)
   assertEq(table.concat(posix, " "), "mkdir -p build/nupp")
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
const Matcher: nupp.Peg.Matcher<integer> = comptime do
    return nupp.peg.compile(nupp.peg.literal("ok"))
end
return Matcher("ok")
]],
   })
   local cold, coldStats = {}, {}
   assertEq(project.build(dir, {produced = cold, stats = coldStats}), 0)
   assertEq(#cold.materializations, 1, "the cold build reports its materialization")
   local observation = cold.materializations[1]
   assertEq(observation.provider, "peg", "provider observation")
   assertEq(observation.schema, 2, "provider schema")
   assertEq(observation.backend, "vm", "selected backend")
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
   reject('{kind = "docs", sources = {"src"}, pages = {{heroTitel = "x"}}}',
      'pages[1] has no key "heroTitel"; did you mean "heroTitle"?')
   reject('{kind = "docs", sources = {"src"}, pages = {{heroActions = '
      .. '{{text = "G", them = "brand"}}}}}',
      'heroActions[1] has no key "them"; did you mean "theme"?')
   reject('{kind = "docs", sources = {"src"}, pages = {{features = '
      .. '{{icon = "x", detials = "d"}}}}}',
      'features[1] has no key "detials"; did you mean "details"?')
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
         heroTitle = "T", hero_text = "S", heroImage = "i.png",
         heroImageAlt = "A", heroActions = {{text = "G", path = "g",
         theme = "brand"}}, features = {{icon = "x", image = "y",
         title = "T", details = "D"}}}},
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

   local config, err, task = load("{cjson = true, lua_utf8 = false, path = true, sha256 = false}")
   assert(config, "boolean native feature overrides are accepted: " .. tostring(err))
   assertEq(task.nativeFeatures.cjson, true, "task reports forced inclusion")
   assertEq(task.nativeFeatures.lua_utf8, false, "task reports forced removal")
   assertEq(task.nativeFeatures.path, true, "new native providers can be forced in")
   assertEq(task.nativeFeatures.sha256, false, "new native providers can be forced out")

   local _, unknown = load("{cjsoon = true}")
   assert(unknown and unknown:find("nativeFeatures names no feature cjsoon", 1, true),
      tostring(unknown))
   local _, wrongType = load("{cjson = 'yes'}")
   assert(wrongType and wrongType:find(
      "nativeFeatures.cjson must be true or false", 1, true), tostring(wrongType))
end

function M.sharedNativeFacilitiesBuildOneFeatureGatedProvider()
   local originalCapture, originalCopy = process.capture, fs.copyFile
   local originalCompilerRoot = compilerEnv.compilerRoot
   local calls, copies = {}, {}
   process.capture = function(argv)
      calls[#calls + 1] = argv
      return 0, ""
   end
   fs.copyFile = function(source, destination)
      copies[#copies + 1] = {source, destination}
      return true
   end
   compilerEnv.compilerRoot = function() return "." end
   local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {
      ["native.path"] = true,
      ["native.sha256"] = true,
   })
   process.capture, fs.copyFile = originalCapture, originalCopy
   compilerEnv.compilerRoot = originalCompilerRoot
   assert(ok, outputs)
   assert(outputs, problem)
   assertEq(#calls, 1, "one Cargo provider build serves both facilities")
   assertEq(#copies, 1, "the shared library is staged once")
   local command = table.concat(calls[1], "\n")
   assert(command:find("--no-default-features", 1, true),
      "provider disables unselected Cargo features")
   assert(command:find("path,sha256", 1, true),
      "provider enables the selected feature union")
   assert(copies[1][2]:find("out/lib/nupp_native", 1, true),
      "provider has one stable public sidecar name")
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
   assert(exists(dir .. "/out/.nupp-complete"), "completion marker is written last")
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
      for _, name in ipairs({"headers.buf", "checks.buf"}) do
         write(dir .. "/out/cache/" .. name, damage)
      end
      assertEq(answerOf(), cold, "a damaged cache gives the cold answer")
   end

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

function M.ownCleanupListsInvalidateIncrementalInterfaces()
   local function library(cleanup)
      return table.concat({
         "@owned(" .. cleanup .. ")",
         "cdef function create(): voidptr",
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
      "@owned cleanup changes recheck dependents")
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

function M.cargoDependencyBuildsCdylib()
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
   -- And into the running process's search path: a build that installs a
   -- renderer is a build that may render with it a moment later.
   assert(package.path:find(dir .. "/.rocks/share/lua/5.1/?.lua", 1, true),
      "the tree is added to the search path this process is using")

   -- A rock already in the tree at the version asked for is left alone, which
   -- is what keeps a warm build from reaching for the network.
   assertEq(project.build(dir), 0, "an installed rock rebuilds")
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

return M
