local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local process = fixture.process
local nativeStage = fixture.nativeStage
local fs = fixture.fs
local compilerEnv = fixture.compilerEnv
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.subprocessPreservesEmptyArguments()
    local dir = tempProject({["argv.sh"] = [[printf '%s|%s|%s' "$#" "$1" "$2"]],})
    local status, output = process.capture({"sh", dir .. "/argv.sh", "", "tail"})
    remove(dir)
    testAssert.eq(status, 0, output)
    testAssert.eq(output, "2||tail", "an empty argv entry reaches the child process")
end

local function compileLibrary(dir, extra)
    fixture.write(dir .. "/native/physics.c", "int physics_add(int a, int b) { return a + b + " .. extra .. "; }\n")
    local command = {os.getenv("CC") or "cc"}
    command[#command + 1] = hostSystem == "darwin" and "-dynamiclib" or "-shared"
    if hostSystem ~= "windows" then
        command[#command + 1] = "-fPIC"
    end
    command[#command + 1] = dir .. "/native/physics.c"
    command[#command + 1] = "-o"
    command[#command + 1] = dir .. "/native/" .. fixture.libraryName("physics")
    local code, output = process.capture(command)
    testAssert.eq(code, 0, output)
end

function M.logicalLibrariesTravelWithVmBinariesAndSurviveBothCaches()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {
    include = {"src"},
    libraries = {physics = {search = {"native"}}, unused = {search = {"not-built"}}},
    build = {kind = "binary", stub = "nupp", entries = {"main"}, outDir = "out", output = "dist/app"},
}]],
        [
            "src/binding.nupp"
        ] = [[module binding
cdef function physics_add(a: int32, b: int32): int32 from "physics"
export function add(a: int32, b: int32): int32 return physics_add(a, b) end
]],
        ["src/main.nupp"] = 'local binding = require("binding")\nprint(tonumber(binding.add(2, 3)))\n',
    })
    compileLibrary(dir, "0")
    local produced = {}
    testAssert.eq(fixture.project.build(dir, {produced = produced}), 0)
    local executable = dir .. "/dist/app" .. (hostSystem == "windows" and ".exe" or "")
    if not fixture.exists(executable) then
        executable = dir .. "/dist/app"
    end
    assert(fixture.exists(dir .. "/dist/lib/" .. fixture.libraryName("physics")))
    local code, output = process.capture({executable}, {cwd = dir})
    testAssert.eq(code, 0, output)
    testAssert.eq(output, "5\n")

    fixture.write(dir .. "/src/main.nupp", 'local binding = require("binding")\nprint(tonumber(binding.add(3, 3)))\n')
    testAssert.eq(fixture.project.build(dir), 0)
    local cached = fixture.read(dir .. "/out/.nupp-vm-program.image")
    assert(fixture.read(dir .. "/out/.nupp-vm-program.libraries"):find("physics", 1, true))
    compileLibrary(dir, "1")
    testAssert.eq(fixture.project.build(dir), 0)
    testAssert.eq(
        fixture.read(dir .. "/out/.nupp-vm-program.image"),
        cached,
        "a native body edit keeps the program image"
    )
    local state = assert(fixture.json.decode(fixture.read(dir .. "/out/.nupp-state.json")))
    testAssert.eq(table.concat(state.nativeLibraries, ","), "physics")

    local moved, away = tempProject({}), tempProject({})
    local copied, detail = process.capture({"cp", "-R", dir .. "/dist/.", moved})
    testAssert.eq(copied, 0, detail)
    remove(dir)
    local name = executable:match("[^/]+$")
    local status, result = process.capture({moved .. "/" .. name}, {cwd = away})
    remove(moved);
    remove(away)
    testAssert.eq(status, 0, result)
    testAssert.eq(result, "7\n", "the moved binary loads its fresh sidecar with no project left")
end

function M.missingLogicalFilesAllowCheckingButRefuseNativeEmission()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, libraries = {physics = {search = {"not-built"}}},
build = {kind = "binary", stub = "nupp", entries = {"main"}, outDir = "out"}}]],
        ["src/main.nupp"] = 'cdef function step(): int32 from "physics"\nprint(tonumber(step()))\n',
    })
    local checked = {}
    testAssert.eq(fixture.project.build(dir, {checkOnly = true, diagnostics = checked}), 0)
    local diagnostics = {}
    local status = fixture.project.build(dir, {diagnostics = diagnostics})
    remove(dir)
    assert(status ~= 0, "executable code cannot retain an unresolved library")
    local messages = {}
    for _, diagnostic in ipairs(diagnostics) do
        messages[#messages + 1] = diagnostic.msg or diagnostic.message or ""
    end
    assert(table.concat(messages, "\n"):find("NUPP2912", 1, true), table.concat(messages, "\n"))
end

return M
