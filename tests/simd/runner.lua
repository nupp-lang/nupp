-- Shared execution boundary for generated SIMD semantic corpora.
-- Every run requests exactly one tier and proves the named probes enter C.
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

--- Proves that the selected compiler and CPU tier can execute native SIMD.
--- Unlike `native`, this returns evidence for `test.requireCapability` rather
--- than turning unavailable hardware into a failed semantic case.
function M.nativeCapability(options)
    options = options or {}
    local compiler = options.compiler
    local selectionProblem = nil
    if compiler == nil then
        local selected, problem = require("nupp.tools.build.aot").toolchain(nil, nil)
        compiler = selected and selected.command or nil
        selectionProblem = problem
    end
    local tier = options.tier or M.hostTier()
    local dir = nativePath(os.tmpname():gsub("\\", "/"))
    os.remove(dir)
    directory(dir)
    local versionLog = dir .. "/compiler.log"
    local buildLog = dir .. "/capabilities-build.log"
    local runLog = dir .. "/capabilities.log"
    local evidence = {compiler = compiler or "", tier = tier, available = false}
    if compiler == nil then
        evidence.reason = selectionProblem or "no supported compiler was found"
    else
        local versionCode = execute(M.quote(compiler) .. " --version >" .. M.quote(versionLog) .. " 2>&1")
        if versionCode ~= 0 then
            evidence.reason = "compiler command failed"
        else
            local versionText = M.read(versionLog)
            evidence.compilerVersion = (versionText:match("[^\r\n]+"))
            local dialect = require("nupp.tools.build.aot").identify(versionText)
            evidence.compilerDialect = dialect or "unknown"
            evidence.compilerSignature = require("nupp.tools.build.aot").toolSignature(compiler)
            local built = execute(
                M.quote(
                    compiler
                ) .. " -std=c11 -O2 -Wall -Wextra -Werror " .. M.quote(
                    root .. "/tests/simd/capabilities.c"
                ) .. " -o " .. M.quote(dir .. "/capabilities.exe") .. " >" .. M.quote(buildLog) .. " 2>&1"
            )
            if built ~= 0 then
                evidence.reason = "capability probe did not compile"
                evidence.log = M.read(buildLog)
            else
                local ran = execute(M.quote(dir .. "/capabilities.exe") .. " >" .. M.quote(runLog) .. " 2>&1")
                if ran ~= 0 then
                    evidence.reason = "capability probe did not execute"
                    evidence.log = M.read(runLog)
                else
                    local capabilities = M.read(runLog):gsub("\r\n", "\n")
                    evidence.capabilities = capabilities
                    evidence.available = ("\n" .. capabilities):find("\n" .. tier .. "\n", 1, true) ~= nil
                    if not evidence.available then
                        evidence.reason = "CPU tier is unavailable"
                    end
                end
            end
        end
    end
    local removed, removeProblem = require("nupp.io.files").remove(dir, true)
    if not removed then
        evidence.cleanupProblem = tostring(removeProblem)
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
    local capability = options.capability or M.nativeCapability({compiler = options.compiler, tier = tier})
    local compiler = options.compiler or capability.compiler or os.getenv("NUPP_NATIVE_CC")
    local capabilities = capability.capabilities or ""
    assert(
        capability.available and ("\n" .. capabilities):find("\n" .. tier .. "\n", 1, true),
        "requested tier " .. tier .. " cannot execute on this host: " .. tostring(capability.reason)
    )
    local env = compiler and ("NUPP_NATIVE_CC=" .. M.quote(compiler) .. " ") or ""
    local build = "cd " .. M.quote(
        dir
    ) .. " && " .. env .. M.quote(options.nupp or root .. "/bin/nupp") .. " build --target native"
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
        "scalar C did not execute the same probe inventory"
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
    local compiler = options.compiler or os.getenv("NUPP_WASM_CC") or os.getenv("EMCC") or "emcc"
    local environment = (options.environment or "") .. "NUPP_WASM_CC=" .. M.quote(compiler) .. " "
    if options.emscriptenCache then
        directory(options.emscriptenCache)
        environment = "EM_CACHE=" .. M.quote(options.emscriptenCache) .. " " .. environment
    end
    M.command(
        "cd " .. M.quote(
            dir
        ) .. " && " .. environment .. M.quote(options.nupp or root .. "/bin/nupp") .. " build --target app",
        dir .. "/build.log"
    )

    return dir
end

return M
