-- Runtime unit fixtures on the owned backend. Builds each unit through the
-- content-addressed code cache, runs every case through the standalone bridge
-- and checks the answers against counts computed here.
--
--   cd native/core/tests/units && NUPP_COMPILER_ROOT=$PWD/../../../.. ../../../../bin/nupp run run.lua [normal|spill]
--
-- NUPP_CORE_BRIDGE selects a prebuilt bridge; otherwise cargo builds one.
local runner = require("nupp.core.unitrunner")
local function cwd()
    local pipe = assert(io.popen("pwd"))
    local path = pipe:read("*l")
    pipe:close()
    return path
end
local HERE = debug.getinfo(1, "S").source:match("^@(/.*)/[^/]*$") or cwd()
local ROOT = HERE .. "/../../../.."
local BUILD = ROOT .. "/build/core-units"

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    return tonumber(output:match("__exit__:(%d+)%s*$")), (output:gsub("__exit__:%d+%s*$", ""))
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local bytes = file:read("*a")
    file:close()
    return bytes
end

local function words(values)
    local out = {}
    for index, value in ipairs(values) do
        local bytes = {}
        for at = 0, 7 do
            bytes[at + 1] = string.char((value >> (at * 8)) & 255)
        end
        out[index] = table.concat(bytes)
    end
    return table.concat(out)
end

local function decode(bytes, index)
    local value = 0
    for at = 8, 1, -1 do
        value = value * 256 + bytes:byte((index - 1) * 8 + at)
    end
    return value
end

local function bridge()
    local given = os.getenv("NUPP_CORE_BRIDGE")
    if given then
        return given
    end
    local target = ROOT .. "/build/core-bridge"
    local status, output = shell(("cargo +stable build --manifest-path %s --offline --locked --bin nupp-core --target-dir %s")
        :format(quote(ROOT .. "/native/core/bridge/Cargo.toml"), quote(target)))
    assert(status == 0, "bridge build failed: " .. output)
    return target .. "/debug/nupp-core"
end

-- Each unit: its fixture modules, the dispatched functions with their arity,
-- and cases of {function, arguments, expected result}.
local UNITS = {
    {
        name = "heapunits",
        modules = {"heapunits", "unitentry"},
        entries = {{"heapunits", "chain", 2}, {"heapunits", "garbage", 2}, {"heapunits", "alternate", 2}},
        cases = function()
            local cases = {}
            for _, stress in ipairs({0, 1}) do
                for _, n in ipairs(stress == 0 and {1, 10, 1000} or {1, 7, 64}) do
                    cases[#cases + 1] = {"chain", {n, stress}, n * 1000000}
                    cases[#cases + 1] = {"garbage", {n, stress}, 0}
                    cases[#cases + 1] = {"alternate", {n, stress}, (n + 1) // 2}
                end
            end
            return cases
        end
    },
    {
        name = "gcunits",
        modules = {"gcunits", "unitentry"},
        entries = {
            {"gcunits", "listSurvives", 2}, {"gcunits", "rings", 2}, {"gcunits", "fanOut", 2},
            {"gcunits", "barrier", 1}, {"gcunits", "initializedBlack", 1}
        },
        cases = function()
            -- Counts from tests/nativeheaptest.lua, computed there independently.
            return {
                {"listSurvives", {1000, 5000}, 1000}, {"listSurvives", {0, 100}, 0},
                {"rings", {10, 100}, 500}, {"rings", {1, 1000}, 1000},
                {"fanOut", {100, 16}, 51}, {"fanOut", {5000, 16}, 2501}, {"fanOut", {50, 40000}, 26},
                {"barrier", {0}, 1}, {"barrier", {1}, 0},
                {"initializedBlack", {3000}, 1}
            }
        end
    }
}

os.execute("mkdir -p " .. quote(BUILD))
local modes = arg[1] and {arg[1]} or {"normal", "spill"}
local tool = bridge()
local failures, passed = 0, 0
for _, unit in ipairs(UNITS) do
    local fixtures = {}
    for _, name in ipairs(unit.modules) do
        fixtures[#fixtures + 1] = {moduleName = name, path = HERE .. "/" .. name .. ".nupp", include = "native/core/tests/units"}
    end
    local index = {}
    for at, entry in ipairs(unit.entries) do
        index[entry[2]] = at - 1
    end
    for _, mode in ipairs(modes) do
        local started = os.time()
        local result = runner.build(fixtures, unit.entries, mode, ROOT .. "/build/core-unit-cache")
        local bundle = BUILD .. "/" .. unit.name .. "-" .. mode .. ".bundle"
        write(bundle, result.bundle)
        print(("%s %s: built in %ds, %d owners, %d selected"):format(unit.name, mode, os.time() - started,
            result.owners, result.selected))
        for _, case in ipairs(unit.cases()) do
            local input, output = bundle .. ".in", bundle .. ".out"
            local values = {index[case[1]]}
            for _, value in ipairs(case[2]) do
                values[#values + 1] = value
            end
            write(input, words(values))
            os.remove(output)
            local status, text = shell(("%s %s %s %s"):format(quote(tool), quote(bundle), quote(input), quote(output)))
            local bytes = read(output)
            local label = ("%s %s %s(%s)"):format(unit.name, mode, case[1], table.concat(case[2], ", "))
            if status ~= 0 or not bytes or #bytes ~= 16 then
                failures = failures + 1
                print("FAIL " .. label .. ": bridge " .. tostring(status) .. " " .. text)
            else
                local value, failure = decode(bytes, 1), decode(bytes, 2)
                if value ~= case[3] or failure ~= 0 then
                    failures = failures + 1
                    print(("FAIL %s: expected %d, got %d (error %d)"):format(label, case[3], value, failure))
                else
                    passed = passed + 1
                end
            end
        end
    end
end
print(("%d passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
