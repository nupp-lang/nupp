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
    assert(arguments:find("-Wl,-export_dynamic", 1, true)
        or arguments:find("-Wl,-E", 1, true)
        or arguments:find("-Wl,--export-all-symbols", 1, true), arguments)
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
    assert(not driver:find("provider_sources", 1, true),
        "the ABI-v1 feature selector remains in the toolchain")
    assert(not driver:match("\n    native%)"),
        "the ABI-v1 provider command remains in the toolchain")
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

    assert(seenCount == expectedCount,
        ("Rust notice covers %d of %d locked packages"):format(seenCount, expectedCount))
    for marker in pairs(expected) do
        assert(seen[marker], "Rust notice omits locked package " .. marker)
    end
    assert(read(ROOT .. "/host/NOTICE.md"):find(
        "notices/Rust-dependencies.html", 1, true),
        "the release notice does not point readers to the Rust aggregate")
end

return M
