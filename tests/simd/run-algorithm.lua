-- Run an existing independent algorithm corpus through one exact native tier.
local runner = require("tests.simd.runner")
local name, directory = assert(arg[1]), assert(arg[2]):gsub("\\", "/")
if package.config:sub(1, 1) == "\\" then
    directory = directory:gsub("^/(%a)/", "%1:/")
end
local targets = {
    utf8simd = {target = "utf8-simd", script = "tests/run.lua"},
    base64simd = {target = "base64-simd", script = "tests/run.lua"},
    ["simd-json"] = {target = "simd-json-index", script = "tests/index.lua"},
    ["fused-json"] = {target = "fused-json", script = "tests/differential.lua"},
}
local selected = assert(targets[name], "unknown algorithm corpus")
local tier = assert(os.getenv("NUPP_SIMD_TIER"), "an exact tier is required")
assert(tier == "baseline" or tier == "avx2" or tier == "avx512f" or tier == "neon")
local root, q = runner.root(), runner.quote
local workspace = directory .. "/workspace"
local project = workspace .. "/bench/" .. name
runner.command("test ! -e " .. q(workspace) .. " && mkdir -p " .. q(workspace), directory .. "/prepare.log")
local capabilities = assert(runner.hostTiers())
assert(("\n" .. capabilities):find("\n" .. tier .. "\n", 1, true), "requested algorithm tier is unavailable")
local projectPath = "bench/" .. name
local listed = runner.command(
    "git -C " .. q(root) .. " ls-files --cached --others --exclude-standard -- " .. q(projectPath),
    directory .. "/copy.log"
)
local copied = 0
for relative in listed:gmatch("[^\r\n]+") do
    local source = root .. "/" .. relative
    local exists = io.open(source, "rb")
    if exists then
        exists:close()
        local target = workspace .. "/" .. relative
        runner.command("mkdir -p " .. q(assert(target:match("^(.*)/"))), directory .. "/copy-directory.log")
        runner.write(target, runner.read(source))
        copied = copied + 1
    end
end
assert(copied > 0, "algorithm project contains no tracked or untracked nonignored files")
runner.command("mkdir -p " .. q(workspace .. "/tests/simd"), directory .. "/helper-directory.log")
runner.write(workspace .. "/tests/simd/nativeproof.lua", runner.read(root .. "/tests/simd/nativeproof.lua"))
runner.write(workspace .. "/tests/simd/corpusmath.lua", runner.read(root .. "/tests/simd/corpusmath.lua"))
runner.write(project .. "/" .. selected.script, runner.read(root .. "/bench/" .. name .. "/" .. selected.script))
if name == "fused-json" then
    local source = "/src/nupp/codec/json/internal/decoder/fused.nupp"
    runner.command(
        "mkdir -p " .. q(workspace .. "/src/nupp/codec/json/internal/decoder"),
        directory .. "/fused-source.log"
    )
    runner.write(workspace .. source, runner.read(root .. source))
    runner.write(
        workspace .. "/tests/jsonfuseddifferentialtest.lua",
        runner.read(root .. "/tests/jsonfuseddifferentialtest.lua")
    )
    runner.command("cd " .. q(project) .. " && bash ./prepare.sh", directory .. "/fused-prepare.log")
end
local manifest = assert(loadfile(project .. "/nupp.lua"))()
manifest.include = {"src", root .. "/src"}
manifest.build.targets[selected.target].aotFeatures = {minimum = tier, maximum = tier}

local function lua(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    if type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    assert(type(value) == "table", "unsupported manifest value")
    local keys, entries = {}, {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
        entries[#entries + 1] = "[" .. lua(key) .. "]=" .. lua(value[key])
    end

    return "{" .. table.concat(entries, ",") .. "}"
end

runner.write(project .. "/nupp.lua", "return " .. lua(manifest) .. "\n")
runner.command(
    "cd " .. q(project) .. " && " .. q(root .. "/bin/nupp") .. " build --target " .. q(selected.target),
    directory .. "/build.log"
)
local units = runner.json(project .. "/build/aot/units.json")
local actual = 0
for _, unit in ipairs(units.units) do
    if not unit.detector then
        assert(unit.tier == tier, "algorithm emitted an unexpected tier")
        actual = actual + 1
    end
end
assert(actual > 0, "algorithm emitted no compiled units")
local path = "build/?.lua;build/?/init.lua;" .. root .. "/build/?.lua;" .. root .. "/build/?/init.lua;;"
local output = runner.command(
    "cd " .. q(project) .. " && LUA_PATH=" .. q(path) .. " luajit -joff " .. q(selected.script),
    directory .. "/execution.log"
)
local calls = assert(tonumber(output:match("SIMD_NATIVE_CALLS=(%d+)")), "algorithm has no completed native-call proof")
local checks = assert(tonumber(output:match("SIMD_CHECKS=(%d+)")), "algorithm checked no reported cases")
assert(calls > 0 and checks > 0)
local digest = "if command -v sha256sum >/dev/null 2>&1; then digest=sha256sum; flags=; else digest=shasum; flags='-a 256'; fi; find "
    .. q(
        project .. "/build"
    ) .. [[ -type f \( -name '*.ll' -o -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -exec "$digest" $flags {} +]]
runner.command(digest, directory .. "/artifacts.sha256")
local report = {
    ok = true,
    tier = tier,
    algorithm = name,
    nativeCalls = calls,
    randomFingerprint = output:match("SIMD_CORPUS_RANDOM=([^\r\n]+)"),
    cases = checks,
    generatedUnits = actual,
    units = units,
    compiler = "llvm",
    capabilities = capabilities,
    executionLog = directory .. "/execution.log",
    artifacts = directory .. "/artifacts.sha256"
}
runner.writeJson(directory .. "/matrix-result.json", report)
print(name .. ": " .. checks .. " cases, " .. calls .. " completed native calls, tier " .. tier)
