-- Shared execution boundary for generated SIMD semantic corpora.
-- Every run requests exactly one tier and proves the named probes enter C.
local M = {}
local regionProof = require("tests.simd.regionproof")
local source = assert(debug.getinfo(1, "S").source:match("^@(.*)$")):gsub("\\", "/")
local root = source:match("^(.*)/tests/simd/runner.lua$") or "."
if root:sub(1, 1) ~= "/" and not root:match("^%a:") then
    local pipe = assert(io.popen("pwd"))
    root = assert(pipe:read("*l")) .. "/" .. root
    pipe:close()
end
root = root:gsub("/%.$", "")
local nativeRoot = root:gsub("^/(%a)/", "%1:/")
local encode = assert(loadfile(nativeRoot .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()
local decode = assert(loadfile(nativeRoot .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()

function M.quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function nativePath(path)
    if package.config:sub(1, 1) == "\\" then
        return path:gsub("^/(%a)/", "%1:/")
    end
    return path
end

function M.read(path)
    path = nativePath(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = handle:read("*a")
    handle:close()

    return text
end

function M.write(path, text)
    path = nativePath(path)
    local handle = assert(io.open(path, "wb"), "cannot write " .. path)
    handle:write(text)
    handle:close()
end

local function execute(command)
    if package.config:sub(1, 1) ~= "\\" or rawget(_G, "__NUPP_TEST_BASH") then
        return os.execute(command)
    end
    -- The normal test runner already provides this boundary. Standalone
    -- matrix runs also use Git Bash, rather than handing POSIX syntax to cmd.
    local bash = assert(os.getenv("NUPP_TEST_BASH"), "NUPP_TEST_BASH must name Git Bash on Windows")
    local script = os.tmpname() .. ".sh"
    M.write(
        script,
        command:gsub("(%a):/", function(drive)
            return "/" .. drive:lower() .. "/"
        end) .. "\n"
    )
    local code = os.execute(('""%s" "%s""'):format(bash, script))
    os.remove(script)

    return code
end

function M.command(command, log)
    local code = execute(command .. " >" .. M.quote(log) .. " 2>&1")
    assert(code == 0, command .. " failed; preserved " .. log .. "\n" .. M.read(log))
    return M.read(log)
end

function M.json(path)
    return decode(M.read(path))
end

function M.writeJson(path, value)
    M.write(path, encode(value) .. "\n")
end

function M.root()
    return nativeRoot
end

local function directory(path)
    assert(execute("mkdir -p " .. M.quote(path)) == 0, "cannot create " .. path)
end

function M.prepare(generated, options)
    options = options or {}
    local dir = nativePath((options.directory or os.tmpname()):gsub("\\", "/"))
    if not options.directory then
        os.remove(dir)
    end
    local previous = io.open(dir .. "/corpus.json", "rb")
    if previous then
        previous:close()
        error("refusing to overwrite SIMD corpus evidence: " .. dir)
    end
    directory(dir .. "/src")
    assert(type(generated.files) == "table" and type(generated.entry) == "string", "invalid SIMD corpus")
    assert(generated.entry:match("^[%w_]+$"), "invalid SIMD entry module")
    local entries = {}
    for filename, text in pairs(generated.files) do
        local module = filename:match("^([%w_]+)%.g%.nupp$") or filename:match("^([%w_]+)%.nupp$")
        assert(module, "generated source must be a plain module filename")
        M.write(dir .. "/src/" .. filename, text)
        entries[#entries + 1] = module
    end
    table.sort(entries)
    M.writeJson(dir .. "/corpus.json", {
        entry = generated.entry,
        probes = generated.probes,
        coverage = generated.coverage,
        entries = entries,
        requiredRegions = regionProof.inventory(generated.files),
    })

    return dir, entries
end

local function tierForHost()
    local jit = require("jit")
    return jit.arch == "arm64" and "neon" or "baseline"
end

function M.native(generated, options)
    options = options or {}
    local tier = options.tier or os.getenv("NUPP_SIMD_TIER") or tierForHost()
    assert(tier == "baseline" or tier == "avx2" or tier == "avx512f" or tier == "neon", "invalid native tier")
    local dir, entries = M.prepare(generated, options)
    local quoted = {}
    for _, entry in ipairs(entries) do
        quoted[#quoted + 1] = string.format("%q", entry)
    end
    M.write(
        dir .. "/nupp.lua",
        (
            [=[
return {include={"src"},build={targets={native={
kind="modules",entries={%s},outDir="build/native",aot="require",
aotFeatures={minimum=%q,maximum=%q},
}}}}
]=]
        ):format(table.concat(quoted, ","), tier, tier)
    )
    local compiler = options.compiler or os.getenv("NUPP_NATIVE_CC")
    local probeCompiler = compiler or "cc"
    M.command(
        M.quote(
            probeCompiler
        ) .. " -std=c11 -O2 -Wall -Wextra -Werror " .. M.quote(
            root .. "/tests/simd/capabilities.c"
        ) .. " -o " .. M.quote(dir .. "/capabilities.exe"),
        dir .. "/capabilities-build.log"
    )
    local capabilities = M.command(M.quote(dir .. "/capabilities.exe"), dir .. "/capabilities.log"):gsub("\r\n", "\n")
    assert(
        ("\n" .. capabilities):find("\n" .. tier .. "\n", 1, true),
        "requested tier " .. tier .. " cannot execute on this host; see " .. dir .. "/capabilities.log"
    )
    local env = compiler and ("NUPP_NATIVE_CC=" .. M.quote(compiler) .. " ") or ""
    local build = "cd " .. M.quote(
        dir
    ) .. " && " .. env .. M.quote(options.nupp or root .. "/bin/nupp") .. " build --target native"
    M.command(build, dir .. "/build.log")
    local units = M.json(dir .. "/build/native/aot/units.json")
    local actual = 0
    for _, unit in ipairs(units.units) do
        if not unit.detector then
            assert(unit.tier == tier, "requested " .. tier .. ", artifact contains " .. tostring(unit.tier))
            actual = actual + 1
        end
    end
    assert(actual > 0, "no native SIMD translation units were emitted")
    local regions = regionProof.verify(regionProof.inventory(generated.files), units, tier, function(path)
        return M.read(dir .. "/build/native/aot/" .. path)
    end)
    M.writeJson(dir .. "/regions.json", regions)
    M.writeJson(dir .. "/execution.json", {root = nativeRoot, directory = dir:gsub("^/(%a)/", "%1:/"), tier = tier})
    local vm = options.lua or os.getenv("NUPP_SIMD_LUA") or "luajit"
    local run = "cd " .. M.quote(
        dir
    ) .. " && " .. M.quote(vm) .. " " .. M.quote(root .. "/tests/simd/execute-native.lua")
    M.command(run, dir .. "/execution.log")
    local result = M.json(dir .. "/result.json")
    assert(result.ok and result.nativeCalls > 0 and result.probes > 0, "no native calls proved")
    M.command(
        "cd " .. M.quote(dir) .. " && " .. M.quote(vm) .. " " .. M.quote(root .. "/tests/simd/execute-scalar.lua"),
        dir .. "/scalar-execution.log"
    )
    local scalar = M.json(dir .. "/scalar-result.json")
    assert(
        scalar.ok
        and scalar.tier == tier
        and scalar.route == "scalar-C"
        and scalar.nativeCalls > 0
        and scalar.cases == result.cases
        and scalar.probes == result.probes,
        "scalar C did not execute the same probe inventory"
    )
    result.scalarC = scalar
    for _, region in ipairs(regions.functions) do
        local module = region.source:gsub("^src/", ""):gsub("%.g%.nupp$", ""):gsub("%.nupp$", "")
        local key = module .. "." .. region.name
        assert(
            (result.calls[key] or 0) > 0 and (scalar.calls[key] or 0) > 0,
            "required region did not execute on both routes: " .. key
        )
    end
    result.requiredRegions = regions
    result.directory = dir
    result.host = {os = jit.os, arch = jit.arch, capabilities = capabilities}
    local digestCommand = "if command -v sha256sum >/dev/null 2>&1; then digest=sha256sum; flags=; "
        .. "else digest=shasum; flags='-a 256'; fi; find "
        .. M.quote(
            dir .. "/build/native"
        )
        .. [[ -type f \( -name '*.c' -o -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -exec "$digest" $flags {} +]]
    local hashes = M.command(digestCommand, dir .. "/artifacts.sha256")
    result.artifacts = {}
    for line in hashes:gmatch("[^\r\n]+") do
        local digest, path = line:match("^(%x+) +%*?(.*)$")
        assert(digest and #digest == 64, "invalid artifact digest: " .. line)
        result.artifacts[#result.artifacts + 1] = {path = path, sha256 = digest}
    end
    assert(#result.artifacts > 0, "no compiled artifact digests")
    result.units = units
    result.coverage = generated.coverage
    if compiler then
        result.compilerCommand = compiler
        result.compilerVersion = M.command(M.quote(compiler) .. " --version", dir .. "/compiler.log"):match("[^\r\n]+")
    end
    local report = options.report or os.getenv("NUPP_SIMD_REPORT")
    if report then
        M.writeJson(report, result)
    end

    return result
end

function M.wasm(generated, options)
    options = options or {}
    local dir = M.prepare(generated, options)
    local runner = "__nupp_wasm_runner"
    M.write(
        dir .. "/src/" .. runner .. ".g.nupp",
        (
            "local entry=require(%q)\nlocal cases=entry.run()\nlocal fingerprint=entry.randomFingerprint and entry.randomFingerprint()\nif fingerprint then return string.format('{\"cases\":%%.0f,\"randomFingerprint\":\"%%s\"}',cases,fingerprint) end\nreturn string.format('{\"cases\":%%.0f}',cases)\n"
        ):format(generated.entry)
    )
    M.write(
        dir .. "/nupp.lua",
        (
            [[
return {include={"src"},build={targets={app={
kind="bundle",entries={%q},sources={"src"},output="dist/app.lua",outDir="build/app",
dialect="luajit",host="browser",aot="require-wasm",aotFeatures={minimum="simd128",maximum="simd128"},
}}}}
]]
        ):format(runner)
    )
    local compiler = options.compiler or os.getenv("NUPP_WASM_CC") or os.getenv("EMCC") or "emcc"
    M.command(
        "cd " .. M.quote(
            dir
        ) .. " && NUPP_WASM_CC=" .. M.quote(
            compiler
        ) .. " " .. M.quote(options.nupp or root .. "/bin/nupp") .. " build --target app",
        dir .. "/build.log"
    )

    local units = M.json(dir .. "/build/app/aot/units.json")
    M.writeJson(
        dir .. "/regions.json",
        regionProof.verify(
            regionProof.inventory(generated.files),
            units,
            "simd128",
            function(path)
                return M.read(dir .. "/build/app/aot/" .. path)
            end
        )
    )

    return dir
end

return M
