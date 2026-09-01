-- The Cargo facade is testable without installing Rust: these fake pinned tools
-- record the exact build contract and plant the artifact the driver expects.

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."
local DRIVER = ROOT .. "/scripts/toolchain"

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local file = assert(io.open(path, "rb"), path .. " is missing")
    local text = file:read("*a")
    file:close()
    return text
end

local function countOccurrences(text, needle)
    local count = 0
    local cursor = 1
    while true do
        local found = text:find(needle, cursor, true)
        if not found then
            return count
        end
        count = count + 1
        cursor = found + #needle
    end
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function temporary()
    local path = os.tmpname()
    os.remove(path)
    assert(os.execute("mkdir -p " .. quote(path)) == 0)
    return path
end

local function run(environment, arguments)
    local prefix = {}
    for name, value in pairs(environment) do
        if name == "PATH" then
            prefix[#prefix + 1] = name .. '="' .. value .. '"'
        else
            prefix[#prefix + 1] = name .. "=" .. quote(value)
        end
    end
    table.sort(prefix)
    local command = (
        "env %s %s %s 2>&1; echo \"__exit__:$?\""
    ):format(table.concat(prefix, " "), quote(DRIVER), arguments)
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local function executable(directory, name, source)
    local path = directory .. "/" .. name
    write(path, source)
    assert(os.execute("chmod +x " .. quote(path)) == 0)
    return path
end

local function fakeCompiler(directory, name, version)
    return executable(
        directory,
        name or "fake-cc",
        ("#!/bin/sh\nprintf '%%s\\n' %s\n"):format(quote(version or "fake-cc-1"))
    )
end

local function artifactNames()
    if package.config:sub(1, 1) == "\\" then
        return "nupp_native_v2.dll", "nupp-host-rust.exe"
    end
    if jit.os == "OSX" then
        return "libnupp_native_v2.dylib", "nupp-host-rust"
    end

    return "libnupp_native_v2.so", "nupp-host-rust"
end

local function fakeRustTools(directory, version, identity)
    local rustc = executable(
        directory,
        "rustc",
        (
            [[#!/bin/sh
case "${1:-}" in
   --version) printf '%%s\n' 'rustc %s (fake)' ;;
   -vV) printf '%%s\n' 'rustc %s (fake)' 'host: %s' ;;
   *) exit 2 ;;
esac
]]
        ):format(version, version, identity)
    )
    local cargo = executable(
        directory,
        "cargo",
        (
            [[#!/bin/sh
if [ "${1:-}" = --version ]; then
   if [ -n "${NUPP_TEST_RUST_TOOL_CHATTER:-}" ]; then
      printf '%%s\n' 'info: syncing pinned Cargo proxy' >&2
   fi
   printf '%%s\n' 'cargo %s (fake)'
   exit 0
fi
arguments="$*"
target=
package=
binary=
while [ "$#" -gt 0 ]; do
   case "$1" in
      --target-dir) shift; target=${1:-} ;;
      --package) shift; package=${1:-} ;;
      --bin) shift; binary=${1:-} ;;
   esac
   shift
done
[ -n "$target" ] || exit 3
mkdir -p "$target/release"
case "$package" in
   nupp-native)
      artifact=$NUPP_TEST_RUST_LIBRARY
      printf '%%s\n' built > "$target/release/libnupp_native_v2.a"
      ;;
   nupp-native-host)
      [ "$binary" = nupp-host-rust ] || exit 4
      artifact=$NUPP_TEST_RUST_HOST
      ;;
   *) exit 5 ;;
esac
printf '%%s\n' built > "$target/release/$artifact"
printf '%%s\n' "$arguments" > "$NUPP_TEST_CARGO_RECORD"
printf '%%s\n' "${NUPP_CC:-}" > "$NUPP_TEST_CARGO_CC_RECORD"
printf '%%s\n' "${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER:-}" > "$NUPP_TEST_CARGO_LINKER_RECORD"
]]
        ):format(version)
    )

    return cargo, rustc
end

local function environment(directory, version, identity)
    local compiler = fakeCompiler(directory)
    local cargo, rustc = fakeRustTools(directory, version or "1.98.0", identity or "fake-unknown-nupp")
    local library, host = artifactNames()
    assert(os.execute("mkdir -p " .. quote(directory .. "/vendor")) == 0)

    return {
        NUPP_TOOLCHAIN_DIR = directory .. "/toolchain",
        NUPP_RUST_BUILD_DIR = directory .. "/build/rust",
        NUPP_CC = compiler,
        NUPP_CXX = compiler,
        NUPP_CARGO = cargo,
        NUPP_RUSTC = rustc,
        NUPP_RUST_VENDOR_DIR = directory .. "/vendor",
        NUPP_TEST_CARGO_RECORD = directory .. "/cargo-arguments",
        NUPP_TEST_CARGO_CC_RECORD = directory .. "/cargo-cc",
        NUPP_TEST_CARGO_LINKER_RECORD = directory .. "/cargo-linker",
        NUPP_TEST_RUST_LIBRARY = library,
        NUPP_TEST_RUST_HOST = host,
        PATH = "$PATH",
    }, library, host
end

local function answer(output)
    local last = nil
    for line in output:gmatch("[^\r\n]+") do
        if line:match("%S") then
            last = line
        end
    end

    return assert(last, "the driver answered no artifact path")
end

function M.nativeBuildIsPinnedOfflineAndFeatureSelected()
    local directory = temporary()
    local env, library = environment(directory)
    env.NUPP_HOST_OFFLINE = "1"
    local status, output = run(env, "native-rust zeta,alpha,zeta")

    assert(status == 0, output)
    local arguments = read(env.NUPP_TEST_CARGO_RECORD)
    assert(arguments:find("--package nupp-native", 1, true), arguments)
    assert(arguments:find("--locked", 1, true), arguments)
    assert(arguments:find("--offline", 1, true), arguments)
    assert(arguments:find("--no-default-features", 1, true), arguments)
    assert(arguments:find("--features alpha,zeta", 1, true), arguments)
    assert(arguments:find("source.crates-io.replace-with='nupp-vendored-sources'", 1, true), arguments)
    assert(arguments:find("source.nupp-vendored-sources.directory='" .. directory .. "/vendor'", 1, true), arguments)
    assert(arguments:find(directory .. "/build/rust/native/", 1, true), arguments)
    assert(output:find(library, 1, true), output)
end

function M.offlineRustBuildNamesItsVendorContract()
    local directory = temporary()
    local env = environment(directory)
    env.NUPP_HOST_OFFLINE = "1"
    env.NUPP_RUST_VENDOR_DIR = nil
    local status, output = run(env, "native-rust gpu")

    assert(status ~= 0, output)
    assert(output:find("offline Rust builds require NUPP_RUST_VENDOR_DIR", 1, true), output)
    assert(output:find("scripts/toolchain rust-vendor OUTPUT", 1, true), output)
end

function M.implicitCargoTargetCannotPoisonTheHostArtifactCache()
    local directory = temporary()
    local env = environment(directory)
    env.CARGO_BUILD_TARGET = "wasm32-unknown-unknown"
    local status, output = run(env, "native-rust gpu")

    assert(status ~= 0, output)
    assert(output:find("CARGO_BUILD_TARGET is unsupported", 1, true), output)
    assert(io.open(env.NUPP_TEST_CARGO_RECORD, "rb") == nil, "Cargo ran with an implicit target")
end

function M.hostBuildSelectsThePinnedWorkspaceBinary()
    local directory = temporary()
    local env, _, host = environment(directory)
    local status, output = run(env, "host-rust")

    assert(status == 0, output)
    local arguments = read(env.NUPP_TEST_CARGO_RECORD)
    assert(arguments:find("--package nupp-native-host", 1, true), arguments)
    assert(arguments:find("--bin nupp-host-rust", 1, true), arguments)
    assert(arguments:find("--locked", 1, true), arguments)
    assert(not arguments:find("--offline", 1, true), arguments)
    assert(arguments:find(directory .. "/build/rust/host-binary/", 1, true), arguments)
    assert(arguments:find("-C link-dead-code", 1, true), arguments)
    assert(
        arguments:find(
            "-Wl,-export_dynamic",
            1,
            true
        ) or arguments:find("-Wl,-E", 1, true) or arguments:find("-Wl,--export-all-symbols", 1, true),
        arguments
    )
    assert(output:find(host, 1, true), output)
end

function M.anUnpinnedToolchainIsRejected()
    local directory = temporary()
    local env = environment(directory, "1.97.0")
    local status, output = run(env, "native-rust")

    assert(status ~= 0, output)
    assert(output:find("requires cargo 1.98.0", 1, true), output)
    assert(io.open(env.NUPP_TEST_CARGO_RECORD, "rb") == nil, "the unpinned Cargo was allowed to build")
end

-- A fresh rustup proxy reports installation and synchronization progress on
-- stderr before printing the requested version on stdout. That progress is a
-- useful build diagnostic, but it is not part of Cargo's tool identity.
function M.rustupProxyProgressDoesNotChangeThePinnedVersion()
    local directory = temporary()
    local env = environment(directory)
    env.NUPP_TEST_RUST_TOOL_CHATTER = "1"
    local status, output = run(env, "native-rust")

    assert(status == 0, output)
    assert(output:find("info: syncing pinned Cargo proxy", 1, true), output)
    assert(not output:find("Cargo is info:", 1, true), output)
end

-- Even on Unix, an ambient cargo/rustc can be rustup proxies rather than the
-- pinned binaries themselves. Resolve both through the exact channel once and
-- never execute those ambient proxies while inspecting or building.
function M.unixSelectsPinnedRustupToolsBeforeAmbientProxies()
    local directory = temporary()
    local env = environment(directory)
    local exactCargo = env.NUPP_CARGO
    local exactRustc = env.NUPP_RUSTC
    local proxy = directory .. "/proxy"
    local proxyRecord = directory .. "/ambient-proxy"
    local rustupRecord = directory .. "/rustup-toolchains"
    assert(os.execute("mkdir -p " .. quote(proxy)) == 0)
    executable(proxy, "uname", [[#!/bin/sh
printf '%s\n' Linux
]])
    executable(
        proxy,
        "cargo",
        (
            "#!/bin/sh\nprintf 'cargo\\n' >> %s\nprintf 'info: syncing ambient Cargo proxy\\n'\nexit 91\n"
        ):format(quote(proxyRecord))
    )
    executable(
        proxy,
        "rustc",
        (
            "#!/bin/sh\nprintf 'rustc\\n' >> %s\nprintf 'info: syncing ambient rustc proxy\\n'\nexit 92\n"
        ):format(quote(proxyRecord))
    )
    executable(
        proxy,
        "rustup",
        (
            [[#!/bin/sh
printf '%%s\n' "${RUSTUP_TOOLCHAIN:-}" >> %s
[ "${1:-}" = which ] || exit 3
case "${2:-}" in
   cargo) printf '%%s\n' %s ;;
   rustc) printf '%%s\n' %s ;;
   *) exit 4 ;;
esac
]]
        ):format(quote(rustupRecord), quote(exactCargo), quote(exactRustc))
    )
    env.NUPP_CARGO = nil
    env.NUPP_RUSTC = nil
    env.NUPP_TEST_RUST_LIBRARY = "libnupp_native_v2.so"
    env.PATH = proxy .. ":$PATH"

    local status, output = run(env, "native-rust")

    assert(status == 0, output)
    assert(io.open(proxyRecord, "rb") == nil, "an ambient Rust proxy was executed")
    local selected = read(rustupRecord)
    local _, count = selected:gsub("1%.98%.0\n", "")
    assert(count == 2, "Cargo and rustc did not both select the pinned Unix toolchain:\n" .. selected)
end

function M.gpuConformanceIsValidPosixShell()
    for _, name in ipairs({"measure-gpu-provider.sh", "test-gpu-conformance.sh", "test-gpu-conformance-windows.sh",}) do
        local script = ROOT .. "/.github/scripts/" .. name
        assert(os.execute("sh -n " .. quote(script)) == 0, name .. " is not valid POSIX shell")
    end
    local workflow = read(ROOT .. "/.github/workflows/compiler.yml")
    local linux = read(ROOT .. "/.github/scripts/test-gpu-conformance.sh")
    local windows = read(ROOT .. "/.github/scripts/test-gpu-conformance-windows.sh")
    local gemm = read(ROOT .. "/bench/wgpu-spike/gemm-api.lua")
    assert(workflow:find("GPU conformance / Windows DX12", 1, true), "the compiler matrix has no Windows GPU gate")
    assert(windows:find("WGPU_BACKEND=dx12", 1, true), "Windows GPU conformance does not force DX12")
    assert(windows:find('cygpath -m "$root"', 1, true), "Windows GPU conformance passes POSIX paths to LuaJIT")
    assert(windows:find("$lua_root/build/?.lua", 1, true), "Windows GPU conformance omits compiled Nupp modules")
    assert(linux:find("$root/build/?.lua", 1, true), "Linux GPU conformance omits compiled Nupp modules")
    assert(windows:find("NUPP_REQUIRE_GPU=1", 1, true), "Windows GPU conformance allows adapter absence")
    assert(windows:find("gemm-api.lua", 1, true), "Windows GPU conformance does not cross the public Nupp API")
    assert(gemm:find('require("nupp.time")', 1, true), "GPU conformance uses a platform-specific benchmark clock")
end

function M.gpuProviderMeasurementsCompareExactFeatureUnions()
    local workflow = read(ROOT .. "/.github/workflows/compiler.yml")
    local measure = read(ROOT .. "/.github/scripts/measure-gpu-provider.sh")

    assert(measure:find("base,files,http,net,process,tls,uri,uuid", 1, true))
    assert(measure:find("base,files,gpu,http,net,process,tls,uri,uuid", 1, true))
    assert(measure:find('"$exact_root/non-gpu"', 1, true), "the non-GPU cold build has no isolated target")
    assert(measure:find('"$exact_root/gpu"', 1, true), "the GPU cold build has no isolated target")
    assert(not measure:find("${RUNNER_TEMP", 1, true), "Git Bash receives a native Windows temporary path")
    assert(measure:find("warm_ms", 1, true), "warm exact-feature lookup time is not recorded")
    assert(measure:find("dynamic_bytes", 1, true), "dynamic provider size is not recorded")
    assert(measure:find("static_bytes", 1, true), "static provider size is not recorded")
    assert(measure:find("observations, not", 1, true), "hosted GPU timings look like acceptance thresholds")
    assert(workflow:find("build/ci-gpu-provider vulkan", 1, true))
    assert(workflow:find("build/ci-gpu-provider dx12", 1, true))
    assert(workflow:find("gpu-provider-linux-vulkan-${{ github.sha }}", 1, true))
    assert(workflow:find("gpu-provider-windows-dx12-${{ github.sha }}", 1, true))
end

function M.nativeRuntimeMeasurementsArePortableAndNonThresholded()
    local workflow = read(ROOT .. "/.github/workflows/compiler.yml")
    local measure = read(ROOT .. "/.github/scripts/measure-native-runtime.sh")
    local benchmark = read(ROOT .. "/bench/native-runtime/src/main.nupp")
    local peer = read(ROOT .. "/bench/native-runtime/server.mjs")
    local resources = read(ROOT .. "/bench/native-runtime/resource.sh")
    local windowsResources = read(ROOT .. "/bench/native-runtime/resource-windows.ps1")

    assert(os.execute("sh -n " .. quote(ROOT .. "/.github/scripts/measure-native-runtime.sh")) == 0)
    assert(os.execute("sh -n " .. quote(ROOT .. "/bench/native-runtime/resource.sh")) == 0)
    assert(os.execute("sh -n " .. quote(ROOT .. "/bench/native-runtime/run.sh")) == 0)
    assert(workflow:find("Native runtime measurements / ${{ matrix.name }}", 1, true))
    assert(workflow:find("native-runtime-${{ matrix.artifact }}-${{ github.sha }}", 1, true))
    assert(measure:find("./bin/nupp build", 1, true), "clean measurement runners do not stage root modules")
    assert(measure:find("bench/native-runtime/run.sh", 1, true))
    assert(measure:find("bench/native-runtime/resource.sh", 1, true))
    assert(measure:find("features=base,filesystem,http,net,uri", 1, true))
    assert(measure:find('benchmark.exe', 1, true), "Windows benchmark size does not resolve the executable suffix")
    assert(measure:find("observations, not", 1, true), "hosted-runner timings are not identified as observations")
    assert(resources:find('Windows:*|*:MINGW*|*:MSYS*|*:CYGWIN*', 1, true), "Windows runner detection is incomplete")
    assert(
        resources:find('./bin/nupp build --target compiler --progress=never', 1, true),
        "the direct resource entry point does not stage compiler-owned runtimes"
    )
    assert(not resources:find("ps -W", 1, true), "the sampler still infers a native PID from MSYS process state")
    assert(resources:find("resource-windows.ps1", 1, true), "Windows does not dispatch to its native sampler")
    assert(resources:find('cygpath -w "$benchmark"', 1, true), "the Windows sampler does not receive a native path")
    assert(windowsResources:find("Start-Process @parameters", 1, true), "PowerShell does not own the benchmark child")
    assert(
        windowsResources:find(
            "RedirectStandardOutput = $Output",
            1,
            true
        ) and windowsResources:find("RedirectStandardError = $ErrorOutput", 1, true),
        "the Windows benchmark output is not retained for readiness and diagnostics"
    )
    assert(windowsResources:find("$Process.WorkingSet64", 1, true), "Windows RSS is not sampled")
    assert(
        windowsResources:find("$stdout = [string](Read-ChildText -Path $Output)", 1, true),
        "empty Windows child output collapses to null before diagnostics"
    )
    assert(
        windowsResources:find("$processHandle = $process.Handle", 1, true),
        "Windows does not retain its exact child process handle while the benchmark is live"
    )
    assert(
        windowsResources:find("WaitForSingleObject(process, Infinite)", 1, true),
        "Windows does not wait on the retained native process handle"
    )
    assert(
        windowsResources:find("GetExitCodeProcess(process, out exitCode)", 1, true),
        "Windows does not read status from the retained native process handle"
    )
    assert(
        windowsResources:find("WaitForExitCode($processHandle)", 1, true),
        "Windows accepts an empty PowerShell Process.ExitCode as success"
    )
    assert(
        windowsResources:find("$reportedPid -ne [long]$Process.Id", 1, true),
        "the benchmark PID is not checked against the retained Windows process"
    )
    assert(not windowsResources:find("Get-Process", 1, true), "the Windows sampler still rediscovers its child by PID")
    assert(
        windowsResources:find(
            "finally",
            1,
            true
        ) and windowsResources:find(
            "Stop-Benchmark -Process $process",
            1,
            true
        ) and windowsResources:find(
            "$Process.Kill()",
            1,
            true
        ) and windowsResources:find("$Process.WaitForExit()", 1, true),
        "the Windows benchmark child is not cleaned up on failure"
    )
    assert(windowsResources:find("$sampleCount -eq 0", 1, true), "a Windows load run can succeed without an RSS sample")
    assert(windowsResources:find('"load peak_rss_kib=$peak"', 1, true), "the Windows load result format drifted")
    assert(windowsResources:find('"$Mode second=$second rss_kib=$rss"', 1, true), "the Windows probe format drifted")
    assert(
        benchmark:find("unsigned long __stdcall GetCurrentProcessId(void);", 1, true),
        "the Windows benchmark does not declare the Win32 PID API"
    )
    assert(benchmark:find('ffi.load("kernel32")', 1, true), "the Windows benchmark does not load the PID API")
    assert(not benchmark:find("ffi.C._getpid", 1, true), "the Windows benchmark still reads an MSYS C-runtime PID")
    assert(benchmark:find("int getpid(void);", 1, true), "the Unix benchmark does not read its native PID")
    assert(benchmark:find("NUPP_BENCH_PID %d", 1, true), "the benchmark does not report a machine-readable PID")
    assert(resources:find("benchmark_pid()", 1, true), "the resource harness does not require the PID report")
    assert(resources:find('native_pid=$(benchmark_pid "$output" "$BENCH_PID"', 1, true))
    assert(countOccurrences(resources, 'rss=$(rss_kib "$native_pid")') == 2, "Unix load and probes do not sample RSS")
    assert(not resources:find('rss=$(rss_kib "$BENCH_PID")', 1, true), "the shell lifecycle PID is still sampled")
    assert(resources:find('while kill -0 "$BENCH_PID" 2>/dev/null; do', 1, true))
    assert(resources:find('elif kill -0 "$BENCH_PID" 2>/dev/null; then', 1, true))
    assert(
        not resources:find("native_process_running", 1, true),
        "the Win32 RSS identity is still used as the Git Bash lifecycle identity"
    )
    assert(
        resources:find("invalid RSS sample", 1, true),
        "missing or non-numeric RSS samples do not fail the measurement"
    )
    assert(
        not resources:find('rss_kib "$BENCH_PID" 2>/dev/null || true', 1, true),
        "load measurement still hides RSS sampler failures"
    )
    assert(resources:find('if [ "$samples" -eq 0 ]', 1, true), "a load run can succeed without an RSS sample")
    assert(resources:find("measure net-slow-reader", 1, true), "the raw network slow-reader resource probe is absent")
    assert(resources:find("measure net-slow-writer", 1, true), "the raw network slow-writer resource probe is absent")
    assert(resources:find("measure http-slow-writer", 1, true), "the HTTP slow-writer resource probe is absent")
    assert(benchmark:find("NUPP_BENCH_NET_PORT", 1, true), "the raw slow writer has no external peer")
    assert(peer:find("createTcpServer", 1, true), "the raw slow-writer peer is absent")
end

function M.featuresAndToolIdentityChangeTheArtifactKey()
    local directory = temporary()
    local env = environment(directory)
    local firstStatus, firstOutput = run(env, "native-rust alpha")
    assert(firstStatus == 0, firstOutput)

    local secondStatus, secondOutput = run(env, "native-rust beta")
    assert(secondStatus == 0, secondOutput)
    assert(answer(firstOutput) ~= answer(secondOutput), "two feature unions shared one artifact")

    local changed = environment(directory, "1.98.0", "different-unknown-nupp")
    local thirdStatus, thirdOutput = run(changed, "native-rust beta")
    assert(thirdStatus == 0, thirdOutput)
    assert(answer(secondOutput) ~= answer(thirdOutput), "two rustc identities shared one artifact")

    changed.RUSTFLAGS = "-Cdebuginfo=1"
    local fourthStatus, fourthOutput = run(changed, "native-rust beta")
    assert(fourthStatus == 0, fourthOutput)
    assert(answer(thirdOutput) ~= answer(fourthOutput), "two codegen configurations shared one artifact")
end

function M.legacyProviderUpgradeBridgeIsGone()
    local driver = read(DRIVER)
    assert(not driver:find("provider_sources", 1, true), "the ABI-v1 feature selector remains in the toolchain")
    assert(not driver:match("\n    native%)"), "the ABI-v1 provider command remains in the toolchain")
end

function M.hostArtifactFollowsTheLuaJitCompilerIdentity()
    local directory = temporary()
    local env = environment(directory)
    local firstStatus, firstOutput = run(env, "host-rust")
    assert(firstStatus == 0, firstOutput)

    local second = fakeCompiler(directory, "second-cc", "fake-cc-2")
    env.NUPP_CC = second
    env.NUPP_CXX = second
    local secondStatus, secondOutput = run(env, "host-rust")
    assert(secondStatus == 0, secondOutput)
    assert(answer(firstOutput) ~= answer(secondOutput), "two LuaJIT compiler identities shared one Rust host")
end

-- The driver can select its compiler through the compatibility alias or by
-- probing PATH. Cargo does not inherit the driver's private shell variable, so
-- pass the resolved answer explicitly to the host crate's C-shim build script.
function M.hostShimUsesTheResolvedLuaJitCompiler()
    local directory = temporary()
    local env = environment(directory)
    local compiler = env.NUPP_CC
    env.NUPP_CC = nil
    env.NUPP_NATIVE_CC = compiler
    local status, output = run(env, "host-rust")

    assert(status == 0, output)
    assert(
        read(env.NUPP_TEST_CARGO_CC_RECORD):match("^" .. compiler:gsub("([^%w])", "%%%1") .. "\n$"),
        "the Rust host build did not receive the compiler selected for LuaJIT"
    )
    local driver = read(DRIVER)
    local forwards = countOccurrences(driver, 'NUPP_CC="$CC"')
    assert(forwards == 2, "the application and embedding host builds do not both forward NUPP_CC")
end

-- The hosted Windows default is the MSVC Rust toolchain, while LuaJIT and the
-- public static link are MinGW. Resolve the exact GNU-hosted toolchain through
-- rustup even when its ordinary Cargo proxy is already on PATH.
function M.windowsSelectsThePinnedGnuRustToolchain()
    local directory = temporary()
    local env = environment(directory, "1.98.0", "x86_64-pc-windows-gnu")
    local rustupRecord = directory .. "/rustup-toolchains"
    executable(directory, "uname", [[#!/bin/sh
printf '%s\n' MINGW64_NT
]])
    executable(
        directory,
        "rustup",
        (
            [[#!/bin/sh
printf '%%s\n' "${RUSTUP_TOOLCHAIN:-}" >> %s
[ "${1:-}" = which ] || exit 3
case "${2:-}" in
   cargo|rustc) printf '%%s/%%s\n' %s "$2" ;;
   *) exit 4 ;;
esac
]]
        ):format(quote(rustupRecord), quote(directory))
    )
    env.NUPP_CARGO = nil
    env.NUPP_RUSTC = nil
    env.NUPP_TEST_RUST_HOST = "nupp-host-rust.exe"
    env.PATH = directory .. ":$PATH"

    local status, output = run(env, "host-rust")

    assert(status == 0, output)
    local selected = read(rustupRecord)
    local _, count = selected:gsub("1%.98%.0%-x86_64%-pc%-windows%-gnu\n", "")
    assert(count == 2, "Cargo and rustc did not both select the pinned Windows GNU toolchain:\n" .. selected)
    assert(
        read(env.NUPP_TEST_CARGO_LINKER_RECORD):match("^" .. env.NUPP_CC:gsub("([^%w])", "%%%1") .. "\n$"),
        "Cargo did not link the Windows GNU artifact with Nupp's selected compiler"
    )
end

function M.windowsCiInstallsThePinnedGnuRustToolchain()
    local compiler = read(ROOT .. "/.github/workflows/compiler.yml")
    local release = read(ROOT .. "/.github/workflows/release.yml")
    local marker = 'rustup toolchain install "${channel}-x86_64-pc-windows-gnu" --profile minimal'
    local compilerInstalls = countOccurrences(compiler, marker)
    local releaseInstalls = countOccurrences(release, marker)
    assert(compilerInstalls == 3, "the Windows compiler, DX12, and native measurement jobs do not provision GNU Rust")
    assert(releaseInstalls == 2, "the Windows host and compiler-pack jobs do not provision GNU Rust")
end

function M.pagesCiInstallsThePinnedRustToolchain()
    local pages = read(ROOT .. "/.github/workflows/pages.yml")
    local marker = 'rustup toolchain install "$channel" --profile minimal'
    assert(
        countOccurrences(pages, marker) == 1,
        "the Pages build does not provision the exact Rust toolchain before building docs"
    )
end

-- The broad suite remains the language gate. Native migration regressions need
-- a smaller named boundary before it: the exact resource crates, C ABI, and
-- production host artifacts on each retained runner. Tagged release jobs must
-- repeat it because one GitHub workflow cannot depend on another workflow's
-- result.
function M.retainedPlatformsGateTheExactRustNativeArtifacts()
    local compiler = read(ROOT .. "/.github/workflows/compiler.yml")
    local release = read(ROOT .. "/.github/workflows/release.yml")
    local gate = read(ROOT .. "/.github/scripts/test-rust-native-platform.sh")
    local marker = ".github/scripts/test-rust-native-platform.sh"

    assert(countOccurrences(compiler, marker) == 1, "the compiler matrix does not run one native artifact gate")
    assert(countOccurrences(release, marker) == 2, "the Unix and Windows release builders do not both run the gate")
    assert(
        gate:find('NUPP_TEST_BASH=${NUPP_TEST_BASH:-$(cygpath -w "$bash_path")}', 1, true),
        "the Windows native gate does not provide Git Bash to its test harness"
    )
    assert(
        gate:find('NUPP_TEST_SH=${NUPP_TEST_SH:-$(cygpath -w "$sh_path")}', 1, true),
        "the Windows native gate does not provide sh.exe to its test harness"
    )
    assert(gate:find("$channel-x86_64-pc-windows-gnu", 1, true), "the gate does not select Windows GNU Rust")
    assert(
        gate:find("lpeg,native-files,native-net,native-process,native-tls,workers", 1, true),
        "the gate does not select the production host feature set"
    )
    for _, package in ipairs({
        "nupp-native-files",
        "nupp-native-process",
        "nupp-native-net",
        "nupp-native-tls",
        "nupp-native-host",
    }) do
        assert(gate:find("--package " .. package, 1, true), "the gate omits " .. package)
    end
    for _, artifact in ipairs({"libnupp.a", "libnupp.dll.a", "libnupp.dylib", "libnupp.so", "nupp.dll"}) do
        assert(gate:find(artifact, 1, true), "the gate does not name " .. artifact)
    end
    assert(gate:find("hostembeddingtest", 1, true), "the gate does not link every host artifact from C")
    assert(compiler:find("./bin/nupp fixpoint", 1, true), "the retained compiler matrix has no fixpoint gate")
    assert(
        countOccurrences(release, "./bin/nupp fixpoint --binary") == 2,
        "the retained release matrix does not verify binary packaging fixpoints"
    )
    assert(release:find("shasum -a 256 -c SHA256SUMS", 1, true), "Unix packaging has no archive fixpoint")
    assert(release:find("release archive checksum mismatch", 1, true), "Windows packaging has no archive fixpoint")
end

-- Every Cargo package can end up in a provider for some feature, platform or
-- build mode. Releases copy host/notices without running Cargo, so the committed
-- aggregate must cover the whole lock file rather than only this machine's
-- resolved graph.
function M.everyLockedRustDependencyHasACommittedNotice()
    local lock = read(ROOT .. "/Cargo.lock")
    local notice = read(ROOT .. "/host/notices/Rust-dependencies.html")
    local expected = {}
    local expectedCount = 0
    local name, version, thirdParty

    local function finishPackage()
        if thirdParty then
            assert(name and version, "a locked Cargo package has no name or version")
            local marker = name .. "@" .. version
            assert(not expected[marker], "duplicate locked Cargo package " .. marker)
            expected[marker] = true
            expectedCount = expectedCount + 1
        end
        name, version, thirdParty = nil, nil, false
    end

    for line in (lock .. "\n[[package]]\n"):gmatch("[^\r\n]+") do
        if line == "[[package]]" then
            finishPackage()
        elseif name == nil then
            name = line:match('^name = "([^"]+)"$')
        elseif version == nil then
            version = line:match('^version = "([^"]+)"$')
        end
        if line:match("^source = ") then
            thirdParty = true
        end
    end

    local seen = {}
    local seenCount = 0
    for marker in notice:gmatch('data%-crate="([^"]+)"') do
        assert(expected[marker], "Rust notice names an unlocked package " .. marker)
        assert(not seen[marker], "Rust notice repeats package " .. marker)
        seen[marker] = true
        seenCount = seenCount + 1
    end

    assert(seenCount == expectedCount, ("Rust notice covers %d of %d locked packages"):format(seenCount, expectedCount))
    for marker in pairs(expected) do
        assert(seen[marker], "Rust notice omits locked package " .. marker)
    end
    assert(
        read(ROOT .. "/host/NOTICE.md"):find("notices/Rust-dependencies.html", 1, true),
        "the release notice does not point readers to the Rust aggregate"
    )
end

return M
