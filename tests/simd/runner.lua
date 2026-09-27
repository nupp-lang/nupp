-- Shared execution boundary for generated SIMD semantic corpora.
-- Every run requests exactly one tier and proves the named probes enter native
-- code.
local M = {}
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
    local requested = (options.directory or os.tmpname()):gsub("\\", "/")
    if requested:sub(1, 1) ~= "/" and not requested:match("^%a:/") then
        requested = root .. "/" .. requested
    end
    local dir = nativePath(requested)
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
    })

    return dir, entries
end

local function tierForHost()
    local jit = require("jit")
    return jit.arch == "arm64" and "neon" or "baseline"
end

function M.hostTier()
    return os.getenv("NUPP_SIMD_TIER") or tierForHost()
end

local function libraryIn(directory)
    for _, name in ipairs({"libnative_aot.dylib", "libnative_aot.so", "native_aot.dll"}) do
        local path = directory .. "/" .. name
        local handle = io.open(path, "rb")
        if handle then
            handle:close()
            return path
        end
    end

    return nil
end

local hostTiersMemo = nil

--- The native tiers this host can execute, one per line, or nil and why not.
---
--- An arm64 host has one. An x86-64 host is asked the way a built library
--- asks it: a probe project spanning every x86-64 tier is compiled, and its
--- library's own feature detector answers, so a tier counts only when the
--- detector every AOT library carries would select it.
function M.hostTiers(options)
    options = options or {}
    if hostTiersMemo then
        return hostTiersMemo
    end
    local arch = jit.arch
    if arch == "arm64" then
        hostTiersMemo = "neon\n"
        return hostTiersMemo
    end
    if arch ~= "x64" then
        return nil, "unmodeled SIMD host architecture " .. tostring(arch)
    end
    local dir = nativePath(os.tmpname():gsub("\\", "/"))
    os.remove(dir)
    directory(dir .. "/src")
    M.write(
        dir .. "/src/tierprobe.nupp",
        [[
module tierprobe

@aot
local function probe(value: number): number
    return value + 1.0
end

export = {probe = probe}
]]
    )
    M.write(
        dir .. "/nupp.lua",
        [[
return {include={"src"},build={targets={native={
kind="modules",entries={"tierprobe"},outDir="build/native",aot="require",
aotFeatures={minimum="baseline",maximum="avx512f"},
}}}}
]]
    )
    local built = execute(
        "cd " .. M.quote(dir) .. " && " .. M.quote(options.nupp or root .. "/bin/nupp")
            .. " build --target native >" .. M.quote(dir .. "/build.log") .. " 2>&1"
    )
    if built ~= 0 then
        return nil, "the tier probe did not build: " .. M.read(dir .. "/build.log")
    end
    local library = libraryIn(dir .. "/build/native/lib")
    if not library then
        return nil, "the tier probe linked no library"
    end
    local ffi = require("ffi")
    pcall(ffi.cdef, "int32_t ks_aot_feature_tier(void);")
    local ok, answer = pcall(function()
        return tonumber(ffi.load(library).ks_aot_feature_tier())
    end)
    execute("rm -rf " .. M.quote(dir))
    if not ok then
        return nil, "the tier probe's detector could not be called: " .. tostring(answer)
    end
    local tiers = {"baseline"}
    if answer >= 1 then
        tiers[#tiers + 1] = "avx2"
    end
    if answer >= 2 then
        tiers[#tiers + 1] = "avx512f"
    end
    hostTiersMemo = table.concat(tiers, "\n") .. "\n"

    return hostTiersMemo
end

--- The code generator every AOT build uses: LLVM, in process.
function M.codegen()
    local ok, codegen = pcall(require, "nupp.compiler.aot.llvm.codegen")
    if not ok then
        package.path = nativeRoot .. "/build/?.lua;" .. nativeRoot .. "/build/?/init.lua;" .. package.path
        ok, codegen = pcall(require, "nupp.compiler.aot.llvm.codegen")
    end
    if not ok then
        return nil, tostring(codegen)
    end
    local available, why = codegen.available()
    if not available then
        return nil, tostring(why)
    end

    return codegen.version()
end

--- Proves that the code generator and CPU tier can execute native SIMD.
--- Unlike `native`, this returns evidence for `test.requireCapability` rather
--- than turning unavailable hardware into a failed semantic case.
function M.nativeCapability(options)
    options = options or {}
    local tier = options.tier or M.hostTier()
    local evidence = {compiler = "llvm", compilerDialect = "llvm", tier = tier, available = false}
    local version, problem = M.codegen()
    if not version then
        evidence.reason = "the LLVM code generator is unavailable: " .. tostring(problem)
        return evidence
    end
    evidence.compilerVersion = version
    local capabilities, tiersProblem = M.hostTiers(options)
    if not capabilities then
        evidence.reason = tiersProblem
        return evidence
    end
    evidence.capabilities = capabilities
    evidence.available = ("\n" .. capabilities):find("\n" .. tier .. "\n", 1, true) ~= nil
    if not evidence.available then
        evidence.reason = "CPU tier is unavailable"
    end

    return evidence
end

function M.native(generated, options)
    options = options or {}
    local tier = options.tier or M.hostTier()
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
    local capability = options.capability or M.nativeCapability({tier = tier, nupp = options.nupp})
    local capabilities = capability.capabilities or ""
    assert(
        capability.available and ("\n" .. capabilities):find("\n" .. tier .. "\n", 1, true),
        "requested tier " .. tier .. " cannot execute on this host: " .. tostring(capability.reason)
    )
    local build = "cd " .. M.quote(dir) .. " && " .. M.quote(options.nupp or root .. "/bin/nupp") .. " build --target native"
    local buildOutput = M.command(build .. (options.buildJson and " --quiet --format json" or ""), dir .. "/build.log")
    local buildReport = options.buildJson and decode(buildOutput) or nil
    local units = M.json(dir .. "/build/native/aot/units.json")
    local actual = 0
    for _, unit in ipairs(units.units) do
        if not unit.detector then
            assert(unit.tier == tier, "requested " .. tier .. ", artifact contains " .. tostring(unit.tier))
            actual = actual + 1
        end
    end
    assert(actual > 0, "no native SIMD translation units were emitted")
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
        "the scalar twins did not execute the same probe inventory"
    )
    result.scalarC = scalar
    for key in pairs(result.calls) do
        assert(scalar.calls[key], "scalar-C route missed native oracle probe " .. key)
        local nativeSymbol = result.symbols and result.symbols[key]
        local scalarSymbol = scalar.symbols and scalar.symbols[key]
        local suffix = "__" .. tier
        assert(
            type(nativeSymbol) == "string"
            and nativeSymbol:sub(-#suffix) == suffix
            and not nativeSymbol:find("_forced_scalar__", 1, true),
            "native route lacks an exact-tier symbol for " .. key
        )
        assert(
            type(scalarSymbol) == "string" and scalarSymbol:match("_forced_scalar__" .. tier .. "$"),
            "scalar-C route lacks its exact-tier twin for " .. key
        )
        assert(nativeSymbol ~= scalarSymbol, "native and scalar-C routes resolved the same symbol for " .. key)
    end
    result.sameOracle = true
    result.distinctRouteSymbols = true
    result.directory = dir
    result.host = {os = jit.os, arch = jit.arch, capabilities = capabilities}
    local digestCommand = "if command -v sha256sum >/dev/null 2>&1; then digest=sha256sum; flags=; "
        .. "else digest=shasum; flags='-a 256'; fi; find "
        .. M.quote(
            dir .. "/build/native"
        )
        .. [[ -type f \( -name '*.ll' -o -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -exec "$digest" $flags {} +]]
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
    local sourceBytes, sourceFiles = 0, 0
    for _, text in pairs(generated.files) do
        sourceBytes = sourceBytes + #text
        sourceFiles = sourceFiles + 1
    end
    result.work = {
        generatedSourceBytes = sourceBytes,
        generatedSourceFiles = sourceFiles,
        generatedUnits = actual,
        buildCommands = 1,
        externalCommands = buildReport
        and buildReport.timing
        and buildReport.timing.aot
        and buildReport.timing.aot.externalCommands
        or nil,
    }
    result.compilerCommand = "llvm"
    result.compilerVersion = capability.compilerVersion
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
    local probeModules = {}
    for module in pairs(generated.probes) do
        probeModules[#probeModules + 1] = module
    end
    table.sort(probeModules)
    local preload = {}
    for _, module in ipairs(probeModules) do
        preload[#preload + 1] = ("require(%q)"):format(module)
    end
    M.write(
        dir .. "/src/" .. runner .. ".g.nupp",
        (
            "local entry=require(%q)\n%s\nif __nuppWasmBeforeRun then __nuppWasmBeforeRun() end\nlocal cases=entry.run()\nreturn string.format('{\"cases\":%%.0f}',cases)\n"
        ):format(generated.entry, table.concat(preload, "\n"))
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
    local environment = options.environment or ""
    M.command(
        "cd " .. M.quote(
            dir
        ) .. " && " .. environment .. M.quote(options.nupp or root .. "/bin/nupp") .. " build --target app",
        dir .. "/build.log"
    )

    return dir
end

return M
