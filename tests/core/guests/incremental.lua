-- A program `nupp __core-compiler` emits is rebuilt from the pieces it kept
-- (nupp.core.piecestore), and what it emits is what a cold build emits:
--
--   NUPP_RUNTIME=core bin/nupp run tests/core/guests/incremental.lua
--
-- The program is four modules staged under the guest project. It is built
-- cold, then again unchanged, after an edit to one module's body, and after
-- an edit to another's exported interface. Each rebuild must reuse exactly
-- the pieces its edit leaves standing -- every one, all but the edited
-- module, and all but the edited module and the modules that read its
-- interface -- and its bundle must be byte for byte the bundle of a build
-- that reuses no piece (NUPP_GUEST_PIECE_STORE=0) of the same sources.
--
-- The runtime's kernels are kept in the same store on the core, so the
-- unchanged rebuild also holds a bundle selected from kept kernels to the one
-- selected afresh. Every build pays the runtime's session; the first pays its
-- selection too, a few minutes on the VM and several more on the core.
local fs = require("nupp.compiler.fs")
local process = require("nupp.compiler.process")

local ROOT = fs.absolute(os.getenv("NUPP_COMPILER_ROOT") or ".")
local OUT = ROOT .. "/build/core-incremental"
-- Under the guest project's include, where the entry and what it requires
-- are found by their names.
local STAGE = ROOT .. "/build/core-guest-programs/source/incrementalcase"
local ENTRY = "build/core-guest-programs/source/incrementalcase/main"
local BUNDLE = "main.bundle"

local failures = 0

local function check(ok, what)
    print((ok and "ok    " or "FAIL  ") .. what)
    if not ok then
        failures = failures + 1
    end
end

local function say(line)
    io.stderr:write("  ", line, "\n")
end

local SHAPES = [[
module incrementalcase.shapes

export function area(width: integer, height: integer): integer
    return width * height
end
]]

local SHAPES_WIDER = [[
module incrementalcase.shapes

export function area(width: integer, height: integer): integer
    return width * height
end

export function perimeter(width: integer, height: integer): integer
    return 2 * (width + height)
end
]]

local COUNTS = [[
module incrementalcase.counts

export function total(limit: integer): integer
    local sum: integer = 0
    for index = 1, limit do
        sum = sum + index
    end

    return sum
end
]]

-- The same function, summing in the other order: what it answers and every
-- fact a caller's check reads of it stand.
local COUNTS_EDITED = [[
module incrementalcase.counts

export function total(limit: integer): integer
    local sum: integer = 0
    for index = 1, limit do
        sum = index + sum
    end

    return sum
end
]]

local PLAN = [[
module incrementalcase.plan

local shapes = require("incrementalcase.shapes")

export function floor(rooms: integer): integer
    return rooms * shapes.area(3, 4)
end
]]

local MAIN = [[
module incrementalcase.main

local counts = require("incrementalcase.counts")
local plan = require("incrementalcase.plan")

export const result = counts.total(10) + plan.floor(2)
]]

local function stage(name, text)
    assert(fs.writeFile(STAGE .. "/" .. name .. ".nupp", text), "cannot stage " .. name)
end

-- Builds the staged program into `directory` with `env` beside the store's;
-- answers its bundle and how many pieces it reused of how many.
local function build(label, directory, env)
    local merged = {NUPP_CACHE_HOME = OUT .. "/store"}
    for name, value in pairs(env or {}) do
        merged[name] = value
    end
    local started = os.time()
    local status, output = process.capture({ROOT .. "/bin/nupp", "__core-compiler", directory, ENTRY}, {
        cwd = ROOT,
        env = merged,
    })
    assert(status == 0, label .. " did not build:\n" .. output:sub(-4000))
    local reused, count = output:match("guest pieces: [^\n]* reused (%d+) of (%d+)")
    say(("%s: reused %s of %s in %ds"):format(label, tostring(reused), tostring(count), os.time() - started))

    return assert(fs.readFile(directory .. "/" .. BUNDLE), label .. " wrote no bundle"), tonumber(reused), tonumber(count)
end

-- What a build that reuses nothing emits from the sources as staged now.
local function cold(label)
    local bundle = build(label .. ", cold", OUT .. "/cold-" .. label, {NUPP_GUEST_PIECE_STORE = "0"})
    return bundle
end

process.run({"rm", "-rf", OUT, STAGE})
assert(process.run({"mkdir", "-p", OUT, STAGE}) == 0, "cannot create " .. OUT)
stage("shapes", SHAPES)
stage("counts", COUNTS)
stage("plan", PLAN)
stage("main", MAIN)

local first, reused, count = build("first", OUT .. "/first")
check(reused == 0, "a build with an empty store reuses no piece")
local modules = count or 0
check(modules >= 4, "the program carries its four modules")

local again
again, reused = build("unchanged", OUT .. "/unchanged")
check(reused == modules, "an unchanged rebuild reuses every piece")
check(again == first, "an unchanged rebuild emits the same bundle")
check(first == cold("unchanged"), "the first build emits what a build reusing nothing emits")

stage("counts", COUNTS_EDITED)
local body
body, reused = build("body edit", OUT .. "/body")
check(reused == modules - 1, "a body edit recompiles only the edited module")
check(body ~= first, "the body edit changes the bundle")
check(body == cold("body"), "the body-edit rebuild emits what a cold build of it emits")

stage("shapes", SHAPES_WIDER)
local interface
interface, reused = build("interface edit", OUT .. "/interface")
check(reused == modules - 3, "an interface edit recompiles the module and the two that read it, one through the other")
check(interface == cold("interface"), "the interface-edit rebuild emits what a cold build of it emits")

process.run({"rm", "-rf", STAGE})
print(("%d failed"):format(failures))
os.exit(failures == 0 and 0 or 1)
