local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local readFile = fixture.readFile
local run = fixture.run
local MANIFEST = fixture.MANIFEST
local MAIN = fixture.MAIN
local GREET = fixture.GREET
local ROCK_MANIFEST = fixture.ROCK_MANIFEST
local ROCK_MAIN = fixture.ROCK_MAIN
local TINY_ROCKSPEC = fixture.TINY_ROCKSPEC
local STD_MANIFEST = fixture.STD_MANIFEST
local diagnosed = fixture.diagnosed

local M = {}

-- One tree, one deliverable, and every claim about it. That a bundle runs under
-- an interpreter that has never heard of nupp, that it carries its resources,
-- that a second build of the same tree produces the same bytes, that it carries
-- what the build compiled rather than what is lying around the output directory,
-- that it says what it could not carry, and that it needs nothing from the tree
-- it came from are six claims about one project -- and were five cases and six
-- builds of the same three files.
--
-- The phases below run in the order they are written and each says what it
-- changed, because two of them do change the tree: the identity phase throws the
-- output directory away so the second build is cold, and the unreachable-resource
-- phase rewrites the manifest. Every assertion names the project it is about, so
-- a failure says which directory to open as well as which claim broke.
function M.oneBundleTreeCarriesRunsRebuildsAndTravelsAlone()
    local dir = tempProject({
        ["nupp.lua"] = MANIFEST,
        ["src/app/main.nupp"] = MAIN,
        ["src/app/greet.nupp"] = GREET,
        ["src/app/data/note.txt"] = "carried along\n",
        ["src/app/data/second.txt"] = "and another\n",
    })
    local where = " (built in " .. dir .. ")"

    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the bundle target builds" .. where .. ": " .. out)
    local first = readFile(dir .. "/build/app.lua")
    assert(first, "the bundle was written to build/app.lua" .. where)

    -- One file, runnable by an interpreter that has never heard of nupp.
    local ran, ranOk = run(dir, "luajit build/app.lua")
    assert(ranOk, "the bundle runs on its own" .. where .. ": " .. ran)
    assert(
        ran:find("hello, world", 1, true),
        "its modules are reachable through package.preload" .. where .. ": " .. ran
    )
    assert(ran:find("carried along", 1, true), "and its resources came with it" .. where .. ": " .. ran)

    -- Taken now, run in the last phase with this project deleted out from under it.
    local elsewhere = os.tmpname()
    os.remove(elsewhere)
    assert(os.execute("mkdir -p '" .. elsewhere .. "'") == 0)
    assert(os.execute(("cp '%s/build/app.lua' '%s/alone.lua'"):format(dir, elsewhere)) == 0)

    -- Byte-identical across builds. The packaging fixpoint rests on this, and a
    -- bundle that embedded a timestamp or a hash order would fail it in a way that
    -- reproduces once a week. The output directory goes first, so nothing is
    -- reused: the ordering has to be decided by the bundler rather than by
    -- whatever order the last build left behind.
    os.execute("rm -rf '" .. dir .. "/build'")
    local rebuilt, rebuiltOk = run(dir, "'" .. NUPP .. "' build")
    assert(rebuiltOk, "the discarded output directory builds again" .. where .. ": " .. rebuilt)
    assert(first == readFile(dir .. "/build/app.lua"), "two cold builds produce the same bundle" .. where)

    -- The output directory is also where native dependencies build, and their
    -- trees are full of .lua that is examples, tests and scripts, some of which is
    -- not a valid preload module -- so a bundle carries what the build compiled,
    -- not what it finds. This one arrives after the fact, the way cargo's does.
    assert(os.execute("mkdir -p '" .. dir .. "/build/native/examples'") == 0)
    local intruder = assert(io.open(dir .. "/build/native/examples/tool.lua", "wb"))
    intruder:write("#!/usr/bin/env lua\nprint('not a module')\n")
    intruder:close()
    local beside, besideOk = run(dir, "'" .. NUPP .. "' build")
    assert(besideOk, "the build still succeeds beside a foreign tree" .. where .. ": " .. beside)
    local bundle = readFile(dir .. "/build/app.lua")
    assert(not bundle:find("not a module", 1, true), "somebody else's script is not preloaded as a module" .. where)
    local again, againOk = run(dir, "luajit build/app.lua")
    assert(againOk, "and the bundle still parses and runs" .. where .. ": " .. again)

    -- A resource staged beside the entry's directory rather than under it has no
    -- name a running program could ask for. It is left out and said out loud, so
    -- the manifest is rewritten here to ask for one that cannot be named, and the
    -- output directory goes again: this report is one a build makes from nothing
    -- rather than one an incremental build happened to keep.
    local reaching = MANIFEST:gsub('"src/app/data/%*%.txt"', '"src/app/data/*.txt", "extra/*.txt"')
    local rewritten = assert(io.open(dir .. "/nupp.lua", "wb"))
    rewritten:write(reaching)
    rewritten:close()
    assert(os.execute("mkdir -p '" .. dir .. "/extra'") == 0)
    local loose = assert(io.open(dir .. "/extra/loose.txt", "wb"))
    loose:write("not reachable\n")
    loose:close()
    os.execute("rm -rf '" .. dir .. "/build'")
    local reported, reportedOk = run(dir, "'" .. NUPP .. "' build")
    assert(reportedOk, "the build still succeeds with an unreachable resource" .. where .. ": " .. reported)
    assert(
        reported:find("could not be bundled", 1, true),
        "and says what it could not carry" .. where .. ": " .. reported
    )
    bundle = readFile(dir .. "/build/app.lua")
    assert(
        not bundle:find("not reachable", 1, true),
        "the unreachable resource is not embedded under a name nothing reads" .. where
    )
    assert(bundle:find("carried along", 1, true), "the reachable one still is" .. where)

    -- Nothing beside it. A bundle that still needed its build tree would be a
    -- bundle in name only, and the failure would be somebody else's, later.
    os.execute("rm -rf '" .. dir .. "'")
    local alone, aloneOk = run(elsewhere, "luajit alone.lua")
    assert(aloneOk, "the copy runs with its whole project deleted (copied to " .. elsewhere .. "): " .. alone)
    assert(
        alone:find("hello, world", 1, true) and alone:find("carried along", 1, true),
        "modules and resources both survived the move (copied to " .. elsewhere .. "): " .. alone
    )
    os.execute("rm -rf '" .. elsewhere .. "'")
end

function M.aCoroutineOnlyTaskBundleDoesNotAcquireWorkersOrTime()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "bundle", entries = {"main"}, outDir = "build",
}}}}
]],
        [
            "src/main.nupp"
        ] = [[
const tasks = require("coroutine")
local answer = 0
do local scope = tasks.scope() ;
    answer = scope:spawn(function(): integer return 42 end):await()
end
print(answer)
]],
    })
    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the coroutine-only task bundle builds without a native host: " .. out)
    local ran, ranOk = run(dir, "luajit build/app.lua")
    assert(ranOk and ran == "42\n", "the standalone task bundle runs: " .. ran)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aBundleCarriesTheRockModulesItWasToldTo()
    local dir = tempProject({
        ["nupp.lua"] = ROCK_MANIFEST,
        ["src/app/main.nupp"] = ROCK_MAIN,
        ["vendor/tinyrock/tinyrock.lua"] = "return {answer = 42}\n",
        ["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC,
    })
    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the bundle target builds: " .. out)

    -- With an empty search path, so nothing installed on this machine can
    -- answer the require: what runs is what the bundle brought.
    local ran, ranOk = run(dir, "LUA_PATH= LUA_CPATH= luajit build/app.lua")
    assert(ranOk, "the bundle runs with nothing on its path: " .. ran)
    assert(ran:find("answer 42", 1, true), "the rock's module came with it: " .. ran)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.theStandardLibrarySurfaceIsTypedAndOwnedOutsideThisTree()
    local dir = tempProject({
        ["nupp.lua"] = STD_MANIFEST,
        ["input.txt"] = "hello\n",
        -- The library is typed, not `any`.
        ["typed.nupp"] = [[
local wrong: integer = io.open("x", "r")

return wrong
]],
        -- `types`' checked functions travel with it.
        [
            "format.nupp"
        ] = [[
local function format<F is string>(
    value: F,
    ...: unpackof types.formatarguments(F)
): string
    return string.format(value, ...)
end

print(format("%s=%d", "answer", 42))
]],
        -- Typed is not enough on its own: the ownership contract has to cross too,
        -- or an ordinary local cannot arrange automatic cleanup.
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
        -- And the workers surface carries both halves.
        ["workerstyped.nupp"] = [[
local tasks = require("coroutine")
local wrong: integer = tasks.scope
return wrong
]],
        [
            "workersowned.nupp"
        ] = [[
local tasks = require("coroutine")
do local scope = tasks.scope() ;
    print(scope ~= nil)
end
return true
]],
    })
    local where = " (checked in " .. dir .. ")"
    local report = run(dir, "'" .. NUPP .. "' check")

    assert(diagnosed(report, "typed.nupp", "NUPP2001"), "the std surface is typed, not any" .. where .. ": " .. report)
    assert(
        not report:find("format.nupp", 1, true),
        "types checked functions are carried with the compiler" .. where .. ": " .. report
    )
    assert(
        diagnosed(report, "workerstyped.nupp", "NUPP2001"),
        "the workers surface is typed rather than gradual" .. where .. ": " .. report
    )
    -- An untouched ordinary owner is discharged by its lexical scope rather than
    -- diagnosed as forgotten, and a worker scope carries the same obligation.
    assert(
        not diagnosed(report, "leak.nupp", "NUPP2603"),
        "the ordinary owner receives automatic cleanup" .. where .. ": " .. report
    )
    assert(
        not diagnosed(report, "workersowned.nupp", "NUPP2603"),
        "a worker scope carries its automatic drain obligation" .. where .. ": " .. report
    )
    -- And each of the two checks clean rather than merely escaping that one code,
    -- which is what their own `check` exiting zero used to say before the files
    -- were checked together with the ones that are meant to fail.
    assert(
        not report:find("leak.nupp", 1, true),
        "an ordinary owner is diagnosed for nothing at all" .. where .. ": " .. report
    )
    assert(
        not report:find("workersowned.nupp", 1, true),
        "an owned worker scope is diagnosed for nothing at all" .. where .. ": " .. report
    )

    -- The private cleanup has to link and run, not only check.
    local acquired, acquiredOk = run(dir, "'" .. NUPP .. "' run acquire.nupp")
    assert(
        acquiredOk and acquired == "hello\n\n",
        "the standard-library private cleanup links and runs" .. where .. ": " .. acquired
    )
    os.execute("rm -rf '" .. dir .. "'")
end

return M
