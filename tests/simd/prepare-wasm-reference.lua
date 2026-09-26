-- The scalar reference for a built Wasm SIMD project:
--
--   luajit tests/simd/prepare-wasm-reference.lua PROJECT OUTPUT
--
-- The project is rebuilt with NUPP_AOT_WASM_ORACLE=1, which points every Wasm
-- entry at its kernel's unoptimized scalar twin, and scalar-selection.json is
-- written beside it. PROJECT must already hold the SIMD route's result.json.
local project, output = assert(arg[1], "PROJECT"), assert(arg[2], "OUTPUT")
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = assert((source:match("^(.*)/tests/simd/[^/]+$") or "."))
package.path = root .. "/?.lua;" .. root .. "/build/?.lua;" .. package.path

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function absolute(path)
    if path:match("^/") then
        return path
    end
    local pipe = assert(io.popen("pwd"))
    local here = pipe:read("*l")
    pipe:close()
    return here .. "/" .. path
end
project, output = absolute(project), absolute(output)

local function run(command)
    local ok = os.execute(command)
    if ok ~= 0 and ok ~= true then
        error("failed: " .. command, 0)
    end
end

local json = require("nupp.codec.json")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function sha256(path)
    local pipe = assert(io.popen("(shasum -a 256 " .. quote(path) .. " || sha256sum " .. quote(path) .. ") 2>/dev/null"))
    local digest = pipe:read("*a"):match("^(%x+)")
    pipe:close()
    return assert(digest, "no digest for " .. path)
end

local reference = read(project .. "/result.json")
local simd = json.decode(reference, json.NULL)
assert(simd.ok and simd.nativeCalls and simd.symbols, "run the SIMD corpus before preparing its reference")
run("mkdir -p " .. quote(output))
run("cp -R " .. quote(project .. "/src") .. " " .. quote(project .. "/nupp.lua") .. " " .. quote(output))
local corpus = io.open(project .. "/corpus.json", "rb")
if corpus then
    corpus:close()
    run("cp " .. quote(project .. "/corpus.json") .. " " .. quote(output))
end
run(
    "cd " .. quote(output) .. " && NUPP_AOT_WASM_ORACLE=1 " .. quote(root .. "/bin/nupp")
        .. " build --target app > " .. quote(output .. "/reference-build.log") .. " 2>&1"
)

-- The rebuilt units are the SIMD ones by source; their names carry the switch.
local original = json.decode(read(project .. "/dist/aot/units.json"), json.NULL)
local rebuilt = json.decode(read(output .. "/dist/aot/units.json"), json.NULL)
local bySource = {}
for _, unit in ipairs(original.units) do
    bySource[unit.source] = unit
end
local units = {}
for _, unit in ipairs(rebuilt.units) do
    if unit.wasm then
        local before = assert(bySource[unit.source], "the reference build has a unit the SIMD build does not")
        units[#units + 1] = {
            unit = unit.unit,
            wasm = unit.wasm,
            originalWasmSha256 = sha256(project .. "/dist/aot/" .. before.wasm),
            wasmSha256 = sha256(output .. "/dist/aot/" .. unit.wasm),
        }
    end
end
local selection = {
    executionPath = "scalar-c",
    originalProject = project,
    referenceExecutionSha256 = sha256(project .. "/result.json"),
    referenceCases = simd.cases,
    referenceCalls = simd.nativeCalls,
    referenceProbes = simd.probes,
    units = units,
}
local file = assert(io.open(output .. "/scalar-selection.json", "wb"))
file:write(json.encode(selection), "\n")
file:close()
print(("Prepared %d reference Wasm units in %s"):format(#units, output))
