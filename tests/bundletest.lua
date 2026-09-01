-- `kind = "bundle"`: a target that comes out as one Lua file.
--
-- The file is the deliverable on its own — it runs under a plain luajit with
-- nothing beside it — and it is also the payload a stub carries, so what is
-- asserted here is what docs/reference/distribution.md promises about payloads.
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

-- What the launcher writes about its own progress, which is not what these cases
-- are reading. Named exactly rather than matched by prefix: a diagnostic the
-- compiler wrote is also spelled `nupp: ...`, and several cases below are
-- checking for one.
local LAUNCHER_NOTICES = {
   "nupp: sources changed, building the compiler\n",
   "nupp: falling back to the bootstrap compiler\n",
   "nupp: the compiler did not build; running the last one that did\n",
}

-- What the program said, without what the launcher said about getting there.
--
-- These cases compare output exactly, and the launcher writes its own progress
-- to standard error -- "sources changed, building the compiler" -- whenever a
-- concurrent shard is mid-build and this tree looks unbuilt. That notice is
-- about the toolchain rather than about the program, and a case that failed on
-- it was reporting a race in the test runner as a fault in the bundle.
local function run(dir, argv)
   local outfile = os.tmpname()
   local status = os.execute(("cd '%s' && %s > '%s' 2>&1")
      :format(dir, argv, outfile))
   local out = readFile(outfile) or ""
   os.remove(outfile)
   -- A program that prints a newline on Windows writes a return with it, which
   -- is the C runtime doing what it is for rather than anything about the
   -- program. These cases compare what was printed, so they compare the line
   -- and not the platform's spelling of the end of one.
   out = out:gsub("\r\n", "\n")
   for _, notice in ipairs(LAUNCHER_NOTICES) do
      out = out:gsub(notice, "")
   end
   return out, status == 0
end

local RUST_HOST

local function rustHost()
   if RUST_HOST then return RUST_HOST end
   local root = HERE .. "/.."
   local output, ok = run(root, "'" .. root .. "/scripts/toolchain' host-rust")
   assert(ok, "the Rust host builds: " .. output)
   RUST_HOST = output:match("([^\n]+)\n?$")
   assert(RUST_HOST and readFile(RUST_HOST), "the Rust host path is reported: " .. output)
   return RUST_HOST
end

local function stampRustHost(dir, payload)
   local suffix = package.config:sub(1, 1) == "\\" and ".exe" or ""
   local output = dir .. "/build/app-rust" .. suffix
   local written, problem = packaging.stampFile(
      output,
      assert(readFile(rustHost())),
      assert(readFile(payload)),
      nil,
      0
   )
   assert(written, "the Rust host accepts the Nupp payload: " .. tostring(problem))
   return "./build/app-rust" .. suffix
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

local COMPONENT_MANIFEST = [[
return {
   include = {"src"},
   build = {
      kind = "component",
      outDir = "build",
      entries = {"app.main"},
      exports = {"game.answer"},
   },
}
]]

function M.aComponentInstallsBeforeItsEntryRuns()
   local dir = tempProject({
      ["nupp.lua"] = COMPONENT_MANIFEST,
      ["src/app/main.g.nupp"] = [[
assert(component_started == nil)
component_started = true
return true
]],
      ["src/game.g.nupp"] = [[
local game = {}
function game.answer(value: integer): integer
   return value + 1
end
return game
]],
   })
   local out, ok = run(dir, "'" .. NUPP .. "' build")
   assert(ok, "the component target builds: " .. out)
   local artifact = readFile(dir .. "/build/component.nuppc")
   local marker = "-- NUPP-COMPONENT 1"
   assert(artifact and artifact:sub(1, #marker) == marker, "the component has a version marker")

   local script = [[
_G.__nuppHost = {hostAbi = 1, hostFeatures = {}}
local descriptor = assert(loadfile("build/component.nuppc"))()
assert(component_started == nil)
local component = descriptor.install()
assert(component_started == nil)
assert(component.exports["game.answer"](41) == 42)
assert(component_started == nil)
component.start()
assert(component_started == true)
]]
   local scriptFile = assert(io.open(dir .. "/run.lua", "wb"))
   scriptFile:write(script)
   scriptFile:close()
   local ran, ranOk = run(dir, "luajit run.lua")
   assert(ranOk, "an installed component starts explicitly: " .. ran)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.componentsShareOneRuntimeAndRejectNameCollisions()
   local dir = tempProject({
      ["build/one/main.lua"] = "return {call=function(n) return n + 1 end}\n",
      ["build/two/main.lua"] = "return {call=function(n) return n + 2 end}\n",
   })
   local function artifact(entry, exported)
      local path = dir .. "/build/" .. entry:gsub("%.", "/") .. ".lua"
      local text = assert(packaging.bundleText(dir, {}, {
         kind = "component", outDir = "build", entries = {entry}, exports = {exported},
      }, nil, {[entry] = {output = path}}, false, nil, {}, {}, true))
      return text
   end
   local one = assert(loadstring(artifact("one.main", "one.main.call")))()
   local two = assert(loadstring(artifact("two.main", "two.main.call")))()
   local collision = assert(loadstring(artifact("one.main", "one.main.other")))()
   local savedHost, savedPublic = _G.__nuppHost, _G.__nuppComponentExports
   _G.__nuppHost = {hostAbi = 1, hostFeatures = {}}
   local first = one.install()
   local second = two.install()
   assert(first.exports["one.main.call"](40) == 41)
   assert(second.exports["two.main.call"](40) == 42)
   local installed, problem = pcall(collision.install)
   assert(not installed and tostring(problem):find("component module collision: one.main", 1, true),
      "a colliding component is refused before replacing the first")
   assert(first.exports["one.main.call"](1) == 2, "the prior component remains installed")
   package.loaded["one.main"], package.loaded["two.main"] = nil, nil
   package.preload["one.main"], package.preload["two.main"] = nil, nil
   _G.__nuppHost, _G.__nuppComponentExports = savedHost, savedPublic
   os.execute("rm -rf '" .. dir .. "'")
end

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
      dir, {}, target, nil, modules, false, nil, {}, {"workers"}
   ))
   local again = assert(packaging.bundleText(
      dir, {}, target, nil, modules, false, nil, {}, {"workers"}
   ))
   assert(text == again, "the payload depends on selected features, not ambient stub state")

   -- The names are kept as a list rather than recovered from the saved table,
   -- because a module that was not preloaded saves as nil and `pairs` does not
   -- visit it. Restoring by iteration therefore left this test's stub opener
   -- installed for every later `require` of it.
   local stubbed = {"lpeg", "nupp.workers.native"}
   local savedPreloads, savedLoaded = {}, package.loaded.lpeg
   local savedPath, savedCpath = package.path, package.cpath
   for _, name in ipairs(stubbed) do
      savedPreloads[name] = package.preload[name]
      package.preload[name] = function() return name end
   end
   package.loaded.lpeg = nil
   package.path, package.cpath = "", ""
   _G.__nuppHost = {hostAbi = 1, hostFeatures = {
      lpeg = true,
      workers = true,
   }}
   local loaded = assert(loadstring(text))()
   assert(not loaded, "a computed require cannot observe an unselected universal feature")
   assert(package.preload["nupp.workers.native"], "selected worker opener remains visible")
   assert(package.preload.lpeg == nil, "unselected universal openers are removed")
   assert(_G.__nuppHost == nil, "the private handshake is gone before user code")
   package.loaded.lpeg = savedLoaded
   package.path, package.cpath = savedPath, savedCpath
   for _, name in ipairs(stubbed) do package.preload[name] = savedPreloads[name] end
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

-- Precompiling is a change to the shape of a payload, and the two things it must
-- not change are what the payload does and what it is called. Code in a bundle
-- finds what travels beside the binary -- the native library, an AOT builder, the
-- compiler's staged declarations -- by reading the chunk name, and the host settles
-- that name from the executable it found itself in. A dump that kept its debug
-- information would answer with a name settled where it was built instead.
function M.aPayloadForThisMachineIsStrippedBytecodeTheHostStillNames()
   local source = "return debug.getinfo(1, 'S').source\n"
   local bytes, flags = packaging.payloadBytes(source, nil)
   assert(bytes, "a payload is produced for this machine")
   assert(flags == packaging.payloadFlagBytecode, "and its trailer says it carries bytecode")
   assert(bytes:sub(1, 3) == "\27LJ", "which is what it is")

   local chunk = assert(loadstring(bytes, "@/somewhere/nupp"))
   assert(chunk() == "@/somewhere/nupp",
      "the name comes from whoever loads it, as it does for a source payload")
end

-- A dump records the endianness and VM configuration it was written for and is
-- refused by one that does not match. A cross-stamped binary is run by a VM this
-- machine never sees, so it carries the bundle itself, which any of them can read.
function M.aPayloadForAnotherPlatformStaysSource()
   local platform = require("nupp.compiler.build.platform")
   local elsewhere
   for _, key in ipairs(platform.keys()) do
      if key ~= platform.hostKey() then elsewhere = key break end
   end
   assert(elsewhere, "the platform list names somewhere this is not")

   local source = "return 1\n"
   local bytes, flags = packaging.payloadBytes(source, elsewhere)
   assert(bytes == source, "a cross-stamped payload is the bundle itself")
   assert(flags == 0, "and its trailer says so")
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
   }, true, nil, {"nupp.suspension", "nupp.workers"})
   assert(text, "the worker payload is assembled: " .. tostring(problem))
   assert(text:find('package.preload["nupp.suspension"]', 1, true),
      "the suspension runtime is carried")
   assert(text:find('package.preload["nupp.workers"]', 1, true),
      "the workers runtime is carried")
   assert(text:find('package.preload["main"]', 1, true),
      "the ordinary entry becomes selectable")
   assert(text:find('local __nuppEntry = rawget(_G, "__nuppWorkerEntry")', 1, true),
      "one dispatcher selects the worker or ordinary entry")
   assert(text:find('local __nuppServed = require(__nuppEntry)', 1, true)
      and text:find('__nuppEntry == "nupp.workers"', 1, true)
      and text:find('rawget(__nuppServed, "__runScheduler")', 1, true)
      and text:find('then __nuppServe() end', 1, true),
      "a scheduler worker selects the compiler-owned scheduler loop")
   -- Not through `require`. It is a C function, and a payload whose entry ran inside
   -- one could not suspend at all on a host whose every wait is a yield back to it.
   assert(text:find('local __nuppLoaded = package.preload["main"]("main")', 1, true)
      and text:find('return __nuppLoaded', 1, true),
      "the ordinary entry is called where the payload runs")
   assert(not text:find('require(__nuppEntry or', 1, true),
      "the ordinary entry does not go through require")
   assert(text:find("if __nuppLoaded == nil then return end", 1, true),
      "an entry that returned nothing still returns nothing")
   assert(not text:find("if __nuppEntry ~= nil then (require", 1, true),
      "a native worker payload installs nothing a lane has to install for itself")
   os.execute("rm -rf '" .. dir .. "'")
end

-- A seam-supplied workers runtime is reached under its public name, which nothing
-- has preloaded until the backends the entry module would have installed are
-- installed. A lane never runs that entry, so the payload installs them for it.
function M.aSeamBackedWorkerPayloadInstallsItsBackendsBeforeTheLaneEntry()
   local dir = tempProject({
      ["build/main.lua"] = "return 'main'\n",
   })
   local text, problem = packaging.bundleText(dir, {}, {
      kind = "bundle",
      outDir = "build",
      entries = {"main"},
   }, nil, {
      main = {output = dir .. "/build/main.lua"},
   }, true, '(require("nupp.runtime.backend.browser")):install();')
   assert(text, "the worker payload is assembled: " .. tostring(problem))
   assert(text:find(
      'if __nuppEntry ~= nil then (require("nupp.runtime.backend.browser")):install(); end',
      1,
      true
   ), "the lane installs the same backends the entry module would have")
   assert(text:find('local __nuppEntry = rawget(_G, "__nuppWorkerEntry")', 1, true)
      < text:find("__nuppEntry ~= nil then", 1, true),
      "the entry is read before it decides whether to install")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.aStampedBinaryRunsStructuredTasksOnTheSharedScheduler()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
      ["src/jobs.nupp"] = [[
module jobs

export function square(value: integer): integer
    return value * value
end

export function pair(value: integer): (integer, string)
    return value * 2, "done"
end

export function fail(): nil
    error("deliberate worker failure", 0)
end

export record Box
    value: integer

    record Label
        text: string

        function size(self): integer
            return #self.text
        end
    end

    function doubled(self): integer
        return self.value * 2
    end
end

export function doubleBox(box: Box): integer
    return box:doubled()
end

export function bumpBox(box: Box): Box
    box.value = box.value + 1
    return box
end

export function labelSize(label: Box.Label): integer
    return label:size()
end

export function gradual(value: any): integer
    return 1
end

export function echo(value: string): string
    return value
end

export record Payload
    id: integer
    label: string
    ready: boolean
end

export function echoPayload(value: Payload): Payload
    return value
end

export function echoDynamic(value: any): any
    return value
end

export record Sparse
    id: integer
    ready: boolean
    note: string?
end

export function echoSparse(value: Sparse): Sparse
    return value
end

const sharedbytes = require("nupp.mem.sharedbytes")

export function firstByte(region: sharedbytes.Region): integer
    return region:view(1, 1)[1]
end

const heap = require("nupp.mem.heap")

export function stamp(takes frame: heap.Array<uint8>, value: integer): affine(heap.Array<uint8>, heap.destroyArray)
    local writable = frame:write()
    writable[1] = value % 256
    drop writable

    return frame
end

export function total(takes values: heap.Array<int32>): integer
    local sum: integer = 0
    do
        local readable = values:read()
        for index = 1, #readable do
            sum = sum + readable[index]
        end
    end
    values:close()

    return sum
end

const workers = require("nupp.workers")

export function nested(shards: integer): integer
    with scope = workers.scope() do
        return shards
    end
end
]],
      ["src/main.nupp"] = [[
const capture = require("capture")
const jobs = require("jobs")
const workers = require("nupp.workers")
const sharedbytes = require("nupp.mem.sharedbytes")

with scope = workers.scope() do
    const left = scope:spawn(6, jobs.square)
    const right = scope:spawn(7, jobs.square)
    const paired = scope:spawn(5, jobs.pair)
    const box = new jobs.Box(value = 8)
    local dynamicBox = box as any
    dynamicBox.extra = "kept"
    const boxed = scope:spawn(box, jobs.doubleBox)
    const returnedBox = scope:spawn(box, jobs.bumpBox)
    const gradualBox = scope:spawn(box, jobs.gradual)
    const nested = scope:spawn(new jobs.Box.Label(text = "worker"), jobs.labelSize)
    const text = scope:spawn("native string", jobs.echo)
    const payload = scope:spawn(new jobs.Payload(id = 9, label = "schema", ready = true), jobs.echoPayload)
    local malformed = new jobs.Payload(id = 10, label = "fallback", ready = false)
    local dynamicMalformed = malformed as any
    dynamicMalformed.id = "dynamic"
    const fallbackPayload = scope:spawn(malformed, jobs.echoPayload)
    const anyPayload = scope:spawn(new jobs.Payload(id = 11, label = "any", ready = false), jobs.echoDynamic)
    local spare = new jobs.Payload(id = 12, label = "extra", ready = true)
    local dynamicSpare = spare as any
    dynamicSpare.extra = "spare"
    const extraPayload = scope:spawn(spare, jobs.echoPayload)
    const region = sharedbytes.copy("region payload")
    const regionByte = scope:spawn(region:slice(8, 14), jobs.firstByte)
    const sparse = scope:spawn(new jobs.Sparse(id = 13, ready = true), jobs.echoSparse)
    const noted = scope:spawn(new jobs.Sparse(id = 14, ready = false, note = "held"), jobs.echoSparse)
    local doubled, label = paired:await()
    const leftValue = left:await()
    const restored = returnedBox:await()
    const restoredPayload = payload:await()
    const restoredFallback = fallbackPayload:await()
    const restoredAny = anyPayload:await()
    const restoredExtra = extraPayload:await()
    const restoredSparse = sparse:await()
    const restoredNoted = noted:await()
    print(
        leftValue,
        left:await(),
        right:await(),
        doubled,
        label,
        boxed:await(),
        restored:doubled(),
        restored is jobs.Box,
        (restored as any).extra,
        gradualBox:await(),
        nested:await(),
        text:await(),
        restoredPayload.id,
        restoredPayload.label,
        restoredPayload.ready,
        restoredPayload is jobs.Payload,
        (restoredFallback as any).id,
        restoredFallback is jobs.Payload,
        (restoredAny as any).id,
        restoredAny is jobs.Payload,
        (restoredExtra as any).extra,
        restoredExtra is jobs.Payload,
        restoredSparse.id,
        restoredSparse.note == nil,
        restoredSparse is jobs.Sparse,
        restoredNoted.note,
        regionByte:await(),
        region:slice(1, 6):text()
    )
end
print(capture.run(40))

local nestedOk, nestedProblem = pcall(function(): nil
    with scope = workers.scope() do
        scope:spawn(4, jobs.nested):await()
    end
end)
print(not nestedOk, tostring(nestedProblem):find("another worker scope", 1, true) ~= nil)


local ok, problem = pcall(function(): nil
    with scope = workers.scope() do
        scope:spawn(jobs.fail)
    end
end)
print(ok, tostring(problem):find("deliberate worker failure", 1, true) ~= nil)

local copied, copyProblem = pcall(function(): nil
    with scope = workers.scope() do
        scope:spawn(setmetatable({value = 1}, {}), jobs.gradual)
    end
end)
print(copied, tostring(copyProblem):find("has a metatable", 1, true) ~= nil)

const ffi = require("ffi")
const heap = require("nupp.mem.heap")

local frame = heap.allocate(ffi.typeof<uint8>(), 64)
with scope = workers.scope() do
    frame = scope:spawn(frame, 200, jobs.stamp):await()
end
do
    local readable = frame:read()
    print(frame.count, readable[1])
end
drop frame

local counts = heap.allocate(ffi.typeof<int32>(), 5)
do
    local writable = counts:write()
    for index = 1, 5 do
        writable[index] = index * 3
    end
    drop writable
end
with scope = workers.scope() do
    print(scope:spawn(counts, jobs.total):await())
end

local builder = sharedbytes.builder()
with writer = builder:reserve(3) do
    writer[1] = 104
    writer[2] = 105
    writer[3] = 33
end
builder:commit(2)
builder:append("!")
print(builder:freeze():text())

local type Accounted = {accounted: nosuspend function(): integer}
local rawShared = require("nupp.mem.sharedbytes.native") as Accounted
collectgarbage("collect")
collectgarbage("collect")
local before = rawShared.accounted()
local grown: sharedbytes.Region? = sharedbytes.copy(("y"):rep(65536))
print(rawShared.accounted() - before == 65536, grown ~= nil)
grown = nil
collectgarbage("collect")
collectgarbage("collect")
print(rawShared.accounted() == before)
]],
      ["src/capture.nupp"] = [[
module capture

const jobs = require("jobs")
const workers = require("nupp.workers")

export function run(base: integer): integer
    const box = new jobs.Box(value = 21)
    with scope = workers.scope() do
        const scalar = scope:spawn(2, |value: integer| -> base + value)
        const record = scope:spawn(|| -> box:doubled())
        return scalar:await() + record:await()
    end
end
]],
   })
   local built, builtOk = run(dir, "'" .. NUPP .. "' build")
   assert(builtOk, "the native worker binary builds: " .. built)
   local portablePayload = assert(readFile(dir .. "/build/app.payload.lua"))
   assert(portablePayload:sub(1, 3) ~= "\27LJ",
      "payloadOutput retains Lua source rather than current-host bytecode")
   assert(loadfile(dir .. "/build/app.payload.lua"),
      "the separately retained payload is a loadable Lua chunk")
   local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
   local output, ranOk = run(dir, executable)
   assert(ranOk, "the native worker binary runs: " .. output)
   local expected = "36\t36\t49\t10\tdone\t16\t18\ttrue\tkept\t1\t6\tnative string\t9\tschema\ttrue\ttrue\tdynamic\ttrue\t11\ttrue\tspare\ttrue\t13\ttrue\ttrue\theld\t112\tregion\n84\ntrue\ttrue\nfalse\ttrue\nfalse\ttrue\n64\t200\n45\nhi!\ntrue\ttrue\ntrue\n"
   assert(output == expected,
      "results, records, captures, and failures cross structured cleanup: " .. output)
   local rustExecutable = stampRustHost(dir, dir .. "/build/app.payload.lua")
   local rustOutput, rustRanOk = run(dir, rustExecutable)
   assert(rustRanOk, "the Rust worker host runs the Nupp payload: " .. rustOutput)
   assert(rustOutput == expected,
      "the Rust host preserves structured worker and shared-byte results: " .. rustOutput)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.taskScopesOwnAndCancelWorkerTasks()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
      ["src/jobs.nupp"] = [[
module jobs

const tasks = require("nupp.tasks")

export function cancellable(limit: integer): integer
    for index = 1, limit do
        tasks.checkpoint()
    end

    return limit
end

export function returnsAfterCancellation(): integer
    const stop = os.clock() + 0.05
    while os.clock() < stop do end

    return 7
end
]],
      ["src/main.nupp"] = [[
const jobs = require("jobs")
const suspension = require("nupp.suspension")
const tasks = require("nupp.tasks")

local runnable: {thread} = {}
local polls = 0
local shutdowns = 0
local function enqueue(task: thread): nil
    runnable[#runnable + 1] = task
end
local function runReady(): nil
    local pass = runnable
    runnable = {}
    for _, task in ipairs(pass) do
        local ok, problem = coroutine.resume(task)
        if not ok then error(problem, 0) end
    end
end
local handler = {
    park = function(_: any, waiting: suspension.Waiting): nil
        const task = assert(coroutine.running())
        while not waiting:ready() do
            waiting:onResume(function(): nil enqueue(task) end)
            if not waiting:ready() then coroutine.yield() end
        end
    end,
    canPark = function(): boolean return true end,
    shutdown = function(): nil
        shutdowns = shutdowns + 1
        while #runnable > 0 do runReady() end
    end,
}

const app = coroutine.create(function(): nil
with handling = suspension.install(handler) do
tasks.run(function(scope: tasks.Scope): nil
    const parallel = scope:workers()
    const running = parallel:spawn(1000000000, jobs.cancellable)
    while running:status() == "queued" do
        suspension.poll()
    end
    const requested = running:cancel("stop running")
    const ok, problem = pcall(function(): integer return running:await() end)
    print(requested, ok, tasks.isCancelled(problem),
        tostring(problem):find("stop running", 1, true) ~= nil)
end)

tasks.run(function(scope: tasks.Scope): nil
    const returning = scope:workers():spawn(jobs.returnsAfterCancellation)
    while returning:status() == "queued" do suspension.poll() end
    const requested = returning:cancel("observe at return")
    const ok, problem = pcall(function(): integer return returning:await() end)
    print(requested, ok, tasks.isCancelled(problem),
        tostring(problem):find("observe at return", 1, true) ~= nil)
end)

pcall(function(): nil
tasks.run(function(scope: tasks.Scope): nil
    const parallel = scope:workers()
    for _ = 1, 64 do
        parallel:spawn(1000000000, jobs.cancellable)
    end
    const queued = parallel:spawn(1, jobs.cancellable)
    const wasQueued = queued:status() == "queued"
    const requested = queued:cancel("never start")
    const ok, problem = pcall(function(): integer return queued:await() end)
    print(wasQueued, requested, ok, tasks.isCancelled(problem))
    error("finish queued cancellation test", 0)
end)
end)

const deadlineOk, deadlineProblem = pcall(function(): nil
    tasks.runFor(1, function(scope: tasks.Scope): nil
        scope:workers():spawn(1000000000, jobs.cancellable):await()
    end)
end)
print(deadlineOk, tasks.isCancelled(deadlineProblem),
    tostring(deadlineProblem):find("deadline", 1, true) ~= nil,
    tostring(deadlineProblem))
end
print(polls > 0, shutdowns == 1)
end)
enqueue(app)
while coroutine.status(app) ~= "dead" or #runnable > 0 do
    polls = polls + 1
    suspension.poll()
    runReady()
end
]],
   })
   local built, builtOk = run(dir, "'" .. NUPP .. "' build")
   assert(builtOk, "the task-owned worker binary builds: " .. built)
   local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
   local output, ranOk = run(dir, executable)
   assert(ranOk, "the task-owned worker binary runs: " .. output)
   -- Every field is exact but the last, which is the cancellation's own message.
   -- Two things can notice one deadline -- the scope that set it and the worker
   -- awaiting inside it -- and a deadline of a millisecond makes which gets
   -- there first a race. Both say the same thing about the same event, and the
   -- field before this one already asserts the message names the deadline.
   local head = "true\tfalse\ttrue\ttrue\ntrue\tfalse\ttrue\ttrue\n"
      .. "true\ttrue\tfalse\ttrue\nfalse\ttrue\ttrue\t"
   local tail = "\ntrue\ttrue\n"
   assert(output:sub(1, #head) == head
      and output:sub(-#tail) == tail
      and output:find("cancelled: its deadline passed", 1, true) ~= nil,
      "running, queued, and deadline cancellation share one task identity: " .. output)
   local rustExecutable = stampRustHost(dir, dir .. "/build/app.payload.lua")
   local rustOutput, rustRanOk = run(dir, rustExecutable)
   assert(rustRanOk, "the Rust worker host runs task cancellation: " .. rustOutput)
   assert(rustOutput:sub(1, #head) == head
      and rustOutput:sub(-#tail) == tail
      and rustOutput:find("cancelled: its deadline passed", 1, true) ~= nil,
      "Rust-owned workers preserve queued, running, and deadline cancellation: " .. rustOutput)
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

function M.aCoroutineOnlyTaskBundleDoesNotAcquireWorkersOrTime()
   local dir = tempProject({
      ["nupp.lua"] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "bundle", entries = {"main"}, outDir = "build",
}}}}
]],
      ["src/main.nupp"] = [[
const tasks = require("nupp.tasks")
print(tasks.run(function(scope: tasks.Scope): integer
    return scope:spawn(function(): integer return 42 end):await()
end))
]],
   })
   local out, ok = run(dir, "'" .. NUPP .. "' build")
   assert(ok, "the coroutine-only task bundle builds without a native host: " .. out)
   local ran, ranOk = run(dir, "luajit build/app.lua")
   assert(ranOk and ran == "42\n", "the standalone task bundle runs: " .. ran)
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
-- are full of .lua that is examples, tests and scripts, some of which are not
-- valid preload modules — so a bundle carries what the build compiled, not what
-- it finds.
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
local wrong: integer = io.open("x", "r")

return wrong
]],
   })
   local out = run(dir, "'" .. NUPP .. "' check --strict typed.nupp")
   assert(out:find("NUPP2001", 1, true),
      "the std surface is typed, not any: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.theTypesNamespaceCarriesItsCheckedFunctionsOutsideThisTree()
   local dir = tempProject({
      ["nupp.lua"] = STD_MANIFEST,
      ["format.nupp"] = [[
local function format<F is string>(
    value: F,
    ...: unpackof nupp.types.formatArguments(F)
): string
    return string.format(value, ...)
end

print(format("%s=%d", "answer", 42))
]],
   })
   local out, ok = run(dir, "'" .. NUPP .. "' check --strict format.nupp")
   assert(ok, "nupp.types checked functions are carried with the compiler: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

-- Typed is not enough on its own: the ownership contract has to cross too, or an
-- ordinary local cannot arrange automatic cleanup.
function M.theStandardLibraryCarriesItsOwnershipOutsideThisTree()
   local dir = tempProject({
      ["nupp.lua"] = STD_MANIFEST,
      ["input.txt"] = "hello\n",
      ["acquire.nupp"] = [[
do
    local file = assert(io.open("input.txt", "r"))
    print(file:read("*a"))
end
]],
      ["leak.nupp"] = [[
local handle = assert(io.open("input.txt", "r"))

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
local wrong: integer = workers.scope
return wrong
]],
      ["owned.nupp"] = [[
local workers = require("nupp.workers")
with scope = workers.scope() do
    print(scope)
end
return true
]],
   })
   local typed = run(dir, "'" .. NUPP .. "' check --strict typed.nupp")
   assert(typed:find("NUPP2001", 1, true),
      "the workers surface is typed rather than gradual: " .. typed)
   local owned, ok = run(dir, "'" .. NUPP .. "' check --strict owned.nupp")
   assert(ok and not owned:find("NUPP2603", 1, true),
      "a worker scope carries its automatic drain obligation: " .. owned)
   os.execute("rm -rf '" .. dir .. "'")
end

return M
