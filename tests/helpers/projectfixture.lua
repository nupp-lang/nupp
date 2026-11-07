local testAssert = require("assert")
local project = require("nupp.tools.build.project")
local deps = require("nupp.tools.build.deps")
local hash = require("nupp.compiler.hash")
local process = require("nupp.compiler.process")
local store = require("nupp.compiler.project.store")
local nativeStage = require("nupp.tools.build.native")
local buildPlatform = require("nupp.tools.build.platform")
local fs = require("nupp.compiler.fs")
local compilerEnv = require("nupp.compiler.project.env")
local json = require("testjson")
local buildSyntax = require("nupp.compiler.shellsyntax")

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
local function elsewhere()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    return dir
end

local function libraryName(name)
    if jit.os == "Windows" then
        return name .. ".dll"
    end
    if jit.os == "OSX" then
        return "lib" .. name .. ".dylib"
    end

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
    local here = assert(require("io.internal.path").cwd()):tostring()
    here = here:gsub("^/([A-Za-z])(/)", "%1:%2")
    local script = (
        "package.path = %q .. %q .. package.path " .. "print('VALUE ' .. tostring(require('main')))"
    ):format(tree .. "/?.lua;", here .. "/build/?.lua;")
    local code, out = process.capture({"luajit", "-e", script}, {cwd = cwd})
    if code ~= 0 then
        return out or ""
    end

    return out:match("VALUE ([^\r\n]+)") or out
end

-- Sets or clears a variable of this process's own environment, which the
-- build it then runs in process reads: POSIX `setenv`, or the Windows C
-- runtime's `_putenv_s`, where an empty value clears it.
local function setEnvironment(name, value)
    local ffi = require("ffi")
    if package.config:sub(1, 1) == "\\" then
        pcall(ffi.cdef, "int _putenv_s(const char *, const char *);")
        ffi.C._putenv_s(name, value or "")
    else
        pcall(ffi.cdef, "int setenv(const char *, const char *, int); int unsetenv(const char *);")
        if value == nil then
            ffi.C.unsetenv(name)
        else
            ffi.C.setenv(name, value, 1)
        end
    end
end

local AOT_SCOPE_MODEL = [[
module model
local bytes = require("bytes")
export type Shape = {value: integer}
export const encoding = bytes.base64encode
@aot
local function twice(value: number): number
    return value * 2.0
end
export const doubled = twice
]]

local function aotScopeFixture(entry)
    local dir = tempProject({
        ["nupp.lua"] = 'return {include={"src"},build={outDir="build",entries={"main"}}}\n',
        ["src/main.nupp"] = entry,
        ["src/model.nupp"] = AOT_SCOPE_MODEL,
    })
    local modules = require("nupp.tools.build.modules")
    local target = {kind = "modules", entries = {"main"}, outDir = "build"}
    local session = modules.session(dir, "build", {include = {"src"}}, target, {})
    local main = dir .. "/src/main.nupp"
    local checked = session.inc.checkFile(main)

    local function valid(diagnostics, phase)
        local failures = {}
        for _, diagnostic in ipairs(diagnostics or {}) do
            if require("nupp.compiler.diagnostics").isFatal(diagnostic) then
                failures[
                    #failures + 1
                ] = tostring(diagnostic.code) .. ": " .. tostring(diagnostic.msg or diagnostic.message)
            end
        end
        assert(#failures == 0, phase .. ": " .. table.concat(failures, "\n"))
    end

    valid(checked.diags, "scope fixture check")
    assert(checked.result, "scope fixture did not produce a checked tree")
    local generated, generationDiagnostics = require("nupp.compiler.lua.gen").generate(checked.result, main)
    valid(generationDiagnostics, "scope fixture generation")
    local scope, problem = modules.targetScope(dir, target, session)
    assert(scope, problem)

    return dir, session, scope, require("nupp.compiler.lua.gen").runtimeModules(generated)
end

local function syntheticStub(platform)
    if platform == "x86_64-unknown-linux-gnu" then
        return "\127ELF" .. string.char(2) .. ("\0"):rep(13) .. string.char(62, 0) .. ("\0"):rep(44)
    end
    if platform == "aarch64-apple-darwin" then
        return "\207\250\237\254" .. string.char(12, 0, 0, 1) .. ("\0"):rep(56)
    end

    return "MZ" .. ("\0"):rep(58) .. string.char(64, 0, 0, 0) .. "PE\0\0" .. string.char(100, 134) .. ("\0"):rep(58)
end

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

return {
    testAssert = testAssert,
    project = project,
    deps = deps,
    hash = hash,
    process = process,
    store = store,
    nativeStage = nativeStage,
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
    AOT_SCOPE_MODEL = AOT_SCOPE_MODEL,
    aotScopeFixture = aotScopeFixture,
    syntheticStub = syntheticStub,
    cheaderProject = cheaderProject,
    callingProject = callingProject,
    TINY_ROCKSPEC = TINY_ROCKSPEC,
    tinyRockFiles = tinyRockFiles,
}
