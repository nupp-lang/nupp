local testAssert = require("assert")
local project = require("nupp.tools.build.project")
local deps = require("nupp.tools.build.deps")
local hash = require("nupp.compiler.hash")
local process = require("nupp.compiler.process")
local store = require("nupp.compiler.project.store")

local buildPlatform = require("nupp.tools.build.platform")
local fs = require("nupp.compiler.fs")
local compilerEnv = require("nupp.compiler.project.env")
local json = require("testjson")
local buildSyntax = require("nupp.compiler.shellsyntax")

local hostSystem = buildPlatform.hostSystem()

local function write(path, text)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then
        os.execute("mkdir -p '" .. dir .. "'")
    end
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
    if not f then
        return false
    end
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
    if probe then
        probe:close()
    end
    if found == nil or found == "" then
        require("assert").suite.skip("cargo is unavailable")
    end
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    for name, text in pairs(files) do
        write(dir .. "/" .. name, text)
    end

    return dir
end

local function remove(dir)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A directory that is neither a project nor one of its output trees, for
-- proving a tree runs from anywhere. This was spelled `/`, which is a
-- directory on POSIX and a switch to cmd's `cd`, so on Windows the run never
-- started and the tests read as though the tree had answered nothing.

local function libraryName(name)
    if hostSystem == "windows" then
        return name .. ".dll"
    end
    if hostSystem == "darwin" then
        return "lib" .. name .. ".dylib"
    end

    return "lib" .. name .. ".so"
end

local function staticLibraryName(name)
    return "lib" .. name .. ".a"
end

local function executableName(name)
    return name .. (hostSystem == "windows" and ".exe" or "")
end

-- Loads an output tree in a fresh interpreter and reports what its entry module
-- answered. The tree is named absolutely and the working directory is somewhere
-- else, so no part of the answer can come from where the process was started.
local function answerFrom(dir)
    local manifest = read(dir .. "/nupp.lua")
    local program, replaced = manifest:gsub(
        'entries%s*=%s*{%s*"main"%s*}',
        'kind = "binary", stub = "nupp", entries = {"answer"}',
        1
    )
    assert(replaced == 1, "the manifest builds main: " .. manifest)
    write(dir .. "/nupp.lua", program)
    write(dir .. "/src/answer.nupp", "print('VALUE ' .. tostring(require('main')))\n")
    local diagnostics = {}
    local built = project.build(dir, {diagnostics = diagnostics})
    write(dir .. "/nupp.lua", manifest)
    os.remove(dir .. "/src/answer.nupp")
    if built ~= 0 then
        return "the program did not build: " .. tostring(diagnostics[1] and diagnostics[1].msg)
    end
    local code, out = process.capture({dir .. "/out/" .. executableName("binary")}, {cwd = dir})
    if code ~= 0 then
        return out or ""
    end

    return out:match("VALUE ([^\r\n]+)") or out
end

-- Sets or clears a variable of this process's own environment, which the
-- build it then runs in process reads: POSIX `setenv`, or the Windows C
-- runtime's `_putenv_s`, where an empty value clears it.

-- A header `cheader` reads is as much the module's input as its source is, so the
-- record a later process reuses has to answer for it. Before it did, an edit to
-- only the header left check and build reusing what the old header said: a warm
-- run accepted a call a cold one refused, and the artifact kept the old cdef.
local function cheaderProject()
    return tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"m"}}}
]],
        [
            "src/m.nupp"
        ] = [[
module m
const C = cheader("probe.h")

export function run(): integer
    return C.probe_add(1, 2)
end
]],
        ["src/probe.h"] = "int probe_add(int a, int b);\n",
    })
end

-- A project whose entry actually calls through the binding, so what is being
-- tested is a load rather than the spelling of a string.
local function callingProject()
    return tempProject({
        [
            "nupp.lua"
        ] = [[
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

local function compiledRuntimeSources(dir, projectModules)
    local expected, seen = {}, {}
    for _, name in ipairs(projectModules) do
        expected[name] = true
    end
    local state = assert(json.decode(read(dir .. "/out/.nupp-state.json")))
    local prefix = dir .. "/out/cache/runtime-source/"
    local count = 0
    for name, record in pairs(state.modules) do
        if record.sourcePath then
            if record.sourcePath:sub(1, #prefix) == prefix then
                count = count + 1
            else
                assert(expected[name], "unexpected project source module: " .. name)
                seen[name] = true
            end
        end
    end
    for _, name in ipairs(projectModules) do
        assert(seen[name], "missing project source module: " .. name)
    end

    return count
end

return {
    testAssert = testAssert,
    project = project,
    deps = deps,
    hash = hash,
    process = process,
    store = store,
    buildPlatform = buildPlatform,
    fs = fs,
    compilerEnv = compilerEnv,
    json = json,
    buildSyntax = buildSyntax,
    write = write,
    read = read,
    contentCacheDir = contentCacheDir,
    exists = exists,
    requireCargo = requireCargo,
    tempProject = tempProject,
    remove = remove,
    elsewhere = elsewhere,
    libraryName = libraryName,
    staticLibraryName = staticLibraryName,
    executableName = executableName,
    answerFrom = answerFrom,
    setEnvironment = setEnvironment,
    aotScopeFixture = aotScopeFixture,
    syntheticStub = syntheticStub,
    cheaderProject = cheaderProject,
    callingProject = callingProject,
    TINY_ROCKSPEC = TINY_ROCKSPEC,
    tinyRockFiles = tinyRockFiles,
    hostSystem = hostSystem,
    compiledRuntimeSources = compiledRuntimeSources,
}
