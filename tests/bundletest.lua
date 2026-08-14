-- `kind = "bundle"`: a target that comes out as one Lua file.
--
-- The file is the deliverable on its own — it runs under a plain luajit with
-- nothing beside it — and it is also the payload a stub carries, so what is
-- asserted here is what docs/distribution.md promises about payloads.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"
local packaging = require("nupp.compiler.build.package")

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for name, text in pairs(files) do
      local sub = name:match("^(.*)/[^/]+$")
      if sub then
         assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
      end
      local f = assert(io.open(dir .. "/" .. name, "wb"))
      f:write(text)
      f:close()
   end
   return dir
end

local function readFile(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local text = f:read("*a")
   f:close()
   return text
end

local function run(dir, argv)
   local outfile = os.tmpname()
   local status = os.execute(("cd '%s' && %s > '%s' 2>&1")
      :format(dir, argv, outfile))
   local out = readFile(outfile) or ""
   os.remove(outfile)
   return out, status == 0
end

local MANIFEST = [[
return {
   include = { "src" },
   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "bundle",
            entries = { "app.main" },
            resources = { "src/app/data/*.txt" },
         },
      },
   },
}
]]

local MAIN = [[
local greet = require("app.greet")
print(greet.hello("world"))

-- Absent when this runs from a build tree rather than a bundle, which is the
-- whole distinction being tested.
local loader = package.preload["nupp.embedded"]
if loader then
    print(tostring(loader()["/data/note.txt"]))
end
]]

local GREET = [[
local greet = {}

function greet.hello(who: string): string
    return "hello, " .. who
end

return greet
]]

local M = {}

function M.compilerHostPreambleMasksUniversalStubFeaturesBeforeUserCode()
   local dir = tempProject({
      ["build/main.lua"] = [[
assert(rawget(_G, "__nuppHost") == nil)
local name = "lp" .. "eg"
local loaded = pcall(require, name)
return loaded
]],
   })
   local target = {kind = "binary", outDir = "build", entries = {"main"}}
   local modules = {main = {output = dir .. "/build/main.lua"}}
   local text = assert(packaging.bundleText(
      dir, {}, target, nil, modules, false, {}, {"cjson"}
   ))
   local again = assert(packaging.bundleText(
      dir, {}, target, nil, modules, false, {}, {"cjson"}
   ))
   assert(text == again, "the payload depends on selected features, not ambient stub state")

   local savedPreloads, savedLoaded = {}, package.loaded.lpeg
   local savedPath, savedCpath = package.path, package.cpath
   for _, name in ipairs({"cjson", "cjson.safe", "lpeg", "lua-utf8", "nupp.workers.native"}) do
      savedPreloads[name] = package.preload[name]
      package.preload[name] = function() return name end
   end
   package.loaded.lpeg = nil
   package.path, package.cpath = "", ""
   _G.__nuppHost = {hostAbi = 1, hostFeatures = {
      cjson = true,
      lpeg = true,
      ["lua-utf8"] = true,
      workers = true,
   }}
   local loaded = assert(loadstring(text))()
   assert(not loaded, "a computed require cannot observe an unselected universal feature")
   assert(package.preload.cjson and package.preload["cjson.safe"],
      "selected cjson openers remain visible")
   assert(package.preload.lpeg == nil and package.preload["lua-utf8"] == nil
      and package.preload["nupp.workers.native"] == nil,
      "unselected universal openers are removed")
   assert(_G.__nuppHost == nil, "the private handshake is gone before user code")
   package.loaded.lpeg = savedLoaded
   package.path, package.cpath = savedPath, savedCpath
   for name, opener in pairs(savedPreloads) do package.preload[name] = opener end
   package.preload["nupp.embedded"] = nil
   os.execute("rm -rf '" .. dir .. "'")
end

function M.machOPackagingReplacesTheStubSignatureWithASignableLayout()
   local function little(value, width)
      local bytes = {}
      for index = 1, width do
         bytes[index] = string.char(value % 256)
         value = math.floor(value / 256)
      end
      return table.concat(bytes)
   end
   local header = "\207\250\237\254" .. little(0x0100000c, 4)
      .. little(0, 4) .. little(2, 4) .. little(2, 4) .. little(88, 4)
      .. little(0, 4) .. little(0, 4)
   local linkedit = little(0x19, 4) .. little(72, 4) .. "__LINKEDIT" .. ("\0"):rep(6)
      .. little(0x1000, 8) .. little(0x1000, 8) .. little(120, 8) .. little(8, 8)
      .. little(1, 4) .. little(1, 4) .. little(0, 4) .. little(0, 4)
   local signature = little(0x1d, 4) .. little(16, 4) .. little(120, 4) .. little(8, 4)
   local stub = header .. linkedit .. signature .. "SIGNHERE"
   local dir = tempProject({})
   local output = dir .. "/app"
   assert(packaging.stampFile(output, stub, "return true\n", "aarch64-apple-darwin"))
   local bytes = assert(readFile(output))
   assert(bytes:sub(-48, -41) == "NUPPLOAD", "the unsigned trailer ends the stamped file")
   assert(bytes:sub(17, 20) == little(1, 4), "the old signature load command is removed")
   assert(bytes:sub(21, 24) == little(72, 4), "the load-command byte count is updated")
   assert(bytes:sub(81, 88) == little(#bytes - 120, 8),
      "__LINKEDIT covers the payload and trailer for the next signer")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.aWorkerPayloadCarriesRuntimeModulesAndDispatchesItsEntry()
   local dir = tempProject({
      ["build/main.lua"] = "return 'main'\n",
      ["build/jobs/hash.lua"] = "return 'worker'\n",
      ["build/nupp/suspension.lua"] = "return {runtime = 'suspension'}\n",
      ["build/nupp/workers.lua"] = "return {runtime = 'workers'}\n",
   })
   local text, problem = packaging.bundleText(dir, {}, {
      kind = "binary",
      outDir = "build",
      entries = {"main"},
   }, nil, {
      main = {output = dir .. "/build/main.lua"},
      ["jobs.hash"] = {output = dir .. "/build/jobs/hash.lua"},
   }, true, {"nupp.suspension", "nupp.workers"})
   assert(text, "the worker payload is assembled: " .. tostring(problem))
   assert(text:find('package.preload["nupp.suspension"]', 1, true),
      "the suspension runtime is carried")
   assert(text:find('package.preload["nupp.workers"]', 1, true),
      "the workers runtime is carried")
   assert(text:find('package.preload["main"]', 1, true),
      "the ordinary entry becomes selectable")
   assert(text:find('__nuppWorkerEntry', 1, true)
      and text:find('return require(__nuppEntry or "main")', 1, true),
      "one dispatcher selects the worker or ordinary entry")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.workersRefuseTargetsWithoutTheCompilerOwnedHost()
   local function rejected(kind, stub)
      local manifest = ([[
return {
   include = {"src"},
   build = {default = "app", targets = {app = {
      kind = %q, entries = {"main"}, stub = %s,
   }}},
}
]]):format(kind, stub and string.format("%q", stub) or "nil")
      local dir = tempProject({
         ["nupp.lua"] = manifest,
         ["src/main.nupp"] = 'local workers = require("nupp.workers")\nreturn workers\n',
      })
      local out, ok = run(dir, "'" .. NUPP .. "' build")
      os.execute("rm -rf '" .. dir .. "'")
      assert(not ok and out:find('workers currently require a binary target with stub = "nupp"', 1, true),
         kind .. " with " .. tostring(stub) .. " is refused before runtime: " .. out)
   end

   rejected("modules")
   rejected("bundle")
   rejected("binary", "third-party-host")
end

-- One file, runnable by an interpreter that has never heard of nupp.
function M.aBundleRunsUnderAPlainInterpreter()
   local dir = tempProject({
      ["nupp.lua"] = MANIFEST,
      ["src/app/main.g.nupp"] = MAIN,
      ["src/app/greet.g.nupp"] = GREET,
      ["src/app/data/note.txt"] = "carried along\n",
   })
   local out, ok = run(dir, "'" .. NUPP .. "' build")
   assert(ok, "the bundle target builds: " .. out)
   local bundle = readFile(dir .. "/build/app.lua")
   assert(bundle, "the bundle was written to build/app.lua")

   local ran, ranOk = run(dir, "luajit build/app.lua")
   assert(ranOk, "the bundle runs on its own: " .. ran)
   assert(ran:find("hello, world", 1, true),
      "its modules are reachable through package.preload: " .. ran)
   assert(ran:find("carried along", 1, true),
      "and its resources came with it: " .. ran)
   os.execute("rm -rf '" .. dir .. "'")
end

-- Nothing beside it. A bundle that still needed its build tree would be a
-- bundle in name only, and the failure would be somebody else's, later.
function M.aBundleNeedsNothingFromTheTreeItCameFrom()
   local dir = tempProject({
      ["nupp.lua"] = MANIFEST,
      ["src/app/main.g.nupp"] = MAIN,
      ["src/app/greet.g.nupp"] = GREET,
      ["src/app/data/note.txt"] = "carried along\n",
   })
   assert(select(2, run(dir, "'" .. NUPP .. "' build")), "builds")

   local elsewhere = os.tmpname()
   os.remove(elsewhere)
   assert(os.execute("mkdir -p '" .. elsewhere .. "'") == 0)
   assert(os.execute(("cp '%s/build/app.lua' '%s/alone.lua'")
      :format(dir, elsewhere)) == 0)
   os.execute("rm -rf '" .. dir .. "'")

   local ran, ok = run(elsewhere, "luajit alone.lua")
   assert(ok, "the copy runs with its whole project deleted: " .. ran)
   assert(ran:find("hello, world", 1, true) and ran:find("carried along", 1, true),
      "modules and resources both survived the move: " .. ran)
   os.execute("rm -rf '" .. elsewhere .. "'")
end

-- Byte-identical across builds. The packaging fixpoint rests on this, and a
-- bundle that embedded a timestamp or a hash-order would fail it in a way that
-- reproduces once a week.
function M.twoBuildsOfOneTreeProduceIdenticalBytes()
   local dir = tempProject({
      ["nupp.lua"] = MANIFEST,
      ["src/app/main.g.nupp"] = MAIN,
      ["src/app/greet.g.nupp"] = GREET,
      ["src/app/data/note.txt"] = "carried along\n",
      ["src/app/data/second.txt"] = "and another\n",
   })
   assert(select(2, run(dir, "'" .. NUPP .. "' build")), "first build")
   local first = readFile(dir .. "/build/app.lua")
   -- From scratch, so nothing is reused: the ordering has to be decided by the
   -- bundler rather than by whatever order the last build left behind.
   os.execute("rm -rf '" .. dir .. "/build'")
   assert(select(2, run(dir, "'" .. NUPP .. "' build")), "second build")
   local second = readFile(dir .. "/build/app.lua")
   assert(first == second, "two cold builds produce the same bundle")
   os.execute("rm -rf '" .. dir .. "'")
end

-- A resource staged beside the entry's directory rather than under it has no
-- name a running program could ask for. It is left out and said out loud.
function M.resourcesThatCannotBeNamedAreReported()
   local manifest = MANIFEST:gsub('"src/app/data/%*%.txt"',
      '"src/app/data/*.txt", "extra/*.txt"')
   local dir = tempProject({
      ["nupp.lua"] = manifest,
      ["src/app/main.g.nupp"] = MAIN,
      ["src/app/greet.g.nupp"] = GREET,
      ["src/app/data/note.txt"] = "carried along\n",
      ["extra/loose.txt"] = "not reachable\n",
   })
   local out, ok = run(dir, "'" .. NUPP .. "' build")
   assert(ok, "the build still succeeds: " .. out)
   assert(out:find("could not be bundled", 1, true),
      "and says what it could not carry: " .. out)
   local bundle = readFile(dir .. "/build/app.lua")
   assert(not bundle:find("not reachable", 1, true),
      "the unreachable resource is not embedded under a name nothing reads")
   assert(bundle:find("carried along", 1, true), "the reachable one still is")
   os.execute("rm -rf '" .. dir .. "'")
end

-- The output directory is also where native dependencies build, and their trees
-- are full of .lua that is examples, tests and scripts. One of lua-cjson's opens
-- with a hashbang, which is a syntax error once a preload wraps it in a
-- function — so a bundle carries what the build compiled, not what it finds.
function M.aBundleCarriesWhatTheBuildCompiledNotWhatIsLyingAround()
   local dir = tempProject({
      ["nupp.lua"] = MANIFEST,
      ["src/app/main.g.nupp"] = MAIN,
      ["src/app/greet.g.nupp"] = GREET,
      ["src/app/data/note.txt"] = "carried along\n",
   })
   assert(select(2, run(dir, "'" .. NUPP .. "' build")), "builds")
   -- A native dependency's tree, arriving in the output directory after the
   -- fact the way cargo's does.
   assert(os.execute("mkdir -p '" .. dir .. "/build/native/examples'") == 0)
   local intruder = assert(io.open(dir .. "/build/native/examples/tool.lua", "wb"))
   intruder:write("#!/usr/bin/env lua\nprint('not a module')\n")
   intruder:close()

   local out, ok = run(dir, "'" .. NUPP .. "' build")
   assert(ok, "the build still succeeds: " .. out)
   local bundle = readFile(dir .. "/build/app.lua")
   assert(not bundle:find("not a module", 1, true),
      "somebody else's script is not preloaded as a module")
   local ran, ranOk = run(dir, "luajit build/app.lua")
   assert(ranOk, "and the bundle still parses and runs: " .. ran)
   os.execute("rm -rf '" .. dir .. "'")
end

-- A rock is a library the program needs and the bundle cannot leave behind: a
-- binary handed to somebody with no rock tree still has to run every command it
-- claims to have. What it carries is what the manifest named, under the name
-- `require` would have found it by in the tree it came from.
local ROCK_MANIFEST = [[
return {
   include = { "src" },
   dependencies = {
      tiny = {
         kind = "luarocks",
         rock = "tinyrock",
         path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec",
         bundle = { "tinyrock.lua" },
      },
   },
   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "bundle",
            entries = { "app.main" },
            dependencies = { "tiny" },
         },
      },
   },
}
]]

local ROCK_MAIN = [[
local tiny = require("tinyrock")
print("answer " .. tostring(tiny.answer))
]]

local TINY_ROCKSPEC = [[
package = "tinyrock"
version = "1.0-1"
source = { url = "file://tinyrock.lua" }
description = { summary = "A rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = { type = "builtin", modules = { tinyrock = "tinyrock.lua" } }
]]

function M.aBundleCarriesTheRockModulesItWasToldTo()
   local dir = tempProject({
      ["nupp.lua"] = ROCK_MANIFEST,
      ["src/app/main.g.nupp"] = ROCK_MAIN,
      ["vendor/tinyrock/tinyrock.lua"] = "return {answer = 42}\n",
      ["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC,
   })
   local out, ok = run(dir, "'" .. NUPP .. "' build")
   assert(ok, "the bundle target builds: " .. out)

   -- With an empty search path, so nothing installed on this machine can
   -- answer the require: what runs is what the bundle brought.
   local ran, ranOk = run(dir, "LUA_PATH= LUA_CPATH= luajit build/app.lua")
   assert(ranOk, "the bundle runs with nothing on its path: " .. ran)
   assert(ran:find("answer 42", 1, true),
      "the rock's module came with it: " .. ran)
   os.execute("rm -rf '" .. dir .. "'")
end

-- The compiler's own stage-0 bundle goes through this same code. If the two
-- ever diverge, the bootstrap is being produced by a path nothing else tests.
function M.theBootstrapIsProducedByTheGeneralBundler()
   local root = HERE .. "/.."
   local bootstrap = readFile(root .. "/bootstrap/nupp.lua")
   assert(bootstrap, "the tracked bootstrap is readable")
   assert(bootstrap:find('package.preload["nupp.embedded"]', 1, true),
      "it carries its resources the way every bundle does")
   assert(bootstrap:find("package.preload[\"nupp.compiler.cst\"]", 1, true),
      "and preloads its modules the way every bundle does")
end

-- The standard library is this compiler's own Nupp, and it is carried as source
-- rather than described by a second declaration of itself. A project outside the
-- tree therefore types against exactly what was compiled into the binary it runs.
-- Before this it resolved to nothing, and gradual typing turned that into `any`
-- without a word — which then surfaced three steps later as an ownership error.
local STD_MANIFEST = 'return {include = {"."}}\n'

function M.theStandardLibraryIsTypedOutsideThisTree()
   local dir = tempProject({
      ["nupp.lua"] = STD_MANIFEST,
      ["typed.nupp"] = [[
local resources = require("nupp.resources")

local wrong: integer = resources.openFile("x", "r")

return wrong
]],
   })
   local out = run(dir, "'" .. NUPP .. "' check --strict typed.nupp")
   assert(out:find("NUPP2001", 1, true),
      "the std surface is typed, not any: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

-- Typed is not enough on its own: the ownership contract has to cross too, or an
-- ordinary local cannot arrange automatic cleanup.
function M.theStandardLibraryCarriesItsOwnershipOutsideThisTree()
   local dir = tempProject({
      ["nupp.lua"] = STD_MANIFEST,
      ["input.txt"] = "hello\n",
      ["acquire.nupp"] = [[
local resources = require("nupp.resources")

do
    local file = resources.openFile("input.txt", "r")
    print(file:read("*a"))
end
]],
      ["leak.nupp"] = [[
local resources = require("nupp.resources")

local handle = resources.openFile("input.txt", "r")

return 1
]],
   })
   local acquired, acquiredOk = run(dir, "'" .. NUPP .. "' run acquire.nupp")
   assert(acquiredOk and acquired == "hello\n\n",
      "the standard-library private cleanup links and runs: " .. acquired)

   -- The obligation crosses too, which is the other half of the contract being
   -- real rather than erased at the boundary. An untouched ordinary owner is
   -- now discharged by its lexical scope rather than diagnosed as forgotten.
   local checked, checkOk = run(dir, "'" .. NUPP .. "' check --strict leak.nupp")
   assert(checkOk and not checked:find("NUPP2603", 1, true),
      "the ordinary owner receives automatic cleanup: " .. checked)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.theWorkersSurfaceIsTypedAndOwnedOutsideThisTree()
   local dir = tempProject({
      ["nupp.lua"] = STD_MANIFEST,
      ["typed.nupp"] = [[
local workers = require("nupp.workers")
local wrong: integer = workers.current
return wrong
]],
      ["owned.nupp"] = [[
local workers = require("nupp.workers")
do
    local worker = workers.spawn("job")
    worker:close()
end
return true
]],
   })
   local typed = run(dir, "'" .. NUPP .. "' check --strict typed.nupp")
   assert(typed:find("NUPP2001", 1, true),
      "the workers surface is typed rather than gradual: " .. typed)
   local owned, ok = run(dir, "'" .. NUPP .. "' check --strict owned.nupp")
   assert(ok and not owned:find("NUPP2603", 1, true),
      "a worker local carries its automatic stop obligation: " .. owned)
   os.execute("rm -rf '" .. dir .. "'")
end

return M
