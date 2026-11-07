-- `kind = "binary"`: a target that comes out as one program file.
--
-- The file is the deliverable on its own -- the VM runtime with the program's
-- image appended, which runs with nothing beside it -- so what is asserted here
-- is what docs/reference/distribution.md promises about stamped programs.
local HERE = require("helpers.paths").absoluteTests
local NUPP = HERE .. "/../bin/nupp"
local packaging = require("nupp.tools.build.package")

local test = require("assert")
local EXECUTABLE = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
local BUILT = package.config:sub(1, 1) == "\\" and "/build/app.exe" or "/build/app"

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
    if not f then
        return nil
    end
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
    "nupp: falling back to the VM compiler\n",
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
    local status = os.execute(("cd '%s' && %s > '%s' 2>&1"):format(dir, argv, outfile))
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

local MANIFEST = [[
return {
   include = { "src" },
   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "binary",
            stub = "nupp",
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

local embedded = require("nupp.embedded") as {[string]: string}
print(tostring(embedded["/data/note.txt"]))
]]

local GREET = [[
local greet = {}

function greet.hello(who: string): string
    return "hello, " .. who
end

return greet
]]

-- 100 records per module, below the local-variable limit a module has.

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
            kind = "binary",
            stub = "nupp",
            entries = { "app.main" },
            dependencies = { "tiny" },
         },
      },
   },
}
]]

local ROCK_MAIN = [[
local tiny = require("tinyrock") as {answer: integer}
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

-- The standard library is this compiler's own Nupp, and it is carried as source
-- rather than described by a second declaration of itself. A project outside the
-- tree therefore types against exactly what was compiled into the binary it runs.
-- Before this it resolved to nothing, and gradual typing turned that into `any`
-- without a word — which then surfaced three steps later as an ownership error.
--
-- Four claims are made about that surface, and each of them used to stand up a
-- project of its own and pay again for compiling it: five checks and a run
-- across four temporary projects, of which the two checks about workers alone
-- cost more than every other bundle case in this file put together. The surface
-- is the fixture, so it is prepared once. One project holds a file per claim,
-- one strict check of the whole project answers all of them at once, and each
-- assertion names the file it is about, so a failure still says which claim
-- broke and which project to look in.
local STD_MANIFEST = 'return {include = {"."}}\n'

--- Whether the report says `code` about `file`.
---
--- Attributed rather than searched: one report now carries every file's
--- diagnostics, so "NUPP2001 is in there somewhere" would pass for the wrong
--- reason as easily as for the right one.
local function diagnosed(report, file, code)
    local prefix = "^" .. file:gsub("%p", "%%%0") .. ":%d+:%d+:"
    for line in report:gmatch("[^\n]+") do
        if line:match(prefix) and line:find(code, 1, true) then
            return true
        end
    end

    return false
end

return {
    HERE = HERE,
    NUPP = NUPP,
    packaging = packaging,
    tempProject = tempProject,
    readFile = readFile,
    LAUNCHER_NOTICES = LAUNCHER_NOTICES,
    run = run,
    rustHost = rustHost,
    stampRustHost = stampRustHost,
    MANIFEST = MANIFEST,
    MAIN = MAIN,
    GREET = GREET,
    recordModule = recordModule,
    ROCK_MANIFEST = ROCK_MANIFEST,
    ROCK_MAIN = ROCK_MAIN,
    TINY_ROCKSPEC = TINY_ROCKSPEC,
    STD_MANIFEST = STD_MANIFEST,
    diagnosed = diagnosed,
    test = test,
    EXECUTABLE = EXECUTABLE,
    BUILT = BUILT,
}
