-- Every benchmark project under `bench/` still checks against the tree it sits in.
--
-- A benchmark project includes `../../src`, so a library change reaches it the way it
-- reaches any caller, and nothing else checks most of them: the SIMD conformance rows
-- build narrow entries of a few, and the rest are run by hand when someone measures.
-- `bench/serde-spike` gathered eighteen "Buffer is not a Buffer" errors that way when
-- the JSON writer moved to `nupp.text` buffers, and `bench/simd-json` two more, with
-- no suite noticing either.
--
-- A project whose sources a script prepares first (`prepare.sh`) is skipped: until
-- the script runs it names an entry that does not exist yet, and the conformance row
-- that runs the script already checks what it builds. So is one whose native
-- packages (`pkgConfig`) this machine's pkg-config cannot resolve: checking it reads
-- their flags, and CI's runners carry neither simdjson nor a luajit.pc.
--
-- Each check starts cold in CI and reads the standard library it reaches, so they run
-- concurrently rather than one after another.

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if HERE:sub(1, 1) ~= "/" and not HERE:match("^%a:[/\\]") then
    local pipe = assert(io.popen("pwd"))
    HERE = assert(pipe:read("*l")) .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."
local NUPP = ROOT .. "/bin/nupp"

local M = {}

local function exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
    end

    return file ~= nil
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return ""
    end
    local content = file:read("*a")
    file:close()

    return content
end

--- Whether pkg-config resolves every package a manifest names under `pkgConfig`.
local function nativePackagesResolve(manifest)
    local packages = {}
    for value in manifest:gmatch("pkgConfig%s*=%s*(%b{})") do
        for name in value:gmatch('"([^"]+)"') do
            packages[#packages + 1] = name
        end
    end
    for value in manifest:gmatch('pkgConfig%s*=%s*"([^"]*)"') do
        for name in value:gmatch("%S+") do
            packages[#packages + 1] = name
        end
    end
    if #packages == 0 then
        return true
    end
    local status = os.execute("pkg-config --exists " .. table.concat(packages, " ") .. " >/dev/null 2>&1")

    return status == 0 or status == true
end

local function projects()
    local pipe = assert(io.popen("cd '" .. ROOT .. "/bench' && ls -d */"))
    local names = {}
    for line in pipe:lines() do
        local name = line:gsub("/$", "")
        local dir = ROOT .. "/bench/" .. name
        if exists(dir .. "/nupp.lua") and not exists(dir .. "/prepare.sh")
            and nativePackagesResolve(read(dir .. "/nupp.lua")) then
            names[#names + 1] = name
        end
    end
    pipe:close()
    table.sort(names)

    return names
end

function M.everyBenchmarkProjectChecks()
    local names = projects()
    assert(#names >= 8, "the benchmark projects were found: " .. #names)
    local scratch = os.tmpname()
    os.remove(scratch)
    assert(os.execute("mkdir -p '" .. scratch .. "'") == 0)
    local commands = {}
    for _, name in ipairs(names) do
        commands[#commands + 1] = (
            "(cd '%s/bench/%s' && NO_COLOR=1 '%s' check >'%s/%s.log' 2>&1; echo $? >'%s/%s.status') &"
        ):format(ROOT, name, NUPP, scratch, name, scratch, name)
    end
    commands[#commands + 1] = "wait"
    os.execute(table.concat(commands, "\n"))
    local problems = {}
    for _, name in ipairs(names) do
        local status = read(scratch .. "/" .. name .. ".status"):match("%d+")
        if status ~= "0" then
            problems[#problems + 1] = ("bench/%s (status %s):\n%s"):format(
                name,
                tostring(status),
                read(scratch .. "/" .. name .. ".log")
            )
        end
    end
    os.execute("rm -rf '" .. scratch .. "'")
    assert(#problems == 0, #problems .. " benchmark projects do not check:\n" .. table.concat(problems, "\n"))
end

return M
