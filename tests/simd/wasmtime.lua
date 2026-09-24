-- Ordinary-harness support for the compact pure-Wasm conformance packs.
local M = {}
local runner = require("tests.simd.runner")
local hash = require("nupp.compiler.hash")
local root = runner.root()

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
        return true
    end

    return false
end

local function basename(path)
    return assert(path:gsub("\\", "/"):match("([^/]+)$"), "path has no basename: " .. path)
end

local function firstLine(text)
    return text:match("[^\r\n]+") or ""
end

local function resolveCommand(command)
    local log = os.tmpname()
    local code = os.execute("command -v " .. runner.quote(command) .. " >" .. runner.quote(log) .. " 2>/dev/null")
    local resolved = code == 0 and firstLine(runner.read(log)) or nil
    os.remove(log)

    return resolved ~= "" and resolved or nil
end

local function commandDirectory(command)
    return command and command:gsub("\\", "/"):match("^(.*)/[^/]+$") or nil
end

local function pathEnvironment(directory)
    if not directory then
        return ""
    end

    return "PATH=" .. runner.quote(directory .. ":" .. (os.getenv("PATH") or "")) .. " "
end

local function tool(command, arguments, environment)
    local log = os.tmpname()
    local code = os.execute(
        (
            environment or ""
        ) .. runner.quote(command) .. " " .. (arguments or "--version") .. " >" .. runner.quote(log) .. " 2>&1"
    )
    local output = exists(log) and runner.read(log) or ""
    os.remove(log)

    return {
        available = code == 0,
        command = command,
        version = firstLine(output),
        output = code == 0 and nil or output,
    }
end

function M.capabilities()
    local compiler = os.getenv("NUPP_WASM_CC") or os.getenv("EMCC") or "emcc"
    local resolvedCompiler = resolveCommand(compiler)
    local compilerDirectory = commandDirectory(resolvedCompiler)
    local compilerEnvironment = pathEnvironment(compilerDirectory)
    local lua = os.getenv("NUPP_SIMD_LUA") or "luajit"
    local prebuilt = os.getenv("NUPP_WASMTIME_HOST_LIBRARY")
    local capabilities = {
        emscripten = tool(compiler, nil, compilerEnvironment),
        node = tool("node"),
        cargo = tool("cargo"),
        rustc = tool("rustc"),
        compiler = compiler,
        compilerDirectory = compilerDirectory,
        compilerEnvironment = compilerEnvironment,
        prebuilt = prebuilt,
        lua = tool(lua, "-v"),
    }
    capabilities.emscripten.resolved = resolvedCompiler
    capabilities.lua.runtime = jit.version
    capabilities.lua.os = jit.os
    capabilities.lua.arch = jit.arch
    if capabilities.emscripten.available then
        local ok, signature = pcall(require("nupp.compiler.build.aot").toolSignature, compiler)
        capabilities.emscripten.signature = ok and signature or nil
        capabilities.emscripten.cache = os.getenv("EM_CACHE")
            or (
                root .. "/build/simd-emscripten-cache/" .. hash.digest(
                    table.concat({capabilities.emscripten.version, capabilities.emscripten.signature or compiler}, "\0")
                )
            )
    end
    if prebuilt then
        capabilities.host = {available = exists(prebuilt), source = "NUPP_WASMTIME_HOST_LIBRARY", path = prebuilt,}
    else
        capabilities.host = {
            available = capabilities.cargo.available and capabilities.rustc.available,
            source = "cargo",
            cargo = capabilities.cargo.version,
            rustc = capabilities.rustc.version,
        }
    end

    return capabilities
end

function M.compilerEnvironment(capabilities)
    return capabilities.compilerEnvironment or ""
end

local function hostSources()
    return {
        root .. "/tests/simd/wasmtime-host/Cargo.toml",
        root .. "/tests/simd/wasmtime-host/Cargo.lock",
        root .. "/tests/simd/wasmtime-host/src/lib.rs",
        root .. "/tests/simd/build-wasmtime-host.sh",
    }
end

local function digestFiles(prefix, paths, extra)
    local parts = {prefix}
    for _, path in ipairs(paths) do
        parts[#parts + 1] = path:sub(#root + 1)
        parts[#parts + 1] = runner.read(path)
    end
    for _, value in ipairs(extra or {}) do
        parts[#parts + 1] = tostring(value)
    end

    return hash.digest(table.concat(parts, "\0"))
end

function M.prepareToolchain(test, capabilities)
    local identity = hash.digest(
        table.concat(
            {capabilities.emscripten.version, capabilities.emscripten.signature or capabilities.compiler,},
            "\0"
        )
    )
    local key = "simd-emscripten-ready-" .. identity
    test.fixture(key, function(private)
        local source = private .. "/probe.c"
        runner.write(source, "void nupp_wasm_cache_probe(void) {}\n")
        runner.command(
            "mkdir -p " .. runner.quote(
                capabilities.emscripten.cache
            ) .. " && " .. M.compilerEnvironment(
                capabilities
            ) .. "EM_CACHE=" .. runner.quote(
                capabilities.emscripten.cache
            ) .. " " .. runner.quote(
                capabilities.compiler
            ) .. " " .. runner.quote(
                source
            ) .. " -std=c11 -O0 -sSTANDALONE_WASM=1 --no-entry -o " .. runner.quote(private .. "/probe.wasm"),
            private .. "/build.log"
        )

        return {compiler = capabilities.emscripten.version, cacheIdentity = identity,}
    end)
end

function M.host(test, capabilities)
    if capabilities.prebuilt then
        return capabilities.prebuilt, {
            key = "prebuilt-" .. hash.digest(runner.read(capabilities.prebuilt)),
            source = "prebuilt",
        }
    end
    local key = "simd-wasmtime-host-" .. digestFiles("simd-wasmtime-host-v1", hostSources(), {
        capabilities.cargo.version,
        capabilities.rustc.version,
        jit.os,
        jit.arch
    })
    local directory, evidence = test.fixture(key, function(private)
        local target = private .. "/target"
        local output = runner.command(
            "NUPP_WASMTIME_TARGET_DIR=" .. runner.quote(
                target
            ) .. " " .. runner.quote(root .. "/tests/simd/build-wasmtime-host.sh"),
            private .. "/build.log"
        )
        local library = output:match("([^\r\n]+)%s*$")
        assert(library and exists(library), "Wasmtime host build returned no library")
        local relative = library:gsub("\\", "/"):sub(#private + 2)
        assert(relative ~= library and relative ~= "", "Wasmtime host library escaped its fixture")

        return {
            library = relative,
            libraryName = basename(library),
            cargo = capabilities.cargo.version,
            rustc = capabilities.rustc.version,
        }
    end)

    return directory .. "/" .. evidence.library, {key = key, source = "fixture", library = evidence.libraryName,}
end

local function generatedSources(generated)
    local paths = {}
    for path in pairs(generated.files) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    local parts = {}
    for _, path in ipairs(paths) do
        parts[#parts + 1] = path
        parts[#parts + 1] = generated.files[path]
    end

    return parts
end

function M.fixtureKey(pack, generated, capabilities, host)
    local paths = {
        root .. "/tests/simd/runner.lua",
        root .. "/tests/simd/wasmtime.lua",
        root .. "/tests/simd/run-wasmtime-guest.lua",
        root .. "/tests/simd/prepare-wasm-scalar.mjs",
        root .. "/tests/simd/native-packs.lua",
    }
    local extra = generatedSources(generated)
    extra[#extra + 1] = pack
    extra[#extra + 1] = capabilities.emscripten.version
    extra[#extra + 1] = capabilities.emscripten.signature
    extra[#extra + 1] = capabilities.node.version
    extra[#extra + 1] = capabilities.lua.command
    extra[#extra + 1] = capabilities.lua.runtime
    extra[#extra + 1] = capabilities.lua.os
    extra[#extra + 1] = capabilities.lua.arch
    extra[#extra + 1] = host.key
    extra[#extra + 1] = require("nupp.compiler.fingerprint").toolFingerprint()

    return "simd-wasmtime-pack-" .. digestFiles("simd-wasmtime-pack-v2", paths, extra)
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    return keys
end

local function routeIdentity(simd, scalar, selection)
    local simdKeys = sortedKeys(simd.symbols)
    local scalarKeys = sortedKeys(scalar.symbols)
    assert(table.concat(simdKeys, "\0") == table.concat(scalarKeys, "\0"), "Wasm route probe inventories differ")
    assert(#simdKeys == simd.probes, "Wasm symbol inventory differs from probe count")
    assert(selection.executionPath == "scalar-c", "scalar-C route selection is missing")
    assert(selection.referenceCases == simd.cases, "scalar-C reference case count differs")
    assert(selection.referenceProbes == simd.probes, "scalar-C reference probe count differs")
    assert(selection.referenceCalls == simd.nativeCalls, "scalar-C reference call count differs")
    assert(type(selection.units) == "table" and #selection.units > 0, "scalar-C route selected no Wasm units")
    local original, rewritten, examples = {}, {}, {}
    table.sort(selection.units, function(left, right)
        return left.unit < right.unit
    end)
    for _, unit in ipairs(selection.units) do
        assert(type(unit.originalWasmSha256) == "string" and #unit.originalWasmSha256 == 64, "missing SIMD Wasm digest")
        assert(type(unit.wasmSha256) == "string" and #unit.wasmSha256 == 64, "missing scalar-C Wasm digest")
        assert(unit.originalWasmSha256 ~= unit.wasmSha256, "SIMD and scalar-C Wasm artifacts are identical")
        original[#original + 1] = unit.unit .. "=" .. unit.originalWasmSha256
        rewritten[#rewritten + 1] = unit.unit .. "=" .. unit.wasmSha256
        if #examples < 3 then
            examples[#examples + 1] = {unit = unit.unit, simd = unit.originalWasmSha256, scalarC = unit.wasmSha256,}
        end
    end
    local simdDigest = hash.digest(table.concat(original, "\0"))
    local scalarDigest = hash.digest(table.concat(rewritten, "\0"))
    assert(simdDigest ~= scalarDigest, "SIMD and scalar-C Wasm inventories are identical")

    return {distinct = true, units = #selection.units, simd = simdDigest, scalarC = scalarDigest, examples = examples,}
end

function M.execute(capabilities, hostLibrary, project, route, log)
    assert(route == "simd" or route == "scalar-c", "unknown Wasmtime execution route")
    runner.command(
        "NUPP_SIMD_HOST_MANIFEST= " .. runner.quote(
            capabilities.lua.command
        ) .. " " .. runner.quote(
            root .. "/tests/simd/run-wasmtime-guest.lua"
        ) .. " " .. runner.quote(project) .. " " .. runner.quote(hostLibrary) .. " " .. route,
        log
    )

    return runner.json(project .. "/result.json")
end

function M.produce(pack, generated, capabilities, hostLibrary, directory)
    local simdDirectory = directory .. "/simd"
    runner.wasm(generated, {
        directory = simdDirectory,
        compiler = capabilities.compiler,
        environment = M.compilerEnvironment(capabilities),
        emscriptenCache = capabilities.emscripten.cache,
    })
    local simd = M.execute(capabilities, hostLibrary, simdDirectory, "simd", directory .. "/simd-execution.log")
    local scalarDirectory = directory .. "/scalar-c"
    runner.command(
        M.compilerEnvironment(
            capabilities
        ) .. "EM_CACHE=" .. runner.quote(
            capabilities.emscripten.cache
        ) .. " NUPP_WASM_CC=" .. runner.quote(
            capabilities.compiler
        ) .. " node " .. runner.quote(
            root .. "/tests/simd/prepare-wasm-scalar.mjs"
        ) .. " " .. runner.quote(simdDirectory) .. " " .. runner.quote(scalarDirectory),
        directory .. "/scalar-build.log"
    )
    local scalar = M.execute(
        capabilities,
        hostLibrary,
        scalarDirectory,
        "scalar-c",
        directory .. "/scalar-execution.log"
    )
    local selection = runner.json(scalarDirectory .. "/scalar-selection.json")
    assert(simd.runtime == "Wasmtime 48 embedded host" and scalar.runtime == simd.runtime, "unpinned Wasm runtime")
    assert(simd.executionPath == "simd" and scalar.executionPath == "scalar-c", "Wasm route identity is missing")
    assert(simd.cases == scalar.cases and simd.probes == scalar.probes, "Wasm routes executed different corpus counts")
    assert(simd.nativeCalls == scalar.nativeCalls and simd.nativeCalls > 0, "Wasm routes executed different calls")
    assert(
        simd.oracleNumericForRuntime == scalar.oracleNumericForRuntime,
        "Wasm routes used different oracle numeric-for runtimes"
    )
    assert(
        simd.oracleNumericForGuardBridges == scalar.oracleNumericForGuardBridges,
        "Wasm routes adapted different numeric-for guard inventories"
    )
    assert(
        type(simd.oracleNumericForGuardBridges) == "number" and simd.oracleNumericForGuardBridges >= 0,
        "Wasm oracle numeric-for adaptation count is missing"
    )
    assert(
        runner.read(simdDirectory .. "/corpus.json") == runner.read(scalarDirectory .. "/corpus.json"),
        "Wasm routes did not execute one authored corpus"
    )
    local identity = routeIdentity(simd, scalar, selection)
    local sourceBytes, sourceFiles = 0, 0
    for _, source in pairs(generated.files) do
        sourceBytes = sourceBytes + #source
        sourceFiles = sourceFiles + 1
    end
    local manifest = runner.json(simdDirectory .. "/dist/aot/units.json")
    local report = {
        pack = pack,
        runtime = simd.runtime,
        tier = simd.tier,
        routes = {"simd", "scalar-c"},
        cases = simd.cases,
        probes = simd.probes,
        simdCalls = simd.nativeCalls,
        scalarCalls = scalar.nativeCalls,
        sameOracle = true,
        oracleNumericForRuntime = simd.oracleNumericForRuntime,
        oracleNumericForGuardBridges = simd.oracleNumericForGuardBridges,
        routeIdentity = identity,
        work = {
            generatedSourceBytes = sourceBytes,
            generatedSourceFiles = sourceFiles,
            generatedUnits = #manifest.units,
            scalarCompiledUnits = #selection.units,
            buildCommands = 2,
        },
    }

    return report
end

return M
